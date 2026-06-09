FROM python:3.13-slim

WORKDIR /app

RUN mkdir -p /tmp/.X11-unix && chmod 1777 /tmp/.X11-unix

# System dependencies: ffmpeg, Xvfb (headless Chromium), curl (healthcheck), Chromium libs
RUN apt-get update && apt-get install -y --no-install-recommends \
    ffmpeg \
    xvfb \
    curl \
    libnss3 \
    libnspr4 \
    libatk1.0-0 \
    libatk-bridge2.0-0 \
    libcups2 \
    libxkbcommon0 \
    libxcomposite1 \
    libxdamage1 \
    libxfixes3 \
    libxrandr2 \
    libgbm1 \
    libpango-1.0-0 \
    libcairo2 \
    libasound2 \
    libx11-6 \
    libx11-xcb1 \
    libxcb1 \
    libxext6 \
    && rm -rf /var/lib/apt/lists/*

# Unprivileged user + runtime directories
RUN adduser --disabled-password --gecos "" aniworld \
    && mkdir -p /app/Downloads /home/aniworld/.aniworld \
    && chown -R aniworld:aniworld /app /home/aniworld

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1

# Default paths and virtual display
ENV ANIWORLD_DOWNLOAD_PATH=/app/Downloads \
    DISPLAY=:99 \
    ANIWORLD_WEB_PORT=8080

# Copy packaging metadata first to maximize layer cache
COPY pyproject.toml /app/
COPY README.md LICENSE MANIFEST.in /app/

RUN pip install --no-cache-dir --upgrade pip

COPY src/ /app/src/

RUN pip install --no-cache-dir .

# Pre-install patchright Chromium so it's available at runtime without network access
RUN python -m patchright install chromium

RUN chown -R aniworld:aniworld /app/Downloads /home/aniworld/.aniworld

USER aniworld

EXPOSE 8080

HEALTHCHECK --interval=30s --timeout=10s --start-period=40s --retries=3 \
    CMD curl -sf http://localhost:${ANIWORLD_WEB_PORT}/api/auth/check > /dev/null || exit 1

# Start Xvfb for headless Chromium, then launch the web UI.
# Auth and other settings are controlled entirely via environment variables —
# see docker-compose.yaml for the full list.
CMD Xvfb :99 -screen 0 1280x720x24 -nolisten tcp & \
    sleep 1 && \
    exec aniworld --web-ui --web-expose --no-browser --web-port ${ANIWORLD_WEB_PORT:-8080}
