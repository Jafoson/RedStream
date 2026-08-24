"""Access-request gate for the Flutter *web* build.

The web build never shows a username/password form. Instead a fresh browser
asks for access, an admin approves or denies it from the server terminal
(`aniworld --web-requests` / `--web-approve` / `--web-deny`), and once
approved the browser receives a bearer token exactly like the desktop app
gets from `/api/auth/login` — it just never had to know a password.
"""

import secrets

from flask import Blueprint, jsonify, request

from .db import create_web_access_request, get_web_access_request

webapp_bp = Blueprint("webapp", __name__, url_prefix="/api/webapp")


@webapp_bp.route("/request-access", methods=["POST"])
def request_access():
    device_id = secrets.token_urlsafe(24)
    ip_address = (request.headers.get("X-Forwarded-For", "") or request.remote_addr or "").split(
        ","
    )[0].strip()
    user_agent = (request.user_agent.string or "")[:256]
    create_web_access_request(device_id, ip_address, user_agent)
    return jsonify({"device_id": device_id, "status": "pending"})


@webapp_bp.route("/request-access/<device_id>")
def request_access_status(device_id):
    row = get_web_access_request(device_id)
    if not row:
        return jsonify({"error": "Unknown request"}), 404
    payload = {"status": row["status"]}
    if row["status"] == "approved" and row["token"]:
        payload["token"] = row["token"]
    return jsonify(payload)
