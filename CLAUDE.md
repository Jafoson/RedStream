# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Commands

```bash
# Install in editable mode for development
pip install -e .

# Run the CLI
python -m aniworld
aniworld

# Launch web UI
aniworld -w

# Run model integration tests (makes real HTTP requests to aniworld.to / serienstream.to)
python tests/test_aniworld_models.py

# Run provider extractor tests (makes real HTTP requests to provider sites)
python tests/test_aniworld_providers.py

# Enable debug logging
aniworld --debug

# Docker
docker build -t aniworld .
docker-compose up -d --build
```

There is no lint or type-check command configured in the project.

## Architecture

### Request flow

`aniworld` CLI → `entry.py:aniworld()` → `arguments.py:parse_args()` → `providers.py:resolve_provider(url)` → either the TUI menu (`menu.py`, npyscreen) or the web UI (`web/app.py`, Flask/Waitress) → resolves to an episode/season/series model → calls `model.download()` / `model.watch()` / `model.syncplay()`.

Setting `ANIWORLD_NO_MENU=1` bypasses the TUI entirely and processes URLs directly.

### Provider registry (`src/aniworld/providers.py`)

`resolve_provider(url)` matches a URL against the `PROVIDERS` list of frozen `Provider` dataclasses, each holding URL regex patterns and the corresponding model classes (`series_cls`, `season_cls`, `episode_cls`). Supported providers: AniWorld, SerienStream, HanimeTV. HiAnime has placeholder patterns (WIP — empty regexes) and `filmpalast_to/` has models but is not registered.

### Model layer (`src/aniworld/models/`)

Each supported site has a subdirectory (`aniworld_to/`, `s_to/`, `hianime_to/`, `hanime_tv/`) with `episode.py`, `season.py`, `series.py`. All episode models share the **same three actions**, which are standalone functions in `models/common/common.py` attached as class attributes:

```python
download = episode_download   # from models/common/common.py
watch    = episode_watch
syncplay = episode_syncplay
```

Episode properties (`stream_url`, `_episode_path`, `provider_data`, …) are all lazy-loaded via `@property` backed by double-underscore private instance vars. Invalidation (e.g. when `selected_language` changes) resets the relevant private vars to `None` in the setter.

### Download pipeline (`models/common/common.py`)

`download()` → iterates provider attempt order with 3 retries each → resolves stream URL → invokes `_run_ffmpeg_with_progress()` → writes HLS output. Partial `.m3u8` and `_NNN.ts` files are deleted on any failure before trying the next provider.

**Output format**: `.m3u8` playlist + `_NNN.ts` segments (4 s each, `independent_segments`, `vod` playlist type). The `.m3u8` path is derived from `self._episode_path` (which itself comes from `NAMING_TEMPLATE`).

`_run_ffmpeg_with_progress()` spawns FFmpeg as a subprocess, reads stderr byte-by-byte via a reader thread, and parses progress lines. Progress is tracked **per download**, not globally: `bind_progress_to_queue_item(queue_id)` binds the calling thread to a bucket in `_ffmpeg_progress_by_item`, so several concurrent downloads (see below) don't clobber each other's numbers; `get_ffmpeg_progress()` returns either one item's snapshot or the whole `{queue_id: progress}` map. Stall detection kills the process after 60 s of no progress. `check_downloaded()` only counts an episode as done when its playlist has `#EXT-X-ENDLIST` (written by FFmpeg at the very end), so a download killed mid-episode is redone instead of skipped.

Provider attempt order: selected provider first, then fallback order from `ANIWORLD_PROVIDER_FALLBACK_ORDER`. `build_provider_attempt_order()` in `config.py` handles deduplication.

**Queue worker pool** (`web/download_worker.py`): a pool of `ANIWORLD_MAX_CONCURRENT_DOWNLOADS` (default 3) threads pulls from `download_queue` (`web/db.py`). Each queued item belongs to a *bucket* — its `profile_id`, or a shared `"_autosync"` bucket for items with no profile (auto-sync-queued). A worker thread only claims an item whose bucket isn't already downloading something, so each profile effectively gets its own serial pipeline while different profiles can download in parallel, up to the pool cap. Priority (0=watch-intent, 1=prefetch, 2=manual, 3=autosync) decides pick order among eligible items; a P0 watch-intent still preempts a running P1 prefetch **in the same bucket** (`maybe_preempt_for_p0()`), requeueing it. Cancellation goes through `db.request_cancel(queue_id, force=...)` + `cancel_flags()`: a still-`queued` item is cancelled outright, a `running` one is flagged and the worker notices between episodes (soft) or has its thread's ffmpeg process killed via `kill_active_ffmpeg(thread_id=...)` (force). Restarts: items still `running` at startup were interrupted by a crash; `reset_stale_running()` requeues them but gives up (marks `failed`) after `MAX_CRASH_RESETS` interruptions, so one download that kills the process can't crash-loop the container — finishing an episode clears the count. A clean stop is different: `start_web_ui()` installs SIGTERM/SIGINT handlers (needed because the image runs `aniworld` as PID 1, which otherwise ignores SIGTERM until Kubernetes SIGKILLs it) that call `download_worker.shutdown()`, which requeues running items without counting a crash. `web/worker.py` is an unrelated, unwired leftover from the last upstream merge (see Branch note) — don't use it; `web/app.py`'s old two-slot express/normal system was replaced by this pool.

