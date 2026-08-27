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

`_run_ffmpeg_with_progress()` spawns FFmpeg as a subprocess, reads stderr byte-by-byte via a reader thread, and parses progress lines. Progress is tracked **per download**, not globally: `bind_progress_to_queue_item(queue_id)` binds the calling thread to a bucket in `_ffmpeg_progress_by_item`, so several concurrent downloads (see below) don't clobber each other's numbers; `get_ffmpeg_progress()` returns either one item's snapshot or the whole `{queue_id: progress}` map. Stall detection kills the process after 60 s of no progress.

Provider attempt order: selected provider first, then fallback order from `ANIWORLD_PROVIDER_FALLBACK_ORDER`. `build_provider_attempt_order()` in `config.py` handles deduplication.

**Queue worker pool** (`web/download_worker.py`): a pool of `ANIWORLD_MAX_CONCURRENT_DOWNLOADS` (default 3) threads pulls from `download_queue` (`web/db.py`). Each queued item belongs to a *bucket* — its `profile_id`, or a shared `"_autosync"` bucket for items with no profile (auto-sync-queued). A worker thread only claims an item whose bucket isn't already downloading something, so each profile effectively gets its own serial pipeline while different profiles can download in parallel, up to the pool cap. Priority (0=watch-intent, 1=prefetch, 2=manual, 3=autosync) decides pick order among eligible items; a P0 watch-intent still preempts a running P1 prefetch **in the same bucket** (`maybe_preempt_for_p0()`), requeueing it. Cancellation goes through `db.request_cancel(queue_id, force=...)` + `cancel_flags()`: a still-`queued` item is cancelled outright, a `running` one is flagged and the worker notices between episodes (soft) or has its thread's ffmpeg process killed via `kill_active_ffmpeg(thread_id=...)` (force). `web/worker.py` is an unrelated, unwired leftover from the last upstream merge (see Branch note) — don't use it; `web/app.py`'s old two-slot express/normal system was replaced by this pool.

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

