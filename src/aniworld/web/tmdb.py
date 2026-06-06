"""TMDB (The Movie Database) integration for poster and backdrop images."""

import logging
import os
import time

import requests

logger = logging.getLogger(__name__)

_cache: dict = {}
_CACHE_TTL = 86400  # 24 hours

_IMAGE_BASE = "https://image.tmdb.org/t/p"
_POSTER_SIZE = "w500"
_BACKDROP_SIZE = "w1280"


def _token() -> str:
    return os.environ.get("ANIWORLD_TMDB_TOKEN", "").strip()


def search_tmdb(title: str) -> dict:
    """Search TMDB for a title and return poster/backdrop URLs.

    Returns a dict with keys 'poster_url' and 'backdrop_url'.
    Both are absolute TMDB CDN URLs or empty strings if not found.
    """
    if not title:
        return {"poster_url": "", "backdrop_url": ""}

    token = _token()
    if not token:
        return {"poster_url": "", "backdrop_url": ""}

    now = time.time()
    cached = _cache.get(title)
    if cached and now - cached["ts"] < _CACHE_TTL:
        return cached["data"]

    data = _fetch(title, token)
    _cache[title] = {"ts": now, "data": data}
    return data


def _fetch(title: str, token: str) -> dict:
    try:
        resp = requests.get(
            "https://api.themoviedb.org/3/search/multi",
            params={"api_key": token, "query": title, "language": "de-DE", "page": 1},
            timeout=10,
        )
        resp.raise_for_status()
        results = resp.json().get("results", [])

        # Prefer TV show, then movie
        result = None
        for r in results:
            if r.get("media_type") == "tv":
                result = r
                break
        if result is None:
            for r in results:
                if r.get("media_type") == "movie":
                    result = r
                    break

        if not result:
            logger.debug(f"TMDB: no result for '{title}'")
            return {"poster_url": "", "backdrop_url": ""}

        poster = result.get("poster_path") or ""
        backdrop = result.get("backdrop_path") or ""
        data = {
            "poster_url": f"{_IMAGE_BASE}/{_POSTER_SIZE}{poster}" if poster else "",
            "backdrop_url": f"{_IMAGE_BASE}/{_BACKDROP_SIZE}{backdrop}" if backdrop else "",
        }
        logger.debug(f"TMDB: '{title}' → poster={bool(poster)} backdrop={bool(backdrop)}")
        return data

    except Exception as e:
        logger.warning(f"TMDB lookup failed for '{title}': {e}")
        return {"poster_url": "", "backdrop_url": ""}
