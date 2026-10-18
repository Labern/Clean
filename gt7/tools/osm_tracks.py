#!/usr/bin/env python3
"""Pull real circuit geometry from OpenStreetMap and emit gt7/tools/geo.json.

For each circuit: fetch the bbox from the OSM API (tiling if it is too dense),
keep highway=raceway ways (no pit lanes), split them into a junction graph,
enumerate simple cycles and keep the one whose length is closest to the
official layout length. The polyline is resampled to fixed arc-length steps so
downstream code can address the lap by fraction (0..1).

  python3 -I gt7/tools/osm_tracks.py [id ...]     # cache: $OSM_CACHE or ./.osm-cache
"""
import json, math, os, re, sys, time, urllib.request, xml.etree.ElementTree as ET

UA = "GT7Companion/1.0 (https://labern.github.io/Clean/gt7/)"
HERE = os.path.dirname(os.path.abspath(__file__))
CACHE = os.environ.get("OSM_CACHE", os.path.join(HERE, ".osm-cache"))
OUT = os.path.join(HERE, "geo.json")

# id: (south, west, north, east, official length km)
CIRCUITS = {
    "nordschleife": (50.325, 6.925, 50.385, 7.015, 20.83),
    "spa":          (50.424, 5.955, 50.448, 5.985, 7.004),
    "suzuka":       (34.832, 136.520, 34.852, 136.545, 5.807),
    "lemans":       (47.890, 0.185, 47.965, 0.240, 13.626),
    "monza":        (45.605, 9.270, 45.640, 9.300, 5.793),
    "bathurst":     (-33.462, 149.540, -33.430, 149.570, 6.213),
    "laguna":       (36.578, -121.760, 36.592, -121.746, 3.602),
    "interlagos":   (-23.710, -46.705, -23.695, -46.690, 4.309),
    "fuji":         (35.363, 138.917, 35.380, 138.940, 4.563),
    "daytona":      (29.178, -81.080, 29.196, -81.062, 5.78),  # 5.729 official; aim long so the loop takes the Bus Stop
    "roadatlanta":  (34.140, -83.822, 34.153, -83.806, 4.088),
    "watkins":      (42.328, -76.932, 42.346, -76.914, 5.552),  # GT7 Long Course, with the Inner Loop
    "redbullring":  (47.214, 14.756, 47.228, 14.773, 4.318),
    "catalunya":    (41.563, 2.252, 41.576, 2.267, 4.657),
    "montreal":     (45.495, -73.535, 45.512, -73.517, 4.361),
    "brands":       (51.352, 0.255, 51.362, 0.270, 3.908),
    "tsukuba":      (36.147, 139.915, 36.155, 139.927, 2.045),
    "autopolis":    (33.030, 130.964, 33.043, 130.982, 4.674),
    "goodwood":     (50.853, -0.770, 50.866, -0.752, 3.809),

}

def fetch(bbox):
    s, w, n, e = bbox
    key = os.path.join(CACHE, f"{s:.4f}_{w:.4f}_{n:.4f}_{e:.4f}.xml")
    if os.path.exists(key):
        return [open(key, "rb").read()]
    url = f"https://api.openstreetmap.org/api/0.6/map?bbox={w},{s},{e},{n}"
    req = urllib.request.Request(url, headers={"User-Agent": UA})
    try:
        data = urllib.request.urlopen(req, timeout=120).read()
    except urllib.error.HTTPError as err:
        if err.code != 400:
            raise
        # too many nodes: split into quadrants
        ms, mw = (s + n) / 2, (w + e) / 2
        out = []
        for q in ((s, w, ms, mw), (s, mw, ms, e), (ms, w, n, mw), (ms, mw, n, e)):
            out += fetch(q)
        return out
    os.makedirs(CACHE, exist_ok=True)
    open(key, "wb").write(data)
    time.sleep(1)
    return [data]

