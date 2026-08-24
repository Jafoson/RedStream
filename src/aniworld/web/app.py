import json
import os
import re
import threading
import time

import requests
from flask import Flask, g, jsonify, redirect, render_template, request, url_for
from flask_wtf.csrf import CSRFProtect

from ..config import (
    LANG_KEY_MAP,
    LANG_LABELS,
    SUPPORTED_PROVIDERS,
    get_provider_fallback_order,
    parse_provider_order,
)
from ..extractors import provider_functions
from ..logger import get_logger
from ..providers import resolve_provider
from . import download_worker
from ..search import (
    SERIES_GENRES,
    fetch_all_animes,
    fetch_all_series,
    fetch_new_animes,
    fetch_new_series,
    fetch_popular_animes,
    fetch_popular_movies,
    fetch_popular_series,
    fetch_series_genre_slugs,
    query_megakino,
    query_s_to,
    random_anime,
)
from ..search import query as aniworld_query
from .tmdb import search_tmdb
from .db import (
    add_autosync_job,
    add_custom_path,
    add_to_queue,
    add_to_watchlist,
    clear_completed,
    clear_series_language,
    create_api_token,
    create_profile,
    delete_api_token,
    delete_profile,
    find_autosync_by_url,
    find_queue_item_by_episode,
    get_all_watch_progress,
    get_autosync_job,
    get_autosync_jobs,
    get_continue_watching,
    get_custom_path_by_id,
    get_custom_paths,
    get_episode_progress_for_urls,
    get_general_stats,
    get_profiles,
    get_queue,
    get_queue_item,
    get_queue_stats,
    get_series_language,
    get_sync_stats,
    get_watch_progress,
    get_watch_progress_for_series,
    get_watchlist,
    get_watchlist_enriched,
    init_autosync_db,
    init_custom_paths_db,
    init_profiles_db,
    init_queue_db,
    init_series_language_prefs_db,
    init_watch_progress_db,
    init_watchlist_db,
    is_episode_completed_for_all_profiles,
    is_in_watchlist,
    is_queue_cancelled,
    is_series_queued_or_running,
    move_queue_item,
    remove_autosync_job,
    remove_custom_path,
    remove_from_queue,
    remove_from_watchlist,
    request_cancel,
    set_captcha_url,
    clear_captcha_url,
    set_queue_status,
    set_series_language,
    update_autosync_job,
    update_profile,
    update_queue_errors,
    update_queue_progress,
    upsert_watch_progress,
    validate_api_token,
)

logger = get_logger(__name__)


def _get_working_providers():
    """Return only providers whose extractors are actually implemented."""
    working = []
    for p in SUPPORTED_PROVIDERS:
        func_name = f"get_direct_link_from_{p.lower()}"
        if func_name not in provider_functions:
            continue
        try:
            provider_functions[func_name]("")
        except NotImplementedError:
            continue
        except Exception:
            working.append(p)
    return tuple(working)


WORKING_PROVIDERS = _get_working_providers()

ANIWORLD_LANGUAGE_BADGE_ORDER = (
    "German Dub",
    "German Sub",
    "English Dub",
    "English Sub",
)

STO_LANGUAGE_BADGE_ORDER = (
    "German Dub",
    "English Dub",
)


def _episode_language_labels(provider_data):
    labels = []
    seen = set()

    if hasattr(provider_data, "_data"):
        lang_tuple_to_label = {}
        for key, (audio, subtitles) in LANG_KEY_MAP.items():
            label = LANG_LABELS.get(key)
            if label:
                lang_tuple_to_label[(audio.value, subtitles.value)] = label

        for (audio, subtitles), providers in provider_data._data.items():
            label = lang_tuple_to_label.get((audio.value, subtitles.value))
            if not label or label in seen or not providers:
                continue
            labels.append(label)
            seen.add(label)

        order = ANIWORLD_LANGUAGE_BADGE_ORDER
    else:
        sto_label_map = {
            ("German", "None"): "German Dub",
            ("English", "None"): "English Dub",
        }
        for (audio, subtitles), providers in provider_data.items():
            label = sto_label_map.get((audio.value, subtitles.value))
            if not label or label in seen or not providers:
                continue
            labels.append(label)
            seen.add(label)

        order = STO_LANGUAGE_BADGE_ORDER

    sort_order = {label: index for index, label in enumerate(order)}
    labels.sort(key=lambda label: (sort_order.get(label, len(sort_order)), label))
    return labels


def _megakino_seasons(prov, url):
    """MegaKino has no seasons: a movie is one item, a serial lists every
    episode on one page. Surface either as a single synthetic season so the
    existing series -> season -> episode navigation works unchanged."""
    if "/serials/" in url.lower():
        try:
            episode = prov.episode_cls(url=url, selected_language="German Dub")
            if episode.is_series:
                return [
                    {
                        "url": url,
                        "season_number": 1,
                        "episode_count": len(episode.series_episodes),
                        "are_movies": False,
                    }
                ]
        except Exception as e:
            logger.warning(f"MegaKino series detection failed: {e}")

    return [{"url": url, "season_number": 1, "episode_count": 1, "are_movies": True}]


def _megakino_episodes(prov, url):
    episode = prov.episode_cls(url=url, selected_language="German Dub")

    if episode.is_series:
        return [
            {
                "url": f"{url}#mkep={entry['number']}",
                "episode_number": entry["number"],
                "title_de": entry["label"] or f"Episode {entry['number']}",
                "title_en": "",
                "downloaded": False,
                "available_languages": ["German Dub"] if entry["providers"] else [],
                "watch_position": 0,
                "watch_duration": 0,
                "is_watched": False,
                "preview_url": None,
            }
            for entry in episode.series_episodes
        ]

    try:
        languages = _episode_language_labels(episode.provider_data)
    except Exception as e:
        logger.warning(f"MegaKino language detection failed: {e}")
        languages = ["German Dub"]

    return [
        {
            "url": url,
            "episode_number": 1,
            "title_de": getattr(episode, "title_cleaned", None) or episode.title,
            "title_en": "",
            "downloaded": False,
            "available_languages": languages,
            "watch_position": 0,
            "watch_duration": 0,
            "is_watched": False,
            "preview_url": None,
        }
    ]


# series url -> {season_number: episodes_before_this_season}. Long-running
# shows split across many AniWorld "seasons" (e.g. One Piece arcs) need this
# to show an absolute episode number; computing it costs one page fetch per
# season, so it's cached for the process lifetime once resolved.
_absolute_ep_cache: dict = {}


def _cumulative_before_map(series):
    key = getattr(series, "url", None)
    if not key:
        return {}
    if key in _absolute_ep_cache:
        return _absolute_ep_cache[key]
    cumulative = {}
    try:
        total = 0
        for s in series.seasons:
            if getattr(s, "are_movies", False):
                continue
            cumulative[s.season_number] = total
            total += s.episode_count or 0
    except Exception as e:
        logger.warning(f"Absolute episode numbering failed for {key}: {e}")
        cumulative = {}
    _absolute_ep_cache[key] = cumulative
    return cumulative


# Only match series-level links: /anime/stream/<slug> (no season/episode)
_SERIES_LINK_PATTERN = re.compile(r"^/anime/stream/[a-zA-Z0-9\-]+/?$", re.IGNORECASE)

# Only match serienstream.to series-level links: /serie/<slug> (no season/episode)
_STO_SERIES_LINK_PATTERN = re.compile(
    r"^/serie/(stream/)?[a-zA-Z0-9\-]+/?$", re.IGNORECASE
)


# Auto-sync worker state
_autosync_worker_started = False

# Track jobs currently being synced to prevent duplicate runs
_syncing_jobs = set()
_syncing_jobs_lock = threading.Lock()

# Schedule intervals in seconds
SYNC_SCHEDULE_MAP = {
    "1min": 60,
    "30min": 1800,
    "1h": 3600,
    "2h": 7200,
    "4h": 14400,
    "8h": 28800,
    "12h": 43200,
    "16h": 57600,
    "24h": 86400,
}

_PUBLIC_IP_LOOKUP_URLS = (
    "https://api.ipify.org?format=json",
    "https://ifconfig.me/all.json",
)


def _fetch_public_ip():
    """Resolve the current public IP address of the running container."""
    last_error = None
    headers = {"User-Agent": "AniWorld Downloader"}
    for url in _PUBLIC_IP_LOOKUP_URLS:
        try:
            resp = requests.get(url, headers=headers, timeout=5)
            resp.raise_for_status()
            data = resp.json()
            ip = (data.get("ip") or data.get("ip_addr") or "").strip()
            if ip:
                return {"ip": ip, "source": url}
            last_error = "No IP address returned by upstream service"
        except requests.RequestException as exc:
            last_error = str(exc)
        except ValueError as exc:
            last_error = f"Invalid response: {exc}"
    raise RuntimeError(last_error or "Failed to resolve public IP")



def _is_user_caught_up(series_url, last_ep):
    """Return True if the user has watched (≥80 %) or completed *last_ep*."""
    # Primary: look up by exact episode URL
    progress_map = get_episode_progress_for_urls([last_ep.url])
    prog = progress_map.get(last_ep.url)
    if prog:
        if prog.get("completed"):
            return True
        dur = prog.get("duration_seconds", 0)
        if dur > 0 and prog.get("position_seconds", 0) / dur >= 0.8:
            return True

    # Fallback: match by (series_url, season, episode_number) in case the URL changed
    last_season = last_ep.season.season_number
    last_ep_num = last_ep.episode_number
    for p in get_watch_progress_for_series(series_url):
        if p.get("season") == last_season and p.get("episode_number") == last_ep_num:
            if p.get("completed"):
                return True
            dur = p.get("duration_seconds", 0)
            if dur > 0 and p.get("position_seconds", 0) / dur >= 0.8:
                return True

    return False


