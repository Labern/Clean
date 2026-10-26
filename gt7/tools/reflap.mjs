#!/usr/bin/env node
// Reference lap for every circuit: a Gr.3-class car with aero grip driven over
// the real geometry (OSM for real tracks, traced course maps for GT originals).
// The racing line is approximated by smoothing curvature (a fast line uses the
// track width to straighten corners); speed comes from a friction-ellipse
// forward/backward pass round the closed lap. Calibrated against the Gr.3
// benchmark times. Writes data/reflaps.js: per-track speed/gear/pedal traces
// (500 points, indexed by lap fraction like the corner `at`s) + per-corner stats.
//
//   node gt7/tools/reflap.mjs [--fit]
import fs from 'fs';
import path from 'path';
import { fileURLToPath, pathToFileURL } from 'url';
import { TRACKS } from '../data/tracks.js';
import { MAPS_GT } from '../data/maps-gt.js';

const HERE = path.dirname(fileURLToPath(import.meta.url));
const GEO = JSON.parse(fs.readFileSync(path.join(HERE, 'geo.json'), 'utf8'));
const G = 9.81, DS = 2;
export const CAR = { P: 330, cd: 0.00064, mu: 1.55, bmu: 1.65, ca: 0.0001, trac: 0.95, vmax: 82, smooth: 10, width: 14 };
const GEARS = [0, 62, 105, 145, 185, 228, 400];  // the gear you'd hold through that speed band

function xyOf(t) {
  const g = GEO[t.map];
  if (g) {
    const c = Math.cos(g.pts[0][0] * Math.PI / 180);
    return g.pts.map(([la, lo]) => [lo * c * 111320, la * 110540]);
  }
  const m = MAPS_GT[t.map];
  return m.pts.map(([x, y]) => [x * m.mPerUnit, -y * m.mPerUnit]);
}

// resample a closed polyline at DS metres; remember the lap fraction of each sample
function resample(P) {
  const n = P.length, seg = [], cum = [0];
  for (let i = 0; i < n; i++) { const a = P[i], b = P[(i + 1) % n]; seg.push(Math.hypot(b[0] - a[0], b[1] - a[1])); cum.push(cum[i] + seg[i]); }
  const L = cum[n], N = Math.round(L / DS / 40) * 40, out = [], frac = [];  // multiple of the coarsest racing-line node step
  let j = 0;
  for (let k = 0; k < N; k++) {
    const s = k * L / N; while (cum[j + 1] < s) j++;
    const u = (s - cum[j]) / Math.max(seg[j], 1e-9), a = P[j], b = P[(j + 1) % n];
    out.push([a[0] + (b[0] - a[0]) * u, a[1] + (b[1] - a[1]) * u]); frac.push((j + u) / n);
  }
  return { pts: out, frac, L };
}

const gauss = (a, sigma) => {
  const n = a.length, r = Math.ceil(sigma * 3), w = []; for (let k = -r; k <= r; k++) w.push(Math.exp(-(k * k) / (2 * sigma * sigma)));
  const ws = w.reduce((x, y) => x + y, 0);
  return a.map((_, i) => { let s = 0; for (let k = -r; k <= r; k++) s += a[(i + k + n) % n] * w[k + r]; return s / ws; });
};

