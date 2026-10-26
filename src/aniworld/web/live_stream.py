"""Direct streaming for the TV web app: play an episode without downloading it.

The hosters (VOE, Vidmoly, Filemoon, …) only hand out their HLS playlists /
MP4 files to clients that send the right Referer/Origin/User-Agent, some sign
the URL against the IP that resolved it, and none of them send CORS headers —
so a browser can't play them itself. Instead the backend resolves the stream
exactly like a download would (``models.common.common.resolve_live_stream``)
and relays it:

- ``POST /api/live/resolve`` → creates a short-lived *live session* (random
  id, upstream URL + headers kept in memory) and returns a same-origin URL.
- ``GET /api/live/<sid>/playlist?u=…`` fetches an upstream playlist and
  rewrites every URI in it (variants, segments, keys, init sections) to point
  back at this proxy.
- ``GET /api/live/<sid>/media?u=…`` relays a segment/key/MP4 with Range
  support, so seeking works without fetching the whole file.

The session id is an unguessable capability (the media routes are exempt from
the login wrapper, because a plain ``<video src>`` can't send an
Authorization header), and a session only ever relays hosts it has seen in
its own playlists — it can't be used as an open proxy.
"""

import base64
import re
import secrets
import threading
import time
from urllib.parse import urljoin, urlsplit

from flask import Blueprint, Response, jsonify, request, stream_with_context

from ..logger import get_logger

logger = get_logger(__name__)

live_bp = Blueprint("live", __name__, url_prefix="/api/live")

SESSION_IDLE_SECONDS = 4 * 3600
_MAX_SESSIONS = 200
_CHUNK = 64 * 1024
_TIMEOUT = (15, 60)

_sessions = {}
_sessions_lock = threading.Lock()

_URI_ATTR_RE = re.compile(r'URI="([^"]*)"')


# ── Sessions ─────────────────────────────────────────────────────────────────


def _prune(now):
    stale = [
        sid
        for sid, sess in _sessions.items()
        if now - sess["last_used"] > SESSION_IDLE_SECONDS
    ]
    for sid in stale:
        del _sessions[sid]
    if len(_sessions) > _MAX_SESSIONS:
        oldest = sorted(_sessions, key=lambda sid: _sessions[sid]["last_used"])
        for sid in oldest[: len(_sessions) - _MAX_SESSIONS]:
            del _sessions[sid]


def create_session(url, headers, provider=None):
    """Register an upstream stream and return its session id."""
    now = time.time()
    sid = secrets.token_urlsafe(18)
    with _sessions_lock:
        _prune(now)
        _sessions[sid] = {
            "url": url,
            "headers": dict(headers or {}),
            "provider": provider,
            "hosts": {urlsplit(url).netloc.lower()},
            "last_used": now,
        }
    return sid


def _get_session(sid):
    with _sessions_lock:
        sess = _sessions.get(sid)
        if sess:
            sess["last_used"] = time.time()
        return sess


def _allow_host(sess, url):
    with _sessions_lock:
        sess["hosts"].add(urlsplit(url).netloc.lower())


def _host_allowed(sess, url):
    parts = urlsplit(url)
    return parts.scheme in ("http", "https") and parts.netloc.lower() in sess["hosts"]


# ── URL encoding / playlist rewriting ────────────────────────────────────────


def _encode(url):
    return base64.urlsafe_b64encode(url.encode("utf-8")).decode("ascii").rstrip("=")


def _decode(token):
    padded = token + "=" * (-len(token) % 4)
    return base64.urlsafe_b64decode(padded.encode("ascii")).decode("utf-8")


def _proxy_url(sid, kind, upstream):
    return f"/api/live/{sid}/{kind}?u={_encode(upstream)}"


def rewrite_playlist(text, base_url, sid, on_url=None):
    """Point every URI of an HLS playlist at this proxy.

    Lines following ``#EXT-X-STREAM-INF`` and ``URI=`` attributes of
    ``#EXT-X-MEDIA`` / ``#EXT-X-I-FRAME-STREAM-INF`` are playlists themselves;
    everything else (segments, ``#EXT-X-KEY``, ``#EXT-X-MAP``) is media.
    ``on_url`` is called with every absolute upstream URL (to allow its host).
    """

    def absolute(uri):
        full = urljoin(base_url, uri.strip())
        if on_url:
            on_url(full)
        return full

    out = []
    next_is_playlist = False
    for raw in text.splitlines():
        line = raw.strip()
        if not line:
            out.append(raw)
            continue
        if line.startswith("#"):
            tag = line.split(":", 1)[0].upper()
            if tag == "#EXT-X-STREAM-INF":
                next_is_playlist = True
            if 'URI="' in line:
                kind = (
                    "playlist"
                    if tag in ("#EXT-X-MEDIA", "#EXT-X-I-FRAME-STREAM-INF")
                    else "media"
                )
                line = _URI_ATTR_RE.sub(
                    lambda m: f'URI="{_proxy_url(sid, kind, absolute(m.group(1)))}"', line
                )
            out.append(line)
            continue
        kind = "playlist" if next_is_playlist else "media"
        next_is_playlist = False
        out.append(_proxy_url(sid, kind, absolute(line)))
    return "\n".join(out) + "\n"


# ── Upstream access ──────────────────────────────────────────────────────────


def _http():
    from ..config import GLOBAL_SESSION

    return GLOBAL_SESSION


