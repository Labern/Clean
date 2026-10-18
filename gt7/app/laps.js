// Lap storage + analysis for the Data Logger.
//  - storage: IndexedDB on this device (laps are too big for localStorage),
//    with cloud copies via sync.js so laps follow you between devices
//  - align(): identifies which real circuit a lap was driven on by fitting the
//    recorded line to every OSM map (rotation + reflection + translation +
//    scale, Procrustes on arc-length samples), then returns the transform that
//    puts the map outline and corner pins into the lap's own coordinates
import { MAPS } from '../data/maps.js';
import { TRACKS } from '../data/tracks.js';

// ── IndexedDB ───────────────────────────────────────────
const DB = 'gt7-endgame-laps';
let dbp = null;
function db() {
  dbp ??= new Promise((res, rej) => {
    const r = indexedDB.open(DB, 1);
    r.onupgradeneeded = () => r.result.createObjectStore('laps', { keyPath: 'id' });
    r.onsuccess = () => res(r.result);
    r.onerror = () => rej(r.error);
  });
  return dbp;
}
const tx = async (mode, fn) => { const d = await db(); return new Promise((res, rej) => { const t = d.transaction('laps', mode); const out = fn(t.objectStore('laps')); t.oncomplete = () => res(out instanceof IDBRequest ? out.result : out); t.onerror = () => rej(t.error); }); };
export const putLap = (lap) => {
  if (lap.pts && !lap.track && !lap.demo) { const a = align(lap); if (a) lap.track = a.track.id; } // identify once, on save
  return tx('readwrite', (s) => s.put(lap));
};
export const getLap = (id) => tx('readonly', (s) => s.get(id));
export const delLap = (id) => tx('readwrite', (s) => s.delete(id));
export async function allLaps() {
  const d = await db();
  return new Promise((res) => { const out = []; const c = d.transaction('laps').objectStore('laps').openCursor(); c.onsuccess = () => { const cur = c.result; if (!cur) return res(out.sort((a, b) => b.t0 - a.t0)); const { pts, ...meta } = cur.value; out.push(meta); cur.continue(); }; });
}

// ── lap shape helpers ───────────────────────────────────
export const cols = (lap) => Object.fromEntries(lap.cols.map((c, i) => [c, i]));
export function distances(lap) {
  const C = cols(lap), d = [0];
  for (let i = 1; i < lap.pts.length; i++) { const a = lap.pts[i - 1], b = lap.pts[i]; d.push(d[i - 1] + Math.hypot(b[C.x] - a[C.x], b[C.z] - a[C.z])); }
  return d;
}
function resample(xy, n) {
  const d = [0];
  for (let i = 1; i < xy.length; i++) d.push(d[i - 1] + Math.hypot(xy[i][0] - xy[i - 1][0], xy[i][1] - xy[i - 1][1]));
  const L = d.at(-1), out = [];
  for (let k = 0, j = 0; k < n; k++) {
    const t = (L * k) / n;
    while (j < d.length - 2 && d[j + 1] < t) j++;
    const f = (t - d[j]) / ((d[j + 1] - d[j]) || 1);
    out.push([xy[j][0] + (xy[j + 1][0] - xy[j][0]) * f, xy[j][1] + (xy[j + 1][1] - xy[j][1]) * f]);
  }
  return { pts: out, len: L };
}
// best similarity transform src→dst (paired points), optional reflection
function procrustes(src, dst, reflect) {
  const n = src.length;
  let sx = 0, sy = 0, dx = 0, dy = 0;
  for (let i = 0; i < n; i++) { sx += src[i][0]; sy += src[i][1] * (reflect ? -1 : 1); dx += dst[i][0]; dy += dst[i][1]; }
  sx /= n; sy /= n; dx /= n; dy /= n;
  let a = 0, b = 0, ss = 0;
  for (let i = 0; i < n; i++) {
    const px = src[i][0] - sx, py = src[i][1] * (reflect ? -1 : 1) - sy, qx = dst[i][0] - dx, qy = dst[i][1] - dy;
    a += px * qx + py * qy; b += px * qy - py * qx; ss += px * px + py * py;
  }
  const th = Math.atan2(b, a), s = Math.hypot(a, b) / ss;
  const c = Math.cos(th) * s, si = Math.sin(th) * s;
  const T = ([x, y]) => { const px = x - sx, py = y * (reflect ? -1 : 1) - sy; return [c * px - si * py + dx, si * px + c * py + dy]; };
  let err = 0;
  for (let i = 0; i < n; i++) { const p = T(src[i]); err += (p[0] - dst[i][0]) ** 2 + (p[1] - dst[i][1]) ** 2; }
  return { T, rms: Math.sqrt(err / n), scale: s };
}

