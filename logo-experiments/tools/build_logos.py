#!/usr/bin/env python3
"""Extract every logo variation from the Keynote decks into logos.js.

Crispness is the only priority, so nothing is ever rasterised into the page:

  * Pages whose artwork is real vector (Keynote text in Canela / Hiragino) keep
    their exact PDF geometry, converted to outlines by mutool.
  * Pages holding a pasted bitmap have that bitmap traced to outlines by potrace
    at its native resolution with heavy upsampling, then dropped back into the
    page at the identical transform, so it lands exactly where it was.

Every page of every deck is walked. The decks show each mark three times — on
black, on white and on violet — so pages are de-duplicated by the shape of
their ink, and the page's own colour is thrown away: the site paints the marks
itself. Section dividers and explanatory slides are skipped.

    python3 tools/build_logos.py
"""
import base64, hashlib, io, json, re, subprocess, tempfile
from pathlib import Path
from PIL import Image, ImageOps

SRC = Path.home() / "Desktop/Logo_Variations"
DECKS = [SRC / "LOGO_VARIATIONS.pdf", SRC / "Trademarks.pdf"]
OUT = Path(__file__).resolve().parent.parent / "logos.js"

BBOX_DPI = 216   # used to find the ink, its bounding box and its fingerprint
UPS      = 6     # upsample factor before tracing a pasted bitmap
MIN_PT   = 46    # anything smaller in both directions is a section divider
SOLID    = .55   # ink filling more of its box than this is a panel, not a mark

# Pages whose artwork is a pasted bitmap carry no text for the labeller to read.
OVERRIDES = {
    ("LOGO_VARIATIONS.pdf", 5): "VERTICAL · PARADOX STACKED",
    ("LOGO_VARIATIONS.pdf", 6): "VERTICAL · PARADOX",
    ("Trademarks.pdf", 2): "BRACKET · PARADOX",
    ("Trademarks.pdf", 3): "BRACKET · PARADOX ™",
    ("Trademarks.pdf", 4): "BRACKET · PARADOX ®",
    ("Trademarks.pdf", 5): "VERTICAL · PARADOX ™",
    ("Trademarks.pdf", 6): "VERTICAL · PARADOX ®",
    ("Trademarks.pdf", 7): "VERTICAL · PARADOX STACKED ™",
    ("Trademarks.pdf", 8): "VERTICAL · PARADOX STACKED ®",
}

FULL_PAGE = re.compile(r"^M0 0H\d+V\d+H0Z$|^M0 \d+H\d+V0H0Z$")
KANA = re.compile(r"[゠-ヿ぀-ゟ一-鿿]")


def sh(*a):
    return subprocess.run(a, check=True, capture_output=True)


def pages(pdf):
    out = sh("mutool", "info", str(pdf)).stdout.decode("utf8", "replace")
    return int(re.search(r"Pages: (\d+)", out).group(1))


# ── ink: bounding box, fingerprint, optical axis ─────────────────────────────
def ink(pdf, page, tmp):
    png = tmp / "bbox.png"
    sh("mutool", "draw", "-r", str(BBOX_DPI), "-o", str(png), str(pdf), str(page))
    g = Image.open(png).convert("L")
    # the outermost pixel row can be a partly-covered edge of the page, which
    # renders bright against nothing and would swallow the bounding box
    INSET = 3
    g = g.crop((INSET, INSET, g.width - INSET, g.height - INSET))
    dark = g.getpixel((4, 4)) < 128
    mask = g.point(lambda p: 255 if (p > 140 if dark else p < 115) else 0)
    box = mask.getbbox()
    if not box:
        return None
    crop = mask.crop(box)
    # a silhouette fingerprint: the same mark on black, on white and on violet
    # thresholds slightly differently, so compare shapes loosely, not byte-wise
    sig = crop.resize((24, 24), Image.LANCZOS).point(lambda p: 1 if p > 110 else 0)
    fill = sum(1 for p in crop.resize((64, 64), Image.LANCZOS).getdata() if p > 110) / 4096
    k = 72.0 / BBOX_DPI
    pt = [(c + INSET) * k for c in box]
    return pt, mask, box, list(sig.getdata()), fill


def same_mark(a, b):
    """Two silhouettes of the same artwork, allowing for threshold noise."""
    return sum(1 for x, y in zip(a, b) if x != y) <= 28   # of 576 cells


