"""Prints screenshots as base64 JPEG chunks into the job log.

The artifact store isn't reachable from every environment that can read job
logs; `##SHOT <name> <i>/<n> <data>` lines can be reassembled from the log.
"""

import base64
import io
import sys
from pathlib import Path

from PIL import Image

CHUNK = 6000
for png in sorted(Path(sys.argv[1]).glob("*.png")):
    img = Image.open(png).convert("RGB")
    img.thumbnail((720, 720))
    buf = io.BytesIO()
    img.save(buf, "JPEG", quality=72)
    data = base64.b64encode(buf.getvalue()).decode()
    parts = [data[i:i + CHUNK] for i in range(0, len(data), CHUNK)]
    for i, part in enumerate(parts, 1):
        print(f"##SHOT {png.stem} {i}/{len(parts)} {part}")
