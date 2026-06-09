# AniWorld-Downloader Web API

Base URL: `http://localhost:8080` (default)

## Authentication

Authentication is opt-in via environment variable:

```bash
ANIWORLD_WEB_AUTH=1      # Local username/password login
ANIWORLD_WEB_SSO=1       # OIDC / SSO login (implies auth)
ANIWORLD_WEB_FORCE_SSO=1 # SSO only, local login disabled
```

When auth is enabled every endpoint requires either a valid **Flask session** (browser) or a **Bearer token** (API clients / Flutter app). A subset of endpoints additionally requires the **admin** role (see table below).

### Bearer Token Flow

```
GET  /api/auth/check   → { auth_enabled, setup_needed }
POST /api/auth/setup   → { token, username, role }   (first-run only, creates admin)
POST /api/auth/login   → { token, username, role }
GET  /api/auth/me      → { id, username, role }
POST /api/auth/logout  → { ok: true }
```

Include the token on every subsequent request:

```
Authorization: Bearer <token>
```

All `/api/auth/*` endpoints are **public** (no auth required). All other `/api/*` endpoints require auth when `ANIWORLD_WEB_AUTH=1`.

---

## Auth Endpoints

### Check auth status
```
GET /api/auth/check
```
Always accessible (no auth required).

Response:
```json
{ "auth_enabled": true, "setup_needed": false }
```
`setup_needed: true` means no admin account exists yet — call `/api/auth/setup` next.

---

### Create first admin *(setup_needed only)*
```
POST /api/auth/setup
```
Returns 409 if an admin already exists.

Body:
```json
{ "username": "admin", "password": "yourpassword" }
```
Response:
```json
{ "token": "…", "username": "admin", "role": "admin" }
```

---

### Login
```
POST /api/auth/login
```
Body:
```json
{ "username": "admin", "password": "yourpassword" }
```
Response:
```json
{ "token": "…", "username": "admin", "role": "admin" }
```

---

### Get current user
```
GET /api/auth/me
```
Response:
```json
{ "id": 1, "username": "admin", "role": "admin" }
```

---

### Logout
```
POST /api/auth/logout
```
Revokes the Bearer token and clears the session. Returns `{ "ok": true }`.

---

## Pages

| Method | Path | Description |
|--------|------|-------------|
| `GET` | `/` | Main download UI |
| `GET` | `/library` | Local library browser |
| `GET` | `/settings` | Settings page *(admin only when auth enabled)* |
| `GET` | `/autosync` | Auto-sync job management page |

---

## Search & Metadata

### Search series
```
POST /api/search
```
Body:
```json
{
  "keyword": "highschool dxd",
  "site": "aniworld"
}
```
`site` accepts `"aniworld"` (default) or `"sto"`.

Response:
```json
{
  "results": [
    { "title": "Highschool DxD", "url": "https://aniworld.to/anime/stream/highschool-dxd" }
  ]
}
```

---

### Get series info
```
GET /api/series?url=<series_url>
```
Response:
```json
{
  "title": "Highschool DxD",
  "poster_url": "/api/proxy-image?url=...",
  "description": "...",
  "genres": ["Action", "Comedy"],
  "release_year": "2012"
}
```

---

### Get seasons
```
GET /api/seasons?url=<series_url>
```
Response:
```json
{
  "seasons": [
    { "url": "https://aniworld.to/anime/stream/highschool-dxd/staffel-1", "season_number": 1, "episode_count": 12, "are_movies": false }
  ]
}
```

---

### Get episodes
```
GET /api/episodes?url=<season_url>
```
Response:
```json
{
  "episodes": [
    {
      "url": "https://aniworld.to/anime/stream/highschool-dxd/staffel-1/episode-1",
      "episode_number": 1,
      "title_de": "Ich habe endlich eine Freundin!",
      "title_en": "I Got a Girlfriend!",
      "downloaded": false,
      "available_languages": ["German Dub", "English Sub", "German Sub"]
    }
  ]
}
```

---

### Get providers for an episode
```
GET /api/providers?url=<episode_url>
```
Response:
```json
{
  "providers": {
    "German Dub": ["VOE", "Vidmoly"],
    "English Sub": ["VOE"]
  }
}
```

---

### Random anime
```
GET /api/random
```
Only available for AniWorld (`site=sto` returns 400).

Response:
```json
{ "url": "https://aniworld.to/anime/stream/some-random-anime" }
```

---

## Browse (cached, 1 h TTL)