export function lap(t, car = CAR) {
  const { pts, frac, L } = resample(xyOf(t));
  const N = pts.length;
  // smooth the geometry a little (OSM nodes), then curvature, then the racing-line smoothing
  const cs = car.csmooth ?? 3, cx = gauss(pts.map((p) => p[0]), cs), cy = gauss(pts.map((p) => p[1]), cs);
  // minimum-curvature racing line inside the track edges (offset n along the centreline
  // normal, |n| <= half width minus a car). Solved coarse to fine (80 → 40 → 20 → 10 m
  // nodes) because a curvature-smoothing iteration only spreads change slowly.
  const half = (car.width ?? 11) / 2 - 1.2;
  const nodeSet = (step) => { const M = Math.floor(N / step), bx = [], by = [], nx = [], ny = []; for (let j = 0; j < M; j++) { const i = j * step, i2 = (i + 1) % N, hh = Math.atan2(cy[i2] - cy[i], cx[i2] - cx[i]); bx.push(cx[i]); by.push(cy[i]); nx.push(-Math.sin(hh)); ny.push(Math.cos(hh)); } return { M, bx, by, nx, ny, step }; };
  const solve = (ns, n0, iters) => {
    const { M, bx, by, nx, ny } = ns, n = n0;
    const X = (q) => bx[q] + nx[q] * n[q], Y = (q) => by[q] + ny[q] * n[q];
    for (let it = 0; it < iters; it++) for (let j = 0; j < M; j++) {
      const a2 = (j - 2 + M) % M, a = (j - 1 + M) % M, b = (j + 1) % M, b2 = (j + 2) % M;
      const px = (-X(a2) + 4 * X(a) + 4 * X(b) - X(b2)) / 6, py = (-Y(a2) + 4 * Y(a) + 4 * Y(b) - Y(b2)) / 6;
      const d = (px - bx[j]) * nx[j] + (py - by[j]) * ny[j];
      n[j] = Math.max(-half, Math.min(half, n[j] + 0.5 * (d - n[j])));
    }
    return n;
  };
  let ns = nodeSet(40), n = solve(ns, new Float64Array(ns.M), 3000);
  for (const step of [20, 10, 5, 2, 1]) {
    const nn = nodeSet(step), up = new Float64Array(nn.M), ratio = ns.step / step;
    for (let j = 0; j < nn.M; j++) { const f = j / ratio, j0 = Math.floor(f) % ns.M, j1 = (j0 + 1) % ns.M, u = f - Math.floor(f); up[j] = n[j0] * (1 - u) + n[j1] * u; }
    ns = nn; n = solve(ns, up, step >= 5 ? 2500 : 1500);
  }
  const { M: M0, nx, ny } = ns, step = 1;
  // back to 2 m samples
  const lx = [], ly = [];
  for (let i = 0; i < N; i++) { const j = Math.floor(i / step) % M0, j2 = (j + 1) % M0, u = (i % step) / step; const nn = n[j] * (1 - u) + n[j2] * u; const nxx = nx[j] * (1 - u) + nx[j2] * u, nyy = ny[j] * (1 - u) + ny[j2] * u; lx.push(cx[i] + nxx * nn); ly.push(cy[i] + nyy * nn); }
  const h = lx.map((x, i) => Math.atan2(ly[(i + 1) % N] - ly[i], lx[(i + 1) % N] - x));
  let k = h.map((v, i) => { const ds = Math.hypot(lx[i] - lx[(i - 1 + N) % N], ly[i] - ly[(i - 1 + N) % N]) || DS; let d = v - h[(i - 1 + N) % N]; while (d > Math.PI) d -= 2 * Math.PI; while (d < -Math.PI) d += 2 * Math.PI; return d / ds; });
  k = gauss(k, car.smooth / DS);
  const latMax = (v) => (car.mu + car.ca * v * v) * G;
  const vlim = k.map((kk) => { const a = Math.abs(kk); if (a < car.ca * G + 1e-6) return car.vmax; return Math.min(car.vmax, Math.sqrt(car.mu * G / (a - car.ca * G))); });
  // three laps so the closed-loop passes settle, keep the middle one
  const M = 3 * N, K = (i) => k[i % N], VL = (i) => vlim[i % N];
  const v = new Float64Array(M); v[0] = 30;
  for (let i = 0; i < M - 1; i++) {
    const lat = Math.min(1, v[i] * v[i] * Math.abs(K(i)) / latMax(v[i]));
    const a = Math.min(car.trac * G, car.P / Math.max(v[i], 4)) * Math.sqrt(1 - lat * lat) - car.cd * v[i] * v[i];
    v[i + 1] = Math.min(VL(i + 1), Math.sqrt(Math.max(1, v[i] * v[i] + 2 * a * DS)));
  }
  for (let i = M - 2; i >= 0; i--) {
    const vn = v[i + 1], lat = Math.min(1, vn * vn * Math.abs(K(i + 1)) / latMax(vn));
    const dec = (car.bmu + car.ca * vn * vn) * G * Math.sqrt(1 - lat * lat) + car.cd * vn * vn;
    v[i] = Math.min(v[i], Math.sqrt(vn * vn + 2 * dec * DS));
  }
  const V = Array.from(v.slice(N, 2 * N));
  let T = 0; const tt = [0];
  for (let i = 0; i < N; i++) { T += DS / ((V[i] + V[(i + 1) % N]) / 2); tt.push(T); }
  const thr = [], brk = [];
  for (let i = 0; i < N; i++) {
    const a = (V[(i + 1) % N] ** 2 - V[i] ** 2) / (2 * DS), need = a + car.cd * V[i] * V[i];
    thr.push(need >= 0 ? Math.min(1, need / Math.min(car.trac * G, car.P / Math.max(V[i], 4)) + (V[i] > car.vmax - 0.5 ? 1 : 0)) : 0);
    brk.push(need < 0 ? Math.min(1, -need / ((car.bmu + car.ca * V[i] * V[i]) * G)) : 0);
  }
  return { N, L, V, k, frac, T, tt, thr, brk, lx, ly, cx, cy, nMax: Math.max(...n.map(Math.abs)), nMean: n.reduce((a, b) => a + Math.abs(b), 0) / M0 };
}

const gearOf = (kmh) => { let g = 1; while (g < 6 && kmh > GEARS[g]) g++; return g; };
const secs = (s) => { const m = String(s).replace(/^~/, '').match(/^(?:(\d+):)?(\d+(?:\.\d+)?)$/); return m ? (+(m[1] || 0)) * 60 + +m[2] : NaN; };

