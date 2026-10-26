"""Demo backend for the Android screenshot run (.github/workflows/android-screenshots.yml).

The real RedStream app server, but with the scraping endpoints answered from
a small fixed catalogue (CI must not depend on aniworld.to & co.), posters and
a playable HLS stream served by a local fake hoster, a seeded database
(profiles, watchlist, progress) and a fake TV that heartbeats like a browser
in screen mode.

    HOME=/tmp/rshome python android/ci/demo_server.py <workdir>
"""

import json
import os
import subprocess
import sys
import threading
import time
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import quote

WORK = Path(sys.argv[1] if len(sys.argv) > 1 else "/tmp/rsdemo")
HOSTER = "http://127.0.0.1:8701"
PORT = 8080

CATALOGUE = [
    # (slug, title, kind, colour, year, genres)
    ("frieren", "Frieren", "anime", (82, 110, 160), "2023", ["Fantasy", "Abenteuer"]),
    ("one-piece", "One Piece", "anime", (200, 90, 40), "1999", ["Action", "Abenteuer"]),
    ("dandadan", "Dandadan", "anime", (150, 60, 160), "2024", ["Action", "Comedy"]),
    ("solo-leveling", "Solo Leveling", "anime", (40, 60, 120), "2024", ["Action", "Fantasy"]),
    ("spy-x-family", "Spy x Family", "anime", (70, 140, 90), "2022", ["Comedy", "Action"]),
    ("vinland-saga", "Vinland Saga", "anime", (120, 100, 70), "2019", ["Drama", "Action"]),
    ("dark", "Dark", "serie", (40, 50, 60), "2017", ["Mystery", "Drama"]),
    ("breaking-bad", "Breaking Bad", "serie", (60, 120, 70), "2008", ["Drama", "Krimi"]),
    ("the-office", "The Office", "serie", (90, 110, 140), "2005", ["Comedy"]),
    ("stranger-things", "Stranger Things", "serie", (160, 30, 40), "2016", ["Mystery", "Horror"]),
    ("dune", "Dune", "film", (190, 150, 90), "2021", ["Sci-Fi"]),
    ("oppenheimer", "Oppenheimer", "film", (120, 60, 30), "2023", ["Drama"]),
]
SEASONS = 2
EPISODES = 8


def site(kind):
    return "https://s.to/serie/stream" if kind == "serie" else "https://aniworld.to/anime/stream"


def series_url(slug, kind):
    return f"{site(kind)}/{slug}"


# ── assets ──────────────────────────────────────────────────────────────────

def make_assets():
    from PIL import Image, ImageDraw, ImageFont

    (WORK / "img").mkdir(parents=True, exist_ok=True)
    for slug, title, _kind, rgb, _y, _g in CATALOGUE:
        for name, size, font_size in (("poster", (412, 600), 46), ("backdrop", (1280, 720), 90)):
            img = Image.new("RGB", size, rgb)
            draw = ImageDraw.Draw(img)
            for y in range(size[1]):  # simple vertical fade
                shade = int(90 * y / size[1])
                draw.line([(0, y), (size[0], y)], fill=tuple(max(0, c - shade) for c in rgb))
            font = ImageFont.load_default(size=font_size)
            words, lines, line = title.split(), [], ""
            for w in words:
                if len(line + " " + w) > (12 if name == "poster" else 20) and line:
                    lines.append(line); line = w
                else:
                    line = (line + " " + w).strip()
            lines.append(line)
            y = size[1] * 0.62 if name == "poster" else size[1] * 0.4
            for ln in lines:
                draw.text((size[0] * 0.08, y), ln, font=font, fill=(255, 255, 255))
                y += font_size * 1.15
            img.save(WORK / "img" / f"{slug}-{name}.png")

    hls = WORK / "hls"
    if not (hls / "index.m3u8").exists():
        hls.mkdir(parents=True, exist_ok=True)
        subprocess.run(
            ["ffmpeg", "-loglevel", "error", "-f", "lavfi", "-i", "testsrc2=size=1280x720:rate=25",
             "-f", "lavfi", "-i", "sine=frequency=440", "-t", "120", "-c:v", "libx264", "-preset", "ultrafast",
             "-g", "50", "-c:a", "aac", "-f", "hls", "-hls_time", "4", "-hls_list_size", "0",
             "-hls_playlist_type", "vod", "-hls_segment_filename", str(hls / "seg_%03d.ts"), str(hls / "index.m3u8")],
            check=True,
        )


