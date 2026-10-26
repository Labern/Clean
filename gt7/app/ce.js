// Sector Trainer: the logic (no DOM, so the tests drive it directly).
// Every run GT7 streams (a sector attempt, or the demo replay) is matched to a
// Circuit Experience section by where it starts on track. One run per section
// is the demo. Each attempt is compared with it at the same place on track.
// Saved in the synced save as s.ce[track][n] = { gold, silver, bronze, demo,
// start, gates, offset, runs: [{ id, ms, gap, complete }], best }.
import * as store from './state.js';
import { CE } from '../data/ce.js';
import { compare, series } from './compare.js';

export const sec = (tid, n) => store.get().ce?.[tid]?.[n] || null;
export const active = () => store.get().ceActive || null;
const put = (tid, n, fn) => store.set((s) => { s.ce = s.ce || {}; s.ce[tid] = s.ce[tid] || {}; s.ce[tid][n] = s.ce[tid][n] || { runs: [] }; fn(s.ce[tid][n], s); });

export const setActive = (tid, n) => store.set((s) => { s.ceActive = tid ? { track: tid, n: +n } : null; });
export function setMedals(tid, n, m) { put(tid, n, (x) => { for (const k of ['gold', 'silver', 'bronze']) if (k in m) x[k] = m[k]; }); }

// Timing gates on the demo, metres along it. The start is where GT7 places the
// car; the finish trims the coast after the line (throttle off, slowing, to the end).
export function autoGates(demo) {
  const d = series(demo);
  let k = d.n - 1;
  while (k > 1 && d.thr[k] < 5 && d.v[k - 1] >= d.v[k] - 0.5) k--;
  return [0, Math.round(d.d[Math.min(d.n - 1, k + 1)])];
}
export function setDemo(tid, n, run) {
  put(tid, n, (x) => { x.demo = run.id; x.start = run.start; x.gates = autoGates(run); x.demoCar = run.car; });
  return sec(tid, n);
}
export const setGates = (tid, n, gates) => put(tid, n, (x) => { x.gates = gates.map(Math.round); });
// GT7 said this attempt took `ms`: the difference to our measurement calibrates the section
export function calibrate(tid, n, runId, ms) {
  const r = sec(tid, n)?.runs.find((x) => x.id === runId);
  if (r?.raw) put(tid, n, (x) => { x.offset = ms - r.raw; x.runs.forEach((y) => { y.ms = Math.round(y.raw + x.offset); }); x.best = bestOf(x); });
}

const near = (a, b, tol) => a && b && Math.hypot(a[0] - b[0], a[1] - b[1]) < tol;
// Which section a run belongs to: one whose demo starts where it started (the
// one you're training first), else the active section if it has no demo yet.
export function match(run) {
  const s = store.get(), act = s.ceActive, cands = [];
  for (const [tid, secs] of Object.entries(s.ce || {})) for (const [n, x] of Object.entries(secs)) if (x.start && near(x.start, run.start, 45)) cands.push({ track: tid, n: +n });
  cands.sort((a, b) => (b.track === act?.track && b.n === act?.n) - (a.track === act?.track && a.n === act?.n));
  if (cands.length) return { ...cands[0], role: 'attempt' };
  if (act && !sec(act.track, act.n)?.demo) return { ...act, role: 'first' };
  return null;
}

const medalOf = (x, ms) => (ms == null ? null : x.gold && ms <= x.gold ? 'gold' : x.silver && ms <= x.silver ? 'silver' : x.bronze && ms <= x.bronze ? 'bronze' : x.gold ? 'none' : null);
const bestOf = (x) => { const ok = x.runs.filter((r) => r.complete && r.id !== x.demo); if (!ok.length) return null; const b = ok.reduce((a, r) => (r.ms < a.ms ? r : a)); return { id: b.id, ms: b.ms, medal: medalOf(x, b.ms) }; };
export const medal = (x, ms) => medalOf(x || {}, ms);

