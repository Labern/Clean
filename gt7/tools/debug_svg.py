#!/usr/bin/env python3
"""Debug render: every raceway way (grey, with its tags on hover) + chosen loop (red)."""
import json, math, os, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import osm_tracks as T
cid, out = sys.argv[1], sys.argv[2]
s, w, n, e, _ = T.padded(cid)
nodes, ways = T.load((s, w, n, e))
# also show ALL raceway ways incl pit-filtered ones in blue
import xml.etree.ElementTree as ET
allw = {}
for blob in T.fetch((s, w, n, e)):
    root = ET.fromstring(blob)
    for wy in root.iter("way"):
        tags = {t.get("k"): t.get("v") for t in wy.iter("tag")}
        if tags.get("highway") in ("raceway",) or tags.get("leisure") == "track":
            allw[wy.get("id")] = ([x.get("ref") for x in wy.iter("nd")], tags)
geo = json.load(open(T.OUT)).get(cid)
c = math.cos(math.radians((s + n) / 2))
X = lambda lo: (lo - w) * c / ((e - w) * c) * 1000
Y = lambda la: (n - la) / (n - s) * 1000 * (n - s) / ((e - w) * c)
H = Y(s)
parts = [f'<svg xmlns="http://www.w3.org/2000/svg" width="1000" height="{H:.0f}" style="background:#fff">']
for wid, (refs, tags) in allw.items():
    p = " ".join(f"{X(nodes[r][1]):.1f},{Y(nodes[r][0]):.1f}" for r in refs if r in nodes)
    col = "#bbb" if wid in ways else "#39f"
    parts.append(f'<polyline points="{p}" fill="none" stroke="{col}" stroke-width="3"/>')
if geo:
    p = " ".join(f"{X(lo):.1f},{Y(la):.1f}" for la, lo in geo["pts"])
    parts.append(f'<polyline points="{p}" fill="none" stroke="red" stroke-width="1.5"/>')
    la, lo = geo["pts"][0]; parts.append(f'<circle cx="{X(lo):.1f}" cy="{Y(la):.1f}" r="8" fill="green"/>')
    la, lo = geo["pts"][30]; parts.append(f'<circle cx="{X(lo):.1f}" cy="{Y(la):.1f}" r="5" fill="orange"/>')
parts.append("</svg>")
open(out, "w").write("\n".join(parts))
for wid, (refs, tags) in allw.items():
    if wid not in ways: print("filtered:", wid, tags)
