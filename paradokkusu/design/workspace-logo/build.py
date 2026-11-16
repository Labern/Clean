import math, sys
from fontTools.ttLib import TTFont
from fontTools.pens.svgPathPen import SVGPathPen
from fontTools.pens.transformPen import TransformPen
from fontTools.pens.boundsPen import BoundsPen

F = TTFont('/tmp/claude-0/-home-user-Clean/8f376678-9137-5c58-984c-ba9f21450ac9/scratchpad/fonts/package/files/noto-serif-jp-latin-900-normal.woff')
gs = F.getGlyphSet(); cmap = F.getBestCmap(); upm = F['head'].unitsPerEm
CAP = F['OS/2'].sCapHeight or 733

def word(text, cap_px, track_em, x0, baseline):
    """Return (path_d, width) for text set with cap height cap_px, tracking in em."""
    s = cap_px / CAP
    pen = SVGPathPen(gs); x = 0; widths = []
    for i, ch in enumerate(text):
        g = cmap[ord(ch)]
        tp = TransformPen(pen, (s, 0, 0, -s, x0 + x, baseline))
        gs[g].draw(tp)
        adv = gs[g].width * s
        x += adv + (track_em * upm * s if i < len(text) - 1 else 0)
    return pen.getCommands(), x

def ink_bounds(text, cap_px, track_em):
    s = cap_px / CAP; x = 0; L = None; R = None
    for i, ch in enumerate(text):
        g = cmap[ord(ch)]; bp = BoundsPen(gs); gs[g].draw(bp)
        if bp.bounds:
            l, _, r, _ = bp.bounds
            L = x + l*s if L is None else L; R = x + r*s
        x += gs[g].width*s + (track_em*upm*s if i < len(text)-1 else 0)
    return L, R

def star(cx, cy, R, ratio=0.382):
    pts = []
    for k in range(10):
        a = -math.pi/2 + k*math.pi/5
        r = R if k % 2 == 0 else R*ratio
        pts.append(f"{cx + r*math.cos(a):.3f},{cy + r*math.sin(a):.3f}")
    return "M" + " L".join(pts) + " Z"

def glyph_path(ch, size_px, cx, cy):
    """Centre a glyph's ink box at (cx, cy); size_px = em size."""
    s = size_px/upm; g = cmap[ord(ch)]; bp = BoundsPen(gs); gs[g].draw(bp)
    l, b, r, t = bp.bounds
    ox = cx - (l + r)/2*s; oy = cy + (b + t)/2*s
    pen = SVGPathPen(gs); gs[g].draw(TransformPen(pen, (s, 0, 0, -s, ox, oy)))
    return pen.getCommands()

def build(W, H, fg, bg, name, text='PARADOXICA'):
    # Proportions tuned on a 320x132 artboard, scaled for any size.
    k = W/320
    track = 0.16; target = 252*k
    L, R = ink_bounds(text, 100, track); cap = 100*target/(R-L)
    L, R = ink_bounds(text, cap, track)
    ww = R - L
    x0 = (W - ww)/2 - L
    # vertical rhythm
    star_R = cap*0.62; gap1 = cap*0.42; x_size = cap*0.95; gap2 = cap*0.40
    xh = x_size*0.62  # approx ink height of ×
    block = 2*star_R*0.95 + gap1 + xh + gap2 + cap
    top = (H - block)/2
    sy = top + star_R  # star centre (ink slightly lower than geometric)
    # stars span the wordmark width
    n = 5; span = ww - 2*star_R*0.95
    stars = " ".join(star(W/2 - span/2 + i*span/(n-1), sy + star_R*0.05, star_R) for i in range(n))
    xc = top + 2*star_R*0.95 + gap1 + xh/2
    times = glyph_path('×', x_size, W/2, xc)
    base = top + block
    d, _ = word(text, cap, track, x0, base)
    bgrect = f'<rect width="{W}" height="{H}" fill="{bg}"/>' if bg else ''
    svg = f'''<svg xmlns="http://www.w3.org/2000/svg" width="{W}" height="{H}" viewBox="0 0 {W} {H}">
<title>★★★★★ × {text}</title>{bgrect}
<g fill="{fg}"><path d="{stars}"/><path d="{times}"/><path d="{d}"/></g>
</svg>'''
    open(name, 'w').write(svg)

out = sys.argv[1]
build(320, 132, '#fff', '#000', f'{out}/paradoxica-logo-white-on-black.svg')
build(320, 132, '#000', '#fff', f'{out}/paradoxica-logo-black-on-white.svg')
build(320, 132, '#fff', None, f'{out}/paradoxica-logo-white-transparent.svg')
build(320, 132, '#000', None, f'{out}/paradoxica-logo-black-transparent.svg')
