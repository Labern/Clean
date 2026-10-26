// Data-logger comparison: your run against a reference (the GT7 demo, or your
// best). Everything is measured at the same place on track: each of your
// samples is projected onto the reference line, giving a common distance axis,
// a running time gap, and corner-by-corner differences (braking point, apex
// speed, line, throttle pickup) ranked by the time they cost.
const col = (r, name) => r.cols.indexOf(name);

export function series(r) {
  const c = (n) => col(r, n), P = r.pts;
  const out = { t: [], x: [], z: [], v: [], thr: [], brk: [], gear: [], steer: [], d: [] };
  let d = 0;
  for (let i = 0; i < P.length; i++) {
    const p = P[i];
    if (i) d += Math.hypot(p[c('x')] - P[i - 1][c('x')], p[c('z')] - P[i - 1][c('z')]);
    out.t.push(p[c('t')]); out.x.push(p[c('x')]); out.z.push(p[c('z')]); out.v.push(p[c('kmh')]);
    out.thr.push(p[c('thr')]); out.brk.push(p[c('brk')]); out.gear.push(p[c('gear')]); out.steer.push(c('steer') >= 0 ? p[c('steer')] : 0); out.d.push(d);
  }
  out.n = P.length; out.dist = d;
  return out;
}

// station of each of your samples along the reference line (monotonic), and the lateral gap
function project(you, ref) {
  const st = [], lat = [];
  let j = 0;
  for (let i = 0; i < you.n; i++) {
    let best = j, bd = Infinity;
    for (let k = Math.max(0, j - 5); k < Math.min(ref.n - 1, j + 60); k++) {
      const ax = ref.x[k], az = ref.z[k], bx = ref.x[k + 1], bz = ref.z[k + 1];
      const vx = bx - ax, vz = bz - az, L2 = vx * vx + vz * vz || 1e-9;
      const u = Math.max(0, Math.min(1, ((you.x[i] - ax) * vx + (you.z[i] - az) * vz) / L2));
      const px = ax + u * vx, pz = az + u * vz, dd = (you.x[i] - px) ** 2 + (you.z[i] - pz) ** 2;
      if (dd < bd) { bd = dd; best = k + u; }
    }
    j = Math.floor(best);
    const k = Math.min(ref.n - 2, j), u = best - k;
    st.push(ref.d[k] + u * (ref.d[k + 1] - ref.d[k]));
    // signed lateral offset: + = left of the reference direction
    const vx = ref.x[k + 1] - ref.x[k], vz = ref.z[k + 1] - ref.z[k], L = Math.hypot(vx, vz) || 1;
    lat.push(((you.x[i] - ref.x[k]) * -vz + (you.z[i] - ref.z[k]) * vx) / L * -1);
  }
  for (let i = 1; i < st.length; i++) if (st[i] < st[i - 1]) st[i] = st[i - 1];   // never backwards
  return { st, lat };
}

// value of arr at station s, sampled by station array S (monotonic)
function at(S, arr, s) {
  let lo = 0, hi = S.length - 1;
  if (s <= S[0]) return arr[0];
  if (s >= S[hi]) return arr[hi];
  while (hi - lo > 1) { const m = (lo + hi) >> 1; if (S[m] <= s) lo = m; else hi = m; }
  const u = (s - S[lo]) / Math.max(1e-9, S[hi] - S[lo]);
  return arr[lo] + (arr[hi] - arr[lo]) * u;
}

