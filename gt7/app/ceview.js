// Sector Trainer views: #/ce (every Circuit Experience), #/ce/<track> (its
// sections, medal targets, the live result after each attempt) and
// #/cerun/<track>.<n>.<runId> (your run against the demo, data-logger style).
import { $, $$, html, raw, esc, toast, cr } from './util.js';
import * as store from './state.js';
import * as L from './laps.js';
import * as CE from './ce.js';
import { CE as INFO, sectionName } from '../data/ce.js';
import { compare } from './compare.js';
import { trackById } from '../data/tracks.js';
import * as direct from './direct.js';
import { probe, bridgeBase } from './telemetry.js';
import { sampleSession } from './cesample.js';
import { openCornerSheet, cornerChips, wireChips } from './cornersheet.js';

const MEDAL = { gold: ['#ffc531', 'Gold'], silver: ['#c9d1e0', 'Silver'], bronze: ['#d08a4c', 'Bronze'], none: ['#5d6b8f', 'No medal'] };
const medalChip = (m) => (m ? `<span class="medal ${m}">${MEDAL[m][1]}</span>` : '');
const S = store.get;

// ── the feed: every run the PS5 streams gets filed and analysed, wherever you are in the app ──
let wired = false, es = null;
export function wireFeed() {
  if (wired) return; wired = true;
  window.addEventListener('gt7-run-saved', async (e) => {
    const run = e.detail;
    const res = await CE.file(run, L.getLap).catch(() => null);
    if (!res) return;
    window.dispatchEvent(new CustomEvent('gt7-run-filed', { detail: res }));
    if (res.role === 'attempt' && !res.entry.complete) return;
    const x = res.sec, nm = `${trackById[res.track].short} ${sectionName(res.track, res.n)}`;
    if (res.role === 'demo') { toast(`${nm}: demo recorded`); speak('Demo recorded.'); return; }
    const md = CE.medal(x, res.entry.ms), tip = res.entry.top;
    const mine = tip && CE.notesFor(x, tip.n).find((no) => no.status === 'trying');
    toast(`${nm}: ${CE.fmt(res.entry.ms)} · ${CE.fmtGap(res.entry.gap)} to the demo`);
    speak(`${md && md !== 'none' ? md + '. ' : ''}${spokenGap(res.entry.gap)} to the demo.${tip ? ` Corner ${tip.n}: ${tip.tip || 'lost ' + tip.lost.toFixed(2)}.` : ''}${mine ? ` Your note: ${mine.text}` : ''}`);
  });
}
const spokenGap = (g) => (Math.abs(g) < 0.0005 ? 'Dead level' : `${g > 0 ? 'Plus' : 'Minus'} ${Math.abs(g).toFixed(2)}`);
function speak(text) {
  if (S().ceVoice === false || !('speechSynthesis' in window)) return;
  try { speechSynthesis.cancel(); const u = new SpeechSynthesisUtterance(text.replace(/km\/h/g, 'kilometres an hour').replace(/(\d) m\b/g, '$1 metres')); u.rate = 1.08; speechSynthesis.speak(u); } catch { /* no voice */ }
}
// on a browser, runs come from the bridge's event stream
async function bridgeFeed() {
  if (direct.available()) { if (direct.status().status === 'off' && S().ps5Ip) direct.startTelemetry(S().ps5Ip).catch(() => {}); return direct.status().status !== 'off' ? 'direct' : 'off'; }
  if (es && es.readyState !== 2) return 'bridge';
  if (!(await probe())) return 'off';
  es = new EventSource(bridgeBase() + '/api/live');
  es.addEventListener('run', async (e) => {
    const m = JSON.parse(e.data), r = await fetch(bridgeBase() + '/api/runs/' + encodeURIComponent(m.id));
    if (!r.ok) return;
    const run = await r.json(); await L.putLap(run);
    window.dispatchEvent(new CustomEvent('gt7-run-saved', { detail: run }));
  });
  return 'bridge';
}
async function loadSample() {
  const lap = await (await fetch('data/demo-lap.json')).json();
  const { demo, attempts } = sampleSession(lap);
  const cur = CE.sec('spa', 2);
  if (cur?.runs?.length && !cur.sample && !confirm('This replaces your Spa Sector 2 data with the sample. Carry on?')) return false;
  for (const r of [demo, ...attempts]) await L.putLap(r);
  store.set((s) => { if (s.ce?.spa?.[2]) delete s.ce.spa[2]; });
  CE.setActive('spa', 2);
  await CE.file(demo, L.getLap);
  const dm = CE.sec('spa', 2).runs[0].ms;
  CE.setMedals('spa', 2, { gold: dm + 60, silver: dm + 400, bronze: dm + 900 });   // made-up targets for the sample
  for (const r of attempts) await CE.file(r, L.getLap);
  store.set((s) => { s.ce.spa[2].sample = true; });
  return true;
}
const rerender = () => window.dispatchEvent(new HashChangeEvent('hashchange'));

