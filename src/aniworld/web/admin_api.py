"""JSON API behind the TV web app's admin dashboard (/verwaltung).

Every route here requires an ``X-Admin-Token`` header holding a live admin
session token — issued only after a terminal approval of an ``admin`` access
request (see webapp_auth.py / db.approve_web_access_request). A normal web
app bearer token is not enough, and an admin token is useless anywhere else.
"""

from flask import Blueprint, g, jsonify, request

from .db import (
    approve_web_access_request,
    delete_watch_progress_entry,
    delete_watch_progress_for_series,
    deny_web_access_request,
    get_profiles,
    get_watch_history,
    get_watch_history_series,
    get_watch_stats_by_profile,
    get_web_access_request_by_id,
    list_web_access_requests,
    revoke_web_access_request,
    validate_admin_token,
)

admin_bp = Blueprint("admin_api", __name__, url_prefix="/api/admin")

_MAX_PAGE = 200


@admin_bp.before_request
def _require_admin_session():
    session_row = validate_admin_token(request.headers.get("X-Admin-Token", "").strip())
    if not session_row:
        return jsonify({"error": "Admin session required"}), 401
    g.admin_session = session_row


@admin_bp.route("/session")
def session_info():
    return jsonify(
        {
            "id": g.admin_session["id"],
            "approved_at": g.admin_session["decided_at"],
            "ip_address": g.admin_session["ip_address"],
        }
    )


@admin_bp.route("/logout", methods=["POST"])
def logout():
    revoke_web_access_request(g.admin_session["id"])
    return jsonify({"ok": True})


# ── Access requests ──────────────────────────────────────────────────────────


@admin_bp.route("/access-requests")
def access_requests():
    return jsonify(
        {
            "requests": list_web_access_requests(),
            "current_session_id": g.admin_session["id"],
        }
    )


_ACTIONS = ("approve", "deny", "revoke")


def _apply(request_id, action):
    """Run one decision; returns (http_status, error_or_None)."""
    row = get_web_access_request_by_id(request_id)
    if not row:
        return 404, "Request not found."
    # Granting admin rights stays terminal-only, otherwise anyone holding an
    # admin session could mint further ones without the server owner noticing.
    if action == "approve" and row["kind"] == "admin":
        return 403, "Admin access can only be approved in the server terminal."
    if action == "approve":
        ok, err, _info = approve_web_access_request(request_id)
    elif action == "deny":
        ok, err = deny_web_access_request(request_id)
    else:
        ok, err = revoke_web_access_request(request_id)
    return (200, None) if ok else (409, err)


def _decide(request_id, action):
    status, err = _apply(request_id, action)
    if err:
        return jsonify({"error": err}), status
    return jsonify({"ok": True})


@admin_bp.route("/access-requests/bulk", methods=["POST"])
def bulk_decide():
    """Apply one action to several requests: {"ids": [..], "action": "..."}.

    Each id is handled on its own; the response lists which succeeded and why
    the others didn't, instead of failing the whole batch on the first one.
    """
    data = request.get_json(silent=True) or {}
    action = data.get("action")
    ids = data.get("ids")
    if action not in _ACTIONS or not isinstance(ids, list) or not ids:
        return jsonify({"error": "ids (list) and a valid action are required"}), 400
    done, failed = [], []
    for raw_id in ids[:500]:
        try:
            request_id = int(raw_id)
        except (TypeError, ValueError):
            failed.append({"id": raw_id, "error": "Invalid id."})
            continue
        _status, err = _apply(request_id, action)
        if err:
            failed.append({"id": request_id, "error": err})
        else:
            done.append(request_id)
    return jsonify({"done": done, "failed": failed})


@admin_bp.route("/access-requests/<int:request_id>/approve", methods=["POST"])
def approve(request_id):
    return _decide(request_id, "approve")


@admin_bp.route("/access-requests/<int:request_id>/deny", methods=["POST"])
def deny(request_id):
    return _decide(request_id, "deny")


@admin_bp.route("/access-requests/<int:request_id>/revoke", methods=["POST"])
def revoke(request_id):
    return _decide(request_id, "revoke")


# ── Profiles & watch history ─────────────────────────────────────────────────


@admin_bp.route("/profiles")
def profiles():
    stats = get_watch_stats_by_profile()
    empty = {"entries": 0, "completed": 0, "last_watched": None}
    return jsonify(
        {"profiles": [{**p, **stats.get(p["id"], empty)} for p in get_profiles()]}
    )


def _page_args():
    limit = max(1, min(request.args.get("limit", 50, type=int), _MAX_PAGE))
    offset = max(0, request.args.get("offset", 0, type=int))
    return limit, offset


@admin_bp.route("/history")
def history():
    profile_id = request.args.get("profile_id", type=int)
    query = (request.args.get("q") or "").strip() or None
    series_url = (request.args.get("series_url") or "").strip() or None
    sort = request.args.get("sort", "recent")
    limit, offset = _page_args()
    rows, total = get_watch_history(
        profile_id, query, limit, offset, series_url=series_url, sort=sort
    )
    return jsonify({"entries": rows, "total": total})


@admin_bp.route("/history/series")
def history_series():
    profile_id = request.args.get("profile_id", type=int)
    query = (request.args.get("q") or "").strip() or None
    sort = request.args.get("sort", "recent")
    limit, offset = _page_args()
    groups, total = get_watch_history_series(profile_id, query, sort, limit, offset)
    return jsonify({"series": groups, "total": total})


@admin_bp.route("/history/<int:entry_id>", methods=["DELETE"])
def delete_history_entry(entry_id):
    if not delete_watch_progress_entry(entry_id):
        return jsonify({"error": "Entry not found."}), 404
    return jsonify({"ok": True})


@admin_bp.route("/history", methods=["DELETE"])
def delete_history_series():
    profile_id = request.args.get("profile_id", type=int)
    series_url = (request.args.get("series_url") or "").strip()
    if profile_id is None or not series_url:
        return jsonify({"error": "profile_id and series_url are required"}), 400
    deleted = delete_watch_progress_for_series(profile_id, series_url)
    return jsonify({"ok": True, "deleted": deleted})
