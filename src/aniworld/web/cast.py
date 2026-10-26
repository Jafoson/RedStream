"""Auf TV abspielen: remote-control a browser running the TV web app.

Every TV web app tab that has screen mode on (Settings → Bildschirm) sends a
heartbeat every ~1.5 s: its name, active profile and what it's playing. The
Android app lists the screens that are online and queues commands for one
(play an episode, pause/resume, seek, stop); the screen picks them up with
its next heartbeat. Everything lives in memory: after a server restart the
screens simply re-register with their next heartbeat.
"""

import secrets
import threading
import time

from flask import Blueprint, jsonify, request

cast_bp = Blueprint("cast", __name__, url_prefix="/api/cast")

ONLINE_SECONDS = 10       # no heartbeat for this long -> screen is offline
FORGET_SECONDS = 3600     # ... and is dropped entirely after this
COMMAND_TTL = 30          # a command not picked up within this is discarded
MAX_QUEUE = 20

COMMAND_TYPES = {"play", "pause", "resume", "toggle", "seek", "stop"}

_screens = {}
_lock = threading.Lock()


def _profile_id():
    raw = request.headers.get("X-Profile-ID", "").strip()
    try:
        return int(raw) if raw else None
    except ValueError:
        return None


def _prune(now):
    for sid in [s for s, v in _screens.items() if now - v["last_seen"] > FORGET_SECONDS]:
        del _screens[sid]


def _public(screen_id, screen, now, profiles):
    return {
        "id": screen_id,
        "name": screen["name"],
        "profile_id": screen["profile_id"],
        "profile_name": profiles.get(screen["profile_id"]),
        "online": now - screen["last_seen"] <= ONLINE_SECONDS,
        "seconds_since_seen": round(now - screen["last_seen"], 1),
        "state": screen["state"],
    }


@cast_bp.route("/heartbeat", methods=["POST"])
def heartbeat():
    """Screen side. Body: {screen_id?, name, state} → {screen_id, commands}.

    An unknown or missing screen_id registers a new screen (the browser keeps
    the returned id). Queued commands are handed out exactly once.
    """
    data = request.get_json(silent=True) or {}
    now = time.time()
    name = (str(data.get("name") or "").strip() or "Bildschirm")[:60]
    state = data.get("state") if isinstance(data.get("state"), dict) else {}
    screen_id = str(data.get("screen_id") or "")
    with _lock:
        _prune(now)
        screen = _screens.get(screen_id)
        if screen is None:
            screen_id = secrets.token_urlsafe(9)
            screen = _screens[screen_id] = {"queue": []}
        screen.update(
            name=name,
            profile_id=_profile_id(),
            state=state,
            last_seen=now,
            user_agent=(request.user_agent.string or "")[:200],
        )
        commands = [c for c in screen["queue"] if now - c["ts"] <= COMMAND_TTL]
        screen["queue"] = []
    return jsonify({"screen_id": screen_id, "commands": commands})


@cast_bp.route("/screens/<screen_id>", methods=["DELETE"])
def unregister(screen_id):
    """Screen side: screen mode switched off / tab closing."""
    with _lock:
        _screens.pop(screen_id, None)
    return jsonify({"ok": True})


@cast_bp.route("/screens")
def screens():
    """Controller side: every screen that's online, newest heartbeat first."""
    from .db import get_profiles

    profiles = {p["id"]: p["name"] for p in get_profiles()}
    now = time.time()
    with _lock:
        _prune(now)
        listed = [
            _public(sid, s, now, profiles)
            for sid, s in _screens.items()
            if now - s["last_seen"] <= ONLINE_SECONDS
        ]
    listed.sort(key=lambda s: s["seconds_since_seen"])
    return jsonify({"screens": listed})


@cast_bp.route("/screens/<screen_id>/command", methods=["POST"])
def command(screen_id):
    """Controller side. Body: {type, ...}.

    - play:   episode_url, series_title, series_url, season, episode_number
              (+ episode_title, language, provider, absolute_episode_number);
              the sender's X-Profile-ID becomes the profile it plays under.
    - seek:   position (seconds) or delta (seconds, may be negative)
    - pause / resume / toggle / stop: no payload
    """
    data = request.get_json(silent=True) or {}
    kind = data.get("type")
    if kind not in COMMAND_TYPES:
        return jsonify({"error": f"type must be one of {sorted(COMMAND_TYPES)}"}), 400
    if kind == "play":
        missing = [k for k in ("episode_url", "series_url", "season", "episode_number") if data.get(k) in (None, "")]
        if missing:
            return jsonify({"error": f"missing for play: {', '.join(missing)}"}), 400
    if kind == "seek" and data.get("position") is None and data.get("delta") is None:
        return jsonify({"error": "seek needs position or delta"}), 400

    cmd = {k: v for k, v in data.items() if k != "type"}
    cmd.update(type=kind, id=secrets.token_hex(6), ts=time.time())
    if kind == "play":
        cmd["profile_id"] = _profile_id()
    now = time.time()
    with _lock:
        screen = _screens.get(screen_id)
        if not screen or now - screen["last_seen"] > ONLINE_SECONDS:
            return jsonify({"error": "Screen is offline"}), 404
        screen["queue"] = (screen["queue"] + [cmd])[-MAX_QUEUE:]
    return jsonify({"ok": True, "id": cmd["id"]})
