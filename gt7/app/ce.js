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
      minis: cmp.minis.map((m) => +m.lost.toFixed(3)),
      // compact per-corner record: what the notes and the corner history read
      cs: cmp.corners.map((c) => ({ n: c.n, a: c.apexD, lost: +c.lost.toFixed(3), mini: +(cmp.minis[c.n - 1]?.lost ?? c.lost).toFixed(3), brake: c.brake, min: c.min, you: c.yourMin, line: c.line, thr: c.throttle, g: c.yourGear, rg: c.refGear, res: c.res, tips: c.tips })) };
    entry.ms = Math.round(entry.raw + (x.offset || 0));
  } else {
    // the demo's own corners: the reference card for every corner's notes
    const self = compare(demo, demo, { from: x.gates[0], to: x.gates[1] });
    put(tid, n, (y) => { y.corners = self.corners.map((c) => ({ n: c.n, a: c.apexD, brakeAt: c.brakeAt, min: c.min, gear: c.refGear, zone: c.zone })); });
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
  await file(run, getRun, { track: tid, n, role: 'attempt' });   // the demo first: it defines the corners
  for (const id of ids.reverse().filter((i) => i !== run.id)) { const r = id === run.id ? run : await getRun(id); if (r) await file(r, getRun, { track: tid, n, role: 'attempt' }); }
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

// ── corner notes ────────────────────────────────────────
// Notes hang off a corner by where its apex is on the demo (metres), so they
// survive a new demo or new gates renumbering the corners. A note can be
// "trying": the attempts driven after it was written are compared with the ones
// before, at that corner only, and the note gets a verdict.
export const corners = (x) => x?.corners || [];
export const cornerOf = (x, apexD) => { let b = null, bd = 70; for (const c of corners(x)) { const d = Math.abs(c.a - apexD); if (d < bd) { bd = d; b = c; } } return b; };
export const notesFor = (x, cn) => { const c = corners(x).find((y) => y.n === cn); return c ? (x.notes || []).filter((no) => cornerOf(x, no.a)?.n === cn).sort((a, b) => b.t - a.t) : []; };
export function addNote(tid, n, cn, text, status = 'trying') {
  const c = corners(sec(tid, n)).find((y) => y.n === cn); if (!c || !text.trim()) return null;
  const no = { id: 'n' + Date.now().toString(36) + Math.random().toString(36).slice(2, 5), a: c.a, text: text.trim(), status, t: Date.now() };
  put(tid, n, (x) => { x.notes = [...(x.notes || []), no]; });
  return no;
}
export const editNote = (tid, n, id, patch) => put(tid, n, (x) => { const no = (x.notes || []).find((y) => y.id === id); if (no) Object.assign(no, patch, patch.status && patch.status !== no.status ? { decided: Date.now() } : {}); });
export const delNote = (tid, n, id) => put(tid, n, (x) => { x.notes = (x.notes || []).filter((y) => y.id !== id); });

// every complete attempt's record at one corner, oldest first
export function history(x, cn) {
  const c = corners(x).find((y) => y.n === cn); if (!c) return [];
  return (x.runs || []).filter((r) => r.complete && !r.demo && r.cs).map((r) => {
    const k = r.cs.reduce((b, y) => (Math.abs(y.a - c.a) < Math.abs((b?.a ?? 1e9) - c.a) ? y : b), null);
    return k && Math.abs(k.a - c.a) < 70 ? { id: r.id, t0: r.t0, ...k } : null;
  }).filter(Boolean).sort((a, b) => a.t0 - b.t0);
}
const mean = (v) => v.reduce((a, b) => a + b, 0) / v.length;
const sd = (v) => { const m = mean(v); return Math.sqrt(mean(v.map((x) => (x - m) ** 2))); };
// did trying this note help at its corner? (time against the demo, per attempt)
export function verdict(x, note) {
  const c = cornerOf(x, note.a); if (!c) return null;
  const h = history(x, c.n), before = h.filter((r) => r.t0 < note.t).slice(-6), after = h.filter((r) => r.t0 >= note.t && (!note.decided || r.t0 <= note.decided));
  if (!after.length) return { state: 'untested', after: 0, text: 'Not driven since you wrote it' };
  if (!before.length) return { state: 'nobase', after: after.length, text: `${after.length} attempt${after.length > 1 ? 's' : ''} since, nothing before to compare` };
  const b = mean(before.map((r) => r.mini)), a = mean(after.map((r) => r.mini)), d = a - b;
  const state = after.length < 2 ? 'early' : d < -0.02 ? 'better' : d > 0.02 ? 'worse' : 'same';
  const words = { early: 'One attempt so far', better: 'Working', worse: 'Costing time', same: 'No real change' }[state];
  return { state, before: b, after: a, delta: d, n: after.length, text: `${words}: ${d <= 0 ? '−' : '+'}${Math.abs(d).toFixed(3)} s at this corner (${after.length} since vs ${before.length} before)` };
}

// What the data says about you at this corner, across attempts: ready-made notes.
export function suggest(x, cn) {
  const c = corners(x).find((y) => y.n === cn), h = history(x, cn).slice(-8), out = [];
  if (!c) return out;
  if (c.brakeAt != null) out.push({ kind: 'demo', text: `Demo: brakes ${Math.round(c.a - c.brakeAt)} m before the apex, ${c.min} km/h at the apex, gear ${c.gear}.` });
  else out.push({ kind: 'demo', text: `Demo: no braking here, ${c.min} km/h at the slowest point, gear ${c.gear}.` });
  if (!h.length) return out;
  const br = h.filter((r) => r.brake != null).map((r) => r.brake), res = Math.max(...h.map((r) => r.res || 6));
  if (br.length >= 2 && mean(br) < -res) out.push({ kind: 'brake', text: `You brake ${Math.round(-mean(br))} m earlier than the demo here (${br.length} attempts). Move your marker later.` });
  if (br.length >= 2 && mean(br) > res) out.push({ kind: 'brake', text: `You brake ${Math.round(mean(br))} m later than the demo here. Brake earlier, carry more speed out.` });
  const ap = h.map((r) => r.you - r.min);
  if (ap.length >= 2 && mean(ap) < -3) out.push({ kind: 'apex', text: `${Math.round(-mean(ap))} km/h slower than the demo at the apex on average. Release the brake earlier and let it roll in.` });
  if (ap.length >= 2 && mean(ap) > 4) out.push({ kind: 'apex', text: `${Math.round(mean(ap))} km/h faster at the apex than the demo: overdriving the entry costs your exit.` });
  const ln = h.map((r) => r.line);
  if (ln.length >= 2 && Math.abs(mean(ln)) > 1.2) out.push({ kind: 'line', text: `Your apex is ${Math.abs(mean(ln)).toFixed(1)} m ${mean(ln) > 0 ? 'left' : 'right'} of the demo's on average. Aim for the demo's apex.` });
  const th = h.filter((r) => r.thr != null).map((r) => r.thr);
  if (th.length >= 2 && mean(th) > 10) out.push({ kind: 'throttle', text: `Full throttle ${Math.round(mean(th))} m later than the demo on exit.` });
  const gw = h.filter((r) => r.g && r.rg && r.g !== r.rg);
  if (gw.length >= Math.max(2, h.length / 2)) out.push({ kind: 'gear', text: `You're in gear ${gw.at(-1).g} at the apex, the demo uses ${gw.at(-1).rg}.` });
  if (br.length >= 3 && sd(br) > 2 * res) out.push({ kind: 'consistency', text: `Your braking point moves around by ±${Math.round(sd(br))} m here. Pick one marker and hit it every time.` });
  const mn = h.map((r) => r.mini);
  if (mn.length >= 3 && sd(mn) > 0.06) out.push({ kind: 'consistency', text: `This corner swings ±${sd(mn).toFixed(2)} s between attempts: consistency here is free time.` });
  return out;
}
// per-corner summary for the chip strip: last and average time against the demo, notes count
export function cornerStrip(x) {
  return corners(x).map((c) => {
    const h = history(x, c.n), last = h.at(-1), avg = h.length ? mean(h.slice(-5).map((r) => r.mini)) : null;
    const ns = notesFor(x, c.n);
    return { ...c, last: last?.mini ?? null, avg, notes: ns.length, trying: ns.filter((no) => no.status === 'trying').length };
  });
}