| Method | Path | Description |
|--------|------|-------------|
| `GET` | `/api/new-animes` | New anime from AniWorld |
| `GET` | `/api/popular-animes` | Popular anime from AniWorld |
| `GET` | `/api/new-series` | New series from s.to |
| `GET` | `/api/popular-series` | Popular series from s.to |

All four return:
```json
{
  "results": [
    { "title": "...", "url": "...", "poster_url": "/api/proxy-image?url=..." }
  ]
}
```

---

## Download Queue

### Enqueue episodes
```
POST /api/download
```
Body:
```json
{
  "title": "Highschool DxD",
  "series_url": "https://aniworld.to/anime/stream/highschool-dxd",
  "episodes": [
    "https://aniworld.to/anime/stream/highschool-dxd/staffel-1/episode-1"
  ],
  "language": "German Dub",
  "provider": "VOE",
  "custom_path_id": null
}
```
Response:
```json
{ "queue_id": 42 }
```

---

### Get queue state
```
GET /api/queue
```
Response:
```json
{
  "items": [
    { "id": 42, "title": "Highschool DxD", "status": "downloading", "progress": 67 }
  ],
  "ffmpeg_progress": {
    "percent": 67.3,
    "time": "00:08:12",
    "speed": "3.2x",
    "bandwidth": "1.4 MB/s",
    "active": true
  }
}
```

---

### Remove a queue item
```
DELETE /api/queue/<id>
```

---

### Cancel a running download
```
POST /api/queue/<id>/cancel
```

---

### Reorder queue
```
POST /api/queue/<id>/move
```
Body:
```json
{ "direction": "up" }
```
`direction` accepts `"up"` or `"down"`.

---

### Clear completed entries
```
DELETE /api/queue/completed
```

---

## Captcha (Playwright)

These endpoints are used by the web UI to let the user solve provider captchas in-browser.

### Get screenshot of captcha page
```
GET /api/captcha/<id>/screenshot
```
Returns a JPEG image (`image/jpeg`). Returns 404 if no active captcha session exists.

---

### Forward a click to the captcha browser
```
POST /api/captcha/<id>/click
```
Body:
```json
{ "x": 320, "y": 240 }
```

---

### Get captcha session status
```
GET /api/captcha/<id>/status
```
Response:
```json
{ "active": true, "done": false }
```

---

## Streaming

### Get the HLS stream URL for a downloaded episode
```
GET /api/stream?folder=<folder>&season=<int>&episode=<int>[&custom_path_id=<int>]
```

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `folder` | string | yes | Series folder name as it appears on disk, e.g. `Highschool DxD (2012) [imdbid-tt2230051]` |
| `season` | int | yes | Season number |
| `episode` | int | yes | Episode number |
| `custom_path_id` | int | no | ID of a custom download path |

Response:
```json
{
  "url": "http://localhost:8080/api/stream/files/Highschool DxD (2012) [imdbid-tt2230051]/Season 01/Highschool DxD S01E01.m3u8"
}
```

The returned URL can be opened directly in any HLS-capable player (VLC, mpv, Safari, hls.js, …).

---

### Serve an HLS file
```
GET /api/stream/files/<path>
```
Serves `.m3u8` playlists and `.ts` segments from the configured download directories. All other file types return 404.

Responses include:
- `Content-Type: application/vnd.apple.mpegurl` for `.m3u8`
- `Content-Type: video/mp2t` for `.ts`
- `Access-Control-Allow-Origin: *` (allows web-based players on any origin)
- `Cache-Control: no-cache`

Path traversal outside the configured download directories is blocked.

---

## Library

### List downloaded titles
```
GET /api/library
```
Scans the download directory (and all custom paths) for video files matching the `S##E###` naming pattern.

Response:
```json
{
  "lang_sep": false,
  "locations": [
    {
      "label": "Default",
      "custom_path_id": null,
      "lang_folders": null,
      "titles": [
        {
          "folder": "Highschool DxD (2012) [imdbid-tt2230051]",
          "seasons": {
            "1": [
              { "episode": 1, "file": "Highschool DxD S01E001.m3u8", "size": 4096, "is_video": true }
            ]
          },
          "total_episodes": 12,
          "total_size": 2147483648
        }
      ]
    }
  ]
}
```

---