// File one run under a section and analyse it against the demo. `getRun(id)`
// loads a stored run (IndexedDB in the app, a map in the tests).
export async function file(run, getRun, where = match(run)) {
  if (!where) return null;
  const { track: tid, n } = where;
  if (where.role === 'first') setDemo(tid, n, run);   // provisional: "that was the demo" moves it
  const x = sec(tid, n), demo = x.demo === run.id ? run : await getRun(x.demo);
  if (!demo) return null;
  let cmp = null, entry = { id: run.id, t0: run.t0, complete: true, raw: null, ms: null, gap: 0 };
  // the demo's time between the gates; an attempt's is the demo's plus the gap at the finish gate
  const dd = series(demo), tAt = (s) => { let i = dd.d.findIndex((v) => v >= s); if (i < 1) i = i < 0 ? dd.n - 1 : 1; const f = (s - dd.d[i - 1]) / ((dd.d[i] - dd.d[i - 1]) || 1); return dd.t[i - 1] + (dd.t[i] - dd.t[i - 1]) * Math.max(0, Math.min(1, f)); };
  const demoRaw = Math.round((tAt(x.gates[1]) - tAt(x.gates[0])) * 1000);
  if (demo.id !== run.id) {
    cmp = compare(run, demo, { from: x.gates[0], to: x.gates[1] });
    entry = { id: run.id, t0: run.t0, complete: cmp.complete, raw: Math.round(demoRaw + cmp.total * 1000), gap: +cmp.total.toFixed(3),
      top: cmp.ranked[0] && cmp.ranked[0].lost > 0.03 ? { n: cmp.ranked[0].n, lost: +cmp.ranked[0].lost.toFixed(3), tip: cmp.ranked[0].tips[0] || null } : null,
      minis: cmp.minis.map((m) => +m.lost.toFixed(3)) };
    entry.ms = Math.round(entry.raw + (x.offset || 0));
  } else {
    entry.raw = demoRaw; entry.ms = Math.round(entry.raw + (x.offset || 0)); entry.demo = true;
  }
  put(tid, n, (y) => { y.runs = [entry, ...y.runs.filter((r) => r.id !== run.id)].slice(0, 80); y.best = bestOf(y); });
  return { track: tid, n, role: demo.id === run.id ? 'demo' : 'attempt', entry, cmp, demo, sec: sec(tid, n) };
}

// Make a filed run the demo instead: every attempt is re-measured against it.
export async function useAsDemo(tid, n, run, getRun) {
  setDemo(tid, n, run);
  const ids = sec(tid, n).runs.map((r) => r.id);
  put(tid, n, (y) => { y.runs = []; y.best = null; });
  for (const id of ids.reverse()) { const r = id === run.id ? run : await getRun(id); if (r) await file(r, getRun, { track: tid, n, role: 'attempt' }); }
}

// Your theoretical best: the best of each mini-sector (corner to corner) across
// every complete attempt, added to the demo's time. Plus where you're least consistent.
export function ideal(x) {
  const runs = (x?.runs || []).filter((r) => r.complete && r.minis && !r.demo);
  const demo = x?.runs.find((r) => r.demo);
  if (runs.length < 2 || !demo) return null;
  const k = Math.min(...runs.map((r) => r.minis.length));
  const best = Array.from({ length: k }, (_, i) => Math.min(...runs.map((r) => r.minis[i])));
  const spread = Array.from({ length: k }, (_, i) => { const v = runs.map((r) => r.minis[i]), m = v.reduce((a, b) => a + b) / v.length; return Math.sqrt(v.reduce((a, b) => a + (b - m) ** 2, 0) / v.length); });
  const worst = spread.indexOf(Math.max(...spread));
  return { ms: Math.round(demo.ms + best.reduce((a, b) => a + b, 0) * 1000), best, spread, wobbly: worst + 1 };
}

// Where the credits are: per track, medals so far, and the next section to work on
// (no medal targets typed yet first, else the one furthest from gold).
export function summary(tid) {
  const info = CE[tid], out = [];
  for (let n = 1; n <= info.sections; n++) {
    const x = sec(tid, n);
    out.push({ n, x, medal: x?.best?.medal || null, toGold: x?.gold && x?.best ? x.best.ms - x.gold : null });
  }
  const golds = out.filter((o) => o.medal === 'gold').length;
  const next = out.find((o) => !o.x?.demo) || out.filter((o) => o.medal !== 'gold').sort((a, b) => (b.toGold ?? 1e9) - (a.toGold ?? 1e9))[0] || null;
  return { sections: out, golds, next, prize: info.prize, allGold: golds === info.sections };
}
export const fmt = (ms) => { if (ms == null) return '—'; const s = Math.abs(ms) / 1000, m = Math.floor(s / 60); return (ms < 0 ? '−' : '') + (m ? `${m}:${(s - m * 60).toFixed(3).padStart(6, '0')}` : s.toFixed(3)); };
export const fmtGap = (s) => (s == null ? '—' : (s > 0 ? '+' : s < 0 ? '−' : '±') + Math.abs(s).toFixed(3));
// "1:02.345" / "62.345" → ms
export const parseMs = (t) => { const m = String(t).trim().match(/^(?:(\d+):)?(\d+(?:\.\d+)?)$/); return m ? Math.round(((+(m[1] || 0)) * 60 + +m[2]) * 1000) : null; };
