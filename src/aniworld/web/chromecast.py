"""Chromecast / Android TV / Google TV, cast by the server itself.

The phones' own Cast support only works where a Cast SDK exists (the
Android/iOS apps, Chrome on Android) — not in Safari, the iPhone home-screen
web app or Firefox. So the server, which sits in the same network as the
TV, does it: it finds Cast devices (mDNS, plus fixed addresses from
ANIWORLD_CAST_HOSTS for setups where multicast doesn't reach it, e.g. a
Kubernetes pod), lists them next to the RedStream screens in
/api/cast/screens (ids ``gc-<uuid>``) and executes the same commands
(web/cast.py) through Google's Default Media Receiver. The TV fetches the
stream itself: a /api/share URL for downloaded episodes, else the
direct-stream relay, both login-free.

Because the server drives the device, it also keeps the session going on its
own: saves progress for the sender's profile every 10 s and moves on to the
next episode 30 s before the end (like the TV web app's player), or when the
receiver reports the episode finished — no phone needs to stay open.

Env:
  ANIWORLD_CHROMECAST=0      switch off
  ANIWORLD_CAST_HOSTS        comma-separated IPs/hostnames of Cast devices
  ANIWORLD_CAST_BASE_URL     base URL the TV uses to reach this server
                             (default: the URL the sender used)
"""

import os
import re
import threading
import time
from pathlib import Path

from ..logger import get_logger

logger = get_logger(__name__)

ADVANCE_REMAINING_S = 30  # like the TV web app: 40 s window minus 10 s countdown
SAVE_EVERY_S = 10
_ID_PREFIX = "gc-"

_lock = threading.RLock()
_state = {"browser": None, "zconf": None, "started": False, "error": None}
_casts = {}  # uuid -> pychromecast.Chromecast
_sessions = {}  # uuid -> dict (what the server plays there)


def enabled():
    return os.environ.get("ANIWORLD_CHROMECAST", "1") != "0"


def is_chromecast_id(screen_id):
    return str(screen_id).startswith(_ID_PREFIX)


# ── Discovery ────────────────────────────────────────────────────────────────


def ensure_started():
    """Starts discovery once (lazily, on the first /api/cast/screens)."""
    with _lock:
        if _state["started"] or not enabled():
            return
        _state["started"] = True
    try:
        import zeroconf
        from pychromecast.discovery import CastBrowser, SimpleCastListener

        hosts = [h.strip() for h in os.environ.get("ANIWORLD_CAST_HOSTS", "").split(",") if h.strip()]
        zconf = zeroconf.Zeroconf()
        browser = CastBrowser(SimpleCastListener(), zconf, known_hosts=hosts or None)
        browser.start_discovery()
        _state.update(browser=browser, zconf=zconf)
        threading.Thread(target=_monitor, name="chromecast-monitor", daemon=True).start()
        logger.info("Chromecast discovery started (known hosts: %s)", hosts or "none")
    except Exception as exc:  # pychromecast missing, no network, …
        _state["error"] = str(exc)
        logger.warning("Chromecast discovery unavailable: %s", exc)


def _devices():
    browser = _state["browser"]
    if not browser:
        return {}
    try:
        return {str(k): v for k, v in dict(browser.devices).items()}
    except Exception:
        return {}


def _get_cast(uuid):
    import pychromecast

    with _lock:
        cast = _casts.get(uuid)
    if cast is not None and cast.socket_client.is_connected:
        return cast
    info = _devices().get(uuid)
    if info is None:
        raise RuntimeError("Gerät nicht gefunden")
    cast = pychromecast.get_chromecast_from_cast_info(info, _state["zconf"], tries=2, retry_wait=2, timeout=10)
    cast.wait(timeout=15)
    with _lock:
        _casts[uuid] = cast
    return cast


def _status(uuid):
    with _lock:
        cast = _casts.get(uuid)
    if cast is None:
        return None
    try:
        return cast.media_controller.status
    except Exception:
        return None


# ── Screens (for /api/cast/screens) ──────────────────────────────────────────


def _player_state(st):
    ps = (getattr(st, "player_state", None) or "").upper()
    return {"PLAYING": "playing", "PAUSED": "paused", "BUFFERING": "buffering"}.get(ps, "idle")


def screens(profile_names):
    if not enabled():
        return []
    ensure_started()
    out = []
    for uuid, info in _devices().items():
        session = _sessions.get(uuid)
        st = _status(uuid)
        state = {"status": "idle"}
        if session:
            item = session["item"]
            status = _player_state(st) if st else "loading"
            if session.get("loading"):
                status = "loading"
            state = {
                "status": status,
                "episode_url": item["episode_url"],
                "series_title": item.get("series_title"),
                "series_url": item.get("series_url"),
                "season": item.get("season"),
                "episode_number": item.get("episode_number"),
                "episode_title": item.get("episode_title"),
                "language": item.get("language"),
                "position": round(getattr(st, "adjusted_current_time", 0) or 0) if st else 0,
                "duration": round(getattr(st, "duration", 0) or 0) if st else 0,
            }
        profile_id = session.get("profile_id") if session else None
        out.append(
            {
                "id": _ID_PREFIX + uuid,
                "name": info.friendly_name or "Chromecast",
                "kind": "chromecast",
                "model": info.model_name,
                "profile_id": profile_id,
                "profile_name": profile_names.get(profile_id),
                "online": True,
                "seconds_since_seen": 0,
                "state": state,
            }
        )
    return out