def _looks_like_playlist(url, content_type="", head=b""):
    path = urlsplit(url).path.lower()
    if path.endswith((".m3u8", ".m3u")):
        return True
    if "mpegurl" in (content_type or "").lower():
        return True
    return head.lstrip()[:7] == b"#EXTM3U"


def _probe_kind(url, headers):
    """'hls' or 'file' for the initial stream URL."""
    if urlsplit(url).path.lower().endswith((".m3u8", ".m3u")):
        return "hls"
    try:
        resp = _http().get(
            url,
            headers={**headers, "Range": "bytes=0-511", "Accept-Encoding": "identity"},
            timeout=_TIMEOUT,
            stream=True,
        )
        try:
            head = next(resp.iter_content(512), b"")
        finally:
            resp.close()
        content_type = resp.headers.get("Content-Type", "")
    except Exception as exc:
        logger.debug("Live stream probe failed for %s: %s", url, exc)
        return "file"
    return "hls" if _looks_like_playlist(url, content_type, head) else "file"


# ── Routes ───────────────────────────────────────────────────────────────────


@live_bp.route("/resolve", methods=["POST"])
def resolve():
    """Body: {episode_url, language?, provider?} → {url, kind, provider}."""
    from ..models.common.common import resolve_live_stream
    from ..providers import resolve_provider

    data = request.get_json(silent=True) or {}
    episode_url = (data.get("episode_url") or "").strip()
    if not episode_url:
        return jsonify({"error": "episode_url is required"}), 400
    try:
        prov = resolve_provider(episode_url)
        kwargs = {"url": episode_url}
        if data.get("language"):
            kwargs["selected_language"] = data["language"]
        if data.get("provider"):
            kwargs["selected_provider"] = data["provider"]
        episode = prov.episode_cls(**kwargs)
        stream = resolve_live_stream(episode)
    except Exception as exc:
        logger.warning("Direct streaming unavailable for %s: %s", episode_url, exc)
        return jsonify({"error": f"Direct streaming unavailable: {exc}"}), 502

    kind = _probe_kind(stream["url"], stream["headers"])
    sid = create_session(stream["url"], stream["headers"], stream["provider"])
    endpoint = "playlist" if kind == "hls" else "media"
    return jsonify(
        {
            "url": _proxy_url(sid, endpoint, stream["url"]),
            "kind": kind,
            "provider": stream["provider"],
        }
    )


def _upstream_target(sid):
    sess = _get_session(sid)
    if not sess:
        return None, None, (jsonify({"error": "Stream session expired"}), 404)
    try:
        url = _decode(request.args.get("u", ""))
    except Exception:
        return None, None, (jsonify({"error": "Invalid stream URL"}), 400)
    if not _host_allowed(sess, url):
        return None, None, (jsonify({"error": "Host not part of this stream"}), 403)
    return sess, url, None


@live_bp.route("/<sid>/playlist")
def playlist(sid):
    sess, url, error = _upstream_target(sid)
    if error:
        return error
    try:
        resp = _http().get(url, headers=sess["headers"], timeout=_TIMEOUT)
    except Exception as exc:
        return jsonify({"error": f"Upstream unreachable: {exc}"}), 502
    if resp.status_code >= 400:
        return jsonify({"error": f"Upstream returned {resp.status_code}"}), 502
    final_url = str(resp.url or url)
    _allow_host(sess, final_url)
    text = resp.content.decode("utf-8", errors="replace")
    if "#EXTM3U" not in text[:1024]:
        return jsonify({"error": "Upstream did not return a playlist"}), 502
    body = rewrite_playlist(text, final_url, sid, on_url=lambda u: _allow_host(sess, u))
    return Response(
        body,
        mimetype="application/vnd.apple.mpegurl",
        headers={"Cache-Control": "no-store"},
    )


_PASS_HEADERS = ("Content-Type", "Content-Length", "Content-Range", "Accept-Ranges", "Last-Modified", "ETag")


@live_bp.route("/<sid>/media")
def media(sid):
    sess, url, error = _upstream_target(sid)
    if error:
        return error
    headers = {**sess["headers"], "Accept-Encoding": "identity"}
    if request.headers.get("Range"):
        headers["Range"] = request.headers["Range"]
    try:
        resp = _http().get(url, headers=headers, timeout=_TIMEOUT, stream=True)
    except Exception as exc:
        return jsonify({"error": f"Upstream unreachable: {exc}"}), 502
    if resp.status_code >= 400:
        resp.close()
        return jsonify({"error": f"Upstream returned {resp.status_code}"}), 502

    out_headers = {k: resp.headers[k] for k in _PASS_HEADERS if resp.headers.get(k)}
    out_headers.setdefault("Accept-Ranges", "bytes")
    out_headers["Cache-Control"] = "private, max-age=3600"
    # Hosters disguise HLS segments as images (.jpg/.png); the browser only
    # cares that it gets bytes, but a wrong image/* type confuses nothing
    # worse than a generic one does.
    if out_headers.get("Content-Type", "").startswith("image/"):
        out_headers["Content-Type"] = "video/mp2t"

    def generate():
        try:
            for chunk in resp.iter_content(_CHUNK):
                if chunk:
                    yield chunk
        finally:
            resp.close()

    return Response(
        stream_with_context(generate()),
        status=resp.status_code,
        headers=out_headers,
        direct_passthrough=True,
    )
