#!/usr/bin/env python3
"""Render PARADOX app-icon variants from the brand's vector masters.

The artwork is never redrawn: each master SVG is rasterised by rsvg-convert,
then only scaled uniformly, rotated, repeated, positioned and recoloured.
Run: python3 make_icons.py   (writes next to this file)
"""
import io
import shutil
import subprocess
from pathlib import Path

import numpy as np
from PIL import Image, ImageChops, ImageDraw, ImageFont

Image.MAX_IMAGE_PIXELS = None
HERE = Path(__file__).resolve().parent
SVG = Path("/Users/labern/Desktop/Clean/paradoxica/site/brand/svg")
CURRENT = Path("/Users/labern/Desktop/Clean/paradox-hq/ios/Resources/Assets.xcassets/AppIcon.appiconset/icon-1024.png")
RSVG = "/opt/homebrew/bin/rsvg-convert"
N = 1024
SS = 2            # supersampling factor for composition
BLACK, WHITE_ART = (0, 0, 0), (255, 255, 255)
LIGHT, DARK_ART = (0xF2, 0xF2, 0xF2), (0, 0, 0)


def mask_of(master, ink_h=None, ink_w=None):
    """Render a master SVG so its *ink* has the given height or width (px).
    Returns an L-mode coverage mask cropped to the ink bbox."""
    path = SVG / f"paradox-{master}-black.svg"
    probe = render(path, 2000)
    bb = probe.getbbox()
    pw, ph = bb[2] - bb[0], bb[3] - bb[1]
    k = (ink_h / ph) if ink_h else (ink_w / pw)
    m = render(path, round(2000 * k))
    return m.crop(m.getbbox())


def render(path, width):
    png = subprocess.run([RSVG, "-w", str(width), str(path)], check=True, capture_output=True).stdout
    return Image.open(io.BytesIO(png)).getchannel("A")


def finish(mask_ss, bg, fg, name):
    mask = mask_ss.resize((N, N), Image.LANCZOS)
    out = Image.composite(Image.new("RGB", (N, N), fg), Image.new("RGB", (N, N), bg), mask)
    out.save(HERE / name)
    return mask


def place(mask, cx, cy):
    """Paste mask so its bbox centre lands on (cx, cy) in a SS canvas."""
    c = Image.new("L", (N * SS, N * SS), 0)
    c.paste(mask, (round(cx - mask.width / 2), round(cy - mask.height / 2)))
    return c


# ---------- 1/2 stacked lockup (stacked-tm-no-brackets) ----------
def stacked():
    target_w = 0.92 * N * SS
    m = mask_of("stacked-tm-no-brackets", ink_w=target_w)
    # Body = everything left of the hanging ™ (largest empty column run).
    a = np.array(m) > 8
    cols = a.any(0)
    best, run, start = (0, 0), 0, 0
    for i, c in enumerate(cols):
        if not c:
            if run == 0:
                start = i
            run += 1
            if run > best[1]:
                best = (start, run)
        else:
            run = 0
    body_w = best[0]
    # Full-bbox centring (™ included) maximises size; the body then sits
    # left of centre by half the ™ hang.
    cy = N * SS / 2
    canvas = place(m, N * SS / 2, cy)
    finish(canvas, BLACK, WHITE_ART, "stacked-black.png")
    finish(canvas, LIGHT, DARK_ART, "stacked-white.png")
    # Alternative: body centred, ™ hangs to ~24px from the edge.
    reach = N * SS / 2 - 24 * SS          # half-body + hang must fit this
    k = reach / (body_w / 2 + (m.width - body_w))
    m2 = m.resize((round(m.width * k), round(m.height * k)), Image.LANCZOS)
    b2 = body_w * k
    c2 = Image.new("L", (N * SS, N * SS), 0)
    c2.paste(m2, (round(N * SS / 2 - b2 / 2), round(cy - m2.height / 2)))
    finish(c2, BLACK, WHITE_ART, "stacked-black-bodycentred.png")
    return m.width / SS / N, body_w / SS / N