def _run_autosync_for_job(job):
    """Queue newly released episodes when the user is caught up with the series."""
    from datetime import datetime

    job_id = job["id"]
    with _syncing_jobs_lock:
        if job_id in _syncing_jobs:
            logger.info("Auto-sync skipped job %d — already running", job_id)
            return
        _syncing_jobs.add(job_id)

    try:
        prov = resolve_provider(job["series_url"])
        series = prov.series_cls(url=job["series_url"])

        # Collect all episodes in season order (stable index for tracking)
        all_seasons = series.seasons
        season_count = len(all_seasons)
        all_episodes = []
        for season in all_seasons:
            season_obj = prov.season_cls(url=season.url, series=series)
            for ep in season_obj.episodes:
                all_episodes.append(ep)

        current_count = len(all_episodes)
        queued_up_to = job.get("episodes_queued_up_to", 0)
        now_str = datetime.utcnow().strftime("%Y-%m-%d %H:%M:%S")

        update_fields = {
            "last_check": now_str,
            "episodes_found": current_count,
            "seasons_found": season_count,
        }

        # First run: record baseline so we know what was available when tracking started.
        # Don't queue anything — we only act on episodes that appear *after* this point.
        if queued_up_to == 0:
            logger.info(
                "Auto-sync '%s': first run, baseline = %d episodes, %d season(s).",
                job.get("title", "?"), current_count, season_count,
            )
            update_fields["episodes_queued_up_to"] = current_count
            update_fields["seasons_queued_up_to"] = season_count
            update_autosync_job(job["id"], **update_fields)
            return

        # Nothing new since last check
        if current_count <= queued_up_to:
            update_autosync_job(job["id"], **update_fields)
            return

        # New episodes appeared — only queue them if the user is caught up
        new_episodes = all_episodes[queued_up_to:]
        last_baseline_ep = all_episodes[queued_up_to - 1]

        if not _is_user_caught_up(job["series_url"], last_baseline_ep):
            logger.info(
                "Auto-sync '%s': %d new episode(s) available but user hasn't watched "
                "S%02dE%02d yet — skipping.",
                job.get("title", "?"), len(new_episodes),
                last_baseline_ep.season.season_number, last_baseline_ep.episode_number,
            )
            update_autosync_job(job["id"], **update_fields)
            return

        # Build language list
        lang_folder_map = {
            "German Dub": "german-dub",
            "English Sub": "english-sub",
            "German Sub": "german-sub",
            "English Dub": "english-dub",
        }
        if job.get("language") == "All Languages":
            disable_eng_sub = os.environ.get("ANIWORLD_DISABLE_ENGLISH_SUB", "0") == "1"
            target_languages = [
                lang for lang in lang_folder_map
                if not (disable_eng_sub and lang == "English Sub")
            ]
        else:
            target_languages = [job["language"]]

        new_ep_urls = [ep.url for ep in new_episodes]
        total_queued = 0

        for target_lang in target_languages:
            if is_series_queued_or_running(job["series_url"], language=target_lang):
                logger.info(
                    "Auto-sync skipped '%s' (%s) — already queued/running",
                    job["title"], target_lang,
                )
                continue
            add_to_queue(
                title=job["title"],
                series_url=job["series_url"],
                episodes=new_ep_urls,
                language=target_lang,
                provider=job["provider"],
                username=job.get("added_by"),
                custom_path_id=job.get("custom_path_id"),
                source="sync:all_langs" if job.get("language") == "All Languages" else "sync",
            )
            total_queued += len(new_ep_urls)
            logger.info(
                "Auto-sync queued %d new episode(s) for '%s' (%s)",
                len(new_ep_urls), job["title"], target_lang,
            )

        if total_queued > 0:
            update_fields["last_new_found"] = now_str

        update_fields["episodes_queued_up_to"] = current_count
        update_autosync_job(job["id"], **update_fields)

    except Exception as e:
        logger.error("Auto-sync failed for '%s': %s", job.get("title", "?"), e)
        from datetime import datetime

        update_autosync_job(
            job["id"],
            last_check=datetime.utcnow().strftime("%Y-%m-%d %H:%M:%S"),
        )
    finally:
        with _syncing_jobs_lock:
            _syncing_jobs.discard(job_id)


def _autosync_worker():
    """Background thread that periodically syncs all enabled autosync jobs.

    Uses short-polling (every 10 s) and checks each job's last_check
    against the configured interval so that schedule changes take effect
    immediately instead of blocking in a long sleep.
    """
    from datetime import datetime, timedelta

    while True:
        try:
            schedule_key = os.environ.get("ANIWORLD_SYNC_SCHEDULE", "0")
            interval = SYNC_SCHEDULE_MAP.get(schedule_key, 0)
            if not interval:
                time.sleep(10)
                continue

            now = datetime.utcnow()
            jobs = get_autosync_jobs()
            for job in jobs:
                if not job.get("enabled"):
                    continue
                # Per-job check: only run if enough time has elapsed
                last_check = job.get("last_check")
                if last_check:
                    try:
                        last_dt = datetime.strptime(last_check, "%Y-%m-%d %H:%M:%S")
                    except (ValueError, TypeError):
                        last_dt = datetime.min
                    if now < last_dt + timedelta(seconds=interval):
                        continue
                _run_autosync_for_job(job)

            time.sleep(10)
        except Exception as e:
            logger.error("Auto-sync worker error: %s", e, exc_info=True)
            time.sleep(30)


def _ensure_autosync_worker():
    """Start the auto-sync worker thread once."""
    global _autosync_worker_started
    if _autosync_worker_started:
        return
    _autosync_worker_started = True
    thread = threading.Thread(target=_autosync_worker, daemon=True)
    thread.start()


def _get_version():
    try:
        from importlib.metadata import version

        return version("aniworld")
    except Exception:
        return ""


def _proxy_image_url(url: str) -> str:
    if not url:
        return url
    from urllib.parse import quote

    return f"/api/proxy-image?url={quote(url, safe='')}"