Flask app served by Waitress, exposing a JSON REST API (documented in `API.md`) consumed by one same-origin browser frontend, built and served independently (plus the native Flutter app, which talks to the same API but isn't served by Flask):

- **RedStream TV web app** (`webapp/`, see below) — the site's only browser frontend, served at `/`. A Vite + React + TypeScript SPA styled after the native Flutter app's TV-oriented design (dark theme, poster rails, D-pad-style focus treatment reused as plain `:hover`/`:focus-visible`), used as the browser/web target for what used to be the Flutter app's own web build. Device-approval auth instead of a login form (see below) — there is no username/password form anywhere in the browser.

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

The web UI polls `get_ffmpeg_progress()` for live download progress.

**RedStream TV web app & device approval** (`webapp/`, `web/webapp_auth.py`): a Vite + React + TypeScript SPA built with `npm run build` in `webapp/` (Docker's `webapp-builder` stage), copied into `web/webapp_dist/` at image build time and served same-origin by Flask at the site root (`app.py`'s `index` route — an SPA-fallback catch-all, `api/`-prefixed paths excluded so a removed/mistyped endpoint 404s instead of silently returning the SPA shell). Local dev: `npm run dev` in `webapp/`, proxying `/api`, `/oidc`, `/admin` to a separately-running `aniworld -w` backend (`vite.config.ts`'s `base` is `/`, matching root serving). Baked into the image unconditionally; `ANIWORLD_ENABLE_WEBAPP` (default `1`) is a runtime on/off switch — set to `0` to fully unregister the web UI and the `/api/webapp/*` blueprint, leaving only `/api/*`. It is independent of `--web-auth`/`--web-sso` and never shows a username/password form: a browser without a token calls `POST /api/webapp/request-access`, gets a `device_id`, and polls `GET /api/webapp/request-access/<device_id>` until an admin approves it from the server terminal (`--web-requests` / `--web-approve <id>` / `--web-deny <id>` / `--web-revoke <id>`, backed by the `web_access_requests` table in `web/db.py`). Approval logs the browser in as the (first) admin account and issues a normal bearer token via the existing `api_tokens` mechanism — revoking just deletes that token (`webapp/src/context/AuthContext.tsx`'s `logout()`, wired to Settings' "Zugriff widerrufen"). The native Flutter app (Android/TV, desktop) is untouched and keeps using its own `LoginScreen`/`SetupScreen` — it no longer has a web build target at all (see "Flutter frontend" below); this SPA replaces that role.

Design system for the TV web app is ported literally from the Flutter app's `lib/theme/rs_theme.dart` (colors, radii, typography, layout constants — see `webapp/src/styles/theme.css`); the Flutter app's D-pad focus engine (`AppNavController`, `TvFocusable`) was deliberately **not** ported (it's remote-control-specific), only the visual focus-ring treatment it drove (accent border + glow + scale), reimplemented as plain CSS `:hover`/`:focus-visible`. Screen-for-screen it mirrors the Flutter app: Home (rails), Grid (Serien/Anime/Filme, paginated), Search, Detail (hero/seasons/episodes/language override/watchlist/autosync), Player (custom HLS controls via `hls.js`, skip-intro/outro, auto-advance, resume), Queue, Library, Watchlist, Settings (Speicher/Verbindung only — no Server/Updates sections, those are native-only), and Profile picker.

### Anime4K (`src/aniworld/anime4k/`)

Optional upscaling via `--anime4k High|Low|Remove`. Installs Anime4K GLSL shaders into the mpv scripts directory (`~/.config/mpv/scripts` on Linux/macOS, `%APPDATA%\mpv\scripts` on Windows).

### Playwright / captcha (`src/aniworld/playwright/`)

Some sites require solving a captcha. `autodeps.py:ensure_patchright_chromium()` (called at startup) downloads a Chromium build via `patchright` if needed. `web/captcha.py` exposes an endpoint for manual captcha solving in the web UI.

### Windows-specific behaviour

On Windows, `DependencyManager` in `autodeps.py` auto-downloads FFmpeg (from BtbN/FFmpeg-Builds) and mpv (`shinchiro/mpv-winbuild-cmake`) if they are not on `PATH`. This runs at the start of every `download()` call.

### Flutter frontend (`app/`)

Android TV client built with Flutter (Dart SDK ^3.12.0), displayed under the app name **RedStream**. Primary target is Android TV — the app locks to landscape and is D-pad/remote-navigable via custom focus widgets (`tv_focusable.dart`, `tv_card.dart`). Native targets only (Android, TV, desktop) — it no longer builds for web; `app/web/` was removed once the RedStream TV web app (`webapp/`, see "Web UI" above) took over that role with its own React implementation of the same screens/design.

**Architecture**: Riverpod for state management, Dio for HTTP. On first launch shows `SetupScreen` to save the backend server URL into `shared_preferences`. All subsequent API calls go through `ApiService` (wraps Dio, routes image URLs through `/api/proxy-image`).

**Screens**: Home, Search, Grid, Detail (series metadata), Episodes, Player (ExoPlayer/native HLS via `video_player`), Queue, Library, Settings.

**Backend integration**: The Flutter app is a thin client that talks exclusively to the Python web UI REST API. It does not talk to aniworld.to directly. Key endpoints it consumes: `/api/search`, `/api/series`, `/api/seasons`, `/api/episodes`, `/api/providers`, `/api/download`, `/api/queue`, `/api/stream`, `/api/library`, `/api/settings`, `/api/proxy-image`.

**Build/run commands** (run from `app/`):
```bash
flutter pub get
flutter run                         # connected Android device / emulator
flutter build apk --release         # release APK
flutter build apk --target-platform android-arm64 --split-per-abi
```

### MCP Server (Dart & Flutter)

The project uses the **official Dart & Flutter MCP server** (ships with Dart SDK ≥ 3.9, no separate install needed). Configuration is in `.claude/settings.json`:

```json
{
  "mcpServers": {
    "dart": {
      "command": "dart",
      "args": ["mcp-server"],
      "cwd": "app"
    }
  }
}
```

The server runs in the context of `app/` and exposes these tools to Claude Code:

| Tool | Funktion |
|---|---|
| `analyze_files` | Dart-Code analysieren & Fehler finden |
| `dart_fix` / `dart_format` | Code auto-reparieren & formatieren |
| `run_tests` | Flutter-Tests ausführen |
| `pub` / `pub_dev_search` | Pakete suchen & in `pubspec.yaml` installieren |
| `hot_reload` / `hot_restart` | Laufende App neuladen |
| `get_runtime_errors` / `get_app_logs` | Laufzeitfehler & Logs abrufen |
| `widget_inspector` | Flutter Widget-Baum inspizieren |
| `list_devices` / `launch_app` / `stop_app` | Gerät & App-Lifecycle steuern |

To add/disable individual tools use `--enable` / `--disable` flags (see `dart mcp-server --help`).

### Branch note

The active development branch is `models`. The `NAMING_TEMPLATE` and all fallback extensions in episode models use `.m3u8` (not `.mkv`) — the final download artefact is an HLS bundle, not a single container file.

### Upstream-merge leftovers (do not build on these)

The `merge: sync with upstream phoenixthrush/AniWorld-Downloader (233 commits)` commit brought in upstream's parallel rewrite of the web layer, which this fork deliberately did not adopt (see that commit's message) because it would have broken every endpoint the Flutter app and this fork's own browser UI depend on. Left behind, unwired, and **incompatible with this fork's actual `web/db.py`** (they expect `db._initialized`, `db.QUEUE_STATUSES`, `db.cancel_flags`, `db.reset_stale_running`, none of which exist here):

- `web/views/` (Flask blueprints, never registered in `create_app()`) and its templates/static assets (`queue.html`, `queue.js`, …).
- `web/worker.py` — a single-item queue consumer; superseded by `web/download_worker.py` for the pool/profile-bucketed design. `autosync.py` used to call `worker.ensure_started()`, which crashed (see below) — that call was replaced with `download_worker.ensure_started()`.
- `tests/test_worker.py`, `tests/test_db_queue.py`, `tests/test_api_queue.py`, `tests/test_theming.py`, and in fact **the entire pytest suite** (`tests/conftest.py`'s autouse `fresh_db` fixture does `monkeypatch.setattr(db, "_initialized", False)`, which fails for every test since that attribute doesn't exist) — this is a pre-existing, branch-wide breakage, not something any single feature session introduced. Fixing it means either adding the compatibility surface to `db.py` or rewriting `conftest.py` for this fork's actual init pattern; nobody has done either yet.

If you're about to "finish" or extend `worker.py`/`views/`, stop — read this section first. Verify anything discovered here against current `git log`/`hasattr()` before trusting it; this note describes state as of the `eaf17ca` commit and may drift.