# ---------- 3/4/5 diagonal pattern (horizontal-paradox) ----------
def diagonal(rows, bg, fg, name):
    span = 2 * 620 * SS                # squircle extent along the anti-diagonal
    pitch = span / rows
    ink_h = 0.42 * pitch
    lock = mask_of("horizontal-paradox", ink_h=ink_h)
    gap = 0.8 * ink_h
    period = lock.width + gap
    big = int(N * SS * 1.5)
    c = Image.new("L", (big, big), 0)
    mid = big / 2
    half = rows // 2
    for r in range(-half - 2, half + 3):
        cy = mid + r * pitch
        offset = (period / 2) if (r % 2) else 0.0
        for j in range(-4, 5):
            cx = mid + j * period + offset
            tile = Image.new("L", c.size, 0)
            tile.paste(lock, (round(cx - lock.width / 2), round(cy - lock.height / 2)))
            c = ImageChops.lighter(c, tile)
    c = c.rotate(45, resample=Image.BICUBIC, center=(mid, mid))
    o = (big - N * SS) // 2
    c = c.crop((o, o, o + N * SS, o + N * SS))
    finish(c, bg, fg, name)
    return ink_h / SS, pitch / SS


# ---------- 6 word / bracket ----------
def word():
    m = mask_of("bracket-paradox", ink_w=0.92 * N * SS)
    finish(place(m, N * SS / 2, N * SS / 2), BLACK, WHITE_ART, "word-black.png")
    return m.width / SS / N, m.height / SS / N


# ---------- 7 kana ----------
def kana():
    m = mask_of("stacked-kana-2", ink_w=0.92 * N * SS)
    finish(place(m, N * SS / 2, N * SS / 2), BLACK, WHITE_ART, "kana-black.png")
    return m.width / SS / N, m.height / SS / N


# ---------- squircle check + contact sheet ----------
def squircle_mask(size, radius_frac=0.225, inset=0):
    m = Image.new("L", (size * 4, size * 4), 0)
    r = radius_frac * size * 4
    i = inset * 4
    ImageDraw.Draw(m).rounded_rectangle((i, i, size * 4 - 1 - i, size * 4 - 1 - i), radius=r, fill=255)
    return m.resize((size, size), Image.LANCZOS)


def clipped(name, bg):
    im = np.array(Image.open(HERE / name).convert("RGB")).astype(int)
    art = np.abs(im - np.array(bg)).sum(2) > 30
    inside = np.array(squircle_mask(N, inset=8)) > 128
    return int((art & ~inside).sum())


def contact(names):
    cell, pad, label_h = 180, 28, 30
    cols = 4
    rows = (len(names) + cols - 1) // cols
    W = cols * (cell + pad) + pad
    H = rows * (cell + pad + label_h) + pad
    sheet = Image.new("RGB", (W, H), (0x8A, 0x8A, 0x8A))
    sq = squircle_mask(cell)
    try:
        font = ImageFont.truetype("/System/Library/Fonts/Helvetica.ttc", 15)
    except OSError:
        font = ImageFont.load_default()
    d = ImageDraw.Draw(sheet)
    for k, n in enumerate(names):
        x = pad + (k % cols) * (cell + pad)
        y = pad + (k // cols) * (cell + pad + label_h)
        ic = Image.open(HERE / n).convert("RGB").resize((cell, cell), Image.LANCZOS)
        sheet.paste(ic, (x, y), sq)
        tw = d.textlength(n, font=font)
        d.text((x + (cell - tw) / 2, y + cell + 7), n, fill=(20, 20, 20), font=font)
    sheet.save(HERE / "contact-sheet.png")


if __name__ == "__main__":
    total, body = stacked()
    print(f"stacked: total ink width {total:.1%}, body (excl. ™) {body:.1%}")
    print("diag5", diagonal(5, BLACK, WHITE_ART, "diagonal5-black.png"))
    print("diag7", diagonal(7, BLACK, WHITE_ART, "diagonal7-black.png"))
    diagonal(5, LIGHT, DARK_ART, "diagonal5-white.png")
    print("word", word())
    print("kana", kana())
    shutil.copyfile(CURRENT, HERE / "current.png")
    names = ["current.png", "stacked-black.png", "stacked-white.png", "stacked-black-bodycentred.png", "word-black.png",
             "diagonal5-black.png", "diagonal7-black.png", "diagonal5-white.png", "kana-black.png"]
    for n in names:
        im = Image.open(HERE / n)
        bg = LIGHT if "white" in n else BLACK
        extra = "" if n.startswith(("diagonal", "current")) else f", px outside squircle(-8px): {clipped(n, bg)}"
        print(f"{n}: {im.size} {im.mode}{extra}")
    contact(names)