// corners from the reference: speed minima with a real dip, and the braking / throttle around them
function corners(ref) {
  const out = [], v = ref.v, n = ref.n;
  for (let i = 3; i < n - 3; i++) {
    if (!(v[i] <= v[i - 1] && v[i] <= v[i + 1])) continue;
    let pre = v[i], post = v[i];
    for (let k = i; k >= 0 && ref.d[i] - ref.d[k] < 400; k--) pre = Math.max(pre, v[k]);
    for (let k = i; k < n && ref.d[k] - ref.d[i] < 400; k++) post = Math.max(post, v[k]);
    if (Math.min(pre, post) - v[i] < 10) continue;
    if (out.length && ref.d[i] - out.at(-1).apexD < 60) { if (v[i] < out.at(-1).min) out.pop(); else continue; }
    let b = i; for (let k = i; k >= 0 && ref.d[i] - ref.d[k] < 450; k--) { if (ref.brk[k] > 15) b = k; else if (b !== i && ref.brk[k] < 3) break; }
    let th = i; for (let k = i; k < n && ref.d[k] - ref.d[i] < 400; k++) { if (ref.thr[k] > 80) { th = k; break; } }
    out.push({ i, apexD: ref.d[i], min: v[i], brakeD: b !== i ? ref.d[b] : null, thrD: ref.d[th], peakBrk: Math.max(...ref.brk.slice(b, i + 1)) });
  }
  return out;
}

