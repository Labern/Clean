#!/usr/bin/env python3
"""Build the company tiles shown beside each link (Logo-* image sets).

Each tile is the company's own mark on the ground its app icon uses. The marks
are never redrawn: the outlines come from the simple-icons package (CC0), the
four-colour Google G from @iconify-json/logos, and Focus from its own site icon.

  npm pack simple-icons @iconify-json/logos && tar xzf each
  python3 make_logos.py <simple-icons/package> <logos/package> <focus icon-512.png>
"""
import json
import re
import sys
from pathlib import Path

from PIL import Image

SIMPLE, LOGOS, FOCUS = (Path(p) for p in sys.argv[1:4])
ASSETS = Path(__file__).resolve().parents[2] / "Resources" / "Assets.xcassets"
N = 120  # the tile's box; the app clips the corners

# name: (simple-icons file, ground, ink, share of the tile the mark fills)
TILES = {
    "Stripe": ("stripe", "#635BFF", "#FFFFFF", 0.56),
    "GitHub": ("github", "#F5F5F5", "#181717", 0.70),
    "Claude": ("claude", "#D97757", "#FAF9F5", 0.64),
    "Tesla": ("tesla", "#E31937", "#FFFFFF", 0.62),
}


def write(name, svg=None, png=None):
    folder = ASSETS / f"Logo-{name}.imageset"
    folder.mkdir(exist_ok=True)
    file = "logo.svg" if svg else "logo.png"
    if svg:
        (folder / file).write_text(svg)
    else:
        png.save(folder / file, optimize=True)
    contents = {"images": [{"filename": file, "idiom": "universal"}], "info": {"author": "xcode", "version": 1}}
    if svg:
        contents["properties"] = {"preserves-vector-representation": True}
    (folder / "Contents.json").write_text(json.dumps(contents, indent=2) + "\n")


def tile(ground, body, width, height, share):
    k = N * share / max(width, height)
    x, y = (N - width * k) / 2, (N - height * k) / 2
    return (f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {N} {N}" width="{N}" height="{N}">'
            f'<rect width="{N}" height="{N}" fill="{ground}"/>'
            f'<g transform="translate({x:.3f} {y:.3f}) scale({k:.5f})">{body}</g></svg>\n')


for name, (slug, ground, ink, share) in TILES.items():
    d = re.search(r'<path d="([^"]+)"', (SIMPLE / "icons" / f"{slug}.svg").read_text()).group(1)
    write(name, svg=tile(ground, f'<path fill="{ink}" d="{d}"/>', 24, 24, share))

logos = json.loads((LOGOS / "icons.json").read_text())
g = logos["icons"]["google-icon"]
write("Google", svg=tile("#FFFFFF", g["body"], g.get("width", logos.get("width", 256)),
                         g.get("height", logos.get("height", 256)), 0.58))

# Focus: Labern's own colours for it, the "Purple & Green" preset in Focus itself
# (violet tile, green lens). The lens is lifted off the site icon, where it is white
# on near-black, and laid on the tile exactly as Focus's appIconRep draws it: the
# tile colour lightened 18% at the top and darkened 22% at the bottom.
VIOLET, GREEN = (0xA7, 0x8B, 0xFA), (0x5F, 0xD7, 0xAF)
icon = Image.open(FOCUS).convert("RGBA")
icon = icon.crop(icon.getchannel("A").getbbox())
top = tuple(c + (255 - c) * 0.18 for c in VIOLET)
bottom = tuple(c * (1 - 0.22) for c in VIOLET)
flat = Image.new("RGB", icon.size)
px, out = icon.load(), flat.load()
edge = icon.width // 12  # a column inside the tile that the lens never reaches
for y in range(icon.height):
    ground = sum(px[edge, y][:3]) / 3
    t = y / (icon.height - 1)
    tile_colour = tuple(top[i] + (bottom[i] - top[i]) * t for i in range(3))
    for x in range(icon.width):
        p = px[x, y]
        lens = max(0.0, min(1.0, (sum(p[:3]) / 3 - ground) / (255 - ground)))
        # The old tile's own rim is not part of the lens.
        if min(x, y, icon.width - 1 - x, icon.height - 1 - y) < edge:
            lens = 0.0
        out[x, y] = tuple(round(tile_colour[i] * (1 - lens) + GREEN[i] * lens) for i in range(3))
write("Focus", png=flat.resize((360, 360), Image.LANCZOS))
print("wrote", ", ".join(sorted(p.name for p in ASSETS.glob("Logo-*.imageset"))))