# ── Stream URLs ──────────────────────────────────────────────────────────────


def _find_download(item):
    """Downloaded playlist for the episode, or None (same naming as /api/stream)."""
    from .share import _download_bases

    season, episode = int(item.get("season") or 0), int(item.get("episode_number") or 0)
    ep_re = re.compile(rf"S{season:02d}E{episode:03d}(?!\d)", re.IGNORECASE)
    titles = {t.lower() for t in [item.get("series_title") or "", item.get("_title_cleaned") or ""] if t}
    if not titles:
        return None
    for base in _download_bases():
        if not base.is_dir():
            continue
        for folder in base.iterdir():
            if not folder.is_dir() or not any(folder.name.lower().startswith(t) for t in titles):
                continue
            for f in folder.rglob("*.m3u8"):
                if ep_re.search(f.name):
                    return f
    return None


def _stream(item):
    """(path, content_type) of a login-free stream for the episode."""
    from .live_stream import _probe_kind, _proxy_url, create_session
    from .share import share_playlist

    playlist = _find_download(item)
    if playlist is None and item.get("series_url") and not item.get("_title_cleaned"):
        # Download folders are named after the site's cleaned title, which can
        # differ from the display title the sender knows.
        try:
            from ..providers import resolve_provider as _rp

            item["_title_cleaned"] = getattr(_rp(item["series_url"]).series_cls(url=item["series_url"]), "title_cleaned", None)
            playlist = _find_download(item)
        except Exception:
            pass
    if playlist is not None:
        return share_playlist(playlist), "application/x-mpegurl"

    from ..models.common.common import resolve_live_stream
    from ..providers import resolve_provider

    prov = resolve_provider(item["episode_url"])
    kwargs = {"url": item["episode_url"]}
    if item.get("language"):
        kwargs["selected_language"] = item["language"]
    if item.get("provider"):
        kwargs["selected_provider"] = item["provider"]
    stream = resolve_live_stream(prov.episode_cls(**kwargs))
    kind = _probe_kind(stream["url"], stream["headers"])
    sid = create_session(stream["url"], stream["headers"], stream["provider"])
    if kind == "hls":
        return _proxy_url(sid, "playlist", stream["url"]), "application/x-mpegurl"
    return _proxy_url(sid, "media", stream["url"]), "video/mp4"


def _next_episode(item):
    """The episode after `item` in its season (same fields), or None."""
    from ..providers import resolve_provider

    series_url = item.get("series_url")
    if not series_url:
        return None
    prov = resolve_provider(series_url)
    series = prov.series_cls(url=series_url)
    season = next((s for s in series.seasons if s.season_number == item.get("season")), None)
    if season is None:
        return None
    eps = list(season.episodes)
    idx = next((i for i, e in enumerate(eps) if e.url == item["episode_url"] or e.episode_number == item.get("episode_number")), -1)
    if idx < 0 or idx + 1 >= len(eps):
        return None
    n = eps[idx + 1]
    nxt = {k: v for k, v in item.items() if k in ("series_title", "series_url", "season", "language")}
    nxt.update(
        episode_url=n.url,
        episode_number=n.episode_number,
        episode_title=(getattr(n, "title_de", "") or getattr(n, "title_en", "") or None),
        _title_cleaned=getattr(series, "title_cleaned", None),
    )
    return nxt


# ── Playback ─────────────────────────────────────────────────────────────────


def _save(session, position, duration, completed=False):
    from .db import upsert_watch_progress

    item = session["item"]
    try:
        upsert_watch_progress(
            episode_url=item["episode_url"],
            series_title=item.get("series_title"),
            series_url=item.get("series_url"),
            season=int(item.get("season") or 0),
            episode_number=int(item.get("episode_number") or 0),
            episode_title=item.get("episode_title"),
            position_seconds=float(position),
            duration_seconds=float(duration),
            completed=completed or (duration > 0 and position / duration >= 0.9),
            profile_id=session.get("profile_id") or 1,
        )
    except Exception as exc:
        logger.debug("Chromecast progress save failed: %s", exc)


def _resume_position(item, profile_id):
    from .db import get_watch_progress

    try:
        p = get_watch_progress(item["episode_url"], profile_id=profile_id or 1)
    except Exception:
        return 0
    if not p or p.get("completed"):
        return 0
    pos, dur = float(p.get("position_seconds") or 0), float(p.get("duration_seconds") or 0)
    return pos if 30 < pos < dur - 10 else 0