### Delete from library *(admin only)*
```
POST /api/library/delete
```
Body:
```json
{
  "folder": "Highschool DxD (2012) [imdbid-tt2230051]",
  "season": 1,
  "episode": 1,
  "custom_path_id": null,
  "lang_folder": null
}
```
Omit `episode` to delete a whole season. Omit both `season` and `episode` to delete the entire series folder.

Response:
```json
{ "ok": true, "deleted": 4 }
```

---

### List downloaded folder names
```
GET /api/downloaded-folders
```
Returns a sorted list of series folder names found in the download directory.

Response:
```json
{ "folders": ["Attack on Titan (2013) [imdbid-tt2560140]", "Highschool DxD (2012) [imdbid-tt2230051]"] }
```

---

## Settings

### Read settings *(admin only)*
```
GET /api/settings
```
Response:
```json
{
  "download_path": "/home/user/Downloads",
  "lang_separation": "0",
  "disable_english_sub": "0",
  "sync_schedule": "0",
  "sync_language": "German Dub",
  "sync_provider": "VOE",
  "provider_fallback_order": ["VOE", "Vidmoly", "Vidoza"],
  "available_providers": ["VOE", "Vidmoly", "Vidoza"]
}
```

---

### Update settings *(admin only)*
```
PUT /api/settings
```
All fields are optional. Only the fields included in the body are updated.

Body:
```json
{
  "download_path": "/mnt/media/anime",
  "lang_separation": false,
  "disable_english_sub": false,
  "sync_schedule": "daily",
  "sync_language": "German Dub",
  "sync_provider": "VOE",
  "provider_fallback_order": ["Vidmoly", "VOE", "Vidoza"]
}
```

---

### Get public IP *(admin only)*
```
GET /api/settings/public-ip
```
Response:
```json
{ "ok": true, "ip": "93.184.216.34", "country": "US" }
```

---

### List custom download paths
```
GET /api/custom-paths
```
Response:
```json
{ "paths": [{ "id": 1, "name": "NAS", "path": "/mnt/nas/anime" }] }
```

---

### Add custom path *(admin only)*
```
POST /api/custom-paths
```
Body:
```json
{ "name": "NAS", "path": "/mnt/nas/anime" }
```
Response:
```json
{ "ok": true, "id": 1 }
```

---

### Delete custom path *(admin only)*
```
DELETE /api/custom-paths/<id>
```

---

## Auto-Sync

Auto-sync jobs download new episodes of a series automatically on a configurable schedule.

### List jobs
```
GET /api/autosync
```
Admins see all jobs. Regular users see only their own.

Response:
```json
{
  "jobs": [
    { "id": 1, "title": "Highschool DxD", "series_url": "...", "language": "German Dub", "provider": "VOE", "enabled": true, "added_by": "alice" }
  ]
}
```

---

### Create a job *(admin only)*
```
POST /api/autosync
```
Body:
```json
{
  "title": "Highschool DxD",
  "series_url": "https://aniworld.to/anime/stream/highschool-dxd",
  "language": "German Dub",
  "provider": "VOE",
  "custom_path_id": null
}
```
Returns 409 if a job for this series already exists.

---

### Update a job *(admin or owner)*
```
PUT /api/autosync/<id>
```
Body (all fields optional):
```json
{ "language": "English Sub", "provider": "Vidmoly", "enabled": false, "custom_path_id": 1 }
```

---

### Delete a job *(admin or owner)*
```
DELETE /api/autosync/<id>
```

---

### Trigger a job manually *(admin or owner)*
```
POST /api/autosync/<id>/sync
```
Starts the sync in a background thread immediately.

Response:
```json
{ "ok": true, "message": "Sync started" }
```
Returns 409 if a sync is already running for that job.

---

### Check if a sync job exists for a URL
```
GET /api/autosync/check?url=<series_url>
```
Returns job details only if you own it or are an admin.

Response:
```json
{ "exists": true, "job": { "id": 1, ... } }
```

---

## Statistics

### Sync statistics
```
GET /api/stats/sync
```
Response:
```json
{
  "total_synced": 48,
  "last_check": "2026-05-31 14:00:00",
  "schedule": "daily",
  "next_run_at": "2026-06-01 14:00:00"
}
```

---

### Queue statistics
```
GET /api/stats/queue
```
Response:
```json
{ "total": 120, "completed": 115, "failed": 2, "pending": 3 }
```

---

### General statistics
```
GET /api/stats/general
```
Response:
```json
{ "total_downloads": 120, "total_size_bytes": 53687091200 }
```

---

## Profiles