def create_app(auth_enabled=False, sso_enabled=False, force_sso=False, api_only=False):

    app = Flask(__name__)
    app_version = _get_version()

    # The Flutter web build ships baked into every image (see Dockerfile), but
    # serving it — and its device-approval API — is opt-out at runtime via env.
    webapp_enabled = os.environ.get("ANIWORLD_ENABLE_WEBAPP", "1") == "1"
    if webapp_enabled:
        from .webapp_auth import webapp_bp

        app.register_blueprint(webapp_bp)

    base_url = os.environ.get("ANIWORLD_WEB_BASE_URL", "").strip().rstrip("/")
    if base_url:
        from urllib.parse import urlparse

        parsed = urlparse(base_url)
        scheme = parsed.scheme or "https"
        host = parsed.netloc

        # WSGI middleware that overrides scheme/host before Flask sees the request
        _inner_wsgi = app.wsgi_app

        def _proxy_wsgi(environ, start_response):
            environ["wsgi.url_scheme"] = scheme
            if host:
                environ["HTTP_HOST"] = host
            return _inner_wsgi(environ, start_response)

        app.wsgi_app = _proxy_wsgi

    if auth_enabled:
        from .auth import (
            auth_bp,
            get_current_user,
            get_or_create_secret_key,
            init_oidc,
            login_required,
            refresh_session_role,
        )
        from .db import has_any_admin, init_db

        app.secret_key = get_or_create_secret_key()
        app.config["SESSION_COOKIE_HTTPONLY"] = True
        app.config["SESSION_COOKIE_SAMESITE"] = "Lax"
        if base_url.startswith("https"):
            app.config["SESSION_COOKIE_SECURE"] = True
        app.config["PERMANENT_SESSION_LIFETIME"] = 86400  # 24 hours

        csrf = CSRFProtect()

        init_db()
        app.register_blueprint(auth_bp)
        csrf.init_app(app)
        if webapp_enabled:
            csrf.exempt(webapp_bp)

        if sso_enabled:
            init_oidc(app, force_sso=force_sso)
        else:
            app.config["OIDC_ENABLED"] = False
            app.config["OIDC_DISPLAY_NAME"] = "SSO"
            app.config["OIDC_ADMIN_USER"] = None
            app.config["OIDC_ADMIN_SUBJECT"] = None
            app.config["FORCE_SSO"] = False

        @app.before_request
        def _check_setup():
            if request.endpoint and request.endpoint.startswith("auth."):
                return None
            if request.endpoint == "static":
                return None
            if request.path.startswith("/api/"):
                return None  # API routes handle their own auth via login_required
            if not app.config.get("FORCE_SSO", False) and not has_any_admin():
                return redirect(url_for("auth.setup"))
            return None

        @app.before_request
        def _refresh_role():
            return refresh_session_role()

        @app.context_processor
        def _inject_auth():
            return {
                "current_user": get_current_user(),
                "auth_enabled": True,
                "oidc_enabled": app.config.get("OIDC_ENABLED", False),
                "oidc_display_name": app.config.get("OIDC_DISPLAY_NAME", "SSO"),
                "force_sso": app.config.get("FORCE_SSO", False),
                "app_version": app_version,
            }
    else:

        @app.context_processor
        def _inject_no_auth():
            return {
                "current_user": None,
                "auth_enabled": False,
                "oidc_enabled": False,
                "oidc_display_name": "SSO",
                "force_sso": False,
                "app_version": app_version,
            }

    # Initialize download queue, custom paths, autosync and watch progress (works with or without auth)
    # Users/api_tokens and web-app access requests are initialized unconditionally:
    # the web-app approval gate works independently of --web-auth/--web-sso.
    from .db import init_db as _init_users_db, init_web_access_requests_db

    _init_users_db()
    init_web_access_requests_db()
    init_profiles_db()
    init_series_language_prefs_db()
    init_queue_db()
    init_custom_paths_db()
    init_autosync_db()
    init_watch_progress_db()
    init_watchlist_db()

    # Wire up captcha hooks so the Playwright module can signal the Web UI
    from ..playwright import captcha as _captcha_mod

    _captcha_mod._on_captcha_start = set_captcha_url
    _captcha_mod._on_captcha_end = clear_captcha_url

    # In debug mode, Flask's reloader runs this in both the parent and child
    # process. Only start workers in the child (actual server) process
    # to avoid duplicate ffmpeg downloads.
    _debug = os.getenv("ANIWORLD_DEBUG_MODE", "0") == "1"
    if not _debug or os.environ.get("WERKZEUG_RUN_MAIN") == "true":
        download_worker.ensure_started()
        _ensure_autosync_worker()

    @app.after_request
    def _set_security_headers(response):
        response.headers.setdefault("X-Content-Type-Options", "nosniff")
        response.headers.setdefault("X-Frame-Options", "DENY")
        response.headers.setdefault(
            "Referrer-Policy", "strict-origin-when-cross-origin"
        )
        return response

    @app.before_request
    def _set_profile_id():
        from flask import g as _g
        raw = request.headers.get("X-Profile-ID", "").strip()
        try:
            _g.profile_id = int(raw) if raw else 1
        except (ValueError, TypeError):
            _g.profile_id = 1

    @app.before_request
    def _enforce_json_content_type():
        """Reject non-JSON POST/PUT/DELETE on API routes to prevent form-based CSRF bypass."""
        if request.method in ("POST", "PUT", "DELETE") and request.path.startswith(
            "/api/"
        ):
            if request.content_length and request.content_length > 0:
                ct = request.content_type or ""
                if not ct.startswith("application/json"):
                    return jsonify(
                        {"error": "Content-Type must be application/json"}
                    ), 415

    @app.route("/api/auth/check")
    def api_auth_check():
        if not auth_enabled:
            return jsonify({"auth_enabled": False, "setup_needed": False})
        from .db import has_any_admin as _has_any_admin
        return jsonify({
            "auth_enabled": True,
            "setup_needed": not _has_any_admin(),
        })

    # ── Flutter web build ───────────────────────────────────────────────────
    # Served same-origin under /app/ so the Flutter client never needs a
    # separately-configured backend URL. Only mounted if the build output
    # (flutter build web --base-href /app/) has been placed alongside this
    # module; absent that, the route simply doesn't exist.
    from pathlib import Path as _Path

    _flutter_web_dir = _Path(__file__).resolve().parent / "flutter_web"
    if webapp_enabled and _flutter_web_dir.is_dir():
        from flask import send_from_directory

        @app.route("/app/")
        @app.route("/app/<path:asset_path>")
        def flutter_web_app(asset_path="index.html"):
            target = _flutter_web_dir / asset_path
            if not target.is_file():
                asset_path = "index.html"
            return send_from_directory(str(_flutter_web_dir), asset_path)

    if not api_only:
        @app.route("/")
        def index():
            sto_lang_labels = {"1": "German Dub", "2": "English Dub"}
            default_web_language = os.environ.get("ANIWORLD_LANGUAGE", "German Dub")
            if default_web_language not in LANG_LABELS.values():
                default_web_language = "German Dub"
            return render_template(
                "index.html",
                lang_labels=LANG_LABELS,
                sto_lang_labels=sto_lang_labels,
                supported_providers=WORKING_PROVIDERS,
                default_web_language=default_web_language,
            )

    @app.route("/api/search", methods=["POST"])
    def api_search():
        data = request.get_json(silent=True) or {}
        keyword = (data.get("keyword") or "").strip()
        site = (data.get("site") or "aniworld").strip()
        if not keyword:
            return jsonify({"error": "keyword is required"}), 400

        results = []

        if site == "megakino":
            # MegaKino search — results already carry absolute URLs/posters.
            mk_results = query_megakino(keyword) or []
            if isinstance(mk_results, dict):
                mk_results = [mk_results]
            for item in mk_results:
                results.append(
                    {
                        "title": item.get("title", "Unknown"),
                        "url": item.get("url", ""),
                        "poster_url": item.get("poster_url", ""),
                    }
                )
        elif site == "sto":
            # serienstream.to search
            sto_results = query_s_to(keyword) or []
            if isinstance(sto_results, dict):
                sto_results = [sto_results]
            for item in sto_results:
                link = item.get("link", "")
                if _STO_SERIES_LINK_PATTERN.match(link):
                    title = (
                        item.get("title", "Unknown")
                        .replace("<em>", "")
                        .replace("</em>", "")
                    )
                    results.append(
                        {
                            "title": title,
                            "url": f"https://serienstream.to{link}",
                        }
                    )
        else:
            # AniWorld search
            aw_results = aniworld_query(keyword) or []
            if isinstance(aw_results, dict):
                aw_results = [aw_results]
            for item in aw_results:
                link = item.get("link", "")
                if _SERIES_LINK_PATTERN.match(link):
                    title = (
                        item.get("title", "Unknown")
                        .replace("<em>", "")
                        .replace("</em>", "")
                    )
                    results.append(
                        {
                            "title": title,
                            "url": f"https://aniworld.to{link}",
                        }
                    )

        return jsonify({"results": _enrich_with_tmdb(results)})

    @app.route("/api/series")
    def api_series():
        url = request.args.get("url", "").strip()
        if not url:
            return jsonify({"error": "url is required"}), 400

        try:
            prov = resolve_provider(url)
            series = prov.series_cls(url=url)
            poster = getattr(series, "poster_url", None)
            # serienstream.to returns relative poster paths - make them absolute
            if poster and poster.startswith("/"):
                from urllib.parse import urlparse

                parsed = urlparse(url)
                poster = f"{parsed.scheme}://{parsed.netloc}{poster}"

            tmdb = search_tmdb(series.title)
            final_poster = tmdb["poster_url"] or poster or ""
            final_backdrop = tmdb["backdrop_url"]

            return jsonify(
                {
                    "title": series.title,
                    "poster_url": _proxy_image_url(final_poster),
                    "backdrop_url": _proxy_image_url(final_backdrop),
                    "description": getattr(series, "description", ""),
                    "genres": getattr(series, "genres", []),
                    "release_year": getattr(series, "release_year", ""),
                }
            )
        except Exception as e:
            logger.error(f"Series fetch failed: {e}", exc_info=True)
            return jsonify({"error": str(e)}), 500

    @app.route("/api/seasons")
    def api_seasons():
        url = request.args.get("url", "").strip()
        if not url:
            return jsonify({"error": "url is required"}), 400

        try:
            prov = resolve_provider(url)
            if prov.name == "MegaKino":
                return jsonify({"seasons": _megakino_seasons(prov, url)})

            series = prov.series_cls(url=url)
            seasons_data = []
            for season in series.seasons:
                seasons_data.append(
                    {
                        "url": season.url,
                        "season_number": season.season_number,
                        "episode_count": season.episode_count,
                        "are_movies": getattr(season, "are_movies", False),
                    }
                )
            return jsonify({"seasons": seasons_data})
        except Exception as e:
            logger.error(f"Seasons fetch failed: {e}", exc_info=True)
            return jsonify({"error": str(e)}), 500

    @app.route("/api/episodes")
    def api_episodes():
        url = request.args.get("url", "").strip()
        if not url:
            return jsonify({"error": "url is required"}), 400

        try:
            prov = resolve_provider(url)
            if prov.name == "MegaKino":
                return jsonify({"episodes": _megakino_episodes(prov, url)})

            # Pass series to avoid broken series URL reconstruction in serienstream.to
            # season model (its fallback splits on "-" which fails)
            series_url = re.sub(r"/staffel-\d+/?$", "", url)
            series_url = re.sub(r"/filme/?$", "", series_url)
            try:
                series = prov.series_cls(url=series_url)
            except Exception:
                series = None
            season = prov.season_cls(url=url, series=series)

            # Scan download directory for downloaded episodes.
            # Uses S##E### filename matching so it works regardless of
            # which NAMING_TEMPLATE was active when files were downloaded.
            from pathlib import Path

            lang_sep = os.environ.get("ANIWORLD_LANG_SEPARATION", "0") == "1"
            lang_folders = ["german-dub", "english-sub", "german-sub", "english-dub"]

            raw = os.environ.get("ANIWORLD_DOWNLOAD_PATH", "")
            if raw:
                dl_base = Path(raw).expanduser()
                if not dl_base.is_absolute():
                    dl_base = Path.home() / dl_base
            else:
                dl_base = Path.home() / "Downloads"

            # Collect all scan roots: default + custom paths
            scan_roots = [dl_base]
            for cp in get_custom_paths():
                cp_path = Path(cp["path"]).expanduser()
                if not cp_path.is_absolute():
                    cp_path = Path.home() / cp_path
                scan_roots.append(cp_path)

            # Build map of (season_num, episode_num) -> preview_url found on disk
            from .thumbnails import preview_path as _preview_path
            downloaded_info: dict[tuple[int, int], str | None] = {}
            try:
                title_clean = ""
                if series:
                    title_clean = (
                        getattr(series, "title_cleaned", None)
                        or getattr(series, "title", "")
                    ).lower()
                if title_clean:
                    ep_re = re.compile(r"S(\d{2})E(\d{2,3})", re.IGNORECASE)
                    all_bases_with_root: list[tuple[Path, Path]] = []
                    for root in scan_roots:
                        if lang_sep:
                            all_bases_with_root.extend(
                                [(root, root / lf) for lf in lang_folders]
                            )
                        else:
                            all_bases_with_root.append((root, root))
                    for root, base in all_bases_with_root:
                        if not base.is_dir():
                            continue
                        for folder in base.iterdir():
                            if (
                                not folder.is_dir()
                                or not folder.name.lower().startswith(title_clean)
                            ):
                                continue
                            for f in folder.rglob("*.m3u8"):
                                if not f.is_file():
                                    continue
                                m = ep_re.search(f.name)
                                if not m:
                                    continue
                                key = (int(m.group(1)), int(m.group(2)))
                                if key in downloaded_info:
                                    continue
                                prev = _preview_path(f)
                                if prev.exists():
                                    try:
                                        rel = prev.relative_to(root)
                                        downloaded_info[key] = f"/api/episode-preview/{rel.as_posix()}"
                                    except ValueError:
                                        downloaded_info[key] = None
                                else:
                                    downloaded_info[key] = None
            except Exception:
                pass

            downloaded_eps = set(downloaded_info.keys())

            # Bulk-fetch watch progress for all episodes in this season
            from flask import g as _g
            ep_urls = [ep.url for ep in season.episodes]
            progress_map = get_episode_progress_for_urls(ep_urls, profile_id=getattr(_g, "profile_id", 1))

            before = _cumulative_before_map(series).get(season.season_number) if series else None

            episodes_data = []
            for ep in season.episodes:
                key = (ep.season.season_number, ep.episode_number)
                downloaded = key in downloaded_eps
                preview_url = downloaded_info.get(key)
                available_languages = _episode_language_labels(ep.provider_data)
                prog = progress_map.get(ep.url, {})

                episodes_data.append(
                    {
                        "url": ep.url,
                        "episode_number": ep.episode_number,
                        "absolute_episode_number": (
                            before + ep.episode_number if before is not None else None
                        ),
                        "title_de": getattr(ep, "title_de", ""),
                        "title_en": getattr(ep, "title_en", ""),
                        "downloaded": downloaded,
                        "available_languages": available_languages,
                        "watch_position": prog.get("position_seconds", 0),
                        "watch_duration": prog.get("duration_seconds", 0),
                        "is_watched": bool(prog.get("completed", 0)),
                        "preview_url": preview_url,
                    }
                )
            return jsonify({"episodes": episodes_data})
        except Exception as e:
            logger.error(f"Episodes fetch failed: {e}", exc_info=True)
            return jsonify({"error": str(e)}), 500

    @app.route("/api/providers")
    def api_providers():
        url = request.args.get("url", "").strip()
        if not url:
            return jsonify({"error": "url is required"}), 400

        try:
            prov = resolve_provider(url)
            ep_kwargs = {"url": url}
            if prov.name == "MegaKino":
                ep_kwargs["selected_language"] = "German Dub"
            episode = prov.episode_cls(**ep_kwargs)
            pd = episode.provider_data

            disable_eng_sub = os.environ.get("ANIWORLD_DISABLE_ENGLISH_SUB", "0") == "1"
            provider_info = {}

            if hasattr(pd, "_data"):
                # AniWorld: ProviderData object
                lang_tuple_to_label = {}
                for key, (audio, subtitles) in LANG_KEY_MAP.items():
                    label = LANG_LABELS.get(key)
                    if label:
                        lang_tuple_to_label[(audio.value, subtitles.value)] = label

                for (audio, subtitles), providers in pd._data.items():
                    label = lang_tuple_to_label.get((audio.value, subtitles.value))
                    if not label:
                        continue
                    if disable_eng_sub and label == "English Sub":
                        continue
                    working = [p for p in providers.keys() if p in WORKING_PROVIDERS]
                    if working:
                        provider_info[label] = working
            else:
                # serienstream.to: plain dict with (Audio, Subtitles) enum tuple keys
                sto_label_map = {
                    ("German", "None"): "German Dub",
                    ("English", "None"): "English Dub",
                }
                for (audio, subtitles), providers in pd.items():
                    label = sto_label_map.get((audio.value, subtitles.value))
                    if not label:
                        continue
                    working = [p for p in providers.keys() if p in WORKING_PROVIDERS]
                    if working:
                        provider_info[label] = working

            return jsonify({"providers": provider_info})
        except Exception as e:
            logger.error(f"Providers fetch failed: {e}", exc_info=True)
            return jsonify({"error": str(e)}), 500

    @app.route("/api/download", methods=["POST"])
    def api_download():
        data = request.get_json(silent=True) or {}
        episodes = data.get("episodes", [])
        language = data.get("language", "German Dub")
        provider = data.get("provider", "VOE")
        title = data.get("title", "Unknown")
        series_url = data.get("series_url", "")

        if not episodes:
            return jsonify({"error": "episodes list is required"}), 400

        if (
            language == "English Sub"
            and os.environ.get("ANIWORLD_DISABLE_ENGLISH_SUB", "0") == "1"
        ):
            return jsonify({"error": "English Sub downloads are disabled"}), 403

        username = None
        if auth_enabled:
            user = get_current_user()
            if user:
                username = (
                    user.get("username")
                    if isinstance(user, dict)
                    else getattr(user, "username", None)
                )

        custom_path_id = data.get("custom_path_id")
        # priority: 0=watch-intent, 1=prefetch, 2=manual(default), 3=autosync
        priority = data.get("priority")
        if priority is not None:
            try:
                priority = int(priority)
            except (TypeError, ValueError):
                priority = None

        queue_id = add_to_queue(
            title,
            series_url,
            episodes,
            language,
            provider,
            username,
            custom_path_id=custom_path_id,
            priority=priority,
            profile_id=g.profile_id,
        )

        # P0 watch-intent: preempt a P1 prefetch already running for this profile
        if priority == 0:
            download_worker.maybe_preempt_for_p0(get_queue_item(queue_id))

        download_worker.ensure_started()
        return jsonify({"queue_id": queue_id})

    @app.route("/api/queue")
    def api_queue():
        from ..models.common.common import get_ffmpeg_progress

        items = get_queue()
        ffmpeg_progress = get_ffmpeg_progress()
        return jsonify({"items": items, "ffmpeg_progress": ffmpeg_progress})

    @app.route("/api/queue/<int:queue_id>", methods=["DELETE"])
    def api_queue_remove(queue_id):
        ok, err = remove_from_queue(queue_id)
        if not ok:
            return jsonify({"error": err}), 400
        return jsonify({"ok": True})

    @app.route("/api/queue/<int:queue_id>/cancel", methods=["POST"])
    def api_queue_cancel(queue_id):
        data = request.get_json(silent=True) or {}
        force = bool(data.get("force", False))

        ok, err = request_cancel(queue_id, force=force)
        if not ok:
            return jsonify({"error": err}), 400

        if force:
            from ..models.common.common import kill_active_ffmpeg

            thread_id = download_worker.thread_id_for(queue_id)
            if thread_id is not None:
                kill_active_ffmpeg(thread_id=thread_id)
        return jsonify({"ok": True})

    @app.route("/api/queue/<int:queue_id>/move", methods=["POST"])
    def api_queue_move(queue_id):
        data = request.get_json(silent=True) or {}
        direction = data.get("direction", "").strip()
        if direction not in ("up", "down"):
            return jsonify({"error": "direction must be 'up' or 'down'"}), 400
        ok, err = move_queue_item(queue_id, direction)
        if not ok:
            return jsonify({"error": err}), 400
        return jsonify({"ok": True})

    @app.route("/api/queue/completed", methods=["DELETE"])
    def api_queue_clear():
        clear_completed()
        return jsonify({"ok": True})

    @app.route("/api/queue/find-by-episode")
    def api_queue_find_by_episode():
        episode_url = request.args.get("url", "").strip()
        if not episode_url:
            return jsonify({"queue_id": None})
        item = find_queue_item_by_episode(episode_url)
        return jsonify({"queue_id": item["id"] if item else None})

    # ── Captcha endpoints ─────────────────────────────────────────────────────

    @app.route("/api/captcha/<int:queue_id>/screenshot")
    def api_captcha_screenshot(queue_id):
        """Return the latest JPEG screenshot of the Playwright captcha page."""
        from ..playwright.captcha import _active_sessions, _active_sessions_lock
        from flask import Response

        with _active_sessions_lock:
            session = _active_sessions.get(queue_id)
        if not session:
            return "", 404
        data = session.get_screenshot()
        if not data:
            return "", 404
        return Response(
            data,
            mimetype="image/jpeg",
            headers={
                "Cache-Control": "no-store, no-cache, must-revalidate",
                "Pragma": "no-cache",
            },
        )

    @app.route("/api/captcha/<int:queue_id>/click", methods=["POST"])
    def api_captcha_click(queue_id):
        """Forward a click event (x, y) to the Playwright captcha browser."""
        from ..playwright.captcha import _active_sessions, _active_sessions_lock

        data = request.get_json(silent=True) or {}
        x = data.get("x")
        y = data.get("y")
        if x is None or y is None:
            return jsonify({"error": "x and y are required"}), 400
        with _active_sessions_lock:
            session = _active_sessions.get(queue_id)
        if not session:
            return jsonify({"error": "no active captcha session"}), 404
        session.enqueue_click(int(x), int(y))
        return jsonify({"ok": True})

    @app.route("/api/captcha/<int:queue_id>/status")
    def api_captcha_status(queue_id):
        """Return whether a captcha session is active and whether it has been solved."""
        from ..playwright.captcha import _active_sessions, _active_sessions_lock

        with _active_sessions_lock:
            session = _active_sessions.get(queue_id)
        if not session:
            return jsonify({"active": False})
        return jsonify({"active": True, "done": session.done})

    # ─────────────────────────────────────────────────────────────────────────

    if not api_only:
        @app.route("/library")
        def library_page():
            return render_template("library.html")

        @app.route("/settings")
        def settings_page():
            from pathlib import Path
            import platform

            env_path = Path.home() / ".aniworld" / ".env"
            if platform.system() != "Windows":
                display = "~/.aniworld/.env"
            else:
                display = str(env_path)
            return render_template("settings.html", env_path=display)

    @app.route("/api/random")
    def api_random():
        site = request.args.get("site", "aniworld").strip()
        if site == "sto":
            return jsonify({"error": "Random is not available for S.TO"}), 400
        url = random_anime()
        if url:
            return jsonify({"url": url})
        return jsonify({"error": "Failed to fetch random anime"}), 500

    @app.route("/api/proxy-image")
    def api_proxy_image():
        from flask import Response

        target = request.args.get("url", "").strip()
        if not target or not target.startswith(("http://", "https://")):
            return "", 400
        try:
            resp = requests.get(target, timeout=10, stream=True)
            resp.raise_for_status()
            content_type = resp.headers.get("Content-Type", "image/jpeg")
            return Response(
                resp.iter_content(chunk_size=8192),
                content_type=content_type,
                headers={"Cache-Control": "public, max-age=3600"},
            )
        except Exception as e:
            logger.warning(f"Image proxy failed for {target}: {e}")
            return "", 502

    # TTL cache for browse endpoints so long-running instances stay fresh
    import time as _time

    _browse_cache = {}
    _BROWSE_TTL = 3600  # 1 hour

    def _cached_browse(key, fetch_fn):
        now = _time.time()
        entry = _browse_cache.get(key)
        if entry and now - entry[0] < _BROWSE_TTL:
            return entry[1]
        results = fetch_fn()
        if results is not None:
            _browse_cache[key] = (now, results)
        return results

    _tmdb_poster_cache: dict = {}

    def _refresh_browse_caches():
        """Force-refetch everything the home screen shows (new/popular anime,
        series, movies) plus drop the poster/absolute-episode caches, which
        otherwise only expire on their own TTL (browse) or never (posters,
        absolute episode numbers) — long-running instances would otherwise
        keep serving stale home-screen data indefinitely."""
        _browse_cache.clear()
        _tmdb_poster_cache.clear()
        _absolute_ep_cache.clear()
        for key, fetch_fn in (
            ("new_animes", fetch_new_animes),
            ("popular_animes", fetch_popular_animes),
            ("new_series", fetch_new_series),
            ("popular_series", fetch_popular_series),
            ("popular_movies", fetch_popular_movies),
        ):
            try:
                _cached_browse(key, fetch_fn)
            except Exception as exc:
                logger.warning(f"Scheduled refresh failed for '{key}': {exc}")

    def _seconds_until_next_midnight():
        from datetime import datetime, timedelta

        now = datetime.now()
        next_midnight = (now + timedelta(days=1)).replace(
            hour=0, minute=0, second=0, microsecond=0
        )
        return (next_midnight - now).total_seconds()

    def _midnight_refresh_loop():
        while True:
            _time.sleep(_seconds_until_next_midnight())
            try:
                logger.info("Midnight refresh: updating home-screen caches")
                _refresh_browse_caches()
            except Exception:
                logger.exception("Midnight browse-cache refresh failed")

    threading.Thread(
        target=_midnight_refresh_loop, name="aniworld-midnight-refresh", daemon=True
    ).start()

    # Separate, shorter-lived cache from _browse_cache: a full directory walk
    # is heavier than a browse-list fetch, but disk usage also changes more
    # often (every download), so 1h would be too stale.
    _storage_cache = {}
    _STORAGE_TTL = 300  # 5 minutes

    @app.route("/api/storage-stats")
    def api_storage_stats():
        from . import library

        now = _time.time()
        entry = _storage_cache.get("stats")
        if entry and now - entry[0] < _STORAGE_TTL:
            return jsonify(entry[1])
        try:
            stats = library.usage_summary()
        except Exception as exc:
            logger.warning(f"Storage usage scan failed: {exc}")
            return jsonify({"error": "Failed to compute storage usage"}), 500
        _storage_cache["stats"] = (now, stats)
        return jsonify(stats)

    @app.route("/api/tmdb-poster")
    def api_tmdb_poster():
        title = request.args.get("title", "").strip()
        if not title:
            return jsonify({"poster_url": ""}), 200
        if title in _tmdb_poster_cache:
            return jsonify({"poster_url": _tmdb_poster_cache[title]})
        result = search_tmdb(title)
        poster = _proxy_image_url(result.get("poster_url", ""))
        _tmdb_poster_cache[title] = poster
        return jsonify({"poster_url": poster})

    def _enrich_with_tmdb(results: list) -> list:
        """Replace poster_url with TMDB image; fall back to original if TMDB has none."""
        enriched = []
        for r in results:
            tmdb = search_tmdb(r.get("title", ""))
            poster = tmdb["poster_url"] or r.get("poster_url", "")
            enriched.append({**r, "poster_url": _proxy_image_url(poster)})
        return enriched

    @app.route("/api/new-animes")
    def api_new_animes():
        results = _cached_browse("new_animes", fetch_new_animes)
        if results is None:
            return jsonify({"error": "Failed to fetch new animes"}), 500
        return jsonify({"results": _enrich_with_tmdb(results)})

    @app.route("/api/popular-animes")
    def api_popular_animes():
        results = _cached_browse("popular_animes", fetch_popular_animes)
        if results is None:
            return jsonify({"error": "Failed to fetch popular animes"}), 500
        return jsonify({"results": _enrich_with_tmdb(results)})

    @app.route("/api/new-series")
    def api_new_series():
        results = _cached_browse("new_series", fetch_new_series)
        if results is None:
            return jsonify({"error": "Failed to fetch new series"}), 500
        return jsonify({"results": _enrich_with_tmdb(results)})

    @app.route("/api/popular-series")
    def api_popular_series():
        results = _cached_browse("popular_series", fetch_popular_series)
        if results is None:
            return jsonify({"error": "Failed to fetch popular series"}), 500
        return jsonify({"results": _enrich_with_tmdb(results)})

    @app.route("/api/popular-movies")
    def api_popular_movies():
        results = _cached_browse("popular_movies", fetch_popular_movies)
        if results is None:
            return jsonify({"error": "Failed to fetch popular movies"}), 500
        return jsonify({"results": _enrich_with_tmdb(results)})

    @app.route("/api/all-animes")
    def api_all_animes():
        page = max(1, int(request.args.get("page", 1)))
        per_page = min(100, max(10, int(request.args.get("per_page", 50))))
        genre = request.args.get("genre", "").strip()
        all_results = _cached_browse("all_animes", fetch_all_animes)
        if all_results is None:
            return jsonify({"error": "Failed to fetch anime list"}), 500
        # Collect all unique genres from the full unfiltered list
        seen_genres = set()
        all_genres = []
        for r in all_results:
            for g in r.get("genres", []):
                if g not in seen_genres:
                    seen_genres.add(g)
                    all_genres.append(g)
        all_genres.sort()
        results = [r for r in all_results if genre in r.get("genres", [])] if genre else all_results
        total = len(results)
        start = (page - 1) * per_page
        end = start + per_page
        return jsonify({
            "results": results[start:end],
            "total": total,
            "page": page,
            "per_page": per_page,
            "has_more": end < total,
            "all_genres": all_genres,
        })

    @app.route("/api/all-series")
    def api_all_series():
        page = max(1, int(request.args.get("page", 1)))
        per_page = min(100, max(10, int(request.args.get("per_page", 50))))
        genre = request.args.get("genre", "").strip()
        all_results = _cached_browse("all_series", fetch_all_series)
        if all_results is None:
            return jsonify({"error": "Failed to fetch series list"}), 500
        # Genres are fetched from serienstream.to genre pages on demand — use the known list immediately.
        all_genres = sorted(SERIES_GENRES.keys())
        if genre and genre in SERIES_GENRES:
            # Filter using pre-fetched serienstream.to genre slugs (blocks until ready, then cached)
            genre_slugs = fetch_series_genre_slugs(genre)
            results = [r for r in all_results if r["url"].rstrip("/").split("/")[-1] in genre_slugs]
        else:
            results = all_results
        total = len(results)
        start = (page - 1) * per_page
        end = start + per_page
        return jsonify({
            "results": results[start:end],
            "total": total,
            "page": page,
            "per_page": per_page,
            "has_more": end < total,
            "all_genres": all_genres,
        })

    @app.route("/api/all-movies")
    def api_all_movies():
        page = max(1, int(request.args.get("page", 1)))
        per_page = min(100, max(10, int(request.args.get("per_page", 50))))
        # MegaKino exposes no paginated catalog or genre pages — the homepage
        # showcase is the whole browsable list, paginated here client-side.
        all_results = _cached_browse("popular_movies", fetch_popular_movies)
        if all_results is None:
            return jsonify({"error": "Failed to fetch movie list"}), 500
        total = len(all_results)
        start = (page - 1) * per_page
        end = start + per_page
        return jsonify({
            "results": all_results[start:end],
            "total": total,
            "page": page,
            "per_page": per_page,
            "has_more": end < total,
            "all_genres": [],
        })

    @app.route("/api/downloaded-folders")
    def api_downloaded_folders():
        from pathlib import Path

        raw = os.environ.get("ANIWORLD_DOWNLOAD_PATH", "")
        if raw:
            p = Path(raw).expanduser()
            if not p.is_absolute():
                p = Path.home() / p
            dl_path = p
        else:
            dl_path = Path.home() / "Downloads"

        lang_sep = os.environ.get("ANIWORLD_LANG_SEPARATION", "0") == "1"
        lang_folders = ["german-dub", "english-sub", "german-sub", "english-dub"]

        # Collect all paths to scan (default + custom)
        scan_roots = [dl_path]
        for cp in get_custom_paths():
            cp_path = Path(cp["path"]).expanduser()
            if not cp_path.is_absolute():
                cp_path = Path.home() / cp_path
            scan_roots.append(cp_path)

        folders = set()
        for root in scan_roots:
            if lang_sep:
                bases = [root / lf for lf in lang_folders]
            else:
                bases = [root]
            for base in bases:
                if not base.is_dir():
                    continue
                for entry in base.iterdir():
                    if entry.is_dir():
                        folders.add(entry.name)
        return jsonify({"folders": sorted(folders)})

    @app.route("/api/settings", methods=["GET"])
    def api_settings():
        from pathlib import Path

        raw = os.environ.get("ANIWORLD_DOWNLOAD_PATH", "")
        if raw:
            p = Path(raw).expanduser()
            if not p.is_absolute():
                p = Path.home() / p
            resolved = str(p)
        else:
            resolved = str(Path.home() / "Downloads")
        lang_separation = os.environ.get("ANIWORLD_LANG_SEPARATION", "0")
        disable_english_sub = os.environ.get("ANIWORLD_DISABLE_ENGLISH_SUB", "0")
        sync_schedule = os.environ.get("ANIWORLD_SYNC_SCHEDULE", "0")
        sync_language = os.environ.get("ANIWORLD_SYNC_LANGUAGE", "German Dub")
        provider_fallback_order = list(get_provider_fallback_order(WORKING_PROVIDERS))
        sync_provider = os.environ.get(
            "ANIWORLD_SYNC_PROVIDER",
            provider_fallback_order[0] if provider_fallback_order else "VOE",
        )
        if sync_provider not in WORKING_PROVIDERS and provider_fallback_order:
            sync_provider = provider_fallback_order[0]
        default_language = os.environ.get("ANIWORLD_LANGUAGE", "German Dub")
        default_provider = os.environ.get("ANIWORLD_PROVIDER", provider_fallback_order[0] if provider_fallback_order else "VOE")
        if default_provider not in WORKING_PROVIDERS and provider_fallback_order:
            default_provider = provider_fallback_order[0]
        return jsonify(
            {
                "download_path": resolved,
                "lang_separation": lang_separation,
                "disable_english_sub": disable_english_sub,
                "sync_schedule": sync_schedule,
                "sync_language": sync_language,
                "sync_provider": sync_provider,
                "provider_fallback_order": provider_fallback_order,
                "available_providers": list(WORKING_PROVIDERS),
                "default_language": default_language,
                "default_provider": default_provider,
            }
        )

    @app.route("/api/settings/public-ip", methods=["GET"])
    def api_settings_public_ip():
        try:
            result = _fetch_public_ip()
            return jsonify({"ok": True, **result})
        except RuntimeError as exc:
            logger.warning("Failed to resolve public IP: %s", exc)
            return jsonify({"ok": False, "error": "Failed to fetch public IP"}), 502

    @app.route("/api/settings", methods=["PUT"])
    def api_settings_update():
        data = request.get_json(silent=True) or {}
        if "download_path" in data:
            os.environ["ANIWORLD_DOWNLOAD_PATH"] = str(data["download_path"]).strip()
        if "lang_separation" in data:
            os.environ["ANIWORLD_LANG_SEPARATION"] = (
                "1" if data["lang_separation"] else "0"
            )
        if "disable_english_sub" in data:
            os.environ["ANIWORLD_DISABLE_ENGLISH_SUB"] = (
                "1" if data["disable_english_sub"] else "0"
            )
        if "sync_schedule" in data:
            sched = str(data["sync_schedule"])
            if sched != "0" and sched not in SYNC_SCHEDULE_MAP:
                return jsonify({"error": f"Invalid sync_schedule: {sched}"}), 400
            os.environ["ANIWORLD_SYNC_SCHEDULE"] = sched
        if "sync_language" in data:
            lang = str(data["sync_language"])
            valid_langs = set(LANG_LABELS.values()) | {"All Languages"}
            if lang not in valid_langs:
                return jsonify({"error": f"Invalid sync_language: {lang}"}), 400
            os.environ["ANIWORLD_SYNC_LANGUAGE"] = lang
        if "sync_provider" in data:
            prov = str(data["sync_provider"])
            if prov not in WORKING_PROVIDERS:
                return jsonify({"error": f"Invalid sync_provider: {prov}"}), 400
            os.environ["ANIWORLD_SYNC_PROVIDER"] = prov
        if "provider_fallback_order" in data:
            raw_order = data["provider_fallback_order"]
            if isinstance(raw_order, list):
                requested_order = [str(provider).strip() for provider in raw_order]
            else:
                requested_order = [
                    provider.strip() for provider in str(raw_order).split(",")
                ]

            requested_order = [provider for provider in requested_order if provider]
            if not requested_order:
                return jsonify(
                    {"error": "provider_fallback_order cannot be empty"}
                ), 400

            invalid = [
                provider
                for provider in requested_order
                if provider not in WORKING_PROVIDERS
            ]
            if invalid:
                invalid_list = ", ".join(sorted(dict.fromkeys(invalid)))
                return (
                    jsonify(
                        {
                            "error": "Invalid provider_fallback_order entries: "
                            + invalid_list
                        }
                    ),
                    400,
                )

            if len(set(requested_order)) != len(requested_order):
                return jsonify(
                    {"error": "provider_fallback_order contains duplicates"}
                ), 400

            os.environ["ANIWORLD_PROVIDER_FALLBACK_ORDER"] = ",".join(
                parse_provider_order(
                    ",".join(requested_order),
                    allowed_providers=WORKING_PROVIDERS,
                )
            )
        return jsonify({"ok": True})

    @app.route("/api/custom-paths")
    def api_custom_paths():
        paths = get_custom_paths()
        return jsonify({"paths": paths})

    @app.route("/api/custom-paths", methods=["POST"])
    def api_custom_paths_add():
        data = request.get_json(silent=True) or {}
        name = (data.get("name") or "").strip()
        path = (data.get("path") or "").strip()
        if not name or not path:
            return jsonify({"error": "name and path are required"}), 400
        path_id = add_custom_path(name, path)
        return jsonify({"ok": True, "id": path_id})

    @app.route("/api/custom-paths/<int:path_id>", methods=["DELETE"])
    def api_custom_paths_delete(path_id):
        remove_custom_path(path_id)
        return jsonify({"ok": True})

    # ===== Auto-Sync Page =====

    if not api_only:
        @app.route("/autosync")
        def autosync_page():
            return render_template("autosync.html")

    # ===== Auto-Sync API =====

    def _get_current_user_info():
        """Return (username, is_admin) for the current request."""
        if not auth_enabled:
            return None, True  # no auth → treat as admin
        user = get_current_user()
        if not user:
            return None, False
        username = (
            user.get("username")
            if isinstance(user, dict)
            else getattr(user, "username", None)
        )
        role = (
            user.get("role")
            if isinstance(user, dict)
            else getattr(user, "role", "user")
        )
        return username, role == "admin"

    @app.route("/api/autosync")
    def api_autosync_list():
        username, is_admin = _get_current_user_info()
        # Admins see all jobs; regular users see only their own
        jobs = get_autosync_jobs(username=None if is_admin else username)
        return jsonify({"jobs": jobs})

    @app.route("/api/autosync", methods=["POST"])
    def api_autosync_create():
        data = request.get_json(silent=True) or {}
        title = (data.get("title") or "").strip()
        series_url = (data.get("series_url") or "").strip()
        language = data.get("language", "German Dub")
        provider = data.get("provider", "VOE")
        custom_path_id = data.get("custom_path_id")

        if not title or not series_url:
            return jsonify({"error": "title and series_url are required"}), 400

        existing = find_autosync_by_url(series_url)
        if existing:
            return jsonify(
                {"error": "A sync job for this series already exists", "job": existing}
            ), 409

        username, _ = _get_current_user_info()
        job_id = add_autosync_job(
            title=title,
            series_url=series_url,
            language=language,
            provider=provider,
            custom_path_id=custom_path_id,
            added_by=username,
        )
        return jsonify({"ok": True, "id": job_id})

    @app.route("/api/autosync/<int:job_id>", methods=["PUT"])
    def api_autosync_update(job_id):
        job = get_autosync_job(job_id)
        if not job:
            return jsonify({"error": "Job not found"}), 404
        username, is_admin = _get_current_user_info()
        if not is_admin and job.get("added_by") != username:
            return jsonify({"error": "Not authorized to edit this job"}), 403
        data = request.get_json(silent=True) or {}
        allowed = {"language", "provider", "enabled", "custom_path_id"}
        filtered = {k: v for k, v in data.items() if k in allowed}
        update_autosync_job(job_id, **filtered)
        return jsonify({"ok": True})

    @app.route("/api/autosync/<int:job_id>", methods=["DELETE"])
    def api_autosync_delete(job_id):
        job = get_autosync_job(job_id)
        if not job:
            return jsonify({"error": "Job not found"}), 404
        username, is_admin = _get_current_user_info()
        if not is_admin and job.get("added_by") != username:
            return jsonify({"error": "Not authorized to delete this job"}), 403
        ok, err = remove_autosync_job(job_id)
        if not ok:
            return jsonify({"error": err}), 404
        return jsonify({"ok": True})

    @app.route("/api/autosync/<int:job_id>/sync", methods=["POST"])
    def api_autosync_trigger(job_id):
        job = get_autosync_job(job_id)
        if not job:
            return jsonify({"error": "Job not found"}), 404
        username, is_admin = _get_current_user_info()
        if not is_admin and job.get("added_by") != username:
            return jsonify({"error": "Not authorized"}), 403
        with _syncing_jobs_lock:
            if job_id in _syncing_jobs:
                return jsonify({"error": "Sync already running for this job"}), 409
        threading.Thread(target=_run_autosync_for_job, args=(job,), daemon=True).start()
        return jsonify({"ok": True, "message": "Sync started"})

    @app.route("/api/autosync/check", methods=["GET"])
    def api_autosync_check():
        """Check if a sync job exists for a given series URL."""
        url = request.args.get("url", "").strip()
        if not url:
            return jsonify({"exists": False})
        job = find_autosync_by_url(url)
        if not job:
            return jsonify({"exists": False})
        # Only expose job details to the owner or admins
        username, is_admin = _get_current_user_info()
        if not is_admin and job.get("added_by") != username:
            return jsonify({"exists": False})
        return jsonify({"exists": True, "job": job})

    # ===== Stats API =====

    @app.route("/api/stats/sync")
    def api_stats_sync():
        stats = get_sync_stats()
        # Compute next_run_at from last check + schedule interval
        schedule_key = os.environ.get("ANIWORLD_SYNC_SCHEDULE", "0")
        interval = SYNC_SCHEDULE_MAP.get(schedule_key, 0)
        stats["schedule"] = schedule_key
        stats["next_run_at"] = None
        if interval and stats.get("last_check"):
            from datetime import datetime, timedelta

            try:
                last = datetime.strptime(stats["last_check"], "%Y-%m-%d %H:%M:%S")
                nxt = last + timedelta(seconds=interval)
                stats["next_run_at"] = nxt.strftime("%Y-%m-%d %H:%M:%S")
            except Exception:
                pass
        return jsonify(stats)

    @app.route("/api/stats/queue")
    def api_stats_queue():
        return jsonify(get_queue_stats())

    @app.route("/api/stats/general")
    def api_stats_general():
        return jsonify(get_general_stats())

    @app.route("/api/library")
    def api_library():
        from pathlib import Path

        raw = os.environ.get("ANIWORLD_DOWNLOAD_PATH", "")
        if raw:
            dl_base = Path(raw).expanduser()
            if not dl_base.is_absolute():
                dl_base = Path.home() / dl_base
        else:
            dl_base = Path.home() / "Downloads"

        lang_sep = os.environ.get("ANIWORLD_LANG_SEPARATION", "0") == "1"
        lang_folders = ["german-dub", "english-sub", "german-sub", "english-dub"]
        ep_re = re.compile(r"S(\d{2})E(\d{2,3})", re.IGNORECASE)
        video_exts = {
            ".m3u8",
            ".mkv",
            ".mp4",
            ".avi",
            ".webm",
            ".flv",
            ".mov",
            ".wmv",
            ".m4v",
            ".ts",
        }

        # Build list of (label, custom_path_id, base_path) to scan
        scan_targets = [("Default", None, dl_base)]
        for cp in get_custom_paths():
            cp_base = Path(cp["path"]).expanduser()
            if not cp_base.is_absolute():
                cp_base = Path.home() / cp_base
            scan_targets.append((cp["name"], cp["id"], cp_base))

        def _scan_base(base):
            """Scan a single base directory and return list of title dicts."""
            lang_folder_set = set(lang_folders)
            titles = {}
            if not base.is_dir():
                return []
            for folder in base.iterdir():
                if not folder.is_dir():
                    continue
                name = folder.name
                if name in lang_folder_set:
                    continue
                if name not in titles:
                    titles[name] = {"folder": name, "seasons": {}, "total_size": 0}
                entry = titles[name]
                for f in folder.rglob("*"):
                    if not f.is_file() or f.name.startswith(".temp_"):
                        continue
                    m = ep_re.search(f.name)
                    if not m:
                        continue
                    snum = int(m.group(1))
                    enum = int(m.group(2))
                    ext = f.suffix.lower()
                    try:
                        fsize = f.stat().st_size
                    except OSError:
                        fsize = 0
                    skey = str(snum)
                    # seasons[skey] is a dict keyed by episode number so each
                    # episode appears exactly once regardless of how many .ts
                    # segment files belong to it.
                    if skey not in entry["seasons"]:
                        entry["seasons"][skey] = {}
                    ep_map = entry["seasons"][skey]
                    if enum not in ep_map:
                        ep_map[enum] = {
                            "episode": enum,
                            "file": f.name,
                            "size": 0,
                            "is_video": False,
                        }
                    ep = ep_map[enum]
                    ep["size"] += fsize
                    entry["total_size"] += fsize
                    # Prefer .m3u8 as the representative file; fall back to any
                    # other video file if no playlist has been seen yet.
                    if ext == ".m3u8":
                        ep["file"] = f.name
                        ep["is_video"] = True
                    elif ext in video_exts and not ep["is_video"]:
                        ep["file"] = f.name
                        ep["is_video"] = True

            result = []
            for entry in sorted(titles.values(), key=lambda x: x["folder"].lower()):
                # Convert per-season dicts → sorted lists
                seasons_out = {}
                for skey, ep_map in entry["seasons"].items():
                    eps = sorted(ep_map.values(), key=lambda e: e["episode"])
                    if eps:
                        seasons_out[skey] = eps
                if not seasons_out:
                    continue
                total_eps = sum(
                    sum(1 for e in eps if e.get("is_video", True))
                    for eps in seasons_out.values()
                )
                result.append(
                    {
                        "folder": entry["folder"],
                        "seasons": seasons_out,
                        "total_episodes": total_eps,
                        "total_size": entry["total_size"],
                    }
                )
            return result

        locations = []
        for label, cp_id, base_path in scan_targets:
            if lang_sep:
                loc_lang_folders = []
                for lf in lang_folders:
                    lf_titles = _scan_base(base_path / lf)
                    if lf_titles:
                        loc_lang_folders.append(
                            {
                                "name": lf,
                                "titles": lf_titles,
                            }
                        )
                if loc_lang_folders:
                    locations.append(
                        {
                            "label": label,
                            "custom_path_id": cp_id,
                            "lang_folders": loc_lang_folders,
                            "titles": None,
                        }
                    )
            else:
                loc_titles = _scan_base(base_path)
                if loc_titles:
                    locations.append(
                        {
                            "label": label,
                            "custom_path_id": cp_id,
                            "lang_folders": None,
                            "titles": loc_titles,
                        }
                    )

        return jsonify({"lang_sep": lang_sep, "locations": locations})

    @app.route("/api/library/delete", methods=["POST"])
    def api_library_delete():
        import shutil
        from pathlib import Path

        data = request.get_json(silent=True) or {}
        folder = data.get("folder", "")
        season = data.get("season")  # int or null
        episode = data.get("episode")  # int or null
        custom_path_id = data.get("custom_path_id")  # int or null

        # Security: reject dangerous folder names
        if (
            not folder
            or ".." in folder
            or "/" in folder
            or "\\" in folder
            or "\x00" in folder
        ):
            return jsonify({"error": "Invalid folder name"}), 400

        # Resolve base path from custom_path_id or default
        if custom_path_id:
            cp = get_custom_path_by_id(custom_path_id)
            if not cp:
                return jsonify({"error": "Custom path not found"}), 404
            dl_base = Path(cp["path"]).expanduser()
            if not dl_base.is_absolute():
                dl_base = Path.home() / dl_base
        else:
            raw = os.environ.get("ANIWORLD_DOWNLOAD_PATH", "")
            if raw:
                dl_base = Path(raw).expanduser()
                if not dl_base.is_absolute():
                    dl_base = Path.home() / dl_base
            else:
                dl_base = Path.home() / "Downloads"

        lang_sep = os.environ.get("ANIWORLD_LANG_SEPARATION", "0") == "1"
        lang_folders = ["german-dub", "english-sub", "german-sub", "english-dub"]
        lang_folder = data.get("lang_folder")  # str or null

        if lang_sep and lang_folder:
            if lang_folder not in lang_folders:
                return jsonify({"error": "Invalid language folder"}), 400
            bases = [dl_base / lang_folder]
        elif lang_sep:
            bases = [dl_base / lf for lf in lang_folders]
        else:
            bases = [dl_base]

        deleted = 0
        for base in bases:
            title_path = base / folder
            # Verify resolved path is a child of the base
            try:
                title_path.resolve().relative_to(base.resolve())
            except ValueError:
                continue
            if not title_path.is_dir():
                continue

            if season is None and episode is None:
                # Delete entire title
                shutil.rmtree(title_path, ignore_errors=True)
                deleted += 1
            else:
                # Build regex pattern
                if episode is not None:
                    pat = re.compile(
                        rf"S{int(season):02d}E{int(episode):03d}(?!\d)", re.IGNORECASE
                    )
                else:
                    pat = re.compile(rf"S{int(season):02d}E\d{{2,3}}", re.IGNORECASE)

                for f in list(title_path.rglob("*")):
                    if f.is_file() and pat.search(f.name):
                        try:
                            f.unlink()
                            deleted += 1
                        except OSError:
                            pass

                # Cleanup empty directories bottom-up
                for dirpath in sorted(
                    title_path.rglob("*"), key=lambda p: len(p.parts), reverse=True
                ):
                    if dirpath.is_dir():
                        try:
                            dirpath.rmdir()  # only succeeds if empty
                        except OSError:
                            pass
                # Remove title folder itself if empty
                try:
                    title_path.rmdir()
                except OSError:
                    pass

        if deleted == 0:
            return jsonify({"error": "Nothing found to delete"}), 404
        return jsonify({"ok": True, "deleted": deleted})

    # ── Streaming endpoints ───────────────────────────────────────────────────

    @app.route("/api/stream")
    def api_stream():
        """Return the HLS stream URL for a downloaded episode.

        Query params:
            folder          – series folder name (e.g. "Highschool DxD (2012) [imdbid-tt…]")
            season          – season number (int)
            episode         – episode number (int)
            custom_path_id  – (optional) custom path id
        """
        from pathlib import Path

        folder = request.args.get("folder", "").strip()
        season = request.args.get("season", type=int)
        episode = request.args.get("episode", type=int)
        custom_path_id_param = request.args.get("custom_path_id", type=int)

        if not folder or season is None or episode is None:
            return jsonify({"error": "folder, season and episode are required"}), 400

        if ".." in folder or "/" in folder or "\\" in folder or "\x00" in folder:
            return jsonify({"error": "invalid folder"}), 400

        # Collect base directories to search
        raw = os.environ.get("ANIWORLD_DOWNLOAD_PATH", "")
        if raw:
            dl_base = Path(raw).expanduser()
            if not dl_base.is_absolute():
                dl_base = Path.home() / dl_base
        else:
            dl_base = Path.home() / "Downloads"

        if custom_path_id_param is not None:
            cp = get_custom_path_by_id(custom_path_id_param)
            if not cp:
                return jsonify({"error": "Custom path not found"}), 404
            search_bases = [Path(cp["path"]).expanduser()]
            if not search_bases[0].is_absolute():
                search_bases[0] = Path.home() / search_bases[0]
        else:
            search_bases = [dl_base]
            for cp in get_custom_paths():
                cp_path = Path(cp["path"]).expanduser()
                if not cp_path.is_absolute():
                    cp_path = Path.home() / cp_path
                search_bases.append(cp_path)

        ep_re = re.compile(rf"S{season:02d}E{episode:03d}(?!\d)", re.IGNORECASE)

        for base in search_bases:
            series_dir = base / folder
            if not series_dir.is_dir():
                continue
            for f in series_dir.rglob("*.m3u8"):
                if not ep_re.search(f.name):
                    continue
                try:
                    rel = f.relative_to(base)
                except ValueError:
                    continue
                stream_url = url_for(
                    "api_stream_file",
                    filepath=rel.as_posix(),
                    _external=True,
                )
                return jsonify({"url": stream_url})

        return jsonify({"error": "Episode not found"}), 404

    @app.route("/api/stream/files/<path:filepath>")
    def api_stream_file(filepath):
        """Serve an .m3u8 playlist or .ts segment for HLS streaming.

        The filepath is relative to one of the configured download directories.
        Only .m3u8 and .ts files are served; anything else returns 404.
        """
        from flask import send_from_directory
        from pathlib import Path

        _ALLOWED_EXTS = {".m3u8", ".ts"}
        _MIME = {
            ".m3u8": "application/vnd.apple.mpegurl",
            ".ts": "video/mp2t",
        }

        ext = Path(filepath).suffix.lower()
        if ext not in _ALLOWED_EXTS:
            return "", 404

        # Collect all allowed base directories
        raw = os.environ.get("ANIWORLD_DOWNLOAD_PATH", "")
        if raw:
            dl_base = Path(raw).expanduser()
            if not dl_base.is_absolute():
                dl_base = Path.home() / dl_base
        else:
            dl_base = Path.home() / "Downloads"

        allowed_bases = [dl_base]
        for cp in get_custom_paths():
            cp_path = Path(cp["path"]).expanduser()
            if not cp_path.is_absolute():
                cp_path = Path.home() / cp_path
            allowed_bases.append(cp_path)

        for base in allowed_bases:
            candidate = (base / filepath).resolve()
            try:
                candidate.relative_to(base.resolve())
            except ValueError:
                continue  # path traversal – skip

            if not candidate.is_file():
                continue

            resp = send_from_directory(
                str(candidate.parent),
                candidate.name,
                mimetype=_MIME[ext],
            )
            resp.headers["Access-Control-Allow-Origin"] = "*"
            resp.headers["Cache-Control"] = "no-cache"
            return resp

        return "", 404

    # ── Watch Progress ────────────────────────────────────────────────────────

    # ── Profiles ─────────────────────────────────────────────────────────────

    @app.route("/api/profiles", methods=["GET"])
    def api_get_profiles():
        return jsonify({"profiles": get_profiles()})

    @app.route("/api/profiles", methods=["POST"])
    def api_create_profile():
        data = request.get_json(force=True) or {}
        name = (data.get("name") or "").strip()
        avatar_color = (data.get("avatar_color") or "#E50914").strip()
        default_language = (data.get("default_language") or "").strip() or None
        if not name:
            return jsonify({"error": "name required"}), 400
        new_id = create_profile(name, avatar_color, default_language=default_language)
        return jsonify({"id": new_id, "ok": True})

    @app.route("/api/profiles/<int:profile_id>", methods=["PUT"])
    def api_update_profile(profile_id):
        data = request.get_json(force=True) or {}
        name = (data.get("name") or "").strip() or None
        avatar_color = (data.get("avatar_color") or "").strip() or None
        kwargs = {}
        if "default_language" in data:
            kwargs["default_language"] = (data.get("default_language") or "").strip() or None
        update_profile(profile_id, name=name, avatar_color=avatar_color, **kwargs)
        return jsonify({"ok": True})

    @app.route("/api/profiles/<int:profile_id>", methods=["DELETE"])
    def api_delete_profile(profile_id):
        ok, err = delete_profile(profile_id)
        if not ok:
            return jsonify({"error": err}), 400
        return jsonify({"ok": True})

    # ── Language preferences (profile default + per-series override) ──────────
    # Cascade: series override (this profile) -> profile default -> global
    # ANIWORLD_LANGUAGE env var -> "German Dub".

    def _resolve_preferred_language(series_url=None):
        profile_id = getattr(g, "profile_id", 1)
        if series_url:
            override = get_series_language(profile_id, series_url)
            if override:
                return override
        for p in get_profiles():
            if p["id"] == profile_id and p.get("default_language"):
                return p["default_language"]
        return os.environ.get("ANIWORLD_LANGUAGE", "German Dub")

    @app.route("/api/preferred-language", methods=["GET"])
    def api_preferred_language():
        series_url = (request.args.get("series_url") or "").strip() or None
        return jsonify({"language": _resolve_preferred_language(series_url)})

    @app.route("/api/series-language", methods=["GET"])
    def api_get_series_language():
        series_url = (request.args.get("url") or "").strip()
        if not series_url:
            return jsonify({"error": "url required"}), 400
        profile_id = getattr(g, "profile_id", 1)
        return jsonify({"language": get_series_language(profile_id, series_url)})

    @app.route("/api/series-language", methods=["PUT"])
    def api_set_series_language():
        data = request.get_json(force=True) or {}
        series_url = (data.get("url") or "").strip()
        language = (data.get("language") or "").strip()
        if not series_url or not language:
            return jsonify({"error": "url and language required"}), 400
        profile_id = getattr(g, "profile_id", 1)
        set_series_language(profile_id, series_url, language)
        return jsonify({"ok": True})

    @app.route("/api/series-language", methods=["DELETE"])
    def api_clear_series_language():
        series_url = (request.args.get("url") or "").strip()
        if not series_url:
            return jsonify({"error": "url required"}), 400
        profile_id = getattr(g, "profile_id", 1)
        clear_series_language(profile_id, series_url)
        return jsonify({"ok": True})

    def _resolve_downloaded_file(stream_file):
        """stream_file is relative to whichever download root it lives under
        (default path or a custom path) — same search order as /api/stream/url."""
        from pathlib import Path as _Path

        raw = os.environ.get("ANIWORLD_DOWNLOAD_PATH", "")
        default_base = _Path(raw).expanduser() if raw else _Path.home() / "Downloads"
        if raw and not default_base.is_absolute():
            default_base = _Path.home() / default_base

        bases = [default_base]
        for cp in get_custom_paths():
            cp_path = _Path(cp["path"]).expanduser()
            if not cp_path.is_absolute():
                cp_path = _Path.home() / cp_path
            bases.append(cp_path)

        for base in bases:
            candidate = base / stream_file
            if candidate.is_file():
                return candidate
        return None

    def _smart_cleanup_watched_episode(episode_url, stream_file):
        """Auto-delete a downloaded episode/movie once every profile has
        watched it (see is_episode_completed_for_all_profiles). Deletes the
        .m3u8 and every _NNN.ts segment sharing its filename stem, then
        removes any directory left empty — mirrors how the download pipeline
        writes HLS output (models/common/common.py), so this works uniformly
        for episodes and movies alike without needing SxxExx parsing."""
        if not is_episode_completed_for_all_profiles(episode_url):
            return
        target = _resolve_downloaded_file(stream_file)
        if target is None:
            return
        stem = target.stem
        parent = target.parent
        deleted = 0
        for f in parent.iterdir():
            if f.is_file() and f.name.startswith(stem):
                try:
                    f.unlink()
                    deleted += 1
                except OSError as exc:
                    logger.warning(f"Smart cleanup: could not delete {f}: {exc}")
        if deleted:
            logger.info(f"Smart cleanup: removed {deleted} file(s) for watched '{stem}'")
            from . import library

            library._prune_empty(parent)

    @app.route("/api/progress", methods=["POST"])
    def api_save_progress():
        data = request.get_json(force=True) or {}
        episode_url = (data.get("episode_url") or "").strip()
        if not episode_url:
            return jsonify({"error": "episode_url is required"}), 400
        try:
            # Extract relative file path from stream URL if provided
            # e.g. "http://host/api/stream/files/One%20Piece/S01E009.m3u8"
            #   -> "One Piece/S01E009.m3u8"
            stream_file = None
            raw_stream_url = (data.get("stream_file") or "").strip()
            if raw_stream_url:
                from urllib.parse import urlparse, unquote
                path = urlparse(raw_stream_url).path
                prefix = "/api/stream/files/"
                if prefix in path:
                    stream_file = unquote(path[path.index(prefix) + len(prefix):])
            from flask import g as _g
            completed = bool(data.get("completed", False))
            upsert_watch_progress(
                episode_url=episode_url,
                series_title=data.get("series_title"),
                series_url=data.get("series_url"),
                season=int(data.get("season") or 0),
                episode_number=int(data.get("episode_number") or 0),
                episode_title=data.get("episode_title"),
                position_seconds=float(data.get("position_seconds") or 0),
                duration_seconds=float(data.get("duration_seconds") or 0),
                completed=completed,
                stream_file=stream_file,
                profile_id=getattr(_g, "profile_id", 1),
            )
            if completed and stream_file:
                try:
                    _smart_cleanup_watched_episode(episode_url, stream_file)
                except Exception as exc:
                    logger.warning(f"Smart cleanup failed for {episode_url}: {exc}")
            return jsonify({"ok": True})
        except Exception as e:
            logger.error(f"Save progress failed: {e}", exc_info=True)
            return jsonify({"error": str(e)}), 500

    @app.route("/api/progress", methods=["GET"])
    def api_get_progress():
        from pathlib import Path as _P
        from .thumbnails import preview_path as _prev_path
        limit = int(request.args.get("limit", 50))
        continue_only = request.args.get("continue", "0") == "1"
        from flask import g as _g
        _pid = getattr(_g, "profile_id", 1)
        rows = get_continue_watching(limit=limit, profile_id=_pid) if continue_only else get_all_watch_progress(limit=limit, profile_id=_pid)

        # Build scan roots (mirrors episodes endpoint logic)
        _dl_str = os.environ.get("ANIWORLD_DOWNLOAD_PATH", "")
        if _dl_str:
            dl_base = _P(_dl_str).expanduser()
            if not dl_base.is_absolute():
                dl_base = _P.home() / dl_base
        else:
            dl_base = _P.home() / "Downloads"
        scan_roots = [dl_base] + [
            (_P(cp["path"]).expanduser() if _P(cp["path"]).is_absolute()
             else _P.home() / cp["path"])
            for cp in get_custom_paths()
        ]

        # Scan all download dirs once and build (title_lower, season, ep) -> preview_url map
        ep_re = re.compile(r"S(\d{2})E(\d{2,3})", re.IGNORECASE)
        unique_titles = set(
            (r.get("series_title") or "").lower()
            for r in rows
            if r.get("series_title")
        )
        preview_map = {}
        for title_lower in unique_titles:
            for root in scan_roots:
                if not root.is_dir():
                    continue
                for folder in root.iterdir():
                    if not folder.is_dir():
                        continue
                    if not folder.name.lower().startswith(title_lower):
                        continue
                    for f in folder.rglob("*.m3u8"):
                        m = ep_re.search(f.name)
                        if not m:
                            continue
                        pkey = (title_lower, int(m.group(1)), int(m.group(2)))
                        if pkey in preview_map:
                            continue
                        prev = _prev_path(f)
                        if prev.exists():
                            try:
                                rel = prev.relative_to(root)
                                preview_map[pkey] = "/api/episode-preview/" + rel.as_posix()
                            except ValueError:
                                pass

        # Enrich rows — build a new list to avoid any in-place mutation issues
        poster_cache = {}
        enriched = []
        for row in rows:
            title = row.get("series_title") or ""
            if title not in poster_cache:
                try:
                    tmdb = search_tmdb(title)
                    poster_cache[title] = _proxy_image_url(tmdb.get("poster_url") or "")
                except Exception:
                    poster_cache[title] = ""
            pkey = (title.lower(), row.get("season") or 0, row.get("episode_number") or 0)
            enriched.append({
                **row,
                "poster_url": poster_cache[title],
                "preview_url": preview_map.get(pkey, ""),
            })

        return jsonify({"progress": enriched})

    @app.route("/api/progress/<path:episode_url>", methods=["GET"])
    def api_get_episode_progress(episode_url):
        from flask import g as _g
        row = get_watch_progress(episode_url, profile_id=getattr(_g, "profile_id", 1))
        if not row:
            return jsonify({"progress": None})
        return jsonify({"progress": row})

    # ── Watchlist ────────────────────────────────────────────────────────────

    @app.route("/api/watchlist", methods=["GET"])
    def api_get_watchlist():
        from flask import g as _g
        items = get_watchlist(profile_id=getattr(_g, "profile_id", 1))
        results = [
            {
                "title": item["series_title"],
                "url": item["series_url"],
                "poster_url": item["poster_url"],
            }
            for item in items
        ]
        return jsonify({"items": results})

    @app.route("/api/watchlist", methods=["POST"])
    def api_add_to_watchlist():
        from flask import g as _g
        data = request.get_json(force=True) or {}
        series_url = (data.get("series_url") or "").strip()
        series_title = (data.get("series_title") or "").strip()
        poster_url = (data.get("poster_url") or "").strip()
        if not series_url:
            return jsonify({"error": "series_url required"}), 400
        add_to_watchlist(series_url, series_title, poster_url, profile_id=getattr(_g, "profile_id", 1))
        return jsonify({"ok": True})

    @app.route("/api/watchlist", methods=["DELETE"])
    def api_remove_from_watchlist():
        from flask import g as _g
        data = request.get_json(force=True) or {}
        series_url = (data.get("series_url") or "").strip()
        if not series_url:
            return jsonify({"error": "series_url required"}), 400
        remove_from_watchlist(series_url, profile_id=getattr(_g, "profile_id", 1))
        return jsonify({"ok": True})

    @app.route("/api/watchlist/check", methods=["GET"])
    def api_check_watchlist():
        from flask import g as _g
        series_url = request.args.get("url", "").strip()
        if not series_url:
            return jsonify({"in_list": False})
        return jsonify({"in_list": is_in_watchlist(series_url, profile_id=getattr(_g, "profile_id", 1))})

    @app.route("/api/watchlist/enriched", methods=["GET"])
    def api_get_watchlist_enriched():
        from flask import g as _g
        items = get_watchlist_enriched(profile_id=getattr(_g, "profile_id", 1))
        results = [
            {
                "title": item["series_title"],
                "url": item["series_url"],
                "poster_url": item["poster_url"],
                "last_watched_at": item["last_watched_at"],
                "new_content": item["new_content"],
            }
            for item in items
        ]
        return jsonify({"items": results})

    @app.route("/api/thumbnails", methods=["GET"])
    def api_thumbnails():
        from .thumbnails import get_or_start, resolve_m3u8, sprite_paths
        filepath = request.args.get("filepath", "").strip()
        if not filepath or ".." in filepath:
            return jsonify({"error": "invalid filepath"}), 400
        m3u8 = resolve_m3u8(filepath)
        if m3u8 is None:
            return jsonify({"error": "file not found"}), 404
        result = get_or_start(m3u8)
        if result.get("status") == "ready":
            sprite_path, _ = sprite_paths(m3u8)
            result["sprite_filepath"] = sprite_path.relative_to(m3u8.parent.parent.parent).as_posix() \
                if False else filepath.rsplit(".", 1)[0] + ".thumbs.jpg"
        return jsonify(result)

    @app.route("/api/thumbnails/sprite/<path:filepath>")
    def api_thumbnails_sprite(filepath):
        from flask import send_from_directory
        from .thumbnails import resolve_m3u8
        from pathlib import Path
        # Replace .m3u8 suffix with .thumbs.jpg if needed, then resolve base dir
        m3u8_filepath = filepath.replace(".thumbs.jpg", ".m3u8")
        m3u8 = resolve_m3u8(m3u8_filepath)
        if m3u8 is None:
            return "", 404
        sprite = m3u8.parent / (m3u8.stem + ".thumbs.jpg")
        if not sprite.exists():
            return "", 404
        return send_from_directory(str(sprite.parent), sprite.name, mimetype="image/jpeg")

    @app.route("/api/episode-preview/<path:filepath>")
    def api_episode_preview(filepath):
        from flask import send_from_directory
        from pathlib import Path

        if ".." in filepath or "\x00" in filepath:
            return "", 404

        raw = os.environ.get("ANIWORLD_DOWNLOAD_PATH", "")
        dl_base = (Path(raw).expanduser() if raw else Path.home() / "Downloads")
        if not dl_base.is_absolute():
            dl_base = Path.home() / dl_base

        search_bases = [dl_base]
        for cp in get_custom_paths():
            cp_path = Path(cp["path"]).expanduser()
            if not cp_path.is_absolute():
                cp_path = Path.home() / cp_path
            search_bases.append(cp_path)

        for base in search_bases:
            candidate = (base / filepath).resolve()
            try:
                candidate.relative_to(base.resolve())
            except ValueError:
                continue
            if candidate.is_file() and candidate.suffix.lower() == ".jpg":
                return send_from_directory(str(candidate.parent), candidate.name, mimetype="image/jpeg")

        return "", 404

    @app.route("/api/skip-times", methods=["GET"])
    def api_skip_times():
        from .skip_times import get_skip_times_for_episode
        title = request.args.get("series_title", "").strip()
        episode = int(request.args.get("episode", 1))
        if not title:
            return jsonify({"op": None, "ed": None})
        times = get_skip_times_for_episode(title, episode)
        return jsonify(times)

    # ─────────────────────────────────────────────────────────────────────────

    if auth_enabled:
        from .auth import admin_required

        # Endpoints that require admin instead of just login
        _admin_only = {
            "settings_page",
            "api_settings",
            "api_settings_public_ip",
            "api_settings_update",
            "api_library_delete",
            "api_custom_paths_add",
            "api_custom_paths_delete",
            "api_autosync_create",
            "api_autosync_update",
            "api_autosync_delete",
            "api_autosync_trigger",
        }

        # Wrap all non-auth, non-static view functions with login_required
        # (admin_required for settings endpoints)
        _exempt = {
            "static",
            "auth.login",
            "auth.logout",
            "auth.setup",
            "auth.oidc_login",
            "auth.oidc_callback",
            "api_auth_check",        # public: lets Flutter detect auth status
            "api_proxy_image",       # public: poster images are not sensitive
            "api_episode_preview",   # public: episode thumbnail images, not sensitive
            "api_thumbnails_sprite", # public: seek-bar sprite thumbnails, not sensitive
            "webapp.request_access",        # public: web build's device-approval gate
            "webapp.request_access_status", # public: polled before a token exists
            "flutter_web_app",              # public: the SPA shell itself, not the data
        }
        for endpoint, view_func in list(app.view_functions.items()):
            if endpoint not in _exempt:
                if endpoint in _admin_only:
                    app.view_functions[endpoint] = admin_required(view_func)
                else:
                    app.view_functions[endpoint] = login_required(view_func)

        # Exempt JSON API routes from CSRF (they use Content-Type: application/json
        # which provides implicit cross-origin protection via CORS preflight)
        for endpoint in list(app.view_functions):
            if endpoint.startswith("api_") or endpoint.startswith("auth.admin_"):
                csrf.exempt(app.view_functions[endpoint])

        # ── Token-based auth routes (registered after the wrapping loop so they
        #    are NOT wrapped by login_required — they handle auth themselves) ──────

        import re as _re

        @app.route("/api/auth/setup", methods=["POST"])
        def api_auth_setup():
            from .db import create_user as _create_user, has_any_admin as _has_any_admin

            if _has_any_admin():
                return jsonify({"error": "Setup already completed"}), 409
            data = request.get_json(silent=True) or {}
            username = (data.get("username") or "").strip()
            password = data.get("password") or ""
            if not username:
                return jsonify({"error": "Username is required"}), 400
            if len(username) > 64:
                return jsonify({"error": "Username must be at most 64 characters"}), 400
            if not _re.match(r"^[a-zA-Z0-9._-]+$", username):
                return jsonify({"error": "Username may only contain letters, digits, dots, hyphens, and underscores"}), 400
            if len(password) < 8:
                return jsonify({"error": "Password must be at least 8 characters"}), 400
            uid = _create_user(username, password, role="admin")
            token = create_api_token(uid)
            return jsonify({"token": token, "username": username, "role": "admin"})

        @app.route("/api/auth/login", methods=["POST"])
        def api_auth_login():
            from .db import verify_user as _verify_user

            data = request.get_json(silent=True) or {}
            username = (data.get("username") or "").strip()
            password = data.get("password") or ""
            user, err = _verify_user(username, password)
            if not user:
                return jsonify({"error": err}), 401
            token = create_api_token(user["id"])
            return jsonify({"token": token, "username": user["username"], "role": user["role"]})

        @app.route("/api/auth/logout", methods=["POST"])
        def api_auth_logout():
            auth_header = request.headers.get("Authorization", "")
            if auth_header.startswith("Bearer "):
                delete_api_token(auth_header[7:].strip())
            from flask import session as _sess
            _sess.clear()
            return jsonify({"ok": True})

        @app.route("/api/auth/me")
        def api_auth_me():
            user = get_current_user()
            if not user:
                auth_header = request.headers.get("Authorization", "")
                if auth_header.startswith("Bearer "):
                    user = validate_api_token(auth_header[7:].strip())
            if not user:
                return jsonify({"error": "Not authenticated"}), 401
            return jsonify({"id": user["id"], "username": user["username"], "role": user["role"]})

        csrf.exempt(api_auth_setup)
        csrf.exempt(api_auth_login)
        csrf.exempt(api_auth_logout)
        csrf.exempt(api_auth_me)

    return app