def _play(uuid, item, profile_id, base_url, start=None):
    """Resolves and starts `item` on the device (blocking, call in a thread)."""
    session = {"item": item, "profile_id": profile_id, "base_url": base_url, "loading": True, "advanced": False, "last_save": 0}
    with _lock:
        _sessions[uuid] = session
    try:
        path, content_type = _stream(item)
        url = base_url.rstrip("/") + path
        cast = _get_cast(uuid)
        subtitle = "S%02dE%02d" % (int(item.get("season") or 0), int(item.get("episode_number") or 0))
        if item.get("episode_title"):
            subtitle += " · " + item["episode_title"]
        cast.media_controller.play_media(
            url,
            content_type,
            title=item.get("series_title") or subtitle,
            current_time=start if start is not None else _resume_position(item, profile_id),
            stream_type="BUFFERED",
            metadata={"metadataType": 2, "seriesTitle": item.get("series_title") or "", "title": subtitle},
            # Our HLS (downloads and most hosters) is MPEG-TS.
            media_info={"hlsSegmentFormat": "ts", "hlsVideoSegmentFormat": "mpeg2_ts"} if "mpegurl" in content_type else None,
        )
        session["content_id"] = url
        session["started_at"] = time.time()
        logger.info("Chromecast %s: playing %s", uuid, item["episode_url"])
    except Exception as exc:
        logger.warning("Chromecast %s: could not play %s: %s", uuid, item.get("episode_url"), exc)
        session["error"] = str(exc)
        with _lock:
            if _sessions.get(uuid) is session:
                del _sessions[uuid]
    finally:
        session["loading"] = False


def _advance(uuid, session):
    """Finishes the current episode and starts the next one (thread)."""
    item = session["item"]
    st = _status(uuid)
    duration = getattr(st, "duration", 0) or 0
    _save(session, duration, duration, completed=True)
    try:
        nxt = _next_episode(item)
    except Exception as exc:
        logger.warning("Chromecast %s: next episode lookup failed: %s", uuid, exc)
        nxt = None
    if nxt is None:
        return
    _play(uuid, nxt, session.get("profile_id"), session["base_url"], start=0)


def _monitor():
    """Progress saving + auto-advance for every device the server plays on."""
    while True:
        time.sleep(1)
        with _lock:
            items = list(_sessions.items())
        for uuid, session in items:
            if session.get("loading") or session.get("advanced"):
                continue
            st = _status(uuid)
            if st is None:
                continue
            # Someone else (another app) took over the device: forget it.
            if session.get("content_id") and st.content_id and st.content_id != session["content_id"]:
                with _lock:
                    if _sessions.get(uuid) is session:
                        del _sessions[uuid]
                continue
            state = (st.player_state or "").upper()
            duration = st.duration or 0
            position = st.adjusted_current_time or 0
            if state == "PLAYING" and time.time() - session["last_save"] >= SAVE_EVERY_S and duration > 0:
                session["last_save"] = time.time()
                _save(session, position, duration)
            finished = state == "IDLE" and (st.idle_reason or "").upper() == "FINISHED"
            near_end = state == "PLAYING" and duration > 60 and duration - position <= ADVANCE_REMAINING_S
            if (finished or near_end) and time.time() - session.get("started_at", 0) > 20:
                session["advanced"] = True
                threading.Thread(target=_advance, args=(uuid, session), daemon=True).start()


# ── Commands (from /api/cast/screens/<id>/command) ───────────────────────────


def command(screen_id, data, profile_id, base_url):
    """Runs a cast command on a Chromecast; returns an error string or None."""
    uuid = str(screen_id)[len(_ID_PREFIX):]
    if uuid not in _devices():
        return "Gerät nicht gefunden"
    kind = data.get("type")
    if kind == "play":
        item = {
            k: data.get(k)
            for k in ("episode_url", "series_title", "series_url", "season", "episode_number", "episode_title", "language", "provider")
        }
        base = os.environ.get("ANIWORLD_CAST_BASE_URL", "").strip() or base_url
        threading.Thread(target=_play, args=(uuid, item, profile_id, base), daemon=True).start()
        return None
    try:
        cast = _get_cast(uuid)
        mc = cast.media_controller
        st = mc.status
        if kind == "pause":
            mc.pause()
        elif kind == "resume":
            mc.play()
        elif kind == "toggle":
            mc.pause() if (st.player_state or "").upper() == "PLAYING" else mc.play()
        elif kind == "seek":
            target = data.get("position")
            if target is None:
                target = (st.adjusted_current_time or 0) + float(data.get("delta") or 0)
            mc.seek(max(0.0, float(target)))
        elif kind == "stop":
            session = _sessions.pop(uuid, None)
            if session:
                _save(session, st.adjusted_current_time or 0, st.duration or 0)
            mc.stop()
    except Exception as exc:
        return f"Chromecast nicht erreichbar: {exc}"
    return None
