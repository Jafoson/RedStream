import json
import os
import subprocess
import threading
from pathlib import Path

try:
    from ..config import logger
except ImportError:
    from aniworld.config import logger

_lock = threading.Lock()
_generating: set[str] = set()

THUMB_W = 160
THUMB_H = 90
TARGET_FRAMES = 100  # aim for ~100 preview images
MIN_INTERVAL = 3     # seconds between frames, minimum

PREVIEW_W = 320
PREVIEW_H = 180


def sprite_paths(m3u8_path: Path) -> tuple[Path, Path]:
    return (
        m3u8_path.parent / f"{m3u8_path.stem}.thumbs.jpg",
        m3u8_path.parent / f"{m3u8_path.stem}.thumbs.json",
    )


def preview_path(m3u8_path: Path) -> Path:
    return m3u8_path.parent / f"{m3u8_path.stem}.preview.jpg"


def _get_duration(m3u8_path: Path) -> float | None:
    try:
        r = subprocess.run(
            ["ffprobe", "-v", "quiet", "-print_format", "json", "-show_format", str(m3u8_path)],
            capture_output=True, text=True, timeout=30,
        )
        return float(json.loads(r.stdout)["format"]["duration"])
    except Exception as e:
        logger.debug(f"ffprobe failed for {m3u8_path}: {e}")
        return None


def _generate(m3u8_path: Path) -> None:
    sprite_path, meta_path = sprite_paths(m3u8_path)
    prev_path = preview_path(m3u8_path)
    try:
        duration = _get_duration(m3u8_path)
        if duration is None or duration < 1:
            return

        interval = max(MIN_INTERVAL, int(duration / TARGET_FRAMES))
        total = max(1, int(duration / interval) + 1)
        cols = min(10, total)
        rows = (total + cols - 1) // cols

        vf = f"fps=1/{interval},scale={THUMB_W}:{THUMB_H},tile={cols}x{rows}"
        cmd = [
            "ffmpeg", "-y",
            "-i", str(m3u8_path),
            "-vf", vf,
            "-frames:v", "1",
            "-q:v", "5",
            str(sprite_path),
        ]
        subprocess.run(cmd, capture_output=True, timeout=600, check=True)

        meta = {
            "status": "ready",
            "interval": interval,
            "total": total,
            "cols": cols,
            "rows": rows,
            "thumb_w": THUMB_W,
            "thumb_h": THUMB_H,
        }
        meta_path.write_text(json.dumps(meta), encoding="utf-8")
        logger.debug(f"Thumbnails generated: {sprite_path}")

        # Generate single preview image at ~30% into the episode
        if not prev_path.exists():
            seek = max(0.0, duration * 0.30)
            prev_cmd = [
                "ffmpeg", "-y",
                "-ss", str(seek),
                "-i", str(m3u8_path),
                "-vf", f"scale={PREVIEW_W}:{PREVIEW_H}",
                "-frames:v", "1",
                "-q:v", "3",
                str(prev_path),
            ]
            subprocess.run(prev_cmd, capture_output=True, timeout=120, check=True)
            logger.debug(f"Preview image generated: {prev_path}")
    except Exception as e:
        logger.warning(f"Thumbnail generation failed for {m3u8_path.name}: {e}")
    finally:
        with _lock:
            _generating.discard(str(m3u8_path))


def get_or_start(m3u8_path: Path) -> dict:
    """Return thumbnail metadata if ready, otherwise start generation and return status=generating."""
    sprite_path, meta_path = sprite_paths(m3u8_path)

    if sprite_path.exists() and meta_path.exists():
        try:
            return json.loads(meta_path.read_text(encoding="utf-8"))
        except Exception:
            pass

    key = str(m3u8_path)
    with _lock:
        if key not in _generating:
            _generating.add(key)
            threading.Thread(target=_generate, args=(m3u8_path,), daemon=True).start()

    return {"status": "generating"}


def resolve_m3u8(filepath: str) -> Path | None:
    """Resolve a relative filepath (from stream URL) to an absolute m3u8 path."""
    raw = os.environ.get("ANIWORLD_DOWNLOAD_PATH", "")
    dl_base = (Path(raw).expanduser() if raw else Path.home() / "Downloads")
    if not dl_base.is_absolute():
        dl_base = Path.home() / dl_base

    from .db import get_custom_paths
    bases = [dl_base]
    for cp in get_custom_paths():
        p = Path(cp["path"]).expanduser()
        bases.append(p if p.is_absolute() else Path.home() / p)

    for base in bases:
        candidate = (base / filepath).resolve()
        try:
            candidate.relative_to(base.resolve())
        except ValueError:
            continue
        if candidate.is_file() and candidate.suffix.lower() == ".m3u8":
            return candidate

    return None