def start_web_ui(
    host="127.0.0.1",
    port=8080,
    open_browser=True,
    auth_enabled=False,
    sso_enabled=False,
    force_sso=False,
):
    """Start the Flask web UI server."""
    import threading
    import webbrowser

    # Allow env var overrides (Docker-friendly)
    force_sso = force_sso or os.getenv("ANIWORLD_WEB_FORCE_SSO", "0") == "1"
    sso_enabled = sso_enabled or force_sso or os.getenv("ANIWORLD_WEB_SSO", "0") == "1"
    auth_enabled = (
        auth_enabled or force_sso or os.getenv("ANIWORLD_WEB_AUTH", "0") == "1"
    )
    api_only = os.getenv("ANIWORLD_API_ONLY", "0") == "1"

    app = create_app(
        auth_enabled=auth_enabled, sso_enabled=sso_enabled, force_sso=force_sso,
        api_only=api_only,
    )
    display_host = "localhost" if host == "127.0.0.1" else host
    url = f"http://{display_host}:{port}"
    print(f"Starting AniWorld Web UI on {url}")

    debug = os.getenv("ANIWORLD_DEBUG_MODE", "0") == "1"

    # In debug mode, Flask's reloader spawns a child process that re-executes
    # this function. Only open the browser in the parent (reloader) process
    # to avoid opening it twice.
    is_reloader_child = os.environ.get("WERKZEUG_RUN_MAIN") == "true"
    if open_browser and not is_reloader_child:
        threading.Timer(0.5, webbrowser.open, args=(url,)).start()

    if debug:
        app.run(host=host, port=port, debug=True)
    else:
        from waitress import serve

        serve(app, host=host, port=port)