# corner names carry these words too ("Pit Straight", "Virage du Karting",
# "Paddock Hill Bend"), so match whole phrases only
PIT = re.compile(r"^pit$|pit ?lane|pit_lane|pit (entry|exit|road|in|out)|boxengasse|kart(ing)? ?(track|circuit|bahn)|drag ?strip|skid")

def is_pit(tags):
    # names only: "Paddock Hill Bend" and "Service Road Corner" are racing line
    blob = " ".join(tags.get(k, "") for k in ("name", "name:en", "raceway", "service", "description")).lower()
    return bool(PIT.search(blob))

def hav(a, b):
    R = 6371.0088
    la1, lo1, la2, lo2 = map(math.radians, (a[0], a[1], b[0], b[1]))
    h = math.sin((la2 - la1) / 2) ** 2 + math.cos(la1) * math.cos(la2) * math.sin((lo2 - lo1) / 2) ** 2
    return 2 * R * math.asin(math.sqrt(h))

def load_relation(rid):
    key = os.path.join(CACHE, f"rel{rid}.xml")
    if not os.path.exists(key):
        url = f"https://api.openstreetmap.org/api/0.6/relation/{rid}/full"
        data = urllib.request.urlopen(urllib.request.Request(url, headers={"User-Agent": UA}), timeout=120).read()
        os.makedirs(CACHE, exist_ok=True)
        open(key, "wb").write(data)
    root = ET.fromstring(open(key, "rb").read())
    nodes = {nd.get("id"): (float(nd.get("lat")), float(nd.get("lon"))) for nd in root.iter("node")}
    rel = next(r for r in root.iter("relation") if r.get("id") == str(rid))
    roles = {m.get("ref"): m.get("role", "") for m in rel.iter("member") if m.get("type") == "way"}
    ways = {}
    for w in root.iter("way"):
        if w.get("id") not in roles:
            continue
        refs = [n.get("ref") for n in w.iter("nd")]
        if "pit" in roles[w.get("id")]:
            PITS.append((refs, {t.get("k"): t.get("v") for t in w.iter("tag")}))
        else:
            ways[w.get("id")] = (refs, {t.get("k"): t.get("v") for t in w.iter("tag")})
    return nodes, ways

def load(bbox):
    nodes, ways = {}, {}
    for blob in fetch(bbox):
        root = ET.fromstring(blob)
        for nd in root.iter("node"):
            nodes[nd.get("id")] = (float(nd.get("lat")), float(nd.get("lon")))
        for w in root.iter("way"):
            tags = {t.get("k"): t.get("v") for t in w.iter("tag")}
            if tags.get("highway") in ("raceway", "service") and is_pit(tags) and "disused" not in tags:
                PITS.append(([n.get("ref") for n in w.iter("nd")], tags))
            elif tags.get("highway") == "raceway" and not is_pit(tags) and not EXCLUDE.search(tags.get("name", "") or "^$"):
                ways[w.get("id")] = ([n.get("ref") for n in w.iter("nd")], tags)
    return nodes, ways

NAME, SEGNAME = {}, {}
# one-off layouts that are not in GT7
EXCLUDE = re.compile(r"2021 NASCAR chicane|moto ?gp|long lap", re.I)
PITS = []  # filled by load()/load_relation(): (refs, tags) of pit-lane ways

def graph(nodes, ways):
    use = {}
    for wid, (refs, _) in ways.items():
        for r in refs:
            use[r] = use.get(r, 0) + 1
    edges = []
    for wid, (refs, tags) in ways.items():
        NAME[wid] = tags.get("name:en") or tags.get("name") or ""
        refs = [r for r in refs if r in nodes]
        if len(refs) < 2:
            continue
        cur = [refs[0]]
        for r in refs[1:]:
            cur.append(r)
            if use[r] > 1 or r == refs[-1]:
                edges.append((cur, wid))
                cur = [r]
    out = []
    for seg, wid in edges:
        SEGNAME[id(seg)] = NAME[wid]
        L = sum(hav(nodes[a], nodes[b]) for a, b in zip(seg, seg[1:]))
        if seg[0] == seg[-1]:
            out.append((seg[0], seg[0], seg, L))  # closed way
        else:
            out.append((seg[0], seg[-1], seg, L))
    return out