### Extractor layer (`src/aniworld/extractors/`)

`extractors/__init__.py` auto-discovers every module under `extractors/provider/` at import time with `pkgutil` and registers any function named `get_direct_link_from_<provider>` or `get_preview_image_link_from_<provider>` into the `provider_functions` dict.

To add a new provider: create `extractors/provider/myprovider.py` with a `get_direct_link_from_myprovider(url) -> str` function — it is automatically registered.

### Configuration

`config.py` is the central config module. Key items:

- `NAMING_TEMPLATE` – controls output path/filename. Default ends in `.m3u8`; override with `ANIWORLD_NAMING_TEMPLATE`.
- `Audio` / `Subtitles` enums and `LANG_KEY_MAP` / `LANG_CODE_MAP` – map site language keys to ISO 639-2 codes used in FFmpeg metadata.
- `SUPPORTED_PROVIDERS` – canonical list for fallback logic (VOE, Vidmoly, Vidoza; others are commented out).
- `VIDEO_CODEC_MAP` – maps user-facing names (`copy`, `h264`, `h265`, `av1`) to FFmpeg codec strings.
- `GLOBAL_SESSION` – shared `niquests.Session` (not `requests`) with DoH (`doh+google://`) and browser-like headers.

User settings live in `~/.aniworld/.env` (template at `src/aniworld/.env.example`). Relevant env vars:

| Variable | Default | Purpose |
|---|---|---|
| `ANIWORLD_DOWNLOAD_PATH` | `~/Downloads` | Root download directory |
| `ANIWORLD_NAMING_TEMPLATE` | (see config.py) | Path/filename template |
| `ANIWORLD_LANGUAGE` | `German Dub` | Default audio language |
| `ANIWORLD_PROVIDER` | `VOE` | Default provider |
| `ANIWORLD_PROVIDER_FALLBACK_ORDER` | all supported | Comma-separated provider priority |
| `ANIWORLD_VIDEO_CODEC` | `copy` | `copy` / `h264` / `h265` / `av1` |
| `ANIWORLD_ANISKIP` | `0` | Enable AniSkip intro/outro detection |
| `ANIWORLD_DEBUG_MODE` | `0` | Verbose FFmpeg + HTTP logging |
| `ANIWORLD_NO_MENU` | `0` | Skip TUI; process URLs directly |
| `ANIWORLD_SYNCPLAY_HOST` | `syncplay.pl:8998` | Syncplay server |
| `ANIWORLD_SYNCPLAY_PASSWORD` | — | Hashed into room name for privacy |
| `ANIWORLD_SYNCPLAY_USERNAME` | system user | Syncplay display name |
| `ANIWORLD_SYNCPLAY_ROOM` | derived | Override auto-generated room name |
| `ANIWORLD_OIDC_ISSUER_URL` | — | OIDC issuer for web UI SSO |
| `ANIWORLD_OIDC_CLIENT_ID` | — | OIDC client ID |
| `ANIWORLD_OIDC_CLIENT_SECRET` | — | OIDC client secret |
| `ANIWORLD_OIDC_DISPLAY_NAME` | `SSO` | Button label in login UI |
| `ANIWORLD_OIDC_ADMIN_USER` | — | Username to grant admin on first SSO login |
| `ANIWORLD_OIDC_ADMIN_SUBJECT` | — | OIDC `sub` claim to grant admin |

### Web UI (`src/aniworld/web/`)

Flask app served by Waitress, exposing a JSON REST API (documented in `API.md`) consumed by one same-origin browser frontend, built and served independently:

- **RedStream TV web app** (`webapp/`, see below) — the site's only browser frontend, served at `/`. A Vite + React + TypeScript SPA with a TV-oriented design (dark theme, poster rails, D-pad-style focus treatment reused as plain `:hover`/`:focus-visible`). Device-approval auth instead of a login form (see below) — there is no username/password form anywhere in the browser.

