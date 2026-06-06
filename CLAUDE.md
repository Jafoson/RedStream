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

`_run_ffmpeg_with_progress()` spawns FFmpeg as a subprocess, reads stderr byte-by-byte via a reader thread, and parses progress lines. It exposes a thread-safe `_ffmpeg_progress` dict (consumed by the web UI via `get_ffmpeg_progress()`). Stall detection kills the process after 600 s of no progress.

Provider attempt order: selected provider first, then fallback order from `ANIWORLD_PROVIDER_FALLBACK_ORDER`. `build_provider_attempt_order()` in `config.py` handles deduplication.

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

Flask app served by Waitress. Templates and static files are in `web/templates/` and `web/static/`.

**Authentication** (`web/auth.py`): Optional local username/password auth or OIDC/SSO via `authlib`. First launch with `--web-auth` shows a setup page to create the first admin account. `--web-force-sso` disables the password form entirely. Roles: `admin` and `user`.

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

The web UI polls `get_ffmpeg_progress()` for live download progress.

### Anime4K (`src/aniworld/anime4k/`)

Optional upscaling via `--anime4k High|Low|Remove`. Installs Anime4K GLSL shaders into the mpv scripts directory (`~/.config/mpv/scripts` on Linux/macOS, `%APPDATA%\mpv\scripts` on Windows).

### Playwright / captcha (`src/aniworld/playwright/`)

Some sites require solving a captcha. `autodeps.py:ensure_patchright_chromium()` (called at startup) downloads a Chromium build via `patchright` if needed. `web/captcha.py` exposes an endpoint for manual captcha solving in the web UI.

### Windows-specific behaviour

On Windows, `DependencyManager` in `autodeps.py` auto-downloads FFmpeg (from BtbN/FFmpeg-Builds) and mpv (`shinchiro/mpv-winbuild-cmake`) if they are not on `PATH`. This runs at the start of every `download()` call.

### Flutter frontend (`app/`)

Android TV client built with Flutter (Dart SDK ^3.12.0), displayed under the app name **RedStream**. Primary target is Android TV — the app locks to landscape and is D-pad/remote-navigable via custom focus widgets (`tv_focusable.dart`, `tv_card.dart`).

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