// opts.from / opts.to: the timing gates, metres along the reference (default: all of it)
export function compare(youRun, refRun, opts = {}) {
  const ref = series(refRun), you = series(youRun), { st, lat } = project(you, ref);
  const from = Math.max(0, opts.from ?? 0), to = Math.min(ref.dist, opts.to ?? ref.dist);
  // your time at each station, zeroed at the start gate; same for the reference
  const t0y = at(st, you.t, from), t0r = at(ref.d, ref.t, from);
  const step = 2, S = [], gap = [], vy = [], vr = [], thy = [], thr = [], bky = [], bkr = [], sty = [], str = [], gy = [], lo = [];
  for (let s = from; s <= to + 1e-6; s += step) {
    S.push(s);
    gap.push((at(st, you.t, s) - t0y) - (at(ref.d, ref.t, s) - t0r));
    vy.push(at(st, you.v, s)); vr.push(at(ref.d, ref.v, s));
    thy.push(at(st, you.thr, s)); thr.push(at(ref.d, ref.thr, s));
    bky.push(at(st, you.brk, s)); bkr.push(at(ref.d, ref.brk, s));
    sty.push(at(st, you.steer, s)); str.push(at(ref.d, ref.steer, s));
    gy.push(Math.round(at(st, you.gear, s))); lo.push(at(st, lat, s));
  }
  const gapAt = (s) => at(S, gap, s);
  const idxS = (d) => Math.max(0, Math.min(S.length - 1, Math.round((d - from) / step)));
  // where your own braking / throttle happen near each reference corner
  // your braking onset for a corner: walk back from your apex through continuous braking
  // (measured the same way on both, on the common 2 m grid, so sampling can't bias it)
  const brakeOnset = (arr, apexD) => {
    // the braking block that ends near this apex: no braking within 150 m before it = a lift or flat
    // (a brief release inside the zone, under 30 m, is still the same stop)
    let k = idxS(apexD + 20), seen = null;
    for (let g = 0; k >= 0 && g < 500 / step; k--, g++) {
      if (arr[k] > 15) seen = S[k];
      else if (seen != null && arr[k] < 3 && seen - S[k] > 30) break;
      else if (seen == null && S[k] < apexD - 150) break;
    }
    return seen;
  };
  const fullThr = (arr, fromD, toD) => { for (let k = idxS(fromD); k < S.length && S[k] <= toD; k++) if (arr[k] > 80) return S[k]; return null; };
  const raw = corners(ref).filter((c) => c.apexD > from + 20 && c.apexD < to - 20);
  const cs = raw.map((c, idx, arr) => {
    // the corner's zone: braking to exit, but never past halfway to the neighbouring corners
    const prevMid = idx ? (arr[idx - 1].apexD + c.apexD) / 2 : from, nextMid = idx < arr.length - 1 ? (arr[idx + 1].apexD + c.apexD) / 2 : to;
    const zoneA = Math.max(prevMid, (c.brakeD ?? c.apexD) - 80), zoneB = Math.min(nextMid, c.thrD + 120);
    const bi = c.brakeD != null ? ref.d.findIndex((x) => x >= c.brakeD) : -1, spacing = bi > 0 ? ref.d[bi] - ref.d[bi - 1] : 4;
    const lost = gapAt(zoneB) - gapAt(zoneA);
    // slowest point near the apex, found the same way on both
    let ymin = Infinity, ymD = c.apexD, rmin = Infinity;
    for (let k = 0; k < S.length; k++) if (S[k] > c.apexD - 30 && S[k] < c.apexD + 30) { if (vy[k] < ymin) { ymin = vy[k]; ymD = S[k]; } rmin = Math.min(rmin, vr[k]); }
    const yb = brakeOnset(bky, c.apexD), rb = brakeOnset(bkr, c.apexD);
    const yt = fullThr(thy, c.apexD - 40, Math.min(to, c.apexD + 300)), rt = fullThr(thr, c.apexD - 40, Math.min(to, c.apexD + 300));
    return { n: idx + 1, apexD: Math.round(c.apexD), lost, min: Math.round(rmin), yourMin: Math.round(ymin),
      brake: rb != null && yb != null ? Math.round(yb - rb) : null, brakeAt: rb,                 // + = you braked later
      throttle: yt != null && rt != null ? Math.round(yt - rt) : null,                                    // + = you got on it later
      line: Math.round(at(S, lo, c.apexD) * 10) / 10, refGear: Math.round(at(ref.d, ref.gear, c.apexD)), yourGear: Math.round(at(S, gy, ymD)),
      res: Math.max(6, Math.round(spacing * 1.2)), zone: [Math.round(zoneA), Math.round(zoneB)] };
  });
  const tips = (c) => {
    const t = [];
    if (c.brake != null && c.brake < -c.res) t.push(`you brake ${-c.brake} m earlier than the demo`);
    if (c.brake != null && c.brake > c.res) t.push(`you brake ${c.brake} m later than the demo (overshooting?)`);
    if (c.yourMin < c.min - 3) t.push(`${c.min - c.yourMin} km/h slower at the apex (${c.yourMin} vs ${c.min})`);
    if (c.yourMin > c.min + 4) t.push(`${c.yourMin - c.min} km/h faster at the apex, which may cost the exit`);
    if (c.throttle != null && c.throttle > 10) t.push(`full throttle ${c.throttle} m later`);
    if (Math.abs(c.line) > 1.5) t.push(`${Math.abs(c.line)} m ${c.line > 0 ? 'left' : 'right'} of the demo's line at the apex`);
    if (c.yourGear && c.refGear && c.yourGear !== c.refGear) t.push(`gear ${c.yourGear} where the demo uses ${c.refGear}`);
    return t;
  };
  cs.forEach((c) => { c.tips = tips(c); });
  const total = gap.at(-1);
  // mini-sectors: the stretch cut halfway between corners. Best of each across
  // attempts adds up to your theoretical best run.
  const cuts = [from, ...raw.slice(1).map((c, i) => (raw[i].apexD + c.apexD) / 2), to];
  const minis = cuts.slice(1).map((b, i) => ({ a: Math.round(cuts[i]), b: Math.round(b), corner: i + 1, lost: gapAt(b) - gapAt(cuts[i]) }));
  const yourTime = at(st, you.t, to) - t0y, refTime = at(ref.d, ref.t, to) - t0r;
  const complete = st.at(-1) >= to - 15 && st[0] <= from + 15;
  return { from, to, yourTime, refTime, complete, minis, S, gap, vy, vr, thy, thr, bky, bkr, sty, str, gy, lat: lo, corners: cs, ranked: cs.slice().sort((a, b) => b.lost - a.lost), total, you, ref, st };
}

// Does a run cover the same stretch as a reference (same start and finish, within a few car lengths)?
export const sameStretch = (a, b, tol = 40) => Math.hypot(a.start[0] - b.start[0], a.start[1] - b.start[1]) < tol && Math.hypot(a.end[0] - b.end[0], a.end[1] - b.end[1]) < tol * 1.5;
