"""Playback URLs for devices that can't log in: Chromecast / Android TV
(Google Cast) and Apple TV (AirPlay) fetch the stream themselves, so they
can't send the Authorization header /api/stream/files needs.

``POST /api/share`` (logged in) takes the path of a downloaded episode's
playlist as returned by /api/stream and hands out a short-lived capability
URL ``/api/share/<token>/<playlist>.m3u8``; the playlist's segments resolve
relative to it, under the same token. A token only ever serves .m3u8/.ts
files from that one episode's directory. Everything here (and the
direct-stream relay, live_stream.py) answers CORS requests, which the Cast
receiver's player needs.
"""

import os
import secrets
import threading
import time
from pathlib import Path
from urllib.parse import quote, unquote, urlsplit

from flask import Blueprint, abort, jsonify, request, send_from_directory

share_bp = Blueprint("share", __name__, url_prefix="/api/share")

TOKEN_SECONDS = 12 * 3600
_MAX_TOKENS = 500
_MIME = {".m3u8": "application/vnd.apple.mpegurl", ".ts": "video/mp2t"}
_FILES_PREFIX = "/api/stream/files/"

_tokens = {}
_lock = threading.Lock()


def add_cors_headers(resp):
    """CORS for media fetched by a Cast receiver (any origin, Range requests)."""
    resp.headers["Access-Control-Allow-Origin"] = "*"
    resp.headers["Access-Control-Allow-Methods"] = "GET, HEAD, OPTIONS"
    resp.headers["Access-Control-Allow-Headers"] = "Range, Content-Type"
    resp.headers["Access-Control-Expose-Headers"] = "Content-Length, Content-Range, Accept-Ranges"
    return resp


share_bp.after_request(add_cors_headers)


def _download_bases():
    """Same directories /api/stream/files serves from."""
    from .db import get_custom_paths

    raw = os.environ.get("ANIWORLD_DOWNLOAD_PATH", "")
    if raw:
        base = Path(raw).expanduser()
        if not base.is_absolute():
            base = Path.home() / base
    else:
        base = Path.home() / "Downloads"
    bases = [base]
    for cp in get_custom_paths():
        p = Path(cp["path"]).expanduser()
        bases.append(p if p.is_absolute() else Path.home() / p)
    return bases


def _locate(rel_path):
    """Absolute file for a path relative to a download base, or None."""
    for base in _download_bases():
        candidate = (base / rel_path).resolve()
        try:
            candidate.relative_to(base.resolve())
        except ValueError:
            continue
        if candidate.is_file():
            return candidate
    return None


@share_bp.route("", methods=["POST"])
def create():
    """Body: {path: "/api/stream/files/…/S01E001.m3u8"} → {url}."""
    data = request.get_json(silent=True) or {}
    path = urlsplit(str(data.get("path") or "")).path
    if not path.startswith(_FILES_PREFIX) or not path.lower().endswith(".m3u8"):
        return jsonify({"error": "path must be an /api/stream/files/… playlist"}), 400
    playlist = _locate(unquote(path[len(_FILES_PREFIX):]))
    if playlist is None:
        return jsonify({"error": "Episode not found"}), 404
    now = time.time()
    token = secrets.token_urlsafe(18)
    with _lock:
        for t in [t for t, v in _tokens.items() if v["expires"] < now]:
            del _tokens[t]
        if len(_tokens) >= _MAX_TOKENS:
            del _tokens[min(_tokens, key=lambda t: _tokens[t]["expires"])]
        _tokens[token] = {"dir": str(playlist.parent), "expires": now + TOKEN_SECONDS}
    return jsonify({"url": f"/api/share/{token}/{quote(playlist.name)}", "expires_in": TOKEN_SECONDS})


@share_bp.route("/<token>/<name>", methods=["GET", "HEAD"])
def serve(token, name):
    with _lock:
        entry = _tokens.get(token)
    if not entry or entry["expires"] < time.time():
        abort(404)
    ext = os.path.splitext(name)[1].lower()
    if ext not in _MIME or "/" in name or "\\" in name or name.startswith("."):
        abort(404)
    if not (Path(entry["dir"]) / name).is_file():
        abort(404)
    resp = send_from_directory(entry["dir"], name, mimetype=_MIME[ext], conditional=True)
    resp.headers["Cache-Control"] = "no-cache" if ext == ".m3u8" else "private, max-age=3600"
    return resp
