// Race Systems: how GT7's race machinery works (pits, fuel, tyres, TCS, ABS,
// brake balance, the MFD, weather, penalties...). Content in data/systems.js.
import { html } from './util.js';
import { SYSTEMS, systemById } from '../data/systems.js';
import { simBlock, mountSimIn } from './simview.js';

const SIM = { tcs: 'throttle', abs: 'braking', 'brake-balance': 'trail', weather: 'wet', tyres: 'tyres', fuel: 'tyres' };
const groups = () => [...new Set(SYSTEMS.map((x) => x.kicker))];

export function systemsIndex() {
  return html`
    <div class="kicker">Race Systems · ${SYSTEMS.length} guides</div><h1>How the Race<br>Machinery Works</h1>
    <p class="muted" style="max-width:70ch;margin-top:12px;font-size:18px">Pit stops, fuel maps, tyres, TCS, ABS, brake balance, the MFD, weather, starts, penalties. What each one does, exactly how to use it, the settings, and the mistakes that cost races.</p>
    ${groups().map((g) => html`<section class="section"><div class="head"><h2>${g}</h2></div>
      <div class="grid g3">${SYSTEMS.filter((x) => x.kicker === g).map((x) => html`<a class="card pad gloss sys-card" href="#/systems/${x.id}">
        <div class="kicker">${x.kicker}${SIM[x.id] ? ' · interactive' : ''}</div><h3 style="font-size:24px;margin:6px 0 8px">${x.title}</h3><p class="muted small" style="margin:0">${x.summary}</p></a>`)}</div></section>`)}`;
}

export function systemView(id) {
  const x = systemById[id];
  if (!x) return html`<h1>Not found</h1>`;
  const i = SYSTEMS.indexOf(x), next = SYSTEMS[i + 1];
  return {
    html: html`
      <a class="back" href="#/systems">← Race Systems</a>
      <div class="kicker">${x.kicker}</div><h1>${x.title}</h1>
      <p class="pull" style="margin-top:16px;max-width:80ch">${x.summary}</p>
      <div class="grid g2" style="align-items:start;margin-top:14px">
        <div class="prose"><h3 style="margin:6px 0 8px">What it does</h3>${x.what.map((p) => html`<p>${p}</p>`)}</div>
        <div class="card pad"><div class="kicker">How to use it</div><ol class="steps">${x.how.map((s) => html`<li>${s}</li>`)}</ol></div>
      </div>
      ${x.settings?.length ? html`<section class="section"><div class="head"><h2>Settings</h2></div>
        <div class="grid g3">${x.settings.map((s) => html`<div class="card pad"><div class="kicker">${s.name}</div><p style="margin:8px 0 0">${s.effect}</p></div>`)}</div></section>` : ''}
      ${SIM[id] ? simBlock(SIM[id], 'See the effect in the inputs') : ''}
      <section class="section grid g2">
        <div class="card pad"><div class="kicker">Pro tips</div><ul class="pts" style="margin-top:10px">${x.tips.map((t) => html`<li>${t}</li>`)}</ul></div>
        <div class="card pad" style="border-left:5px solid var(--red)"><div class="kicker">Mistakes that cost races</div><ul class="pts" style="margin-top:10px">${x.mistakes.map((t) => html`<li>${t}</li>`)}</ul></div>
      </section>
      <section class="section card pad"><div class="kicker">On your G PRO</div><p style="margin-top:8px">${x.wheel}</p></section>
      ${x.related?.length ? html`<div class="row" style="margin-top:18px">${x.related.map((r) => systemById[r] ? html`<a class="chip blue" href="#/systems/${r}">${systemById[r].title}</a>` : '')}</div>` : ''}
      <div class="row" style="margin-top:22px">${next ? html`<a class="btn ghost" href="#/systems/${next.id}">Next: ${next.title} →</a>` : html`<a class="btn ghost" href="#/systems">All systems →</a>`}</div>`,
    wire(root) { mountSimIn(root); },
  };
}