function procrustesInv(b) {
  // fit lap→map directly; reflection is symmetric so reuse the flag
  const r = procrustes(b.lapPts, b.shifted, b.reflect);
  return r.T;
}

const alignCache = new Map();
export function align(lap) {
  if (alignCache.has(lap.id)) return alignCache.get(lap.id);
  const C = cols(lap), N = 160;
  const lapXY = resample(lap.pts.map((p) => [p[C.x], p[C.z]]), N);
  let best = null;
  for (const t of TRACKS) {
    const m = t.map && MAPS[t.map];
    if (!m) continue;
    const mm = m.km * 1000;
    if (Math.abs(lapXY.len - mm) / mm > 0.15) continue; // racing line is a bit shorter than the centreline
    const mapXY = resample(m.pts.map(([x, y]) => [x * m.mPerUnit, y * m.mPerUnit]), N);
    for (const reflect of [false, true]) {
      for (let off = -12; off <= 12; off += 1) { // the lap may start a little off the map's line
        const shifted = mapXY.pts.map((_, i) => mapXY.pts[(i + off + N) % N]);
        const r = procrustes(shifted, lapXY.pts, reflect);
        if (r.scale < 0.85 || r.scale > 1.15) continue;
        if (!best || r.rms < best.rms) best = { track: t, map: m, rms: r.rms, T: r.T, scale: r.scale, off, reflect, shifted, lapPts: lapXY.pts };
      }
    }
  }
  const out = best && best.rms < 40 ? best : null;
  // inverse (lap → map, north-up) for drawing in the same frame as the guides
  if (out) out.Tinv = procrustesInv(out);
  alignCache.set(lap.id, out);
  return out;
}

// map lap fraction f → point on the aligned outline in lap coordinates
export function mapPointAt(al, f) {
  const m = al.map, i = Math.round(f * m.pts.length) % m.pts.length;
  return al.T([m.pts[i][0] * m.mPerUnit, m.pts[i][1] * m.mPerUnit]);
}

// time-delta of lap vs ref by distance, every 20 m
export function delta(lap, ref) {
  const a = distances(lap), b = distances(ref), Ca = cols(lap), Cb = cols(ref);
  const tAt = (pts, d, C, D) => { let j = D.findIndex((x) => x >= d); if (j < 1) j = 1; const f = (d - D[j - 1]) / ((D[j] - D[j - 1]) || 1); return pts[j - 1][C.t] + (pts[j][C.t] - pts[j - 1][C.t]) * f; };
  const L = Math.min(a.at(-1), b.at(-1)), out = [];
  for (let d = 0; d <= L; d += 20) out.push([d, tAt(lap.pts, d, Ca, a) - tAt(ref.pts, d, Cb, b)]);
  return out;
}

// for cloud: thin a lap to ~10 Hz to keep messages small
export function thin(lap) {
  const C = cols(lap), out = [];
  let last = -1;
  for (const p of lap.pts) if (p[C.t] - last >= 0.095) { out.push(p); last = p[C.t]; }
  if (out.at(-1) !== lap.pts.at(-1)) out.push(lap.pts.at(-1));
  return { ...lap, pts: out, n: out.length, thinned: true };
}

export const fmtLap = (ms) => { if (ms == null || ms < 0) return '—'; const s = ms / 1000, m = Math.floor(s / 60); return `${m}:${(s - m * 60).toFixed(3).padStart(6, '0')}`; };
