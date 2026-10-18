// Beyond the Apex: the official manual's concepts, each demonstrated on real
// corners. Content in data/apex.js; maps from map.js focusMap.
import { $, $$, html, raw } from './util.js';
import * as store from './state.js';
import { mountWidget } from './widgets.js';
import { focusMap } from './map.js';
import { APEX, APEX_PARTS, apexById, apexUrl, apexForTrack } from '../data/apex.js';
import { trackById } from '../data/tracks.js';
import { LESSONS } from '../data/academy.js';

const seen = () => store.get().apex || {};
export const nextApex = () => APEX.find((a) => !seen()[a.id]) || null;

const cornerNames = (t, idxs) => idxs.map((i) => t.corners[i]?.name).filter(Boolean).join(' · ');

export function apexIndex() {
  const s = seen(), n = APEX.filter((a) => s[a.id]).length, nx = nextApex();
  return html`
    <div class="kicker">Beyond the Apex · ${n}/${APEX.length} concepts done</div><h1>The Manual,<br>On Track</h1>
    <p class="muted" style="max-width:70ch;margin-top:12px;font-size:18px">Polyphony's official GT7 guide explains the driving and the engineering. Here each idea is pinned to the exact corners where you'll feel it, with a drill to run there. Summaries are ours; the full articles are linked.</p>
    <div class="bar red" style="height:10px;margin:18px 0;max-width:520px"><i style="width:${(n / APEX.length) * 100}%"></i></div>
    ${nx ? html`<a class="btn red" href="#/apex/${nx.id}">${n ? 'Next' : 'Begin'}: ${nx.title} →</a>` : html`<span class="chip ok">✓ All concepts done</span>`}
    ${APEX_PARTS.map((p) => html`<section class="section"><div class="head"><h2>${p.title}</h2><span class="muted small">${p.kicker}</span></div>
      <div class="grid g3">${APEX.filter((a) => a.part === p.id).map((a) => {
        const d = a.demos[0], t = trackById[d.track];
        return html`<a class="card apex-card gloss ${s[a.id] ? 'done' : ''}" href="#/apex/${a.id}">
          <div class="apex-map">${raw(focusMap(t, d.corners, true))}</div>
          <div class="body"><div class="kicker">${s[a.id] ? '✓ ' : ''}${a.demos.map((x) => trackById[x.track].short).filter((v, i, arr) => arr.indexOf(v) === i).join(' · ')}</div>
          <h3 style="font-size:23px;margin:4px 0 6px">${a.title}</h3><div class="muted small">${a.points[0]}.</div></div></a>`;
      })}</div></section>`)}
    <section class="section card pad"><div class="kicker">Source</div><p style="margin-top:8px">Beyond the Apex is published free by Polyphony Digital at <a href="https://www.gran-turismo.com/us/gt7/apex/" target="_blank" rel="noopener" style="text-decoration:underline">gran-turismo.com/gt7/apex</a>. Read it there; use this to go and drive it.</p></section>`;
}

