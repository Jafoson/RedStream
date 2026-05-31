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

`aniworld` CLI → `entry.py:aniworld()` → `arguments.py:parse_args()` → either the TUI menu (`menu/app.py`, npyscreen) or the web UI (`web/app.py`, Flask/Waitress) → resolves to an episode/season/series model → calls `model.download()` / `model.watch()` / `model.syncplay()`.

### Model layer (`src/aniworld/models/`)

Each supported site has a subdirectory (`aniworld_to/`, `s_to/`, `filmpalast_to/`, `hianime_to/`) with `episode.py`, `season.py`, `series.py`. All episode models share the **same three actions**, which are standalone functions in `models/common/common.py` attached as class attributes:

```python
download = episode_download   # from models/common/common.py
watch    = episode_watch
syncplay = episode_syncplay
```

Episode properties (`stream_url`, `_episode_path`, `provider_data`, …) are all lazy-loaded via `@property` backed by double-underscore private instance vars. Invalidation (e.g. when `selected_language` changes) resets the relevant private vars to `None` in the setter.

### Download pipeline (`models/common/common.py`)

`download()` → checks if HLS output already exists (`check_downloaded`) → resolves stream URL with provider fallback → invokes `_run_ffmpeg_with_progress()` → writes HLS output.

**Output format**: `.m3u8` playlist + `_NNN.ts` segments (4 s each, `independent_segments`, `vod` playlist type). The `.m3u8` path is derived from `self._episode_path` (which itself comes from `NAMING_TEMPLATE`).

`_run_ffmpeg_with_progress()` spawns FFmpeg as a subprocess and parses stderr line-by-line for progress data. It exposes a thread-safe `_ffmpeg_progress` dict consumed by the web UI via `get_ffmpeg_progress()`. Stall detection kills the process after 600 s of no progress.

### Extractor layer (`src/aniworld/extractors/`)

`extractors/__init__.py` auto-discovers every module under `extractors/provider/` at import time with `pkgutil` and registers any function named `get_direct_link_from_<provider>` or `get_preview_image_link_from_<provider>` into the `provider_functions` dict.

To add a new provider: create `extractors/provider/myprovider.py` with a `get_direct_link_from_myprovider(url) -> str` function — it is automatically registered.

### Configuration

`config.py` is the central config module. Key items:

- `NAMING_TEMPLATE` – controls output path/filename. Default ends in `.m3u8`; override with `ANIWORLD_NAMING_TEMPLATE`.
- `Audio` / `Subtitles` enums and `LANG_KEY_MAP` / `LANG_CODE_MAP` – map site language keys to ISO 639-2 codes used in FFmpeg metadata.
- `SUPPORTED_PROVIDERS` – canonical list for fallback logic.
- `VIDEO_CODEC_MAP` – maps user-facing names (`copy`, `h264`, `h265`, `av1`) to FFmpeg codec strings.

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

### Web UI (`src/aniworld/web/`)

Flask app served by Waitress. Templates and static files are in `web/templates/` and `web/static/` and are declared as package data in `pyproject.toml`. The web UI polls `get_ffmpeg_progress()` for live download progress.

### Windows-specific behaviour

On Windows, `DependencyManager` in `autodeps.py` auto-downloads FFmpeg (from BtbN/FFmpeg-Builds) and mpv (mpv.net) if they are not on `PATH`. This runs at the start of every `download()` call.

### Branch note

The active development branch is `models`. The `NAMING_TEMPLATE` and all fallback extensions in episode models use `.m3u8` (not `.mkv`) — the final download artefact is an HLS bundle, not a single container file.
