#!/usr/bin/env python3
"""List detected corners per track from data/geo.json: lap fraction, L/R,
total heading change, tightest radius, OSM name. Used to author the corner
guides so every corner pin lands on the real geometry.

  python3 -I gt7/tools/corners.py [id ...]
"""
import json, math, os, sys
GEO = os.path.join(os.path.dirname(os.path.abspath(__file__)), "geo.json")

def detect(g, min_deg=18):
    P = g["pts"]; n = len(P); step = g["km"] * 1000 / n
    c = math.cos(math.radians(P[0][0]))
    xy = [(lo * c * 111320, la * 110540) for la, lo in P]
    hd = []
    for i in range(n):
        a, b = xy[i], xy[(i + 1) % n]
        hd.append(math.atan2(b[1] - a[1], b[0] - a[0]))
    d = []
    for i in range(n):
        x = hd[i] - hd[i - 1]
        while x > math.pi: x -= 2 * math.pi
        while x < -math.pi: x += 2 * math.pi
        d.append(x)
    w = max(1, round(25 / step))  # ~50 m window
    sm = [sum(d[(i + k) % n] for k in range(-w, w + 1)) / (2 * w + 1) for i in range(n)]
    thr = step / 300  # radius < ~300 m counts as cornering
    regions, cur = [], None
    for i in range(n):
        s = 1 if sm[i] > thr else -1 if sm[i] < -thr else 0
        if s and cur and cur[0] == s and i - cur[2] <= max(1, round(40 / step)):
            cur[2] = i
        elif s:
            cur = [s, i, i]; regions.append(cur)
    out = []
    for s, a, b in regions:
        ang = math.degrees(sum(d[k % n] for k in range(a, b + 1)))
        if abs(ang) < min_deg:
            continue
        peak = max(range(a, b + 1), key=lambda k: abs(sm[k % n]))
        r = step / abs(sm[peak % n]) if sm[peak % n] else 9999
        name = ""
        for nm, f0, f1 in g.get("names", []):
            if f0 <= peak / n < f1: name = nm
        # CCW positive in east/north coords => left turn
        out.append({"at": round(peak / n, 3), "from": round(a / n, 3), "to": round(b / n, 3),
                    "dir": "L" if ang > 0 else "R", "deg": round(abs(ang)), "r": round(r), "osm": name})
    return out

if __name__ == "__main__":
    geo = json.load(open(GEO))
    for cid in sys.argv[1:] or geo:
        g = geo[cid]
        print(f"== {cid} {g['km']} km")
        for k, x in enumerate(detect(g), 1):
            print(f"  {k:2d} @{x['at']:.3f} ({x['from']:.3f}-{x['to']:.3f}) {x['dir']} {x['deg']:3d}° r{x['r']:4d}m  {x['osm']}")