def axis(mask, box):
    """Fraction across the mark where its upper cluster (the stars) sits.
    The page's chrome hangs off this line, not off the window's centre."""
    x0, y0, x1, y1 = box
    band = mask.crop((x0, y0, x1, y0 + max(1, int((y1 - y0) * .35))))
    px, (w, h) = band.load(), band.size
    tot = num = 0
    for x in range(w):
        c = sum(1 for y in range(h) if px[x, y] > 128)
        tot += c * (x + .5); num += c
    return round((tot / num) / w, 4) if num else .5


# ── tracing a pasted bitmap back into outlines ───────────────────────────────
def trace_bitmap(png_bytes, w_attr, h_attr, tmp):
    im = Image.open(io.BytesIO(png_bytes))
    mask = None
    if "A" in im.getbands():
        a = im.convert("RGBA").getchannel("A")
        if a.getextrema()[0] < 250:
            mask = a.point(lambda p: 255 if p > 128 else 0)
    if mask is None:                        # opaque art: ink = whatever isn't the corner
        g = im.convert("L")
        corner = g.getpixel((0, 0))
        mask = g.point(lambda p: 255 if (p > 140 if corner < 128 else p < 115) else 0)

    W, H = mask.size
    big = mask.resize((W * UPS, H * UPS), Image.LANCZOS)
    bw = ImageOps.invert(big).point(lambda p: 255 if p > 128 else 0).convert("1")
    pbm, svg = tmp / "t.pbm", tmp / "t.svg"
    bw.save(pbm)
    sh("potrace", "-s", "-o", str(svg), "--turdsize", "2",
       "--alphamax", "1", "--opttolerance", ".12", str(pbm))
    s = svg.read_text()
    tw, th = (float(v) for v in re.search(r'viewBox="0 0 ([\d.]+) ([\d.]+)"', s).groups())
    g = re.search(r"<g transform=\"([^\"]+)\"[^>]*>(.*)</g>", s, re.S)
    body = "".join(f'<path d="{d.replace(chr(10), " ").strip()}"/>'
                   for d in re.findall(r'<path d="(.*?)"', g.group(2), re.S))
    return (f'<g transform="scale({w_attr / tw:.9g},{h_attr / th:.9g})">'
            f'<g transform="{g.group(1)}">{body}</g></g>')


# ── one page → one mark ──────────────────────────────────────────────────────
def artwork(pdf, page, tmp):
    svg_path = tmp / "page.svg"
    sh("mutool", "draw", "-F", "svg", "-O", "text=path", "-o", str(svg_path), str(pdf), str(page))
    s = svg_path.read_text()
    inner = s.split(">", 1)[1].rsplit("</svg>", 1)[0]
    glyphs = re.findall(r'data-text="([^"]*)"', inner)
    # the glyph outlines live in <defs> as <symbol>s that <use> points at, so
    # they must survive; only the page's clip rectangles go. Each mark becomes
    # its own standalone document, so ids never collide between marks.
    inner = re.sub(r"<clipPath\b.*?</clipPath>", "", inner, flags=re.S)
    inner = re.sub(r"\sclip-path=\"[^\"]*\"", "", inner)

    # Keynote exports a pasted bitmap as an opaque plate plus a greyscale soft
    # mask holding its alpha. The mask IS the silhouette, so trace that and
    # throw the plate away; the two are paired by size.
    masks = {}
    for mb in re.finditer(r"<mask\b.*?</mask>", inner, flags=re.S):
        img = re.search(r"<image\b[^>]*/>", mb.group(0), flags=re.S)
        if img:
            key = (re.search(r'width="([\d.]+)"', img.group(0)).group(1),
                   re.search(r'height="([\d.]+)"', img.group(0)).group(1))
            masks[key] = img.group(0)
    inner = re.sub(r"<mask\b.*?</mask>", "", inner, flags=re.S)
    inner = re.sub(r'\smask="url\(#[^)]*\)"', "", inner)

    seen = set()

    def swap_image(m):
        tag = m.group(0)
        ws = re.search(r'width="([\d.]+)"', tag).group(1)
        hs = re.search(r'height="([\d.]+)"', tag).group(1)
        tag = masks.get((ws, hs), tag)
        raw = base64.b64decode(re.sub(r"\s+", "", re.search(
            r'xlink:href="data:image/[a-z]+;base64,([^"]+)"', tag, re.S).group(1)))
        key = hashlib.sha1(raw).hexdigest()
        if key in seen:                     # Keynote sometimes stacks a duplicate
            return ""
        seen.add(key)
        return trace_bitmap(raw, float(ws), float(hs), tmp)

    inner = re.sub(r"<image\b[^>]*/>", swap_image, inner, flags=re.S)
    inner = re.sub(r'<path transform="[^"]*" d="([^"]*)"[^>]*/>',
                   lambda m: "" if FULL_PAGE.match(m.group(1).strip()) else m.group(0), inner)
    inner = re.sub(r'\sfill(-opacity)?="[^"]*"', "", inner)       # the site paints it
    return re.sub(r"\s+", " ", inner).strip(), glyphs


