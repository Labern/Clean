// Generate data/demo-lap.json: a plausible Gr.3 lap of Spa built from the real
// OSM centreline, so the Data Logger has something to replay before a PS5 is
// connected (and so the bridge's --demo mode has a source).
//   node gt7/tools/make_demo_lap.mjs [trackId]
// Model: smooth the centreline toward a racing line (clamped to ±5.5 m), take
// curvature, cap speed by lateral grip (v = sqrt(a·R)), then forward/backward
// passes for traction and braking limits. Output is rotated/mirrored into an
// arbitrary frame like GT7's world coordinates, which the app's aligner must undo.
import fs from 'fs';
import path from 'path';
import { fileURLToPath } from 'url';
import { MAPS } from '../data/maps.js';

const HERE = path.dirname(fileURLToPath(import.meta.url));
const id = process.argv[2] || 'spa';
const m = MAPS[id];
const P = m.pts.map(([x, y]) => [x * m.mPerUnit, y * m.mPerUnit]); // metres, y = south
const n = P.length, ds = (m.km * 1000) / n;

// racing line: heavy moving average, then clamp the offset from centre
const W = Math.round(45 / ds), HALF = 5.5;
const line = P.map((_, i) => {
  let sx = 0, sy = 0;
  for (let k = -W; k <= W; k++) { const q = P[(i + k + n) % n]; sx += q[0]; sy += q[1]; }
  let x = sx / (2 * W + 1), y = sy / (2 * W + 1);
  const dx = x - P[i][0], dy = y - P[i][1], d = Math.hypot(dx, dy);
  if (d > HALF) { x = P[i][0] + dx / d * HALF; y = P[i][1] + dy / d * HALF; }
  return [x, y];
});
// curvature by the three-point circle
const R = line.map((_, i) => {
  const a = line[(i - 3 + n) % n], b = line[i], c = line[(i + 3) % n];
  const ab = Math.hypot(b[0] - a[0], b[1] - a[1]), bc = Math.hypot(c[0] - b[0], c[1] - b[1]), ca = Math.hypot(a[0] - c[0], a[1] - c[1]);
  const area2 = Math.abs((b[0] - a[0]) * (c[1] - a[1]) - (b[1] - a[1]) * (c[0] - a[0]));
  return area2 < 1e-6 ? 1e9 : (ab * bc * ca) / (2 * area2);
});
const sign = line.map((_, i) => {
  const a = line[(i - 3 + n) % n], b = line[i], c = line[(i + 3) % n];
  return Math.sign((b[0] - a[0]) * (c[1] - b[1]) - (b[1] - a[1]) * (c[0] - b[0]));
});
const ALAT = 17, VMAX = 285 / 3.6, ACC = 5.5, BRK = 15;
let v = R.map((r) => Math.min(VMAX, Math.sqrt(ALAT * r)));
for (let pass = 0; pass < 2; pass++) {
  for (let i = 1; i < 2 * n; i++) { const a = (i - 1) % n, b = i % n; v[b] = Math.min(v[b], Math.sqrt(v[a] ** 2 + 2 * ACC * ds)); }
  for (let i = 2 * n - 2; i >= 0; i--) { const a = (i + 1) % n, b = i % n; v[b] = Math.min(v[b], Math.sqrt(v[a] ** 2 + 2 * BRK * ds)); }
}
// frame transform: rotate 37° and mirror, like an arbitrary game world frame
const th = 37 * Math.PI / 180, cx = P.reduce((s, p) => s + p[0], 0) / n, cy = P.reduce((s, p) => s + p[1], 0) / n;
const toGame = ([x, y]) => { const X = x - cx, Y = y - cy; return [X * Math.cos(th) - Y * Math.sin(th) + 412.5, -(X * Math.sin(th) + Y * Math.cos(th)) - 233.1]; };
const GEARS = [0, 95, 135, 170, 205, 240, 400];
let t = 0;
const pts = [];
for (let i = 0; i <= n; i++) {
  const k = i % n, vk = v[k], prev = v[(k - 1 + n) % n];
  if (i) t += ds / ((vk + prev) / 2);
  if (i % 2) continue; // ~7 m spacing is plenty for the demo
  const acc = (vk - prev) / (ds / Math.max(1, vk));
  const thr = acc > 0.3 ? 100 : acc > -0.5 ? 45 : 0, brk = acc < -2 ? Math.min(100, Math.round(-acc / BRK * 100)) : 0;
  const kmh = vk * 3.6, gear = GEARS.findIndex((g) => kmh < g) || 6;
  const lo = GEARS[gear - 1] || 0, hi = GEARS[gear] > 300 ? 300 : GEARS[gear];
  const rpm = Math.round(4800 + 3600 * Math.min(1, (kmh - lo) / Math.max(1, hi - lo)));
  const [gx, gz] = toGame(line[k]);
  const steer = +(sign[k] * Math.min(0.6, 2.7 / R[k] * 12)).toFixed(3);
  pts.push([+t.toFixed(3), +gx.toFixed(2), +gz.toFixed(2), 0, +kmh.toFixed(1), thr, brk, gear, rpm, steer]);
}
const time = Math.round(t * 1000);
const doc = { id: `demo-${id}`, demo: true, track: id, car: 3437, lap: 1, t0: Date.UTC(2026, 9, 18, 12), time, timeSource: 'model', n: pts.length,
  cols: ['t', 'x', 'z', 'y', 'kmh', 'thr', 'brk', 'gear', 'rpm', 'steer'], pts };
fs.writeFileSync(path.join(HERE, '..', 'data', 'demo-lap.json'), JSON.stringify(doc));
console.log(`demo lap ${id}: ${(time / 1000).toFixed(2)} s, ${pts.length} samples, vmin ${Math.min(...v.map((x) => x * 3.6)).toFixed(0)} km/h`);