There used to be a second frontend, a `/react` dashboard with local username/password + OIDC/SSO login, served at this same root; it was removed so this is the only web UI. `ANIWORLD_ENABLE_WEBAPP` is now the sole on/off switch for the web UI (see below) — the old `ANIWORLD_API_ONLY` flag that used to disable just the React dashboard no longer exists, since there's nothing left for it to selectively disable. `web/templates/` and `web/static/` (the pre-React Jinja/vanilla-JS dashboard, removed earlier) and `react/` (removed with this change) — don't recreate either; add SPA components under `webapp/src/` instead.

**Authentication** (`web/auth.py`): Optional local username/password auth or OIDC/SSO via `authlib`, exposed purely as a JSON API (`POST /api/auth/login`, `POST /api/auth/setup`, `GET /api/auth/me`) — with the React dashboard gone, nothing in this repo's own UI actually drives it anymore (the TV web app never shows a password/SSO form; see its device-approval flow below), but the endpoints stay for API consumers/integrations that might. OIDC/SSO still uses server-side redirects (`/oidc/login`, `/oidc/callback`) since that's an IdP round-trip a `fetch()` call can't perform; on failure it redirects to `/?login_error=<message>` — since the TV web app doesn't read that param, this now just lands on its normal device-approval/profile screen with the error silently ignored. `--web-force-sso` disables the password form entirely (still relevant for the JSON API itself). Roles: `admin` and `user`.

**Database** (`web/db.py`): SQLite at `~/.aniworld/`. Manages:
- Download queue (status, progress, errors)
- Autosync jobs (periodic episode checks)
- Custom download paths

**CLI flags for web UI**:

| Flag | Purpose |
|---|---|
| `-w` / `--web-ui` | Start the web UI |
| `-wP` / `--web-port` | Port (default 8080) |
| `-wN` / `--no-browser` | Don't open browser on start |
| `-wE` / `--web-expose` | Bind to `0.0.0.0` instead of localhost |
| `-wA` / `--web-auth` | Enable local auth |
| `-wS` / `--web-sso` | Enable OIDC/SSO login |
| `-wFS` / `--web-force-sso` | Force SSO-only (implies `--web-auth` + `--web-sso`) |
| `--web-requests` | List TV web app access requests and exit |
| `--web-approve <id>` | Approve a pending web-app access request and exit |
| `--web-deny <id>` | Deny a pending web-app access request and exit |
| `--web-revoke <id>` | Revoke a previously approved web-app access request and exit |

The same four flags also cover **admin dashboard** requests (type `admin` in the `--web-requests` listing, each with a confirmation code the browser shows too).

The web UI polls `get_ffmpeg_progress()` for live download progress.

