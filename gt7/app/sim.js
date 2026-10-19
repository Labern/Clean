// Input simulator core: a small point-mass lap model that turns a racing line
// into the inputs a fast driver would make (steering angle, brake %, throttle %,
// gear), plus speed, G and tyre loads. Nothing here is hand-animated: speeds come
// from a friction-ellipse forward/backward pass, inputs from the resulting
// acceleration, steering from the line's curvature. Scenarios (one per Academy
// lesson) live in SCENARIOS and differ only in road, line and driver.
const G = 9.81;
export const CAR = { P: 300, cd: 0.00055, mu: 1.35, brakeG: 1.45, tracG: 0.85, L: 2.65, ratio: 13, ku: 0.035, h: 0.45, tw: 1.6, vmax: 85 };
const DS = 0.5; // metres between samples along the centreline

// ── road ───────────────────────────────────────────────────────────────────
// A road is straights and corners; corners ease in and out (linear curvature
// ramps, like real circuits) so the steering trace is continuous.
export class Road {
  constructor(w = 12) { this.w = w; this.segs = []; this.corners = []; this.len = 0; }
  straight(L) { this.segs.push([L, 0, 0]); this.len += L; return this; }
  corner(deg, R, dir, tr) {
    const th = deg * Math.PI / 180, k = (dir === 'L' ? 1 : -1) / R;
    tr = tr ?? Math.min(18, 0.35 * th * R);
    const arc = th * R - tr;
    const c = { dir: dir === 'L' ? 1 : -1, deg, R, s0: this.len, sA: this.len + tr, mid: this.len + tr + arc / 2, sB: this.len + tr + arc, s1: this.len + 2 * tr + arc };
    this.segs.push([tr, 0, k], [arc, k, k], [tr, k, 0]);
    this.len = c.s1; this.corners.push(c); return this;
  }
  build() {
    const N = Math.round(this.len / DS) + 1;
    const x = new Float64Array(N), y = new Float64Array(N), h = new Float64Array(N), k = new Float64Array(N);
    let si = 0, segStart = 0;
    h[0] = Math.PI / 2;
    for (let i = 0; i < N; i++) {
      const s = i * DS;
      while (si < this.segs.length - 1 && s > segStart + this.segs[si][0]) { segStart += this.segs[si][0]; si++; }
      const [L, k0, k1] = this.segs[si];
      k[i] = L ? k0 + (k1 - k0) * Math.min(1, (s - segStart) / L) : 0;
      if (i) { h[i] = h[i - 1] + k[i] * DS; x[i] = x[i - 1] + Math.cos(h[i]) * DS; y[i] = y[i - 1] + Math.sin(h[i]) * DS; }
    }
    return { N, x, y, h, k, w: this.w, corners: this.corners };
  }
}