// ── #/ce ────────────────────────────────────────────────
export function ceIndex() {
  const act = CE.active();
  const rows = Object.keys(INFO).filter((t) => trackById[t]).map((tid) => ({ tid, t: trackById[tid], i: INFO[tid], sum: CE.summary(tid) }));
  const totalGold = rows.reduce((a, r) => a + (r.sum.allGold ? r.i.prize.gold : 0), 0), totalAll = rows.reduce((a, r) => a + r.i.prize.gold, 0);
  return {
    html: html`
    <div class="kicker">Sector Trainer</div><h1>Gold on every sector</h1>
    <p class="muted" style="max-width:74ch;margin-top:10px">Circuit Experience, beaten corner by corner. Watch the demo in GT7 and the app records it. Then every attempt you drive is laid over it at the same place on track: where you braked, how fast you went through the apex, your line, when you got back on the power, and how much time each corner cost you. You'll hear the result as you hit retry.</p>
    ${act ? html`<a class="card pad now-card" href="#/ce/${act.track}" style="display:block;margin-top:18px"><div class="kicker" style="color:#ff8a90">Training now</div><h2 style="margin-top:6px;color:#fff">${trackById[act.track]?.short} · ${sectionName(act.track, act.n)}</h2><div style="color:#9fb3e6;margin-top:6px">Open the live result →</div></a>` : ''}
    <div class="row" style="margin-top:16px"><span class="chip gold">All-gold prizes earned: ${cr(totalGold)} of ${cr(totalAll)}</span><button class="btn sm ghost" id="ce-sample">Try it with a sample session</button></div>
    <section class="section grid g3">
      ${rows.map((r) => html`<a class="card pad gloss ce-tile" href="#/ce/${r.tid}">
        <div class="row" style="justify-content:space-between"><span class="kicker">${r.t.flag} ${r.i.sections} sections</span><span class="muted small">${raw(r.sum.sections.map((s) => `<i class="pip ${s.medal || ''}"></i>`).join(''))}</span></div>
        <h3 style="margin:8px 0 4px">${r.t.short}${r.i.layout ? ' · ' + r.i.layout : ''}</h3>
        <div class="muted small">${r.i.car}</div>
        <div class="small" style="margin-top:8px"><b>${cr(r.i.prize.gold)}</b> <span class="muted">all gold · ${r.sum.golds}/${r.i.sections} done</span></div></a>`)}
    </section>`,
    wire(root) {
      $('#ce-sample', root).onclick = async (e) => { e.target.disabled = true; e.target.textContent = 'Building…'; if (await loadSample()) location.hash = '#/ce/spa'; else { e.target.disabled = false; e.target.textContent = 'Try it with a sample session'; } };
    },
  };
}

