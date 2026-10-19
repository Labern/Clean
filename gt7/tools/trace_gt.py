#!/usr/bin/env python3
"""Trace the GT original circuits (no real-world geometry) from their in-game
course maps into the same format as data/maps.js. numpy + PIL only.

  python3 -I gt7/tools/trace_gt.py <dir with the map images> [--debug]

Per image: threshold the drawn line, keep the biggest blob, open it to drop
thin pit lanes, fill the region the lap encloses, grow it back out to the
line's centre, trace that outline (Moore neighbour), resample to 1000 points,
then orient it from a known start point + direction and scale to the official
length. Writes data/maps-gt.js.
"""
import json, math, os, sys
import numpy as np
from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, '..', 'data', 'maps-gt.js')

# file, line colour ('light' on dark / 'dark' on light), official km,
# start point as image fractions, travel direction there (image coords, y down),
# opening radius (px after resize) to remove thin pit lanes.
SPEC = {
    'trialmountain': dict(f='trialmountain.png', line='light', km=5.44, start=(0.54, 0.81), dir=(1, 0), open=0, close=5,
                          erase=[((0.215, 0.735), (0.305, 0.757))]),  # pit lane, where it splits from the T13 bend
    'deepforest':    dict(f='df2.png', line='light', km=4.25, start=(0.32, 0.15), dir=(-1, 0), open=0, close=4),
    'dragontrail':   dict(f='dragontrail2.jpg', line='dark', km=5.3, start=(0.12, 0.72), dir=(0.35, -1), open=1),
    'sardegna':      dict(f='sardegna.jpg', line='dark', km=5.113, start=(0.18, 0.55), dir=(0, -1), open=0),
    'tokyo':         dict(f='tokyo.jpg', line='dark', km=4.400, start=(0.55, 0.03), dir=(1, 0), open=1),
    'highspeedring': dict(f='highspeedring.png', line='light', km=4.0, start=(0.58, 0.08), dir=(-1, 0), open=0, close=5),
    'grandvalley':   dict(f='grandvalley.png', line='light', km=5.100, start=(0.80, 0.72), dir=(0, 1), open=1),
}

def load(path, line, maxdim=900):
    im = Image.open(path).convert('RGB')
    s = maxdim / max(im.size)
    if s < 1: im = im.resize((round(im.width * s), round(im.height * s)), Image.LANCZOS)
    a = np.asarray(im).astype(int)
    r, g, b = a[..., 0], a[..., 1], a[..., 2]
    lum = (r + g + b) / 3
    if line == 'light':
        m = (np.minimum(np.minimum(r, g), b) > 150) | ((r > 150) & (g < 90) & (b < 90))
    else:
        m = lum < 110
    return m, im

def shift_max(m, k=1):
    out = m.copy()
    for _ in range(k):
        p = np.pad(out, 1)
        out = np.zeros_like(out)
        for dy in (0, 1, 2):
            for dx in (0, 1, 2):
                out |= p[dy:dy + m.shape[0], dx:dx + m.shape[1]]
    return out

def shift_min(m, k=1):
    return ~shift_max(~m, k)

def components(m):
    """Label 8-connected components; returns list of index arrays, largest first."""
    h, w = m.shape
    lab = np.zeros((h, w), int)
    comps = []
    ys, xs = np.nonzero(m)
    cur = 0
    for y0, x0 in zip(ys, xs):
        if lab[y0, x0]: continue
        cur += 1
        stack = [(y0, x0)]; lab[y0, x0] = cur; pix = []
        while stack:
            y, x = stack.pop(); pix.append((y, x))
            for dy in (-1, 0, 1):
                for dx in (-1, 0, 1):
                    ny, nx = y + dy, x + dx
                    if 0 <= ny < h and 0 <= nx < w and m[ny, nx] and not lab[ny, nx]:
                        lab[ny, nx] = cur; stack.append((ny, nx))
        comps.append(pix)
    comps.sort(key=len, reverse=True)
    return comps

def mask_of(pix, shape):
    m = np.zeros(shape, bool)
    for y, x in pix: m[y, x] = True
    return m

def interior(line):
    """Pixels not on the line and not reachable from the border = inside the lap."""
    free = ~line
    comps = components(free)
    h, w = line.shape
    inside = [c for c in comps if not any(y in (0, h - 1) or x in (0, w - 1) for y, x in c)]
    return mask_of(inside[0], line.shape) if inside else None

def trace(blob):
    """Moore-neighbour boundary trace of a single blob → ordered (x, y) list."""
    ys, xs = np.nonzero(blob)
    i = np.argmin(ys * 10000 + xs)
    start = (ys[i], xs[i])
    nb = [(-1, 0), (-1, 1), (0, 1), (1, 1), (1, 0), (1, -1), (0, -1), (-1, -1)]
    pts = [start]; cur = start; back = 6  # came from the west
    h, w = blob.shape
    for _ in range(200000):
        found = False
        for k in range(8):
            d = (back + 1 + k) % 8
            ny, nx = cur[0] + nb[d][0], cur[1] + nb[d][1]
            if 0 <= ny < h and 0 <= nx < w and blob[ny, nx]:
                back = (d + 4) % 8
                cur = (ny, nx); found = True; break
        if not found or (cur == start and len(pts) > 2): break
        pts.append(cur)
    return [(x, y) for y, x in pts]