**RedStream TV web app & device approval** (`webapp/`, `web/webapp_auth.py`): a Vite + React + TypeScript SPA built with `npm run build` in `webapp/` (Docker's `webapp-builder` stage), copied into `web/webapp_dist/` at image build time and served same-origin by Flask at the site root (`app.py`'s `index` route — an SPA-fallback catch-all, `api/`-prefixed paths excluded so a removed/mistyped endpoint 404s instead of silently returning the SPA shell). Local dev: `npm run dev` in `webapp/`, proxying `/api`, `/oidc`, `/admin` to a separately-running `aniworld -w` backend (`vite.config.ts`'s `base` is `/`, matching root serving). Baked into the image unconditionally; `ANIWORLD_ENABLE_WEBAPP` (default `1`) is a runtime on/off switch — set to `0` to fully unregister the web UI and the `/api/webapp/*` blueprint, leaving only `/api/*`. It is independent of `--web-auth`/`--web-sso` and never shows a username/password form: a browser without a token calls `POST /api/webapp/request-access`, gets a `device_id`, and polls `GET /api/webapp/request-access/<device_id>` until an admin approves it from the server terminal (`--web-requests` / `--web-approve <id>` / `--web-deny <id>` / `--web-revoke <id>`, backed by the `web_access_requests` table in `web/db.py`). Approval logs the browser in as the (first) admin account and issues a normal bearer token via the existing `api_tokens` mechanism — revoking just deletes that token (`webapp/src/context/AuthContext.tsx`'s `logout()`, wired to Settings' "Zugriff widerrufen").

**Admin dashboard** (`webapp/src/pages/AdminPage.tsx` at `/verwaltung`, linked from Settings → Verwaltung; backend `web/admin_api.py`): a second, terminal-only approval on top of the web app's own. An already-approved browser calls `POST /api/webapp/admin-access`, shows the returned code, and the owner approves that `admin`-type row in `web_access_requests` with `--web-approve <id>`. That issues a separate admin token (stored only as `token_hash` once picked up, valid for that browser until revoked, `X-Admin-Token` header) that works solely for `/api/admin/*`; admin requests can never be approved from inside the dashboard. The download queue ("Downloads") and the on-disk library with storage stats and per-episode/season/title deletion ("Bibliothek") live only here (`webapp/src/pages/admin/`), not in the sidebar — the TV app's normal sidebar has no Queue/Library screens anymore. The dashboard approves/denies/revokes web-app devices and shows every profile's `watch_progress` rows, where deleting a row (or a whole series per profile) makes the episode count as never watched again.

**Direct streaming** (`web/live_stream.py`, `webapp/src/api/live.ts`): when an episode isn't on disk, `DownloadPlayPage` first calls `POST /api/live/resolve` (provider fallback via `models/common/common.py:resolve_live_stream()`, the same resolution `watch()` uses for mpv) and plays the returned same-origin relay URL — HLS playlists are fetched with the provider's `PROVIDER_HEADERS_D` and every URI rewritten back to `/api/live/<sid>/…`, segments/keys/MP4s are streamed through with Range support, nothing touches disk. If resolving fails, or the player hits a fatal error mid-stream (`HlsPlayer`'s `onFatalError` → `PlayerPage` re-enters `/download-play` with `forceDownload`), it falls back to the old download-and-play path. Per-browser toggle in Settings → Wiedergabe (`rstv_direct_stream`, default on). While direct streaming, `PlayerPage` doesn't enqueue the next episode's prefetch download.

**Language switch in the player**: `PlayerPage` loads the episode's languages from `/api/providers` and `PlayerControls` shows them in a menu (mouse or D-pad: focus "lang" in the control row, ↑/↓, Enter). Choosing one saves the series language for the profile (`PUT /api/series-language`) and re-enters `/download-play` with `languageSwitch` set — that path skips the library (it can't tell which language a downloaded file is in) and always direct-streams; resume comes from the saved progress. If the new language can't be streamed it offers to continue in the previous one.

**Cast to a TV** (`web/cast.py`, `webapp/src/cast/`): every web app tab with Settings → Bildschirm → "Als Bildschirm verfügbar" on (default) runs `CastReceiver`, which heartbeats `POST /api/cast/heartbeat` every 1.5 s with its name, profile and `cast/playback.ts`'s now-playing state, and executes the commands queued for it (play → re-enters `/download-play` after switching to the sender's profile; pause/resume/toggle/seek act on the `<video>`; stop → Home). The Android app is the controller.

### Android app (`android/`)

Native Kotlin + Jetpack Compose app (package `de.redstream.app`, minSdk 26), a client of the same JSON API as the web app: setup = server URL + the web app's device approval (`/api/webapp/request-access`, code shown, approved in the terminal), then profile picker; tabs Start / Entdecken / Suche / Meine Liste / Mehr; detail page with seasons/episodes/progress/language/watchlist; Media3 player (downloaded episodes via `/api/stream`, others via `/api/live/resolve`, resume + progress saving, auto next episode, language menu). Playback target is either the phone or a TV picked from `/api/cast/screens` (`CastController`, remote bar with seek/toggle/stop); "Auf TV" in the player hands over at the current position. Built only on GitHub Actions (`.github/workflows/android.yml`, on pushes touching `android/`; manual dispatch can attach the APK to a release) — the Android SDK isn't reachable from the dev container. Release APKs are signed with the debug key (sideloading). No UI tests; it has never been run on an emulator from here.

### iOS app (`ios/`)

Native SwiftUI app (bundle id `de.redstream.app`, iOS 16+), feature-for-feature the same as the Android app and a client of the same JSON API (device approval, profiles, tabs, detail, AVPlayer player with resume/progress/next episode/language menu/hand-over to a TV, cast sheet + remote bar). The Xcode project is generated from `ios/project.yml` with XcodeGen — no `.xcodeproj` is checked in. Built only on GitHub Actions (`.github/workflows/ios.yml`, macOS runner, on pushes touching `ios/`; manual dispatch with `release` attaches the IPA to an `ios-v<version>` release). The IPA is **unsigned** (no Apple developer account): it is installed by sideloading with AltStore / Sideloadly, which sign it with the user's Apple ID. `ios-screenshots.yml` runs `RedStreamUITests/ScreenshotTests` in the simulator against `android/ci/demo_server.py` (pending approvals are approved by `ios/ci/auto_approve.py`) and pushes the PNGs to the `ci-screenshots-ios` tag; `android-screenshots.yml` does the same on an Android emulator (`android/ci/drive.py`, tag `ci-screenshots`).