// Racing line as lateral offset keys [[station, n]] (n > 0 = left of centre),
// eased with cosines so the line is smooth. Helpers build the usual shape.
export const half = (road, m = 1.2) => road.w / 2 - m;
export function lineKeys(road, c, { ti, ap, to, apN = 1, outN = 1 }) {
  const H = half(road);
  return [[ti, -c.dir * H * outN, 'Turn-in'], [ap, c.dir * H * apN, 'Apex'], [to, -c.dir * H * outN, 'Track-out']];
}
// The manual's corner: steering winds on linearly from 0 at turn-in to peak lock,
// then unwinds linearly to 0 at track-out. r = where peak lock falls along the
// corner (low = late apex: tight early, long straightening exit; 0.5 = even;
// high = early apex: you run out of road and must tighten). The solver finds the
// turn-in point and length S so the line clips the inside kerb and leaves on the
// outside edge. Returns the line itself (points, exact curvature, station).
export function cornerLine(road, c, r = 0.5, { apN = 1, outN = 1 } = {}) {
  const { N, x, y, h, w } = road, H = w / 2 - 1.2, dir = c.dir, th = c.deg * Math.PI / 180;
  const OUT = -dir * H * outN;
  const lateral = (px, py, from) => {
    let best = from, bd = 1e18;
    for (let j = Math.max(0, from - 6); j < Math.min(N, from + 40); j++) { const d = (px - x[j]) ** 2 + (py - y[j]) ** 2; if (d < bd) { bd = d; best = j; } }
    return [best, (px - x[best]) * -Math.sin(h[best]) + (py - y[best]) * Math.cos(h[best])];
  };
  const run = (ti, S, keep) => {
    const i0 = Math.max(0, Math.min(N - 2, Math.round(ti / DS)));
    const A = r * S, B = S - A, kp = dir * th / (S / 2), step = keep ? DS : 1;
    let px = x[i0] - OUT * Math.sin(h[i0]), py = y[i0] + OUT * Math.cos(h[i0]), hh = h[i0], j = i0, maxIn = -1e9, apJ = i0, apS = 0;
    const P = keep ? [] : null;
    for (let s = 0; s < S; s += step) {
      const k = s < A ? kp * s / A : kp * (S - s) / B;
      hh += k * step; px += Math.cos(hh) * step; py += Math.sin(hh) * step;
      const q = lateral(px, py, j); j = q[0];
      if (dir * q[1] > maxIn) { maxIn = dir * q[1]; apJ = j; }
      if (keep) P.push([px, py, k, j]);
    }
    return { err: [-dir * lateral(px, py, j)[1] - H * outN, maxIn - H * apN], apJ, endJ: j, P, px, py, hh, i0 };
  };
  const cost = (ti, S) => { const e = run(ti, S).err; return e[0] * e[0] + Math.max(e[1], -3 * e[1]) ** 2; };
  let best = { c: Infinity };
  for (let ti = Math.max(1, c.s0 - 90); ti <= c.mid; ti += 3)
    for (let S = 12; S <= 5 * c.R * th + 60; S += 6) { const v = cost(ti, S); if (v < best.c) best = { c: v, ti, S }; }
  for (let st = 2; st > 0.05; st /= 2) {        // pattern search refine
    let moved = true;
    while (moved) {
      moved = false;
      for (const [dt, dS] of [[st, 0], [-st, 0], [0, st], [0, -st], [st, st], [-st, -st], [st, -st], [-st, st]]) {
        const v = cost(best.ti + dt, Math.max(4, best.S + dS)); if (v < best.c - 1e-9) { best = { c: v, ti: best.ti + dt, S: Math.max(4, best.S + dS) }; moved = true; }
      }
    }
  }
  const fin = run(best.ti, best.S, true);
  const px = [], py = [], K = [], st = [];
  for (let i = 0; i <= fin.i0; i++) { px.push(x[i] - OUT * Math.sin(h[i])); py.push(y[i] + OUT * Math.cos(h[i])); K.push(0); st.push(i * DS); }
  for (const [a, b, k, j] of fin.P) { px.push(a); py.push(b); K.push(k); st.push(j * DS); }
  let qx = fin.px, qy = fin.py, j = fin.endJ;
  while (j < N - 2) { qx += Math.cos(fin.hh) * DS; qy += Math.sin(fin.hh) * DS; const q = lateral(qx, qy, j); if (q[0] < j) break; j = q[0]; px.push(qx); py.push(qy); K.push(0); st.push(j * DS); if (px.length > 4 * N) break; }
  return { px, py, K, st, marks: [[best.ti, 'Turn-in'], [fin.apJ * DS, 'Apex'], [fin.endJ * DS, 'Track-out']], S: best.S, r, err: run(best.ti, best.S).err };
}

function offsets(N, keys) {
  const n = new Float64Array(N);
  const ks = keys.slice().sort((a, b) => a[0] - b[0]);
  for (let i = 0; i < N; i++) {
    const s = i * DS;
    if (s <= ks[0][0]) { n[i] = ks[0][1]; continue; }
    if (s >= ks[ks.length - 1][0]) { n[i] = ks[ks.length - 1][1]; continue; }
    let j = 0; while (ks[j + 1][0] < s) j++;
    const [s0, n0] = ks[j], [s1, n1] = ks[j + 1];
    const u = (s - s0) / (s1 - s0);
    n[i] = n0 + (n1 - n0) * (1 - Math.cos(Math.PI * u)) / 2;
  }
  return n;
}

// ── car model ──────────────────────────────────────────────────────────────
const drag = (car, v) => car.cd * v * v;
const engine = (car, v) => Math.min(car.tracG * G, car.P / Math.max(v, 4));

// Smooth a Float64Array with a small gaussian (in samples).
function smooth(a, sigma) {
  const r = Math.ceil(sigma * 3), w = [];
  for (let k = -r; k <= r; k++) w.push(Math.exp(-(k * k) / (2 * sigma * sigma)));
  const out = new Float64Array(a.length);
  for (let i = 0; i < a.length; i++) {
    let s = 0, ws = 0;
    for (let k = -r; k <= r; k++) { const j = i + k; if (j < 0 || j >= a.length) continue; s += a[j] * w[k + r]; ws += w[k + r]; }
    out[i] = s / ws;
  }
  return out;
}

