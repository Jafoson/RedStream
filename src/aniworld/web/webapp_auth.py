"""Access-request gate for the Flutter *web* build.

The web build never shows a username/password form. Instead a fresh browser
asks for access, an admin approves or denies it from the server terminal
(`aniworld --web-requests` / `--web-approve` / `--web-deny`), and once
approved the browser receives a bearer token exactly like the desktop app
gets from `/api/auth/login` — it just never had to know a password.
"""

import secrets

from flask import Blueprint, jsonify, request

from .db import (
    create_web_access_request,
    get_web_access_request,
    pick_up_admin_token,
    validate_api_token,
)

webapp_bp = Blueprint("webapp", __name__, url_prefix="/api/webapp")


def _client_info():
    ip_address = (request.headers.get("X-Forwarded-For", "") or request.remote_addr or "").split(
        ","
    )[0].strip()
    return ip_address, (request.user_agent.string or "")[:256]


@webapp_bp.route("/request-access", methods=["POST"])
def request_access():
    device_id = secrets.token_urlsafe(24)
    ip_address, user_agent = _client_info()
    code = create_web_access_request(device_id, ip_address, user_agent)
    return jsonify({"device_id": device_id, "status": "pending", "code": code})


@webapp_bp.route("/request-access/<device_id>")
def request_access_status(device_id):
    row = get_web_access_request(device_id)
    if not row:
        return jsonify({"error": "Unknown request"}), 404
    payload = {"status": row["status"]}
    if row["status"] == "approved" and row["token"]:
        payload["token"] = row["token"]
    return jsonify(payload)


# ── Admin dashboard gate ─────────────────────────────────────────────────────
# Second, separate approval on top of the one above: only a browser that is
# already let into the web app may ask, and the admin has to approve it from
# the server terminal again (`aniworld --web-approve <id>`). The resulting
# admin token only works for /api/admin/* (see admin_api.py) and expires.


def _bearer_user():
    auth_header = request.headers.get("Authorization", "")
    if not auth_header.startswith("Bearer "):
        return None
    return validate_api_token(auth_header[7:].strip())


@webapp_bp.route("/admin-access", methods=["POST"])
def request_admin_access():
    if not _bearer_user():
        return jsonify({"error": "Web app access required"}), 401
    device_id = secrets.token_urlsafe(24)
    ip_address, user_agent = _client_info()
    code = create_web_access_request(device_id, ip_address, user_agent, kind="admin")
    return jsonify({"device_id": device_id, "status": "pending", "code": code})


@webapp_bp.route("/admin-access/<device_id>")
def admin_access_status(device_id):
    if not _bearer_user():
        return jsonify({"error": "Web app access required"}), 401
    row = get_web_access_request(device_id, kind="admin")
    if not row:
        return jsonify({"error": "Unknown request"}), 404
    payload = {"status": row["status"]}
    if row["status"] == "approved":
        token = pick_up_admin_token(device_id)
        if token:
            payload["token"] = token
            payload["expires_at"] = row["expires_at"]
        else:
            # Already handed out once; the browser that holds it keeps it.
            payload["status"] = "used"
    return jsonify(payload)