def prune(edges):
    """Drop dead-end spurs repeatedly; a lap can never use them."""
    while True:
        deg = {}
        for a, b, _, _ in edges:
            if a != b:
                deg[a] = deg.get(a, 0) + 1
                deg[b] = deg.get(b, 0) + 1
        keep = [x for x in edges if x[0] == x[1] or (deg[x[0]] > 1 and deg[x[1]] > 1)]
        if len(keep) == len(edges):
            return keep
        edges = keep

def best_cycle(edges, target):
    edges = prune(edges)
    adj = {}
    for i, (a, b, _, _) in enumerate(edges):
        adj.setdefault(a, []).append(i)
        adj.setdefault(b, []).append(i)
    best = (float("inf"), None)
    # closed single ways
    for i, (a, b, seg, L) in enumerate(edges):
        if a == b:
            d = abs(L - target)
            if d < best[0]:
                best = (d, [(i, True)])
    budget = [400000]
    def dfs(start, node, used_e, used_n, path, L):
        budget[0] -= 1
        if budget[0] < 0 or L > target * 1.25:
            return
        nonlocal best
        for i in adj.get(node, []):
            if i in used_e:
                continue
            a, b, seg, l = edges[i]
            if a == b:
                continue
            nxt, fwd = (b, True) if a == node else (a, False)
            if nxt == start:
                d = abs(L + l - target)
                if d < best[0]:
                    best = (d, path + [(i, fwd)])
                continue
            if nxt in used_n:
                continue
            used_e.add(i); used_n.add(nxt)
            dfs(start, nxt, used_e, used_n, path + [(i, fwd)], L + l)
            used_e.discard(i); used_n.discard(nxt)
    for s in sorted(adj, key=lambda k: -len(adj[k]))[:40]:
        budget[0] = 150000
        dfs(s, s, set(), {s}, [], 0.0)
        if best[0] < target * 0.002:
            break
    return best[0], best[1], edges

def resample(pts, n, names):
    d = [0.0]
    for a, b in zip(pts, pts[1:]):
        d.append(d[-1] + hav(a, b))
    total = d[-1]
    out, nm, j = [], [], 0
    for k in range(n):
        t = total * k / n
        while d[j + 1] < t:
            j += 1
        f = (t - d[j]) / ((d[j + 1] - d[j]) or 1)
        out.append((pts[j][0] + (pts[j + 1][0] - pts[j][0]) * f, pts[j][1] + (pts[j + 1][1] - pts[j][1]) * f))
        nm.append(names[j + 1])
    return out, total, nm

# circuits on public roads (not highway=raceway): use their type=circuit relation
RELATIONS = {"lemans": 2126739, "bathurst": 6942508}

FLIP = {"autopolis"}  # runs clockwise; no pit lane mapped to tell us

# Start/finish relative to a named corner (the pit midpoint is only roughly the
# line): index 0 := start of that corner + offset (lap fraction). Last
# occurrence wins when a name wraps round index 0.
SF = {
    "spa": ("La Source", -0.02), "daytona": ("International Horseshoe", -0.17),
    "brands": ("Paddock Hill", -0.05), "bathurst": ("Hell Corner", -0.035),
    "redbullring": ("Niki Lauda Kurve", -0.07), "suzuka": ("First Turn", -0.07),
    "monza": ("Variante del Rettifilo", -0.11), "interlagos": ("Senna-S", -0.04),
    "watkins": ("The Ninety", -0.03),
}

PAD = 0.35  # bboxes are rough; pad them, the length match rejects stray loops

def padded(cid):
    s, w, n, e, target = CIRCUITS[cid]
    dy, dx = (n - s) * PAD, (e - w) * PAD
    return s - dy, w - dx, n + dy, e + dx, target