def text_of(pdf, page):
    return sh("mutool", "draw", "-F", "txt", "-o", "-", str(pdf), str(page)) \
        .stdout.decode("utf8", "replace")


def describe(txt, glyphs, aspect):
    form = "VERTICAL" if aspect < .35 else "HORIZONTAL" if aspect > 2.2 else "STACKED"
    if KANA.search(txt):
        script = "パラドックス"
    elif "PARADOX" in txt.upper():
        script = "PARADOX"
    else:
        return "MARK · ★" + (" ™" if ("T" in glyphs and "M" in glyphs)
                             else " ®" if "\u00ae" in glyphs else "")
    mark = " ™" if ("T" in glyphs and "M" in glyphs) else " ®" if "®" in glyphs else ""
    return f"{form} · {script}{mark}"


def main():
    logos, fps, counts, ids = [], [], {}, set()
    with tempfile.TemporaryDirectory() as td:
        tmp = Path(td)
        for pdf in DECKS:
            n = pages(pdf)
            print(f"\n{pdf.name} — {n} pages")
            for page in range(1, n + 1):
                got = ink(pdf, page, tmp)
                if not got:
                    continue
                (x0, y0, x1, y1), mask, box, sig, fill = got
                w, h = x1 - x0, y1 - y0
                if w < MIN_PT and h < MIN_PT:
                    continue                                   # section divider
                if fill > SOLID:
                    continue                                   # a colour plate, not a mark
                if any(abs(w - pw) < 2 and abs(h - ph) < 2 and same_mark(sig, ps)
                       for pw, ph, ps in fps):
                    continue                                   # same mark, other colourway
                txt = text_of(pdf, page)
                plain = re.sub(r"[★×✕\s®™]", "", txt)
                if len(plain) > 20:
                    continue                                   # an explanatory slide
                body, glyphs = artwork(pdf, page, tmp)
                label = OVERRIDES.get((pdf.name, page)) or describe(txt, glyphs, w / h)
                counts[label] = counts.get(label, 0) + 1
                if counts[label] > 1:
                    label = f"{label}  {counts[label]}"
                slug = (label.replace("™", " tm").replace("®", " r")
                             .replace("パラドックス", "kana").lower())
                lid = re.sub(r"-+", "-", re.sub(r"[^a-z0-9]+", "-", slug)).strip("-") or f"mark-{page}"
                while lid in ids:
                    lid = re.sub(r"-(\d+)$", lambda m: f"-{int(m.group(1))+1}", lid) \
                          if re.search(r"-\d+$", lid) else lid + "-2"
                ids.add(lid)
                fps.append((w, h, sig))
                logos.append({
                    "id": lid, "label": label,
                    "vb": f"{x0:.3f} {y0:.3f} {w:.3f} {h:.3f}",
                    "w": round(w, 3), "h": round(h, 3),
                    "ax": axis(mask, box),
                    "d": body,
                    "src": f"{pdf.name} p{page}",
                })
                print(f"  p{page:<3} {label:<28} {w:7.1f}×{h:7.1f}pt")
    # browsing order: the verticals first, the bare star last
    RANK = ["VERTICAL", "BRACKET", "STACKED", "HORIZONTAL"]
    def order(pair):
        pos, l = pair
        form = l["label"].split(" ")[0]
        return (9 if l["label"].startswith("MARK") else RANK.index(form),
                "パ" in l["label"], pos)
    logos = [l for _, l in sorted(enumerate(logos), key=order)]
    js = ("/* generated by tools/build_logos.py — do not edit by hand */\n"
          "window.LOGOS = " + json.dumps(logos, ensure_ascii=False, separators=(",", ":")) + ";\n")
    OUT.write_text(js)
    print(f"\n→ {OUT}  ({len(js)/1024:.0f} kB, {len(logos)} marks)")


if __name__ == "__main__":
    main()
