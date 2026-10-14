#!/usr/bin/env python3
"""Builds preview/preview.html: a single-file browser preview of WaterBuddy with sprites embedded."""
import base64
import glob
import io
import json
import os

from PIL import Image

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SPRITES = os.path.join(ROOT, "Resources", "sprites")


def data_uri(path):
    buf = io.BytesIO()
    Image.open(path).save(buf, "WEBP", quality=82, method=6)
    return "data:image/webp;base64," + base64.b64encode(buf.getvalue()).decode()


def main():
    sprites = {}
    for name in ("walk", "wave", "jump", "sad"):
        files = sorted(glob.glob(os.path.join(SPRITES, f"{name}_*.png")),
                       key=lambda p: int(p.rsplit("_", 1)[1].split(".")[0]))
        sprites[name] = [data_uri(f) for f in files]
    with open(os.path.join(ROOT, "tools", "preview_template.html")) as f:
        html = f.read().replace("__SPRITES__", json.dumps(sprites))
    os.makedirs(os.path.join(ROOT, "preview"), exist_ok=True)
    out = os.path.join(ROOT, "preview", "preview.html")
    with open(out, "w") as f:
        f.write(html)
    print(f"{out}: {len(html) / 1024:.0f} KB")


if __name__ == "__main__":
    main()