def serve_assets():
    class Quiet(SimpleHTTPRequestHandler):
        def __init__(self, *a, **kw):
            super().__init__(*a, directory=str(WORK), **kw)

        def log_message(self, *a):
            pass

    srv = ThreadingHTTPServer(("127.0.0.1", 8701), Quiet)
    threading.Thread(target=srv.serve_forever, daemon=True).start()


def proxied(path):
    return "/api/proxy-image?url=" + quote(f"{HOSTER}/{path}", safe="")


# ── app with patched scraping endpoints ─────────────────────────────────────

def build_app():
    from flask import jsonify, request

    import aniworld.providers as providers
    from aniworld.models.common import common
    from aniworld.web.app import create_app

    by_url = {series_url(s, k): (s, t, k, rgb, y, g) for s, t, k, rgb, y, g in CATALOGUE}

    def item(entry):
        slug, title, kind = entry[0], entry[1], entry[2]
        return {"title": title, "url": series_url(slug, kind), "poster_url": proxied(f"img/{slug}-poster.png")}

    def results(kinds):
        return jsonify({"results": [item(e) for e in CATALOGUE if e[2] in kinds]})

    def paged(kinds):
        genre = request.args.get("genre")
        rows = [e for e in CATALOGUE if e[2] in kinds and (not genre or genre in e[5])]
        genres = sorted({g for e in CATALOGUE if e[2] in kinds for g in e[5]})
        return jsonify({"results": [item(e) for e in rows], "total": len(rows), "page": 1,
                        "per_page": 30, "has_more": False, "all_genres": genres})

    def search():
        data = request.get_json(silent=True) or {}
        q = (data.get("keyword") or "").lower()
        kinds = {"aniworld": ("anime",), "sto": ("serie",), "megakino": ("film",)}.get(data.get("site"), ("anime",))
        return jsonify({"results": [item(e) for e in CATALOGUE if e[2] in kinds and q in e[1].lower()]})

    def series():
        e = by_url.get(request.args.get("url", ""))
        if not e:
            return jsonify({"error": "unknown"}), 404
        slug, title, _k, _rgb, year, genres = e
        return jsonify({"title": title, "poster_url": proxied(f"img/{slug}-poster.png"),
                        "backdrop_url": proxied(f"img/{slug}-backdrop.png"),
                        "description": f"{title} – Demo-Beschreibung für die Screenshots der Android-App. "
                                       "Die echten Inhalte kommen im Betrieb von den Seiten selbst.",
                        "genres": genres, "release_year": year})

    def seasons():
        url = request.args.get("url", "")
        e = by_url.get(url)
        n = 1 if e and e[2] == "film" else SEASONS
        return jsonify({"seasons": [{"url": f"{url}/staffel-{i}", "season_number": i, "episode_count": EPISODES,
                                     "are_movies": bool(e and e[2] == "film")} for i in range(1, n + 1)]})

    def episodes():
        url = request.args.get("url", "")
        count = 1 if "/dune/" in url or "/oppenheimer/" in url else EPISODES
        return jsonify({"episodes": [{
            "url": f"{url}/episode-{i}", "episode_number": i,
            "title_de": f"Folge {i}" if i != 1 else "Der Anfang", "title_en": f"Episode {i}",
            "downloaded": i == 2, "available_languages": ["German Dub", "German Sub", "English Sub"],
            "folder": "Demo" if i == 2 else None, "absolute_episode_number": None, "preview_url": None,
        } for i in range(1, count + 1)]})

    class FakeEpisode:
        def __init__(self, url, **kw):
            self.url = url

    providers.resolve_provider = lambda url: type("P", (), {"episode_cls": FakeEpisode, "name": "AniWorld"})
    common.resolve_live_stream = lambda ep: {"provider": "VOE", "url": f"{HOSTER}/hls/index.m3u8", "headers": {}}

    import aniworld.web.app as web_app

    def fake_tmdb(title):
        e = next((c for c in CATALOGUE if c[1] == title), None)
        if not e:
            return {}
        return {"poster_url": f"{HOSTER}/img/{e[0]}-poster.png", "backdrop_url": f"{HOSTER}/img/{e[0]}-backdrop.png"}

    web_app.search_tmdb = fake_tmdb  # Weiterschauen cards look up artwork via TMDB

    app = create_app()
    overrides = {
        "api_new_animes": lambda: results(("anime",)),
        "api_popular_animes": lambda: results(("anime",)),
        "api_new_series": lambda: results(("serie",)),
        "api_popular_series": lambda: results(("serie",)),
        "api_popular_movies": lambda: results(("film",)),
        "api_all_animes": lambda: paged(("anime",)),
        "api_all_series": lambda: paged(("serie",)),
        "api_all_movies": lambda: paged(("film",)),
        "api_search": search,
        "api_series": series,
        "api_seasons": seasons,
        "api_episodes": episodes,
        "api_providers": lambda: jsonify({"providers": {"German Dub": ["VOE"], "German Sub": ["VOE"], "English Sub": ["Vidmoly"]}}),
        # downloaded episodes: point straight at the demo stream
        "api_stream": lambda: jsonify({"url": f"{HOSTER}/hls/index.m3u8"}),
    }
    for name, fn in overrides.items():
        assert name in app.view_functions, name
        app.view_functions[name] = fn
    return app


