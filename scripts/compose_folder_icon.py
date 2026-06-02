#!/usr/bin/env python3
"""Composite the pickle jar line-art onto the macOS folder icon with an engraved
(emboss) look. Full state = open folder + pickle jar; empty = closed folder +
empty jar."""
import sys
from PIL import Image, ImageOps, ImageChops

HOME = sys.argv[1]
GUIDE = sys.argv[2]


def ink_mask(path, size):
    """Return an 'L' mask where the jar's dark lines are bright (opaque)."""
    img = Image.open(path).convert("RGBA")
    alpha = img.split()[3]
    lum = img.convert("L")
    ink = ImageOps.invert(lum)            # dark lines -> high
    ink = ImageChops.multiply(ink, alpha)  # ignore fully transparent areas
    return ink.resize(size, Image.LANCZOS)


def tinted(mask, color, opacity):
    layer = Image.new("RGBA", mask.size, color + (0,))
    layer.putalpha(mask.point(lambda v: int(v * opacity)))
    return layer


def place(canvas_size, layer, topleft):
    canvas = Image.new("RGBA", canvas_size, (0, 0, 0, 0))
    canvas.alpha_composite(layer, topleft)
    return canvas


def compose(folder_path, jar_path, out_path):
    folder = Image.open(folder_path).convert("RGBA")
    W, H = folder.size

    jar_w = int(W * 0.50)
    src = Image.open(jar_path).convert("RGBA")
    jar_h = int(jar_w * src.height / src.width)
    mask = ink_mask(jar_path, (jar_w, jar_h))

    cx = W // 2
    cy = int(H * 0.60)                      # lower body, below the folder tab
    tlx, tly = cx - jar_w // 2, cy - jar_h // 2

    # Engrave: dark edge up-left, light edge down-right.
    shadow = tinted(mask, (20, 50, 80), 0.50)
    light = tinted(mask, (255, 255, 255), 0.55)

    out = folder.copy()
    out = Image.alpha_composite(out, place((W, H), shadow, (tlx - 2, tly - 2)))
    out = Image.alpha_composite(out, place((W, H), light, (tlx + 2, tly + 2)))
    # A faint mid tint so the jar reads even on flat areas.
    body = tinted(mask, (30, 70, 110), 0.22)
    out = Image.alpha_composite(out, place((W, H), body, (tlx, tly)))

    out.save(out_path)
    print("wrote", out_path)


# Full = open folder + pickle jar; Empty = closed folder + empty jar.
compose(f"{HOME}/Downloads/맥기본폴더_열림_1024.png",
        f"{GUIDE}/폴더아이콘.png",
        f"{HOME}/Downloads/pickle_folder_full.png")
compose(f"{HOME}/Downloads/맥기본폴더_닫힘_1024.png",
        f"{GUIDE}/폴더아이콘 빈병.png",
        f"{HOME}/Downloads/pickle_folder_empty.png")