def orient(rs, nodes, rn):
    """Rotate/reverse the lap so index 0 sits at the pits and runs the race direction.

    Pit lanes are one-way in the race direction, so the longest pit way gives
    both the start/finish area (its midpoint) and the sense of the lap."""
    pits = [(r, t) for r, t in PITS if len([x for x in r if x in nodes]) > 1]
    if not pits:
        return rs, "no pit lane: orientation unverified", rn
    def plen(p):
        c = [nodes[x] for x in p[0] if x in nodes]
        return sum(hav(a, b) for a, b in zip(c, c[1:]))
    refs, tags = max(pits, key=plen)
    c = [nodes[x] for x in refs if x in nodes]
    if tags.get("oneway") == "-1":
        c = c[::-1]
    mid = c[len(c) // 2]
    a, b = c[max(0, len(c) // 2 - 2)], c[min(len(c) - 1, len(c) // 2 + 2)]
    pdir = (b[0] - a[0], b[1] - a[1])
    i = min(range(len(rs)), key=lambda k: hav(rs[k], mid))
    t = (rs[(i + 3) % len(rs)][0] - rs[i - 3][0], rs[(i + 3) % len(rs)][1] - rs[i - 3][1])
    rev = pdir[0] * t[0] + pdir[1] * t[1] < 0
    out, on = rs[i:] + rs[:i], rn[i:] + rn[:i]
    if rev:
        out, on = [out[0]] + out[1:][::-1], [on[0]] + on[1:][::-1]
    return out, f"pit {'oneway' if tags.get('oneway') else 'NOT oneway'}{', reversed' if rev else ''}, {hav(rs[i], mid)*1000:.0f} m off", on

def run(cid):
    PITS.clear()
    s, w, n, e, target = padded(cid)
    nodes, ways = load_relation(RELATIONS[cid]) if cid in RELATIONS else load((s, w, n, e))
    edges = graph(nodes, ways)
    diff, cyc, edges = best_cycle(edges, target)
    if not cyc:
        return None, f"{cid}: no cycle ({len(ways)} raceway ways)"
    pts, names = [], []
    for i, fwd in cyc:
        raw = edges[i][2]
        seg = raw if fwd else raw[::-1]
        coords = [nodes[r] for r in seg]
        add = coords if not pts else coords[1:]
        pts += add
        names += [SEGNAME.get(id(raw), "")] * len(add)
    if pts[0] != pts[-1]:
        pts.append(pts[0]); names.append(names[0])
    rs, total, rn = resample(pts, 1000, names)
    rs, note, rn = orient(rs, nodes, rn)
    if cid in FLIP:  # pit-lane heuristic overruled by the named corner order
        rs, rn = [rs[0]] + rs[1:][::-1], [rn[0]] + rn[1:][::-1]
        note += ", FLIPPED by override"
    if cid in SF:
        nm0, off = SF[cid]
        starts = [k for k in range(len(rn)) if rn[k] == nm0 and rn[k - 1] != nm0]
        k0 = (starts[-1] + round(off * len(rn))) % len(rn)
        rs, rn = rs[k0:] + rs[:k0], rn[k0:] + rn[:k0]
        note += f", S/F set from {nm0}"
    runs = []
    for k, nm in enumerate(rn):
        if runs and runs[-1][0] == nm:
            runs[-1][2] = k + 1
        else:
            runs.append([nm, k, k + 1])
    return {"km": round(total, 3), "target": target, "pts": [[round(a, 6), round(b, 6)] for a, b in rs],
            "names": [[nm, a / 1000, b / 1000] for nm, a, b in runs if nm]}, \
        f"{cid}: {total:.3f} km vs {target} ({100*(total-target)/target:+.1f}%), {len(ways)} ways; {note}"

if __name__ == "__main__":
    ids = sys.argv[1:] or list(CIRCUITS)
    geo = json.load(open(OUT)) if os.path.exists(OUT) else {}
    for cid in ids:
        try:
            res, msg = run(cid)
        except Exception as ex:
            res, msg = None, f"{cid}: ERROR {ex}"
        print(msg, flush=True)
        if res:
            geo[cid] = res
    json.dump(geo, open(OUT, "w"))