function build(car) {
  const out = {};
  for (const t of TRACKS) {
    if (!t.map) continue;
    const r = lap(t, car);
    // 500-point traces by lap fraction
    const S = 500, idxAt = (f) => { let best = 0, bd = 9; for (let i = 0; i < r.N; i++) { let d = Math.abs(r.frac[i] - f); d = Math.min(d, 1 - d); if (d < bd) { bd = d; best = i; } } return best; };
    const order = r.frac.map((f, i) => [f, i]).sort((a, b) => a[0] - b[0]);
    const at = (f) => { let lo = 0, hi = order.length - 1; while (hi - lo > 1) { const m = (lo + hi) >> 1; if (order[m][0] <= f) lo = m; else hi = m; } return order[lo][1]; };
    const tr = { v: [], g: [], thr: [], brk: [] };
    for (let s = 0; s < S; s++) { const i = at(s / S); const kmh = r.V[i] * 3.6; tr.v.push(Math.round(kmh)); tr.g.push(gearOf(kmh)); tr.thr.push(Math.round(r.thr[i] * 100)); tr.brk.push(Math.round(r.brk[i] * 100)); }
    // per corner: minimum speed near the marked position, gear there, entry speed, braking distance
    const corners = t.corners.map((c) => {
      // the corner's own tightest point near its marker, then the slowest point just around it
      const i0 = at(c.at), win = Math.round(30 / DS), near = Math.round(15 / DS);
      let ik = i0; for (let d = -win; d <= win; d++) { const j = (i0 + d + r.N) % r.N; if (Math.abs(r.k[j]) > Math.abs(r.k[ik])) ik = j; }
      let im = ik; for (let d = -near; d <= near; d++) { const j = (ik + d + r.N) % r.N; if (r.V[j] < r.V[im]) im = j; }
      let ib = im; for (let d = 1; d < 600 / DS; d++) { const j = (im - d + r.N) % r.N; if (r.brk[j] > 0.25) ib = j; else if (ib !== im && r.brk[j] < 0.05 && r.thr[j] > 0.5) break; }
      let ie = ib; for (let d = 1; d < 80 / DS; d++) { const j = (ib - d + r.N) % r.N; if (r.V[j] > r.V[ie]) ie = j; }
      const brakeM = ib === im ? 0 : Math.round(((im - ib + r.N) % r.N) * DS);
      const minK = Math.round(r.V[im] * 3.6);
      return { min: minK, gear: gearOf(minK), entry: Math.max(minK, Math.round(r.V[ie] * 3.6)), brake: brakeM, apexAt: +r.frac[im].toFixed(4), brakeAt: +r.frac[ib].toFixed(4) };
    });
    out[t.id] = { lap: +r.T.toFixed(2), top: Math.max(...tr.v), ...tr, corners, bench: secs(t.laps?.['Gr.3']?.[1]) };
  }
  return out;
}

const main = process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href;
const fit = process.argv.includes('--fit');
let car = { ...CAR };
if (main && fit) {
  // one global grip scale so the sim lands near the 'Fast' Gr.3 benchmarks on real tracks
  // fit base grip + downforce: lap times vs the Gr.3 benchmarks, and corner minimum speeds
  // vs the guides' own figures (both are estimates, so weigh them together)
  const spd = (x) => +String(x).replace(/[^0-9]/g, '') || null;
  for (const ca of [0.0001, 0.00013, 0.00016]) for (const mu of [1.5, 1.6, 1.7]) {
    const c = { ...CAR, width: 14, ca, mu, bmu: mu + 0.1 };
    const b = build(c); const e = [], ce = [];
    for (const [id, x] of Object.entries(b)) {
      const t = TRACKS.find((q) => q.id === id); if (!GEO[t.map]) continue;
      if (x.bench) e.push((x.lap - x.bench) / x.bench);
      t.corners.forEach((cc, i) => { const g = spd(cc.speed); if (g && g < 300 && !/flat/i.test(cc.speed)) ce.push((x.corners[i].min - g) / g); });
    }
    const rms = (a) => Math.sqrt(a.reduce((s2, v) => s2 + v * v, 0) / a.length), mean = (a) => a.reduce((s2, v) => s2 + v, 0) / a.length;
    console.log(`ca ${ca} mu ${mu}: lap bias ${(mean(e) * 100).toFixed(1)}% rms ${(rms(e) * 100).toFixed(1)}% | corner bias ${(mean(ce) * 100).toFixed(1)}% rms ${(rms(ce) * 100).toFixed(1)}%`);
  }
} else if (main) {
  const b = build(car);
  for (const [id, x] of Object.entries(b)) console.log(id.padEnd(14), `sim ${Math.floor(x.lap / 60)}:${(x.lap % 60).toFixed(1).padStart(4, '0')}`, x.bench ? `bench ${Math.floor(x.bench / 60)}:${(x.bench % 60).toFixed(1).padStart(4, '0')} (${((x.lap / x.bench - 1) * 100).toFixed(1)}%)` : '', `top ${x.top}`);
  fs.writeFileSync(path.join(HERE, '..', 'data', 'reflaps.js'),
    '// Generated by tools/reflap.mjs: a simulated Gr.3-class reference lap on each circuit\'s real\n' +
    '// geometry (no elevation). Traces are 500 points by lap fraction; corners follow the guide order.\n' +
    'export const REFLAPS = ' + JSON.stringify(b) + ';\n');
  console.log('wrote data/reflaps.js');
}
