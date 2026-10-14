#!/usr/bin/env python3
"""Slice the sprite sheets in source-sprites/ into per-frame PNGs in Resources/sprites/.

Each character on a sheet is found as a connected blob in the alpha channel; stray
specks are dropped. Frames of one animation share a canvas so they line up when played.
Requires: pip install pillow numpy scipy
"""
import os
import numpy as np
from PIL import Image
from scipy import ndimage as nd

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SRC = os.path.join(ROOT, "source-sprites")
OUT = os.path.join(ROOT, "Resources", "sprites")

STANDING_PX = 360   # standing character height in output pixels (shown at 180pt, @2x)
MIN_AREA = 5000


def blobs(img):
    a = np.array(img)[:, :, 3]
    lab, n = nd.label(a > 30)
    areas = nd.sum(np.ones_like(lab), lab, range(1, n + 1))
    objs = nd.find_objects(lab)
    return lab, [(i + 1, objs[i]) for i, s in enumerate(areas) if s >= MIN_AREA]


def cut(img, lab, ids, xs, ys):
    """Copy region (xs, ys) keeping only pixels belonging to label ids."""
    arr = np.array(img)[ys, xs].copy()
    keep = np.isin(lab[ys, xs], ids)
    keep = nd.binary_dilation(keep, iterations=2)  # keep soft anti-aliased edges
    arr[~keep] = 0
    return arr


def split_merged(img, lab, lid, sl, count):
    """Split a blob that contains `count` touching characters at the thinnest columns."""
    ys, xs = sl
    mask = lab[ys, xs] == lid
    cols = mask.sum(0)
    w = mask.shape[1]
    cuts = [0]
    for k in range(1, count):
        c = w * k // count
        lo, hi = c - w // 8, c + w // 8
        cuts.append(lo + int(np.argmin(cols[lo:hi])))
    cuts.append(w)
    parts = []
    for a, b in zip(cuts, cuts[1:]):
        parts.append((lid, (ys, slice(xs.start + a, xs.start + b))))
    return parts


def frames_from_sheet(name, expected, standing_index=0, region=None):
    img = Image.open(os.path.join(SRC, name)).convert("RGBA")
    if region:
        img = img.crop(region)
    lab, bl = blobs(img)
    parts = []
    widths = sorted(sl[1].stop - sl[1].start for _, sl in bl)
    median_w = widths[len(widths) // 2]
    for lid, sl in bl:
        w = sl[1].stop - sl[1].start
        n = max(1, round(w / median_w))
        parts.extend(split_merged(img, lab, lid, sl, n) if n > 1 else [(lid, sl)])
    parts.sort(key=lambda p: (p[1][1].start + p[1][1].stop) / 2)
    assert len(parts) == expected, f"{name}: found {len(parts)} frames, expected {expected}"

    # Shared vertical span keeps the ground line consistent (jumps stay in the air).
    top = min(sl[0].start for _, sl in parts)
    bottom = max(sl[0].stop for _, sl in parts)
    width = max(sl[1].stop - sl[1].start for _, sl in parts)
    sy = parts[standing_index][1][0]
    scale = STANDING_PX / (sy.stop - sy.start)

    out = []
    for lid, (ys, xs) in parts:
        piece = cut(img, lab, [lid], xs, slice(top, bottom))
        canvas = np.zeros((bottom - top, width, 4), dtype=np.uint8)
        x0 = (width - piece.shape[1]) // 2
        canvas[:, x0:x0 + piece.shape[1]] = piece
        im = Image.fromarray(canvas)
        im = im.resize((round(im.width * scale), round(im.height * scale)), Image.LANCZOS)
        out.append(im)
    return out


def save(prefix, frames):
    for i, im in enumerate(frames):
        im.save(os.path.join(OUT, f"{prefix}_{i}.png"), optimize=True)
    print(f"{prefix}: {len(frames)} frames, {frames[0].size}")


def main():
    os.makedirs(OUT, exist_ok=True)
    save("walk", frames_from_sheet("walk.png", 8))
    save("wave", frames_from_sheet("wave.png", 8))
    save("jump", frames_from_sheet("jump.png", 8))
    # poses.png bottom row: jump, sad, idle. Only the sad pose is used.
    save("sad", frames_from_sheet("poses.png", 1, region=(600, 505, 1000, 1024)))


if __name__ == "__main__":
    main()