export function apexView(id) {
  const a = apexById[id];
  if (!a) return html`<h1>Not found</h1><p class="muted"><a href="#/apex" style="text-decoration:underline">Back to Beyond the Apex</a></p>`;
  const i = APEX.indexOf(a), next = APEX[i + 1];
  const done = seen()[id];
  const lesson = LESSONS.find((l) => l.id === a.lesson);
  let cur = 0;
  const demo = (k) => {
    const d = a.demos[k], t = trackById[d.track];
    return html`<div class="apex-demo">
      <div class="mapstage apex-stage">${raw(focusMap(t, d.corners))}</div>
      <div class="grid" style="gap:12px;align-content:start">
        <div><div class="kicker">${t.flag} ${t.short} · ${cornerNames(t, d.corners)}</div><h3 style="font-size:26px;margin:6px 0 8px">${d.title}</h3><p style="margin:0">${d.watch}</p></div>
        ${d.drill ? html`<div class="card pad" style="border-left:5px solid var(--red)"><div class="kicker">Drill</div><p style="margin:8px 0 0">${d.drill}</p></div>` : ''}
        ${d.corners.map((ci) => { const c = t.corners[ci]; return c ? html`<div class="card pad apex-corner"><div class="row" style="gap:8px"><b>${c.n} ${c.name}</b><span class="chip">${c.dir}</span><span class="chip dark">Gear ${c.gear}</span><span class="chip blue">${c.speed}</span></div><p class="muted small" style="margin:8px 0 0"><b>Line.</b> ${c.line}</p></div>` : ''; })}
        <a class="btn ghost" href="#/track/${t.id}">Full ${t.short} guide →</a>
      </div>
    </div>`;
  };
  return {
    html: html`
      <a class="back" href="#/apex">← Beyond the Apex</a>
      <div class="kicker">${APEX_PARTS.find((p) => p.id === a.part).title} · ${a.demos.length} track demo${a.demos.length > 1 ? 's' : ''}</div><h1>${a.title}</h1>
      <div class="grid g2" style="align-items:start;margin-top:18px">
        <div class="prose">${a.idea.map((p, k) => html`<p class="${k ? '' : 'pull'}">${p}</p>`)}
          <p class="muted small">From <a href="${apexUrl(a)}" target="_blank" rel="noopener" style="text-decoration:underline">${a.article}</a> (Beyond the Apex, Polyphony Digital). Paraphrased.</p></div>
        <div class="grid" style="gap:16px;align-content:start">
          ${a.widget ? raw('<div class="widget" id="awidget"></div>') : ''}
          <div class="card pad"><div class="kicker">Remember</div><ul class="pts" style="margin-top:10px">${a.points.map((p) => html`<li style="font-weight:500">${p}</li>`)}</ul></div>
          <div class="row">${lesson ? html`<a class="chip blue" href="#/lesson/${lesson.id}">Academy: ${lesson.title}</a>` : ''}${a.tool ? html`<a class="chip blue" href="${a.tool[0]}">${a.tool[1]}</a>` : ''}</div>
        </div>
      </div>
      <section class="section">
        <div class="head"><h2>On Track</h2><span class="muted small">Where you'll feel it</span></div>
        ${a.demos.length > 1 ? html`<div class="seg" id="demo-tabs" style="margin-bottom:16px">${a.demos.map((d, k) => { const t = trackById[d.track], dup = a.demos.filter((x) => x.track === d.track).length > 1; return html`<button data-d="${k}" class="${k ? '' : 'on'}">${dup ? t.corners[d.corners[0]].name.replace(/^T\d+\S*\s/, '') : t.short}</button>`; })}</div>` : ''}
        <div id="demo">${demo(0)}</div>
      </section>
      <div class="row" style="margin-top:26px">
        <button class="btn ${done ? 'ghost' : 'red'}" id="adone">${done ? 'Driven ✓' : 'I\'ve driven the drills'}</button>
        ${next ? html`<a class="btn ghost" href="#/apex/${next.id}">Next: ${next.title} →</a>` : html`<a class="btn ghost" href="#/apex">All concepts →</a>`}
      </div>`,
    wire(root) {
      const el = $('#awidget', root); if (el) mountWidget(a.widget, el);
      $$('[data-d]', root).forEach((b) => (b.onclick = () => {
        cur = +b.dataset.d;
        $$('[data-d]', root).forEach((x) => x.classList.toggle('on', +x.dataset.d === cur));
        $('#demo', root).innerHTML = String(demo(cur));
      }));
      $('#adone', root).onclick = () => {
        store.set((s) => { s.apex = { ...(s.apex || {}), [id]: !done }; if (!done && APEX.every((x) => s.apex[x.id])) s.done.apex = true; });
        const to = !done && next ? '#/apex/' + next.id : '#/apex/' + id;
        if (location.hash === to) window.dispatchEvent(new HashChangeEvent('hashchange')); else location.hash = to;
      };
    },
  };
}

// For the track guide: every concept demonstrated here.
export function apexOnTrack(tid) {
  const list = apexForTrack(tid);
  if (!list.length) return '';
  const t = trackById[tid];
  return html`<section class="section"><div class="head"><h2>Beyond the Apex Here</h2><span class="muted small">The official manual, demonstrated at ${t.short}</span></div>
    <div class="grid g3">${list.map(({ a, d }) => html`<a class="card pad gloss" href="#/apex/${a.id}"><div class="kicker">${cornerNames(t, d.corners)}</div><h3 style="font-size:22px;margin:6px 0">${a.title}</h3><div class="muted small">${d.title}</div></a>`)}</div></section>`;
}