Design system for the TV web app: dark theme, poster rails, colors/radii/typography/layout constants in `webapp/src/styles/theme.css`; remote-control (D-pad) navigation via the app's own focus engine (`webapp/src/tv/FocusEngine.tsx`), with the focus ring (accent border + glow + scale) also shown on plain `:hover`/`:focus-visible`. Screens: Home (rails), Grid (Serien/Anime/Filme, paginated), Search, Detail (hero/seasons/episodes/language override/watchlist/autosync), Player (custom HLS controls via `hls.js`, skip-intro/outro, auto-advance, resume, language switch), Watchlist, Settings (Speicher/Anzeige/Wiedergabe/Verbindung/Verwaltung), Profile picker, and the admin dashboard. The former Flutter client (`app/`) was removed; the native clients are `android/` and `ios/`.

### Anime4K (`src/aniworld/anime4k/`)

Optional upscaling via `--anime4k High|Low|Remove`. Installs Anime4K GLSL shaders into the mpv scripts directory (`~/.config/mpv/scripts` on Linux/macOS, `%APPDATA%\mpv\scripts` on Windows).

### Playwright / captcha (`src/aniworld/playwright/`)

Some sites require solving a captcha. `autodeps.py:ensure_patchright_chromium()` (called at startup) downloads a Chromium build via `patchright` if needed. `web/captcha.py` exposes an endpoint for manual captcha solving in the web UI.

### Windows-specific behaviour

On Windows, `DependencyManager` in `autodeps.py` auto-downloads FFmpeg (from BtbN/FFmpeg-Builds) and mpv (`shinchiro/mpv-winbuild-cmake`) if they are not on `PATH`. This runs at the start of every `download()` call.

### Branch note

The active development branch is `models`. The `NAMING_TEMPLATE` and all fallback extensions in episode models use `.m3u8` (not `.mkv`) — the final download artefact is an HLS bundle, not a single container file.

### Upstream-merge leftovers (do not build on these)

The `merge: sync with upstream phoenixthrush/AniWorld-Downloader (233 commits)` commit brought in upstream's parallel rewrite of the web layer, which this fork deliberately did not adopt (see that commit's message) because it would have broken every endpoint the Flutter app and this fork's own browser UI depend on. Left behind, unwired, and **incompatible with this fork's actual `web/db.py`** (they expect `db._initialized`, `db.QUEUE_STATUSES`, `db.cancel_flags`, `db.reset_stale_running`, none of which exist here):

- `web/views/` (Flask blueprints, never registered in `create_app()`) and its templates/static assets (`queue.html`, `queue.js`, …).
- `web/worker.py` — a single-item queue consumer; superseded by `web/download_worker.py` for the pool/profile-bucketed design. `autosync.py` used to call `worker.ensure_started()`, which crashed (see below) — that call was replaced with `download_worker.ensure_started()`.
- `tests/test_worker.py`, `tests/test_db_queue.py`, `tests/test_api_queue.py`, `tests/test_theming.py`, and in fact **the entire pytest suite** (`tests/conftest.py`'s autouse `fresh_db` fixture does `monkeypatch.setattr(db, "_initialized", False)`, which fails for every test since that attribute doesn't exist) — this is a pre-existing, branch-wide breakage, not something any single feature session introduced. Fixing it means either adding the compatibility surface to `db.py` or rewriting `conftest.py` for this fork's actual init pattern; nobody has done either yet.

The second upstream sync (`merge: sync with upstream … (114 commits)`, up to upstream `f952f29`) followed the same rule: backend (`models/`, `extractors/`, `search.py`, `playwright/`, `config.py`, `arguments.py`) taken from upstream; `web/app.py`, `web/auth.py`, `web/db.py` kept as this fork's, with only upstream's login throttle (`web/throttle.py`, used by `/api/auth/login`), the unknown-username dummy-hash timing fix, pinned static MIME types and `ANIWORLD_WEB_TRUSTED_PROXY` ported in by hand; the download path in `models/common/common.py` stays HLS-only (upstream's separate-audio-rendition MKV muxing for HentaiHaven/Moflix was not adopted). Upstream dropped `rich`, so CLI output in `arguments.py` is plain `print()`.

If you're about to "finish" or extend `worker.py`/`views/`, stop — read this section first. Verify anything discovered here against current `git log`/`hasattr()` before trusting it; this note describes state as of the `eaf17ca` commit and may drift.