// ── #/ce/<track> ────────────────────────────────────────
export function ceTrack(tid) {
  const t = trackById[tid], info = INFO[tid];
  if (!t || !info) return html`<h1>No Circuit Experience here</h1><a class="back" href="#/ce">← Sector Trainer</a>`;
  const act = CE.active(), sum = CE.summary(tid), voice = S().ceVoice !== false;
  const secRow = (o) => {
    const x = o.x || { runs: [] }, isAct = act?.track === tid && act?.n === o.n, id = ideal(x);
    const attempts = x.runs.filter((r) => !r.demo), last = attempts[0];
    return html`<div class="card pad ce-sec ${isAct ? 'on' : ''}" data-n="${o.n}">
      <div class="row" style="justify-content:space-between">
        <div><div class="kicker">${sectionName(tid, o.n)}${x.sample ? ' · sample' : ''}</div>
          <h3 style="margin:6px 0 0">${x.best ? CE.fmt(x.best.ms) : 'No time yet'} ${raw(medalChip(x.best?.medal))}</h3>
          <div class="muted small" style="margin-top:4px">${x.demo ? `Demo ${CE.fmt(x.runs.find((r) => r.demo)?.ms)}` : 'No demo yet'} · ${attempts.length} attempt${attempts.length === 1 ? '' : 's'}${o.toGold != null ? ` · ${o.toGold <= 0 ? 'gold by ' + CE.fmt(-o.toGold) : CE.fmt(o.toGold) + ' to gold'}` : ''}${x.offset == null && x.demo ? ' · times uncalibrated' : ''}</div></div>
        ${isAct ? raw('<span class="chip red">● Training</span>') : html`<button class="btn sm" data-train="${o.n}">Train this</button>`}
      </div>
      <div class="medals">${['gold', 'silver', 'bronze'].map((m) => html`<label class="f"><span><i class="pip ${m}"></i> ${MEDAL[m][1]}</span><input type="text" inputmode="decimal" placeholder="0:00.000" data-medal="${m}" data-n="${o.n}" value="${x[m] ? CE.fmt(x[m]) : ''}"></label>`)}</div>
      ${raw(cornerChips(tid, o.n))}
      ${id ? html`<div class="ideal"><b>Theoretical best ${CE.fmt(id.ms)}</b> ${raw(medalChip(CE.medal(x, id.ms)))}<span class="muted small">your best corner-to-corner pieces, stitched together. Least consistent: corner ${id.wobbly}.</span></div>` : ''}
      ${attempts.length ? html`<div class="runs">${attempts.slice(0, 8).map((r) => html`<a class="run" href="#/cerun/${tid}.${o.n}.${encodeURIComponent(r.id)}"><b>${r.complete ? CE.fmt(r.ms) : 'aborted'}</b><span class="${r.gap > 0 ? 'lose' : 'gain'}">${CE.fmtGap(r.gap)}</span>${raw(medalChip(r.complete ? CE.medal(x, r.ms) : null))}<span class="muted small">${r.top ? `C${r.top.n} −${r.top.lost.toFixed(2)}s` : ''}</span></a>`)}</div>` : ''}
      ${last && last.complete ? html`<a class="btn sm red" style="margin-top:10px" href="#/cerun/${tid}.${o.n}.${encodeURIComponent(last.id)}">Open the last attempt vs the demo →</a>` : ''}
    </div>`;
  };
  return {
    html: html`
    <a class="back" href="#/ce">← Sector Trainer</a>
    <div class="kicker">${t.flag} Circuit Experience${info.layout ? ' · ' + info.layout : ''}</div><h1>${t.name}</h1>
    <div class="row" style="margin-top:10px"><span class="chip dark">${info.car}</span><span class="chip gold">All gold ${cr(info.prize.gold)}</span><span class="chip">All bronze ${cr(info.prize.bronze)}</span><span class="chip ${sum.golds === info.sections ? 'ok' : ''}">${sum.golds}/${info.sections} gold</span></div>
    <section class="section grid g2" style="align-items:start;margin-top:22px">
      <div class="card pad live-card" id="ce-live"><div class="kicker" style="color:#ff8a90">Live</div><h3 style="color:#fff;margin-top:6px">Connecting…</h3></div>
      <div class="card pad"><h3>How to use it</h3><ol class="steps">
        <li>Tap <b>Train this</b> on the section you're doing, and type the gold time GT7 shows.</li>
        <li>In GT7, watch the <b>demo</b>. The app records it (telemetry streams during replays too).</li>
        <li>Drive. Each time you hit retry you get your time, the gap to the demo and the one corner that cost you most, out loud.</li>
        <li>Once, type the time GT7 gave you for an attempt: every time after that is calibrated to GT7's clock.</li>
      </ol><label class="row small" style="margin-top:10px"><input type="checkbox" id="ce-voice" ${voice ? 'checked' : ''}> Speak the result after each attempt</label></div>
    </section>
    <section class="section grid" style="gap:14px">${sum.sections.map(secRow)}</section>`,
    async wire(root) {
      $$('[data-train]', root).forEach((b) => (b.onclick = () => { CE.setActive(tid, +b.dataset.train); rerender(); }));
      $$('[data-medal]', root).forEach((i) => (i.onchange = () => { const ms = CE.parseMs(i.value); if (i.value && ms == null) return toast('Type it like 1:02.345'); CE.setMedals(tid, +i.dataset.n, { [i.dataset.medal]: ms }); toast('Saved'); }));
      wireChips(root);
      const refreshChips = () => { if (!root.isConnected) return window.removeEventListener('gt7-notes-changed', refreshChips); $$('.cchips', root).forEach((w) => { const t = document.createElement('div'); t.innerHTML = cornerChips(w.dataset.tid, +w.dataset.n); w.replaceWith(t.firstElementChild); }); wireChips(root); paint(); };
      window.addEventListener('gt7-notes-changed', refreshChips);
      $('#ce-voice', root).onchange = (e) => store.set((s) => { s.ceVoice = e.target.checked; });
      const live = $('#ce-live', root), mode = await bridgeFeed();
      let lastRes = null;
      const paint = () => {
        const a = CE.active();
        if (!a || a.track !== tid) { live.innerHTML = `<div class="kicker" style="color:#ff8a90">Live</div><h3 style="color:#fff;margin-top:6px">Pick a section</h3><p style="color:#9fb3e6">Tap <b>Train this</b> below. Runs you drive are matched to it automatically.</p>`; return; }
        const x = CE.sec(tid, a.n) || { runs: [] }, src = mode === 'direct' ? 'PS5 direct' : mode === 'bridge' ? 'bridge' : null;
        const head = `<div class="row" style="justify-content:space-between"><div class="kicker" style="color:#ff8a90">● ${esc(sectionName(tid, a.n))}</div><div style="color:#9fb3e6;font-weight:600">${src ? 'via ' + src : 'not connected'}</div></div>`;
        if (!lastRes) {
          live.innerHTML = head + (x.demo ? `<h3 style="color:#fff;margin-top:8px">Ready. Drive the section.</h3><p style="color:#9fb3e6">Demo ${CE.fmt(x.runs.find((r) => r.demo)?.ms)}${x.gold ? ' · gold ' + CE.fmt(x.gold) : ' · type the gold time below'}</p>` : `<h3 style="color:#fff;margin-top:8px">Watch the demo in GT7</h3><p style="color:#9fb3e6">The first run recorded becomes the demo. Drove first? Mark the right run as the demo once it's in.</p>`)
            + (src ? '' : `<p style="color:#9fb3e6;margin-top:8px">${direct.available() ? 'Connect to your PS5 on the Data Logger page.' : 'Start the bridge on your Mac, or use the phone app.'} <a href="#/telemetry" style="color:#fff;text-decoration:underline">Data Logger →</a></p>`);
          return;
        }
        const e = lastRes.entry, md = CE.medal(x, e.ms), tip = e.top;
        live.innerHTML = head + (lastRes.role === 'demo' ? `<h2 style="color:#fff;margin-top:8px">Demo recorded</h2><p style="color:#9fb3e6">${CE.fmt(e.ms)} between the gates. Now drive it.</p>` : `
          <div class="row" style="gap:20px;align-items:end;margin-top:8px">
            <div><div class="big">${e.complete ? CE.fmt(e.ms) : 'aborted'}</div><div style="color:#9fb3e6;font-weight:600">${md ? MEDAL[md][1] : 'your time'}${x.offset == null ? ' · measured' : ''}</div></div>
            <div><div class="big" style="color:${e.gap > 0 ? '#ff6b73' : '#36d399'}">${CE.fmtGap(e.gap)}</div><div style="color:#9fb3e6;font-weight:600">to the demo</div></div>
            ${x.gold && e.complete ? `<div><div class="big" style="color:#ffc531">${CE.fmtGap((e.ms - x.gold) / 1000)}</div><div style="color:#9fb3e6;font-weight:600">to gold</div></div>` : ''}
          </div>
          ${tip ? `<div class="fix"><b>Corner ${tip.n}</b> cost ${tip.lost.toFixed(3)} s${tip.tip ? ': ' + esc(tip.tip) : ''}${liveNotes(x, tip.n)}<button class="btn sm light-solid" data-cn="${tip.n}" style="margin-top:10px">Corner ${tip.n} notes</button></div>` : '<div class="fix">No corner cost more than a couple of hundredths. That\'s the demo\'s pace.</div>'}
          ${triedNotes(x, tip?.n)}
          <div class="row" style="margin-top:12px"><a class="btn sm red" href="#/cerun/${tid}.${a.n}.${encodeURIComponent(e.id)}">See it on the logger →</a><button class="btn sm ghost light" id="ce-isdemo">That was the demo</button></div>
          <div class="row" style="margin-top:10px"><label class="f" style="max-width:220px;color:#9fb3e6">GT7 said<input type="text" id="ce-cal" inputmode="decimal" placeholder="0:00.000"></label></div>`);
        $$('[data-cn]', live).forEach((b) => (b.onclick = () => openCornerSheet(tid, a.n, +b.dataset.cn)));
        $('#ce-isdemo', live)?.addEventListener('click', async () => { const run = await L.getLap(e.id); await CE.useAsDemo(tid, a.n, run, L.getLap); toast('Demo set. Attempts re-measured'); rerender(); });
        $('#ce-cal', live)?.addEventListener('change', (ev) => { const ms = CE.parseMs(ev.target.value); if (ms == null) return toast('Type it like 1:02.345'); CE.calibrate(tid, a.n, e.id, ms); toast('Calibrated to GT7\'s clock'); rerender(); });
      };
      paint();
      const onFiled = (ev) => { if (!root.isConnected) return window.removeEventListener('gt7-run-filed', onFiled); if (ev.detail.track !== tid) return; lastRes = ev.detail; paint(); };
      window.addEventListener('gt7-run-filed', onFiled);
      // a section with an existing last attempt: show it
      const a = CE.active(); if (a?.track === tid) { const x = CE.sec(tid, a.n), e = x?.runs[0]; if (e) { lastRes = { role: e.demo ? 'demo' : 'attempt', entry: e }; paint(); } }
    },
  };
}
const ideal = (x) => CE.ideal(x);
// your notes at the corner that cost most, and how the ones you're trying are going
function liveNotes(x, cn) {
  const ns = CE.notesFor(x, cn).filter((no) => no.status !== 'nope').slice(0, 2);
  return ns.length ? `<div class="live-notes">${ns.map((no) => `<div><span class="npill ${no.status === 'trying' ? 'try' : no.status === 'works' ? 'ok' : 'plain'}">${no.status === 'trying' ? 'Trying' : no.status === 'works' ? 'Works' : 'Note'}</span> ${esc(no.text)}</div>`).join('')}</div>` : '';
}
function triedNotes(x, skip) {
  const rows = (x.notes || []).filter((no) => no.status === 'trying').map((no) => ({ no, c: CE.cornerOf(x, no.a), v: CE.verdict(x, no) })).filter((r) => r.c && r.c.n !== skip && r.v && r.v.state !== 'untested');
  return rows.length ? `<div class="tried">${rows.slice(0, 3).map((r) => `<button class="tried-row ${r.v.state}" data-cn="${r.c.n}"><b>C${r.c.n}</b><span>${esc(r.no.text)}</span><i>${esc(r.v.text.split(':')[0])}${r.v.delta != null ? ` ${r.v.delta <= 0 ? '−' : '+'}${Math.abs(r.v.delta).toFixed(2)}s` : ''}</i></button>`).join('')}</div>` : '';
}

