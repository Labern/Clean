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

# Focus: its own icon, cropped to the dark body; the clear corners take the
# colour beside them so the app's own corner clip is the only edge.
icon = Image.open(FOCUS).convert("RGBA")
icon = icon.crop(icon.getchannel("A").getbbox())
flat = Image.new("RGBA", icon.size)
px, out = icon.load(), flat.load()
for y in range(icon.height):
    solid = px[icon.width // 2, y]
    for x in range(icon.width):
        p = px[x, y]
        a = p[3] / 255
        out[x, y] = tuple(round(p[i] * a + solid[i] * (1 - a)) for i in range(3)) + (255,)
write("Focus", png=flat.convert("RGB").resize((360, 360), Image.LANCZOS))
print("wrote", ", ".join(sorted(p.name for p in ASSETS.glob("Logo-*.imageset"))))