def seed():
    from aniworld.web import db

    for init in ("init_db", "init_web_access_requests_db", "init_profiles_db", "init_watch_progress_db", "init_watchlist_db", "init_queue_db"):
        getattr(db, init)()
    if not db.has_any_admin():
        db.create_user("admin", "demo-password", role="admin")
    if not any(p["name"] == "Lena" for p in db.get_profiles()):
        db.create_profile("Lena", "#3b82f6")
    for slug, title, kind, *_ in CATALOGUE[:4]:
        db.add_to_watchlist(series_url(slug, kind), title, proxied(f"img/{slug}-poster.png"), profile_id=1)
    for slug, ep, pos, done in (("frieren", 3, 610, False), ("one-piece", 7, 1300, True), ("dark", 2, 900, False)):
        e = next(c for c in CATALOGUE if c[0] == slug)
        su = series_url(slug, e[2])
        db.upsert_watch_progress(
            f"{su}/staffel-1/episode-{ep}", series_title=e[1], series_url=su, season=1, episode_number=ep,
            episode_title=f"Folge {ep}", position_seconds=pos, duration_seconds=1420, completed=done, profile_id=1,
        )


def fake_tv(app):
    """A 'browser in screen mode' named TV Wohnzimmer, playing Frieren."""
    client = app.test_client()
    screen_id, pos = None, 300
    while True:
        state = {"status": "playing", "episode_url": series_url("frieren", "anime") + "/staffel-1/episode-3",
                 "series_title": "Frieren", "series_url": series_url("frieren", "anime"), "season": 1,
                 "episode_number": 3, "episode_title": "Folge 3", "language": "German Dub",
                 "position": pos, "duration": 1420}
        r = client.post("/api/cast/heartbeat", json={"screen_id": screen_id, "name": "TV Wohnzimmer", "state": state},
                        headers={"X-Profile-ID": "1"}).get_json()
        screen_id = r["screen_id"]
        for cmd in r["commands"]:
            print("TV received command:", json.dumps(cmd), flush=True)
        pos += 1
        time.sleep(1)


def main():
    make_assets()
    serve_assets()
    seed()
    app = build_app()
    threading.Thread(target=fake_tv, args=(app,), daemon=True).start()
    from waitress import serve

    print(f"Demo backend on :{PORT}", flush=True)
    serve(app, host="0.0.0.0", port=PORT, threads=16)


if __name__ == "__main__":
    os.environ.setdefault("ANIWORLD_ENABLE_WEBAPP", "1")
    main()