// Turn a road + line + driver into a full sample set.
export function simulate(roadDef, keys, opt = {}) {
  const road = roadDef.build ? roadDef.build() : roadDef;
  const car = { ...CAR, ...(opt.car || {}) };
  const d = { brake: 1, trail: true, brakeRise: 14, brakeFall: 3, thrRise: 4, thrFall: 12, mu: 1, ...(opt.driver || {}) };
  const marks = keys.marks || keys.filter((k) => k[2]).map((k) => [k[0], k[2]]);
  let px, py, K, st, N;
  if (keys.px) {            // a designed line: exact curvature, no differentiation noise
    px = Float64Array.from(keys.px); py = Float64Array.from(keys.py); K = Float64Array.from(keys.K); st = Float64Array.from(keys.st); N = px.length;
  } else {                  // offset keys: build the path, differentiate for curvature
    const { x: cx, y: cy, h: ch } = road; N = road.N;
    const n = offsets(N, keys);
    px = new Float64Array(N); py = new Float64Array(N); st = new Float64Array(N);
    for (let i = 0; i < N; i++) { px[i] = cx[i] - n[i] * Math.sin(ch[i]); py[i] = cy[i] + n[i] * Math.cos(ch[i]); st[i] = i * DS; }
  }
  const hp = new Float64Array(N), dsp = new Float64Array(N);
  for (let i = 0; i < N - 1; i++) { hp[i] = Math.atan2(py[i + 1] - py[i], px[i + 1] - px[i]); dsp[i] = Math.max(1e-3, Math.hypot(px[i + 1] - px[i], py[i + 1] - py[i])); }
  hp[N - 1] = hp[N - 2]; dsp[N - 1] = dsp[N - 2];
  if (!K) {
    K = new Float64Array(N);
    for (let i = 1; i < N - 1; i++) { let dh = hp[i] - hp[i - 1]; while (dh > Math.PI) dh -= 2 * Math.PI; while (dh < -Math.PI) dh += 2 * Math.PI; K[i] = dh / ((dsp[i] + dsp[i - 1]) / 2); }
    K = smooth(K, 3);
  }
  // speed: friction ellipse, forward then backward pass
  const ay = car.mu * d.mu * G, ab = car.brakeG * d.mu * G * d.brake;
  const vlim = new Float64Array(N), v = new Float64Array(N);
  for (let i = 0; i < N; i++) vlim[i] = Math.min(car.vmax, Math.sqrt(ay / Math.max(Math.abs(K[i]), 1e-6)));
  v[0] = Math.min(opt.v0 ?? 50, vlim[0]);
  for (let i = 0; i < N - 1; i++) {
    const lat = Math.min(1, (v[i] * v[i] * Math.abs(K[i])) / ay);
    const a = engine(car, v[i]) * Math.sqrt(Math.max(0, 1 - lat * lat)) - drag(car, v[i]);
    v[i + 1] = Math.min(vlim[i + 1], Math.sqrt(Math.max(0.1, v[i] * v[i] + 2 * a * dsp[i])));
  }
  for (let i = N - 2; i >= 0; i--) {
    const lat = Math.min(1, (v[i + 1] * v[i + 1] * Math.abs(K[i + 1])) / ay);
    const avail = d.trail ? Math.sqrt(Math.max(0, 1 - lat * lat)) : (lat > 0.12 ? 0 : 1);
    const dec = ab * avail + drag(car, v[i + 1]);
    v[i] = Math.min(v[i], Math.sqrt(v[i + 1] * v[i + 1] + 2 * dec * dsp[i]));
  }
  // pure braking-limit curve (what the corners ahead allow), for co-simulation
  const vb = Float64Array.from(vlim);
  for (let i = N - 2; i >= 0; i--) {
    const lat = Math.min(1, (vb[i + 1] * vb[i + 1] * Math.abs(K[i + 1])) / ay);
    const avail = d.trail ? Math.sqrt(Math.max(0, 1 - lat * lat)) : (lat > 0.12 ? 0 : 1);
    vb[i] = Math.min(vb[i], Math.sqrt(vb[i + 1] * vb[i + 1] + 2 * (ab * avail + drag(car, vb[i + 1])) * dsp[i]));
  }
  // time + longitudinal accel
  const t = new Float64Array(N), ax = new Float64Array(N);
  for (let i = 1; i < N; i++) t[i] = t[i - 1] + dsp[i - 1] / Math.max(0.5, (v[i] + v[i - 1]) / 2);
  for (let i = 0; i < N - 1; i++) ax[i] = (v[i + 1] * v[i + 1] - v[i] * v[i]) / (2 * dsp[i]);
  ax[N - 1] = ax[N - 2];
  // raw pedal demand, then a human's rate limits
  const thr = new Float64Array(N), brk = new Float64Array(N);
  for (let i = 0; i < N; i++) {
    const need = ax[i] + drag(car, v[i]);
    if (need >= 0) thr[i] = Math.min(1, need / engine(car, v[i]) + (v[i] >= car.vmax - 0.3 ? 1 : 0));
    else brk[i] = Math.min(1, -need / (car.brakeG * d.mu * G));
  }
  const dt = (i) => Math.max(1e-3, t[Math.min(N - 1, i + 1)] - t[i]);
  const limit = (a, rise, fall) => {
    for (let i = N - 2; i >= 0; i--) a[i] = Math.max(a[i], a[i + 1] - rise * dt(i)); // anticipate: ramp up before it's needed
    for (let i = 1; i < N; i++) a[i] = Math.max(a[i], a[i - 1] - fall * dt(i - 1));  // release can't be instant
  };
  limit(brk, d.brakeRise, d.brakeFall);
  for (let i = 1; i < N; i++) thr[i] = Math.min(thr[i], thr[i - 1] + d.thrRise * dt(i - 1));
  for (let i = N - 2; i >= 0; i--) thr[i] = Math.min(thr[i], thr[i + 1] + d.thrFall * dt(i));
  for (let i = 0; i < N; i++) if (brk[i] > 0.02) thr[i] = 0;
  // steering (hand-wheel degrees, + = right), G, gear
  const steer = new Float64Array(N), latG = new Float64Array(N), lonG = new Float64Array(N), gear = new Uint8Array(N), rpm = new Float64Array(N);
  const GEARS = [0, 70, 110, 150, 190, 230, 275, 400];
  for (let i = 0; i < N; i++) {
    latG[i] = v[i] * v[i] * K[i] / G;
    const delta = Math.atan(car.L * K[i]) + car.ku * latG[i];
    steer[i] = -delta * car.ratio * 180 / Math.PI;
    lonG[i] = (thr[i] * engine(car, v[i]) - brk[i] * car.brakeG * d.mu * G - drag(car, v[i])) / G;
    const kmh = v[i] * 3.6;
    let g = 1; while (g < 6 && kmh > GEARS[g]) g++;
    gear[i] = g; rpm[i] = 0.55 + 0.45 * Math.min(1, (kmh - GEARS[g - 1]) / (GEARS[g] - GEARS[g - 1]));
  }
  const out = { N, ds: DS, road, marks, st, vb, x: px, y: py, h: hp, k: K, v, t, ax, thr, brk, steer, latG, lonG, gear, rpm, car, driver: d };
  if (opt.post) opt.post(out);
  loads(out);
  return out;
}

