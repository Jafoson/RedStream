# RedStream — Server Setup Guide

Self-host the RedStream backend on any Linux server using Docker Compose.
The Flutter Android TV app connects to this backend over the local network or internet.

---

## Table of Contents

1. [Prerequisites](#prerequisites)
2. [Quick Start](#quick-start)
3. [Configuration Reference](#configuration-reference)
4. [Reverse Proxy (HTTPS)](#reverse-proxy-https)
5. [OIDC / SSO Login](#oidc--sso-login)
6. [Android TV App Setup](#android-tv-app-setup)
7. [Updating](#updating)
8. [Backup & Restore](#backup--restore)
9. [Troubleshooting](#troubleshooting)

---

## Prerequisites

- A Linux server (Debian/Ubuntu recommended) with root or sudo access
- [Docker](https://docs.docker.com/engine/install/) ≥ 24 and [Docker Compose](https://docs.docker.com/compose/install/) v2
- Port **8080** open in your firewall (or whichever port you choose)

```bash
# Verify Docker is running
docker --version
docker compose version
```

---

## Quick Start

### 1. Create a project directory

```bash
mkdir -p ~/redstream && cd ~/redstream
```

### 2. Download the Compose file

```bash
curl -fsSL https://raw.githubusercontent.com/phoenixthrush/AniWorld-Downloader/models/docker-compose.yaml \
  -o docker-compose.yaml
```

Or copy the `docker-compose.yaml` from this repository.

### 3. Create the downloads directory

> Docker creates missing bind-mount directories as **root**, which causes permission errors at runtime.
> Always create the directory yourself first.

```bash
mkdir -p downloads
```

### 4. Set your admin credentials

Open `docker-compose.yaml` and change these two lines before starting:

```yaml
ANIWORLD_WEB_ADMIN_USER: "admin"
ANIWORLD_WEB_ADMIN_PASS: "changeme"   # ← change this!
```

The admin account is created automatically on first startup. The setup page is skipped entirely.

### 5. Start the service

```bash
docker compose up -d
```

### 6. Open the Web UI

```
http://<your-server-ip>:8080
```

Log in with the credentials you set above.

---

## Configuration Reference

All settings are controlled via environment variables in `docker-compose.yaml`.
No config file needs to be edited inside the container.

| Variable | Default | Description |
|---|---|---|
| `ANIWORLD_WEB_AUTH` | `0` | `1` = enable local username/password login |
| `ANIWORLD_WEB_ADMIN_USER` | — | Auto-create this admin username on first run |
| `ANIWORLD_WEB_ADMIN_PASS` | — | Password for the auto-created admin |
| `ANIWORLD_WEB_SSO` | `0` | `1` = enable OIDC SSO login button |
| `ANIWORLD_WEB_FORCE_SSO` | `0` | `1` = SSO only, disable local login |
| `ANIWORLD_WEB_BASE_URL` | — | Full public URL, e.g. `https://redstream.example.com` (needed behind a reverse proxy) |
| `ANIWORLD_WEB_PORT` | `8080` | Port the server listens on inside the container |
| `ANIWORLD_LANGUAGE` | `German Dub` | Default download language |
| `ANIWORLD_PROVIDER` | `VOE` | Default streaming provider |
| `ANIWORLD_PROVIDER_FALLBACK_ORDER` | `VOE,Vidmoly,Vidoza` | Comma-separated fallback order |
| `ANIWORLD_VIDEO_CODEC` | `copy` | `copy` / `h264` / `h265` / `av1` |
| `ANIWORLD_LANG_SEPARATION` | `0` | `1` = separate downloads into language subfolders |
| `ANIWORLD_DISABLE_ENGLISH_SUB` | `0` | `1` = block all English Sub downloads |
| `ANIWORLD_SYNC_SCHEDULE` | `0` | Auto-sync interval: `0` / `1min` / `1h` / `4h` / `24h` … |
| `ANIWORLD_SYNC_LANGUAGE` | `German Dub` | Language for auto-synced episodes |
| `ANIWORLD_TMDB_TOKEN` | — | **Required** for thumbnails/posters. Get it at [themoviedb.org/settings/api](https://www.themoviedb.org/settings/api) |
| `ANIWORLD_DOWNLOAD_PATH` | `/app/Downloads` | Download directory inside the container |

### Change the host port

Map a different host port without touching the container config:

```yaml
ports:
  - "9090:8080"   # access via http://server:9090
```

### Persist downloads to a custom path

Replace the bind-mount with your preferred path:

```yaml
volumes:
  - /mnt/media/redstream:/app/Downloads
  - redstream-data:/home/aniworld/.aniworld
```

---

## Reverse Proxy (HTTPS)

Running behind a reverse proxy is strongly recommended for internet-facing deployments.

### Nginx example

```nginx
server {
    listen 80;
    server_name redstream.example.com;
    return 301 https://$host$request_uri;
}

server {
    listen 443 ssl;
    server_name redstream.example.com;

    ssl_certificate     /etc/letsencrypt/live/redstream.example.com/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/redstream.example.com/privkey.pem;

    # Increase timeout for long-running downloads
    proxy_read_timeout 3600;
    proxy_send_timeout 3600;

    location / {
        proxy_pass         http://127.0.0.1:8080;
        proxy_set_header   Host              $host;
        proxy_set_header   X-Real-IP         $remote_addr;
        proxy_set_header   X-Forwarded-For   $proxy_add_x_forwarded_for;
        proxy_set_header   X-Forwarded-Proto $scheme;
    }
}
```

Then set `ANIWORLD_WEB_BASE_URL` in docker-compose so redirects (OAuth callbacks, etc.) use the correct external URL:

```yaml
ANIWORLD_WEB_BASE_URL: "https://redstream.example.com"
```

### Caddy example

```
redstream.example.com {
    reverse_proxy localhost:8080
}
```

Caddy handles TLS automatically via Let's Encrypt.

---

## OIDC / SSO Login

Connect to any OpenID Connect provider (Keycloak, Authentik, Google, …).

```yaml
environment:
  ANIWORLD_WEB_AUTH: "1"
  ANIWORLD_WEB_SSO: "1"
  ANIWORLD_OIDC_ISSUER_URL: "https://keycloak.example.com/realms/myrealm"
  ANIWORLD_OIDC_CLIENT_ID: "redstream"
  ANIWORLD_OIDC_CLIENT_SECRET: "your-client-secret"
  ANIWORLD_OIDC_DISPLAY_NAME: "Mit Keycloak anmelden"
  # Promote a specific OIDC user to admin on first login (use sub claim, not username)
  ANIWORLD_OIDC_ADMIN_SUBJECT: "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx"
```

**Redirect URI** to register in your IdP:
```
https://redstream.example.com/oidc/callback
```

To disable local login entirely (SSO only):

```yaml
ANIWORLD_WEB_FORCE_SSO: "1"
```

---

## Android TV App Setup

1. Install the RedStream APK on your Android TV device.
2. On first launch the app asks for the **Server URL**.
   - Same network: `http://192.168.x.x:8080`
   - Over the internet: `https://redstream.example.com`
3. The app will detect that auth is enabled and show the login screen.
4. Log in with your admin credentials (or any user account created in Settings → Users).

> The app stores a Bearer token in local storage. Tokens persist until you log out or the account is deleted server-side.

---

## Updating

Pull the latest image and recreate the container. Your data (downloads + database) is safe because it lives in the volume and bind-mount, not inside the container.

```bash
cd ~/redstream
docker compose pull
docker compose up -d
```

To build from source instead of using the pre-built image:

```yaml
# docker-compose.yaml
services:
  redstream:
    build: .              # ← use this instead of image:
    # image: ghcr.io/...  # ← comment out
```

Then rebuild:

```bash
docker compose build --no-cache
docker compose up -d
```

---

## Backup & Restore

All persistent state lives in two places:

| What | Where |
|---|---|
| Downloads | `./downloads/` (bind-mount on host) |
| Config, DB, tokens | Docker volume `redstream-data` |

### Backup the volume

```bash
docker run --rm \
  -v redstream_redstream-data:/data \
  -v $(pwd):/backup \
  alpine tar czf /backup/redstream-data-backup.tar.gz -C /data .
```

### Restore the volume

```bash
docker compose down
docker run --rm \
  -v redstream_redstream-data:/data \
  -v $(pwd):/backup \
  alpine sh -c "cd /data && tar xzf /backup/redstream-data-backup.tar.gz"
docker compose up -d
```

### Reset admin password

If you are locked out, change the env vars and restart — the auto-create logic only runs when **no admin exists**. To force a reset, drop into the container and use SQLite directly:

```bash
docker compose exec redstream python - <<'EOF'
from aniworld.web.db import get_db
from werkzeug.security import generate_password_hash
conn = get_db()
conn.execute("UPDATE users SET password_hash = ? WHERE username = ?",
             (generate_password_hash("newpassword"), "admin"))
conn.commit()
conn.close()
print("Password updated.")
EOF
```

---

## Troubleshooting

### View logs

```bash
docker compose logs -f redstream
```

### Container won't start — permission error on ./downloads

Docker created the directory as root before you could. Fix it:

```bash
sudo chown -R 1000:1000 ./downloads
```

### 401 Unauthorized from the Flutter app

The stored token may have been invalidated (e.g. after a database reset). Open the app → Settings → Log out, then log in again.

### Check the auth API directly

```bash
# Is auth enabled?
curl http://localhost:8080/api/auth/check

# Login and get a token
curl -X POST http://localhost:8080/api/auth/login \
  -H "Content-Type: application/json" \
  -d '{"username":"admin","password":"yourpassword"}'

# Use the token
curl http://localhost:8080/api/profiles \
  -H "Authorization: Bearer <token>"
```

### Chromium / captcha issues

The container runs Xvfb for a virtual display. If captcha solving fails, check that the `DISPLAY=:99` env var is set and Xvfb is running:

```bash
docker compose exec redstream ps aux | grep Xvfb
```
