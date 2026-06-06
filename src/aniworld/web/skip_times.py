from ..config import GLOBAL_SESSION, logger
from ..aniskip.jikan import search_jikan
from ..aniskip.aniskip import get_skip_times as _aniskip_get

_mal_id_cache: dict = {}
_skip_cache: dict = {}

ANIMESKIP_URL = "https://api.anime-skip.com/graphql"
# Public client ID used by the AnimeSkip browser extension for unauthenticated reads
ANIMESKIP_CLIENT_ID = "ZGV2ZWxvcGVyc0BhbmltZS1za2lwLmNvbQ=="


# ── AniSkip ───────────────────────────────────────────────────────────────────

def _mal_id_for(title: str) -> int | None:
    key = title.lower()
    if key in _mal_id_cache:
        return _mal_id_cache[key]
    results = search_jikan(title, limit=5)
    mal_id = next((r["mal_id"] for r in results if r.get("type") == "TV"), None)
    _mal_id_cache[key] = mal_id
    return mal_id


def _from_aniskip(title: str, episode: int) -> dict:
    mal_id = _mal_id_for(title)
    if not mal_id:
        return {}
    data = _aniskip_get(mal_id, episode)
    if not data or not data.get("found"):
        return {}
    result = {}
    for entry in data.get("results", []):
        skip_type = entry.get("skip_type")
        interval = entry.get("interval", {})
        if skip_type in ("op", "ed"):
            result[skip_type] = {
                "start": float(interval.get("start_time", 0)),
                "end": float(interval.get("end_time", 0)),
            }
    return result


# ── AnimeSkip (GraphQL fallback) ───────────────────────────────────────────────

def _from_animeskip(title: str, episode: int) -> dict:
    try:
        search_q = """
        query($q: String!) {
          searchShows(search: $q) { id name }
        }
        """
        r = GLOBAL_SESSION.post(
            ANIMESKIP_URL,
            json={"query": search_q, "variables": {"q": title}},
            headers={"X-Client-ID": ANIMESKIP_CLIENT_ID},
            timeout=8,
        )
        r.raise_for_status()
        shows = (r.json().get("data") or {}).get("searchShows", [])
        if not shows:
            return {}

        show_id = shows[0]["id"]

        ep_q = """
        query($showId: ID!) {
          show(id: $showId) {
            episodes {
              number
              timestamps { at type { name skipType } }
            }
          }
        }
        """
        r2 = GLOBAL_SESSION.post(
            ANIMESKIP_URL,
            json={"query": ep_q, "variables": {"showId": show_id}},
            headers={"X-Client-ID": ANIMESKIP_CLIENT_ID},
            timeout=10,
        )
        r2.raise_for_status()
        episodes = (r2.json().get("data") or {}).get("show", {}).get("episodes", [])

        # Find the matching episode (number can be int or float)
        ep_data = next(
            (e for e in episodes if abs(float(e.get("number", -1)) - episode) < 0.5),
            None,
        )
        if not ep_data:
            return {}

        timestamps = sorted(ep_data.get("timestamps", []), key=lambda t: t.get("at", 0))
        result = {}

        for i, ts in enumerate(timestamps):
            skip_type_raw = (ts.get("type") or {}).get("skipType", "")
            at = float(ts.get("at", 0))

            # Determine end: next timestamp's start, or +90s for intro, +120s for outro
            if i + 1 < len(timestamps):
                end = float(timestamps[i + 1].get("at", at + 90))
            else:
                end = at + 120.0

            if skip_type_raw == "INTRO" and "op" not in result:
                result["op"] = {"start": at, "end": end}
            elif skip_type_raw == "OUTRO" and "ed" not in result:
                result["ed"] = {"start": at, "end": end}

        return result
    except Exception as e:
        logger.debug(f"AnimeSkip lookup failed for '{title}' E{episode}: {e}")
        return {}


# ── Public ────────────────────────────────────────────────────────────────────

def get_skip_times_for_episode(title: str, episode: int) -> dict:
    cache_key = (title.lower(), episode)
    if cache_key in _skip_cache:
        return _skip_cache[cache_key]

    result = _from_aniskip(title, episode)
    if not result:
        result = _from_animeskip(title, episode)

    result.setdefault("op", None)
    result.setdefault("ed", None)

    _skip_cache[cache_key] = result
    return result