// Tyre loads through a sprung body: pitch and roll follow the inputs through a
// second-order lag, so abrupt pedals make the car rock and smooth ones don't.
function loads(o) {
  const { N, t, car } = o;
  const wn = 2 * Math.PI * 1.4, z = o.driver.damping ?? 0.45;
  const pitch = new Float64Array(N), roll = new Float64Array(N);
  let p = 0, pv = 0, r = 0, rv = 0;
  for (let i = 1; i < N; i++) {
    let dt = t[i] - t[i - 1]; const sub = Math.max(1, Math.ceil(dt / 0.01)); dt /= sub;
    for (let k = 0; k < sub; k++) {
      pv += (wn * wn * (o.lonG[i] - p) - 2 * z * wn * pv) * dt; p += pv * dt;
      rv += (wn * wn * (o.latG[i] - r) - 2 * z * wn * rv) * dt; r += rv * dt;
    }
    pitch[i] = p; roll[i] = r;
  }
  o.fl = new Float64Array(N); o.fr = new Float64Array(N); o.rl = new Float64Array(N); o.rr = new Float64Array(N);
  for (let i = 0; i < N; i++) {
    const front = 0.5 - pitch[i] * car.h / car.L, right = 0.5 + roll[i] * car.h / car.tw;
    o.fl[i] = front * (1 - right); o.fr[i] = front * right; o.rl[i] = (1 - front) * (1 - right); o.rr[i] = (1 - front) * right;
  }
  o.pitch = pitch; o.roll = roll;
}

// Index at time T (fractional, for smooth playback).
export function atTime(o, T) {
  const { t, N } = o;
  if (T <= 0) return 0;
  if (T >= t[N - 1]) return N - 1;
  let lo = 0, hi = N - 1;
  while (hi - lo > 1) { const m = (lo + hi) >> 1; if (t[m] <= T) lo = m; else hi = m; }
  return lo + (T - t[lo]) / Math.max(1e-6, t[hi] - t[lo]);
}
export const lerp = (a, f) => { const i = Math.floor(f), u = f - i; return i + 1 < a.length ? a[i] * (1 - u) + a[i + 1] * u : a[i]; };
export const stationOf = (s) => Math.round(s / DS);