// ── #/cerun/<track>.<n>.<runId>: your run against the demo ──
export function ceRun(arg) {
  const [tid, n, ...rest] = String(arg).split('.'), id = rest.join('.');
  return {
    html: html`<a class="back" href="#/ce/${tid}">← ${trackById[tid]?.short || ''} Circuit Experience</a><div id="cmpwrap"><p class="muted">Loading…</p></div>`,
    async wire(root) {
      const x = CE.sec(tid, +n), run = await L.getLap(id), demo = x?.demo && (await L.getLap(x.demo));
      const wrap = $('#cmpwrap', root);
      if (!run || !demo) { wrap.innerHTML = '<h1>Run not found</h1><p class="muted">It may still be on your other device.</p>'; return; }
      const best = x.best && x.best.id !== id ? await L.getLap(x.best.id) : null;
      renderCompare(wrap, { tid, n: +n, x, run, demo, best });
    },
  };
}

function renderCompare(el, { tid, n, x, run, demo, best }) {
  let refRun = demo, refName = 'demo', zoom = null, notesDirty = false;
  // redraw once the notes sheet closes, so new notes show on the cards and pins
  const mo = new MutationObserver(() => { if (!el.isConnected) return mo.disconnect(); if (notesDirty && !document.querySelector('.sheet-wrap')) { notesDirty = false; const y = window.scrollY; draw(); window.scrollTo(0, y); } });
  mo.observe(document.body, { childList: true });
  const draw = () => {
    const cmp = compare(run, refRun, { from: x.gates[0], to: x.gates[1] });
    const entry = x.runs.find((r) => r.id === run.id), md = entry && CE.medal(x, entry.ms);
    const you = cmp.you, ref = cmp.ref, S = cmp.S;
    // turn the stretch so it fills the screen: long side across on a wide screen, down on a phone
    {
      const mx = ref.x.reduce((a, b) => a + b) / ref.n, mz = ref.z.reduce((a, b) => a + b) / ref.n;
      let sxx = 0, szz = 0, sxz = 0; for (let i = 0; i < ref.n; i++) { const dx = ref.x[i] - mx, dz = ref.z[i] - mz; sxx += dx * dx; szz += dz * dz; sxz += dx * dz; }
      const th = 0.5 * Math.atan2(2 * sxz, sxx - szz), wide = window.innerWidth >= 760;
      const a = (wide ? 0 : Math.PI / 2) - th, c = Math.cos(a), si = Math.sin(a);
      // rotation keeps left/right, so line offsets stay true
      for (const r of [you, ref]) for (let i = 0; i < r.n; i++) { const dx = r.x[i] - mx, dz = r.z[i] - mz; r.x[i] = c * dx - si * dz; r.z[i] = si * dx + c * dz; }
    }
    // map frame: both lines, in GT7's own coordinates
    const xs = [...ref.x, ...you.x], zs = [...ref.z, ...you.z];
    let box = [Math.min(...xs), Math.min(...zs), Math.max(...xs), Math.max(...zs)];
    if (zoom) box = zoom;
    const pad = Math.max(box[2] - box[0], box[3] - box[1]) * 0.08, vb = [box[0] - pad, box[1] - pad, box[2] - box[0] + 2 * pad, box[3] - box[1] + 2 * pad], sw = Math.max(vb[2], vb[3]) / 260;
    const refAt = (s, arr) => { let i = ref.d.findIndex((d) => d >= s); if (i < 0) i = ref.n - 1; return arr[i]; };
    const refLine = ref.x.map((v, i) => `${v.toFixed(1)},${ref.z[i].toFixed(1)}`).join(' ');
    // your line coloured by where you gain (green) or lose (red) against the reference
    const segs = []; for (let i = 1; i < you.n; i++) {
      const s0 = cmp.st[i - 1], s1 = cmp.st[i]; if (s1 < cmp.from || s0 > cmp.to) continue;
      const g0 = at(S, cmp.gap, s0), g1 = at(S, cmp.gap, s1), rate = (g1 - g0) / Math.max(1, s1 - s0) * 100;   // s lost per 100 m
      const k = Math.max(-1, Math.min(1, rate / 0.06)), col = k > 0 ? `rgb(255,${Math.round(200 - 150 * k)},${Math.round(90 - 60 * k)})` : `rgb(${Math.round(160 + 95 * k)},${Math.round(220 - 10 * k)},${Math.round(150 + 0 * k)})`;
      segs.push(`<line x1="${you.x[i - 1].toFixed(1)}" y1="${you.z[i - 1].toFixed(1)}" x2="${you.x[i].toFixed(1)}" y2="${you.z[i].toFixed(1)}" stroke="${col}" stroke-width="${sw * 2}" stroke-linecap="round"/>`);
    }
    const tick = (s, col, label) => { const i = Math.max(1, ref.d.findIndex((d) => d >= s)), dx = ref.x[i] - ref.x[i - 1], dz = ref.z[i] - ref.z[i - 1], Lh = Math.hypot(dx, dz) || 1, nx = -dz / Lh * sw * 7, nz = dx / Lh * sw * 7;
      return `<line x1="${ref.x[i] - nx}" y1="${ref.z[i] - nz}" x2="${ref.x[i] + nx}" y2="${ref.z[i] + nz}" stroke="${col}" stroke-width="${sw * 1.1}"/>${label ? `<text x="${ref.x[i] + nx * 1.4}" y="${ref.z[i] + nz * 1.4}" fill="${col}" style="font-size:${sw * 4}px;font-weight:800" text-anchor="middle">${label}</text>` : ''}`; };
    const youPt = (s) => { let i = cmp.st.findIndex((v) => v >= s); if (i < 0) i = you.n - 1; return [you.x[i], you.z[i]]; };
    const marks = cmp.corners.map((c) => `${c.brakeAt != null ? tick(c.brakeAt, 'rgba(255,255,255,.85)') : ''}${c.brake != null ? tick(c.brakeAt + c.brake, '#ff6b73') : ''}
      <g class="cpin" data-c="${c.n}" transform="translate(${refAt(c.apexD, ref.x)},${refAt(c.apexD, ref.z)})"><circle r="${sw * 4.4}" fill="${c.lost > 0.02 ? '#e1131f' : '#0b1f4b'}" stroke="#fff" stroke-width="${sw * 0.8}"/><text text-anchor="middle" dy="${sw * 1.5}" fill="#fff" style="font-size:${sw * 4.2}px;font-weight:800">${c.n}</text>${(() => { const dc = CE.cornerOf(CE.sec(tid, n), c.apexD); const k = dc ? CE.notesFor(CE.sec(tid, n), dc.n).length : 0; return k ? `<circle cx="${sw * 3.6}" cy="${-sw * 3.6}" r="${sw * 2.2}" fill="#ffc531" stroke="#0b1f4b" stroke-width="${sw * 0.5}"/>` : ''; })()}</g>`).join('');
    const gates = `${tick(cmp.from, '#36d399', 'START')}${tick(cmp.to, '#ffc531', 'FINISH')}`;

    // traces against distance
    const W = 1000, H = 120, X = (s) => ((s - cmp.from) / Math.max(1, cmp.to - cmp.from)) * W;
    const poly = (arr, max, min = 0) => arr.map((v, i) => `${X(S[i]).toFixed(1)},${(H - ((v - min) / (max - min)) * (H - 10) - 5).toFixed(1)}`).join(' ');
    const vmax = Math.max(...cmp.vy, ...cmp.vr) + 5, vmin = Math.max(0, Math.min(...cmp.vy, ...cmp.vr) - 10);
    const smax = Math.max(0.05, ...cmp.sty.map(Math.abs), ...cmp.str.map(Math.abs));
    const gmax = Math.max(0.1, ...cmp.gap.map(Math.abs));
    const cornerBands = cmp.corners.map((c) => `<rect x="${X(c.zone[0])}" width="${X(c.zone[1]) - X(c.zone[0])}" y="0" height="${H}" fill="${c.lost > 0.02 ? 'rgba(225,19,31,.13)' : 'rgba(255,255,255,.04)'}"/><text x="${X(c.apexD)}" y="14" fill="#9fb3e6" text-anchor="middle" style="font-size:12px;font-weight:800">${c.n}</text>`).join('');
    const ph = (i) => `<line class="ph" x1="0" x2="0" y1="0" y2="${H}" stroke="#fff" stroke-width="2"/>`;
    const trace = (title, body, h = H) => `<div class="tr"><div class="kicker" style="color:#9fb3e6">${title}</div><svg class="trace" viewBox="0 0 ${W} ${h}" preserveAspectRatio="none" style="height:${Math.round(h * 0.8)}px">${cornerBands}${body}${ph()}</svg></div>`;
    const ranked = cmp.ranked.filter((c) => Math.abs(c.lost) > 0.005);
    // notes belong to the demo's corners; against your best the corners still sit at the same places
    const demoCorner = (c) => CE.cornerOf(CE.sec(tid, n), c.apexD);
    const cardNotes = (c) => { const dc = demoCorner(c); if (!dc) return ''; const ns = CE.notesFor(CE.sec(tid, n), dc.n);
      return `${ns.length ? `<div class="card-notes">${ns.slice(0, 3).map((no) => `<div><span class="npill ${no.status === 'trying' ? 'try' : no.status === 'works' ? 'ok' : no.status === 'nope' ? 'no' : 'plain'}">${{ trying: 'Trying', works: 'Works', nope: 'Didn\'t', note: 'Note' }[no.status]}</span> ${esc(no.text)}</div>`).join('')}</div>` : ''}<button class="btn sm ghost notes-btn" data-notes="${dc.n}">${ns.length ? `Notes · ${ns.length}` : '＋ Note for this corner'}</button>`; };

    el.innerHTML = String(html`
      <div class="row" style="justify-content:space-between;align-items:end">
        <div><div class="kicker">${trackById[tid].short} · ${sectionName(tid, n)} · vs ${refName}</div>
          <h1>${entry?.complete === false ? 'Aborted run' : CE.fmt(entry?.ms ?? Math.round(cmp.yourTime * 1000))} ${raw(medalChip(md))}</h1></div>
        <div class="row"><div class="seg">${[['demo', 'vs demo'], ...(best ? [['best', 'vs your best']] : [])].map(([k, l]) => html`<button data-ref="${k}" class="${refName === (k === 'demo' ? 'demo' : 'your best') ? 'on' : ''}">${l}</button>`)}</div></div>
      </div>
      <div class="cmp-sum">
        <div><b style="color:${cmp.total > 0 ? 'var(--red)' : 'var(--ok)'}">${CE.fmtGap(cmp.total)}</b><span>to the ${refName}</span></div>
        ${x.gold && entry?.complete ? html`<div><b style="color:#a37b00">${CE.fmtGap((entry.ms - x.gold) / 1000)}</b><span>to gold</span></div>` : ''}
        <div><b>${ranked.filter((c) => c.lost > 0).length}</b><span>corners lost time</span></div>
        ${ranked[0] ? html`<div><b>C${ranked[0].n}</b><span>biggest loss, ${ranked[0].lost.toFixed(3)} s</span></div>` : ''}
      </div>
      ${raw(cornerChips(tid, n))}
      <div class="t-hero" style="margin-top:16px">
        <div class="mapstage" style="padding-bottom:18px;min-height:0;align-self:start">
          <svg id="cmap" viewBox="${vb.join(' ')}" preserveAspectRatio="xMidYMid meet" style="max-height:min(620px,64vh)">
            <polyline points="${refLine}" fill="none" stroke="rgba(255,255,255,.10)" stroke-width="${sw * 9}" stroke-linejoin="round" stroke-linecap="round"/>
            ${raw(segs.join(''))}
            <polyline points="${refLine}" fill="none" stroke="rgba(255,255,255,.8)" stroke-width="${sw * 0.6}" stroke-dasharray="${sw * 2} ${sw * 1.6}"/>
            ${raw(gates)}${raw(marks)}
            <circle id="c-ref" r="${sw * 3}" fill="rgba(255,255,255,.85)" stroke="#0b1f4b" stroke-width="${sw * 0.6}"/>
            <circle id="c-you" r="${sw * 3.6}" fill="#fff" stroke="#e1131f" stroke-width="${sw * 1.5}"/>
          </svg>
          <div class="maplegend"><span><i style="background:#36d399"></i>gaining</span><span><i style="background:#ff5a3c"></i>losing</span><span><i style="background:#fff;height:2px"></i>${refName}'s line</span><span><i style="background:#ff6b73;height:8px;width:2px"></i>your brake point</span>${zoom ? raw('<button class="btn sm ghost light" id="unzoom">Show all</button>') : ''}</div>
        </div>
        <div class="grid" style="gap:14px;align-content:start">
          <div class="card pad hudcmp">
            <div class="row" style="justify-content:space-between"><div class="kicker" style="color:#ff8a90" id="h-d">0 m</div><div id="h-gap" style="font-weight:800">±0.000</div></div>
            <table><tr><th></th><th>You</th><th>${refName}</th></tr>
              <tr><td>Speed</td><td id="h-vy">—</td><td id="h-vr">—</td></tr>
              <tr><td>Gear</td><td id="h-gy">—</td><td id="h-gr">—</td></tr>
              <tr><td>Throttle</td><td><div class="bar"><i id="h-ty" style="background:#36d399"></i></div></td><td><div class="bar"><i id="h-tr" style="background:#36d399"></i></div></td></tr>
              <tr><td>Brake</td><td><div class="bar"><i id="h-by" style="background:#e1131f"></i></div></td><td><div class="bar"><i id="h-br" style="background:#e1131f"></i></div></td></tr>
              <tr><td>Line</td><td colspan="2" id="h-lat">—</td></tr></table>
          </div>
          <div class="card pad"><div class="row"><button class="btn red" id="c-play">▶ Play both</button><div class="seg">${[['0.5', '½×'], ['1', '1×'], ['2', '2×']].map(([k, l]) => html`<button data-sp="${k}" class="${k === '1' ? 'on' : ''}">${l}</button>`)}</div></div>
            <input type="range" id="c-scrub" min="${cmp.from}" max="${cmp.to}" step="1" value="${cmp.from}" style="width:100%;margin-top:14px;accent-color:var(--red)">
            <p class="muted small" style="margin-top:6px">Play runs both cars on the clock, so you see the gap open up. Drag to compare the two at the same spot.</p></div>
        </div>
      </div>
      <section class="section card pad" style="background:#0b1f4b;color:#fff" id="traces">
        ${raw(trace('Speed · you <span style="color:#5aa2ff">■</span> · ' + refName + ' <span style="color:#fff">■</span>', `<polyline points="${poly(cmp.vr, vmax, vmin)}" fill="none" stroke="rgba(255,255,255,.8)" stroke-width="2" stroke-dasharray="6 4"/><polyline points="${poly(cmp.vy, vmax, vmin)}" fill="none" stroke="#5aa2ff" stroke-width="2.6"/>`))}
        ${raw(trace('Time gap · up = you\'re slower', `<line x1="0" x2="${W}" y1="${H / 2}" y2="${H / 2}" stroke="#3f5ea8"/><polyline points="${poly(cmp.gap, gmax, -gmax)}" fill="none" stroke="#ffc531" stroke-width="2.6"/><text x="6" y="${H - 6}" fill="#9fb3e6" style="font-size:12px">±${gmax.toFixed(2)} s</text>`))}
        ${raw(trace('Brake · you <span style="color:#ff6b73">■</span> · ' + refName + ' <span style="color:#fff">■</span>', `<polyline points="${poly(cmp.bkr, 100)}" fill="none" stroke="rgba(255,255,255,.8)" stroke-width="2" stroke-dasharray="6 4"/><polyline points="${poly(cmp.bky, 100)}" fill="none" stroke="#ff6b73" stroke-width="2.4"/>`, 90))}
        ${raw(trace('Throttle · you <span style="color:#36d399">■</span> · ' + refName + ' <span style="color:#fff">■</span>', `<polyline points="${poly(cmp.thr, 100)}" fill="none" stroke="rgba(255,255,255,.8)" stroke-width="2" stroke-dasharray="6 4"/><polyline points="${poly(cmp.thy, 100)}" fill="none" stroke="#36d399" stroke-width="2.4"/>`, 90))}
        ${raw(trace('Steering', `<line x1="0" x2="${W}" y1="${H / 2}" y2="${H / 2}" stroke="#3f5ea8"/><polyline points="${poly(cmp.str, smax, -smax)}" fill="none" stroke="rgba(255,255,255,.8)" stroke-width="2" stroke-dasharray="6 4"/><polyline points="${poly(cmp.sty, smax, -smax)}" fill="none" stroke="#c89bff" stroke-width="2.4"/>`, 90))}
        ${raw(trace('Gear', `<polyline points="${poly(cmp.S.map((s) => refAt(s, ref.gear)), 7)}" fill="none" stroke="rgba(255,255,255,.8)" stroke-width="2" stroke-dasharray="6 4"/><polyline points="${poly(cmp.gy, 7)}" fill="none" stroke="#ffc531" stroke-width="2.4"/>`, 70))}
      </section>
      <section class="section"><div class="head"><h2>Where the time went</h2><span class="muted small">Worst first. Tap one to zoom the map.</span></div>
        <div class="grid g2">${ranked.map((c) => html`<div class="card pad corner-card ${c.lost > 0.02 ? 'bad' : c.lost < -0.02 ? 'good' : ''}" data-c="${c.n}">
          <div class="row" style="justify-content:space-between"><h3>Corner ${c.n}</h3><b class="${c.lost > 0 ? 'lose' : 'gain'}" style="font-size:22px">${c.lost > 0 ? '−' : '+'}${Math.abs(c.lost).toFixed(3)} s</b></div>
          <table class="tbl" style="margin-top:8px"><tr><th></th><th>You</th><th>${refName}</th></tr>
            <tr><td>Brake point</td><td>${c.brake == null ? (c.brakeAt == null ? 'lift' : 'no brake') : c.brake === 0 ? 'same' : `${Math.abs(c.brake)} m ${c.brake < 0 ? 'earlier' : 'later'}`}</td><td>${c.brakeAt == null ? 'lift / flat' : Math.round(c.apexD - c.brakeAt) + ' m before apex'}</td></tr>
            <tr><td>Apex speed</td><td>${c.yourMin} km/h</td><td>${c.min} km/h</td></tr>
            <tr><td>Gear</td><td>${c.yourGear}</td><td>${c.refGear}</td></tr>
            <tr><td>Full throttle</td><td>${c.throttle == null ? '—' : c.throttle === 0 ? 'same' : `${Math.abs(c.throttle)} m ${c.throttle > 0 ? 'later' : 'sooner'}`}</td><td></td></tr>
            <tr><td>Line at apex</td><td colspan="2">${Math.abs(c.line) < 0.6 ? 'on the line' : `${Math.abs(c.line)} m ${c.line > 0 ? 'left' : 'right'}`}</td></tr></table>
          ${c.tips.length ? html`<ul class="tips">${c.tips.map((t) => html`<li>${t}</li>`)}</ul>` : html`<p class="muted small" style="margin-top:8px">Matches the ${refName} within what the telemetry can resolve.</p>`}
          ${raw(cardNotes(c))}
        </div>`)}</div>
      </section>
      <section class="section card pad"><details><summary><b>Timing gates</b> <span class="muted small">start ${Math.round(cmp.from)} m · finish ${Math.round(cmp.to)} m along the demo</span></summary>
        <p class="muted small" style="margin-top:8px">The trainer times you from where GT7 drops the car to where the demo's coast after the line begins. Move them to GT7's actual start and finish lines for exact times, or just type GT7's time once on the section page.</p>
        <label class="f">Start <input type="range" id="g-a" min="0" max="${Math.round(ref.dist)}" value="${Math.round(x.gates[0])}"></label>
        <label class="f">Finish <input type="range" id="g-b" min="0" max="${Math.round(ref.dist)}" value="${Math.round(x.gates[1])}"></label>
        <button class="btn sm" id="g-save" style="margin-top:8px">Save gates and re-measure</button></details></section>`);

    // ── scrub + play ──
    const you0 = at(S, S.map((s) => at(cmp.st, you.t, s)), cmp.from), ref0 = at(ref.d, ref.t, cmp.from);
    const set = (id, v) => { const e = el.querySelector(id); if (e) e.textContent = v; };
    const show = (s, youT) => {
      s = Math.max(cmp.from, Math.min(cmp.to, s));
      const k = Math.min(S.length - 1, Math.round((s - cmp.from) / 2));
      const yp = youT != null ? posAtTime(you, youT + you0) : youPt(s), rp = youT != null ? posAtTime(ref, youT + ref0) : [refAt(s, ref.x), refAt(s, ref.z)];
      el.querySelector('#c-you').setAttribute('cx', yp[0]); el.querySelector('#c-you').setAttribute('cy', yp[1]);
      el.querySelector('#c-ref').setAttribute('cx', rp[0]); el.querySelector('#c-ref').setAttribute('cy', rp[1]);
      set('#h-d', Math.round(s - cmp.from) + ' m'); set('#h-gap', CE.fmtGap(cmp.gap[k]));
      el.querySelector('#h-gap').style.color = cmp.gap[k] > 0 ? '#ff6b73' : '#36d399';
      set('#h-vy', Math.round(cmp.vy[k]) + ' km/h'); set('#h-vr', Math.round(cmp.vr[k]) + ' km/h');
      set('#h-gy', cmp.gy[k] || 'N'); set('#h-gr', Math.round(refAt(s, ref.gear)) || 'N');
      el.querySelector('#h-ty').style.width = cmp.thy[k] + '%'; el.querySelector('#h-tr').style.width = cmp.thr[k] + '%';
      el.querySelector('#h-by').style.width = cmp.bky[k] + '%'; el.querySelector('#h-br').style.width = cmp.bkr[k] + '%';
      set('#h-lat', Math.abs(cmp.lat[k]) < 0.6 ? 'on the ' + refName + '\'s line' : `${Math.abs(cmp.lat[k]).toFixed(1)} m ${cmp.lat[k] > 0 ? 'left' : 'right'} of it`);
      $$('.ph', el).forEach((l) => { l.setAttribute('x1', X(s)); l.setAttribute('x2', X(s)); });
      el.querySelector('#c-scrub').value = s;
    };
    let playing = false, speed = 1, T = 0, lastF = 0;
    const tEnd = cmp.yourTime;
    const stAtTime = (tt) => { const t = tt + you0; let i = you.t.findIndex((v) => v >= t); if (i < 0) i = you.n - 1; return cmp.st[i]; };
    const loop = (now) => { if (!playing || !el.isConnected) return; T += ((now - lastF) / 1000) * speed; lastF = now; if (T > tEnd + 1) T = 0; show(stAtTime(T), T); requestAnimationFrame(loop); };
    el.querySelector('#c-play').onclick = (e) => { playing = !playing; e.target.textContent = playing ? '❚❚ Pause' : '▶ Play both'; lastF = performance.now(); if (playing) requestAnimationFrame(loop); };
    $$('[data-sp]', el).forEach((b) => (b.onclick = () => { speed = +b.dataset.sp; $$('[data-sp]', el).forEach((y) => y.classList.toggle('on', y === b)); }));
    el.querySelector('#c-scrub').oninput = (e) => { playing = false; el.querySelector('#c-play').textContent = '▶ Play both'; show(+e.target.value); };
    $$('.trace', el).forEach((svg) => (svg.onclick = (e) => { const r = svg.getBoundingClientRect(); show(cmp.from + ((e.clientX - r.left) / r.width) * (cmp.to - cmp.from)); }));
    const focus = (cn) => {
      const c = cmp.corners.find((y) => y.n === cn); if (!c) return;
      // from the braking point to just past the apex, at most a couple of hundred metres
      const a0 = Math.max(c.zone[0], (c.brakeAt ?? c.apexD) - 40), a1 = Math.min(c.zone[1], c.apexD + 90);
      const i0 = Math.max(0, ref.d.findIndex((d) => d >= a0)), i1 = Math.max(i0 + 1, ref.d.findIndex((d) => d >= a1));
      const zx = ref.x.slice(i0, i1 + 1), zz = ref.z.slice(i0, i1 + 1);
      const cx = (Math.min(...zx) + Math.max(...zx)) / 2, cz = (Math.min(...zz) + Math.max(...zz)) / 2, r = Math.min(220, Math.max(70, Math.max(...zx) - Math.min(...zx), Math.max(...zz) - Math.min(...zz)) / 2 + 20);
      zoom = [cx - r, cz - r, cx + r, cz + r];
      draw(); show(c.brakeAt ?? c.zone[0]); el.querySelector('#cmap').scrollIntoView({ behavior: 'smooth', block: 'center' });
    };
    $$('.corner-card', el).forEach((c) => (c.onclick = (e) => { if (e.target.closest('.notes-btn')) return; focus(+c.dataset.c); }));
    wireChips(el);
    $$('.notes-btn', el).forEach((b) => (b.onclick = () => openCornerSheet(tid, n, +b.dataset.notes)));
    const onNotes = () => { if (!el.isConnected) return window.removeEventListener('gt7-notes-changed', onNotes); notesDirty = true; };
    window.addEventListener('gt7-notes-changed', onNotes);
    $$('#cmap .cpin', el).forEach((p) => (p.onclick = () => focus(+p.dataset.c)));
    el.querySelector('#unzoom')?.addEventListener('click', () => { zoom = null; draw(); });
    $$('[data-ref]', el).forEach((b) => (b.onclick = () => { refRun = b.dataset.ref === 'best' ? best : demo; refName = b.dataset.ref === 'best' ? 'your best' : 'demo'; zoom = null; draw(); }));
    el.querySelector('#g-save').onclick = async () => {
      const a = +el.querySelector('#g-a').value, b = +el.querySelector('#g-b').value;
      if (b - a < 100) return toast('The finish has to be after the start');
      CE.setGates(tid, n, [a, b]); await CE.useAsDemo(tid, n, demo, L.getLap); toast('Gates saved, attempts re-measured'); rerender();
    };
    show(cmp.from);
  };
  draw();
}
function at(S, arr, s) {
  let lo = 0, hi = S.length - 1;
  if (s <= S[0]) return arr[0];
  if (s >= S[hi]) return arr[hi];
  while (hi - lo > 1) { const m = (lo + hi) >> 1; if (S[m] <= s) lo = m; else hi = m; }
  return arr[lo] + (arr[hi] - arr[lo]) * ((s - S[lo]) / Math.max(1e-9, S[hi] - S[lo]));
}
function posAtTime(r, t) {
  let i = r.t.findIndex((v) => v >= t); if (i < 1) i = i < 0 ? r.n - 1 : 1;
  const f = Math.max(0, Math.min(1, (t - r.t[i - 1]) / ((r.t[i] - r.t[i - 1]) || 1)));
  return [r.x[i - 1] + (r.x[i] - r.x[i - 1]) * f, r.z[i - 1] + (r.z[i] - r.z[i - 1]) * f];
}
