// A sample Circuit Experience session built from the demo Spa lap: one demo run
// and a handful of attempts, each with a real, specific mistake. Lets you try
// the Sector Trainer before connecting the PS5, and gives the tests real data.
const MISTAKES = [
  { label: 'brakes 30 m early and is slow through the corner', dip: 0, early: 30, slow: 9 },
  { label: 'runs 2 m wide and gets on the power late', dip: 1, wide: 2.2, slow: 6, late: 60 },
  { label: 'carries too much speed in and overshoots', dip: 3, early: -26, slow: -7, exitSlow: 14 },
  { label: 'close: a touch slow at the last corner', dip: 4, slow: 4 },
];
export function sampleSession(lap, t0 = Date.now()) {
  const c = Object.fromEntries(lap.cols.map((k, i) => [k, i]));
  const seg = lap.pts.slice(Math.round(lap.pts.length * 0.02), Math.round(lap.pts.length * 0.34));
  const dist = [0];
  for (let i = 1; i < seg.length; i++) dist.push(dist[i - 1] + Math.hypot(seg[i][c.x] - seg[i - 1][c.x], seg[i][c.z] - seg[i - 1][c.z]));
  const v = seg.map((p) => p[c.kmh]), dips = [];
  for (let i = 5; i < v.length - 5; i++) if (v[i] < v[i - 1] && v[i] <= v[i + 1] && Math.max(...v.slice(Math.max(0, i - 60), i)) - v[i] > 20 && (!dips.length || dist[i] - dist[dips.at(-1)] > 80)) dips.push(i);
  const build = (m, k, id) => {
    const pts = seg.map((p) => p.slice());
    if (m) {
      const a = dips[Math.min(m.dip, dips.length - 1)];
      let bs = a; for (let i = a; i > 0; i--) { if (seg[i][c.brk] > 15) bs = i; else if (dist[bs] - dist[i] > 30) break; }   // the start of this corner's braking
      for (let i = 0; i < seg.length; i++) {
        const dd = dist[i] - dist[bs], w = Math.max(0, 1 - Math.abs(dist[i] - dist[a]) / 120);
        if (m.early > 0 && dd > -m.early && dd < 0) { pts[i][c.brk] = 55; pts[i][c.thr] = 0; }
        if (m.early < 0 && dd >= 0 && dd < -m.early) { pts[i][c.brk] = 0; pts[i][c.thr] = 0; }
        pts[i][c.kmh] = seg[i][c.kmh] - (m.slow || 0) * w - (m.exitSlow || 0) * (dist[i] > dist[a] ? Math.max(0, 1 - (dist[i] - dist[a]) / 260) : 0);
        if (m.late && dist[i] > dist[a] - 40 && dist[i] - dist[a] < m.late && pts[i][c.thr] > 30) pts[i][c.thr] = 30;
        if (m.wide) {
          const j0 = Math.max(i - 1, 0), j1 = Math.min(i + 1, seg.length - 1), hx = seg[j1][c.x] - seg[j0][c.x], hz = seg[j1][c.z] - seg[j0][c.z], L = Math.hypot(hx, hz) || 1;
          pts[i][c.x] += (-hz / L) * m.wide * w; pts[i][c.z] += (hx / L) * m.wide * w;
        }
      }
    }
    // a little noise, like a real driver; then re-time the run from its own speeds
    for (const p of pts) { p[c.kmh] = +(p[c.kmh] + (m ? Math.sin(k * 31 + p[c.x]) * 0.6 : 0)).toFixed(1); }
    // the coast after the finish line, before GT7 resets the car
    const last = pts.at(-1), hx = last[c.x] - pts.at(-2)[c.x], hz = last[c.z] - pts.at(-2)[c.z], L = Math.hypot(hx, hz) || 1;
    for (let j = 1; j <= 25; j++) { const p = last.slice(); p[c.kmh] = Math.max(30, last[c.kmh] - j * 5); p[c.thr] = 0; p[c.brk] = 20; p[c.x] = last[c.x] + (hx / L) * j * 8; p[c.z] = last[c.z] + (hz / L) * j * 8; pts.push(p); }
    pts[0][c.t] = 0; let d = 0; const out = [];
    for (let i = 0; i < pts.length; i++) {
      if (i) { const ds = Math.hypot(pts[i][c.x] - pts[i - 1][c.x], pts[i][c.z] - pts[i - 1][c.z]); d += ds; pts[i][c.t] = +(pts[i - 1][c.t] + ds / (Math.max(5, (pts[i][c.kmh] + pts[i - 1][c.kmh]) / 2) / 3.6)).toFixed(3); }
      out.push([pts[i][c.t], pts[i][c.x], pts[i][c.z], pts[i][c.y], pts[i][c.kmh], pts[i][c.thr], pts[i][c.brk], pts[i][c.gear], pts[i][c.rpm], pts[i][c.steer], +d.toFixed(1)]);
    }
    return { id, kind: 'run', sample: true, car: lap.car, t0: t0 + k * 60e3, time: Math.round(out.at(-1)[0] * 1000), dist: Math.round(d), n: out.length,
      cols: ['t', 'x', 'z', 'y', 'kmh', 'thr', 'brk', 'gear', 'rpm', 'steer', 'd'], pts: out, start: [out[0][1], out[0][2]], end: [out.at(-1)[1], out.at(-1)[2]], note: m ? m.label : 'demo' };
  };
  return { demo: build(null, 0, 'sample-demo'), attempts: MISTAKES.map((m, i) => build(m, i + 1, 'sample-try-' + (i + 1))) };
}