User profiles are scoped per-session. Include the active profile by setting the `X-Profile-ID` header (or it defaults to profile 1).

### List profiles
```
GET /api/profiles
```
Response:
```json
{ "profiles": [{ "id": 1, "name": "Jason", "avatar_color": "#E50914" }] }
```

---

### Create profile
```
POST /api/profiles
```
Body:
```json
{ "name": "Jason", "avatar_color": "#E50914" }
```
Response:
```json
{ "id": 1, "ok": true }
```

---

### Update profile
```
PUT /api/profiles/<id>
```
Body (all fields optional):
```json
{ "name": "Jason", "avatar_color": "#1DB954" }
```

---

### Delete profile
```
DELETE /api/profiles/<id>
```
Returns 400 if the profile cannot be deleted (e.g. last remaining profile).

---

## Watch Progress

Progress is scoped per profile via `X-Profile-ID` header.

### Save / update progress
```
POST /api/progress
```
Body:
```json
{
  "episode_url": "https://aniworld.to/anime/stream/…/episode-1",
  "series_title": "Highschool DxD",
  "series_url": "https://aniworld.to/anime/stream/highschool-dxd",
  "season": 1,
  "episode_number": 1,
  "episode_title": "I Got a Girlfriend!",
  "position_seconds": 423.5,
  "duration_seconds": 1452.0,
  "completed": false,
  "stream_file": "http://localhost:8080/api/stream/files/Highschool%20DxD/S01E001.m3u8"
}
```
`stream_file` is optional — used to attach a local preview thumbnail.

---

### List watch progress (Continue Watching)
```
GET /api/progress?limit=50&continue=0
```

| Parameter | Default | Description |
|-----------|---------|-------------|
| `limit` | 50 | Max results |
| `continue` | `0` | `1` = only return incomplete episodes (Continue Watching) |

Response:
```json
{
  "progress": [
    {
      "episode_url": "…",
      "series_title": "Highschool DxD",
      "series_url": "…",
      "season": 1,
      "episode_number": 1,
      "episode_title": "I Got a Girlfriend!",
      "position_seconds": 423.5,
      "duration_seconds": 1452.0,
      "completed": false,
      "updated_at": "2026-06-09 14:00:00",
      "poster_url": "/api/proxy-image?url=…",
      "preview_url": "/api/episode-preview/…"
    }
  ]
}
```

---

### Get progress for a single episode
```
GET /api/progress/<episode_url>
```
Response:
```json
{ "progress": { "position_seconds": 423.5, "duration_seconds": 1452.0, "completed": false, … } }
```
Returns `{ "progress": null }` if no record exists.

---

## Watchlist

Watchlist is scoped per profile via `X-Profile-ID` header.

### Get watchlist
```
GET /api/watchlist
```
Response:
```json
{ "items": [{ "title": "Highschool DxD", "url": "…", "poster_url": "/api/proxy-image?url=…" }] }
```

---

### Get enriched watchlist (with new-content flag)
```
GET /api/watchlist/enriched
```
Response:
```json
{
  "items": [
    {
      "title": "Highschool DxD",
      "url": "…",
      "poster_url": "/api/proxy-image?url=…",
      "last_watched_at": "2026-06-09 14:00:00",
      "new_content": false
    }
  ]
}
```
`new_content: true` means new episodes have been released since this series was last watched.

---

### Add to watchlist
```
POST /api/watchlist
```
Body:
```json
{ "series_url": "…", "series_title": "Highschool DxD", "poster_url": "/api/proxy-image?url=…" }
```

---

### Remove from watchlist
```
DELETE /api/watchlist
```
Body:
```json
{ "series_url": "…" }
```

---

### Check if in watchlist
```
GET /api/watchlist/check?url=<series_url>
```
Response:
```json
{ "in_list": true }
```

---

## Utilities

### Proxy an external image
```
GET /api/proxy-image?url=<image_url>
```
Proxies external poster images to avoid CORS issues in the browser. Cached for 1 hour.

---

## Error responses

All endpoints return errors in a consistent JSON envelope:

```json
{ "error": "description of the problem" }
```

Common HTTP status codes:

| Code | Meaning |
|------|---------|
| `400` | Missing or invalid parameters |
| `403` | Action not permitted (e.g. English Sub disabled, insufficient role) |
| `404` | Resource not found |
| `409` | Conflict (e.g. duplicate autosync job, sync already running) |
| `500` | Internal server error |
| `502` | Upstream request failed (proxy image, public IP lookup) |