def resample(pts, n=1000):
    P = np.array(pts, float)
    # light smoothing of the pixel staircase (circular moving average)
    k = 7
    P = np.array([P[np.arange(i - k, i + k + 1) % len(P)].mean(0) for i in range(len(P))])
    seg = np.linalg.norm(np.diff(np.vstack([P, P[:1]]), axis=0), axis=1)
    cum = np.concatenate([[0], np.cumsum(seg)])
    L = cum[-1]
    out = []
    for t in np.linspace(0, L, n, endpoint=False):
        j = np.searchsorted(cum, t, side='right') - 1
        u = (t - cum[j]) / max(seg[j], 1e-9)
        a, b = P[j], P[(j + 1) % len(P)]
        out.append(a + (b - a) * u)
    return np.array(out), L

def main():
    src = sys.argv[1]
    debug = '--debug' in sys.argv
    maps = {}
    for tid, sp in SPEC.items():
        line, im = load(os.path.join(src, sp['f']), sp['line'])
        h0, w0 = line.shape
        for (ax, ay), (bx, by) in sp.get('erase', []):   # hand-picked pit-lane cuts
            for t in np.linspace(0, 1, 200):
                x, y = (ax + (bx - ax) * t) * w0, (ay + (by - ay) * t) * h0
                line[max(0, int(y) - 4):int(y) + 5, max(0, int(x) - 4):int(x) + 5] = False
        c = sp.get('close', 2)                # bridge corner ticks / start marker gaps
        base = mask_of(components(shift_min(shift_max(line, c), c))[0], line.shape)
        inside = None
        for r in range(sp['open'], -1, -1):   # strongest opening that still leaves a closed lap
            line = base
            if r:
                opened = shift_max(shift_min(base, r), r)
                line = mask_of(components(opened)[0], base.shape)
            inside = interior(line)
            ys, xs = np.nonzero(line)
            bbox = (ys.max() - ys.min()) * (xs.max() - xs.min())
            if inside is not None and inside.sum() > 0.25 * bbox: break
            inside = None
        if inside is None:
            print(tid, 'no closed lap found'); continue
        # grow the lap's interior out to the centre of the drawn line
        half = max(1, round(line.sum() / max(1, len(trace(shift_max(inside, 1)))) / 2))
        blob = shift_max(inside, half)
        pts, L = resample(trace(blob))
        h, w = line.shape
        # orient: start at the point nearest the given start, heading the given way
        sx, sy = sp['start'][0] * w, sp['start'][1] * h
        i0 = int(np.argmin(((pts - [sx, sy]) ** 2).sum(1)))
        pts = np.roll(pts, -i0, axis=0)
        tang = pts[5] - pts[0]
        if tang @ np.array(sp['dir'], float) < 0:
            pts = np.vstack([pts[:1], pts[1:][::-1]])
        mpu_px = sp['km'] * 1000 / L  # metres per image pixel
        # normalise to the maps.js convention: longest side = 1000 units, y down, north up
        mn = pts.min(0); span = (pts.max(0) - mn).max()
        u = (pts - mn) / span * 1000
        maps[tid] = {'km': sp['km'], 'w': int(round(u[:, 0].max())), 'h': int(round(u[:, 1].max())),
                     'mPerUnit': round(mpu_px * span / 1000, 3), 'traced': True,
                     'pts': [[int(round(x)), int(round(y))] for x, y in u]}
        print(f'{tid:14s} {len(pts)} pts  line half-width {half}px  perimeter {L:.0f}px')
        if debug:
            dbg = im.copy().convert('RGB')
            from PIL import ImageDraw
            d = ImageDraw.Draw(dbg)
            d.line([tuple(p) for p in pts] + [tuple(pts[0])], fill=(255, 200, 0), width=2)
            d.ellipse([pts[0][0] - 6, pts[0][1] - 6, pts[0][0] + 6, pts[0][1] + 6], fill=(0, 200, 0))
            d.ellipse([pts[40][0] - 4, pts[40][1] - 4, pts[40][0] + 4, pts[40][1] + 4], fill=(0, 120, 255))
            dbg.save(os.path.join(src, f'dbg_{tid}.png'))
    with open(OUT, 'w') as f:
        f.write('// Generated by tools/trace_gt.py from the in-game course maps of the GT original\n')
        f.write('// circuits (no real-world geometry exists). Same format as maps.js: north up,\n')
        f.write('// 1000 points per lap at equal arc length from the start/finish line.\n')
        f.write('export const MAPS_GT = ' + json.dumps(maps, separators=(',', ':')) + ';\n')
    print('wrote', OUT)

if __name__ == '__main__':
    main()
