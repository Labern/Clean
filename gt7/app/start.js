// Start Here: the beginners' course. Content in data/beginners.js; physics
// chapters embed the Academy's interactive diagrams.
import { $, html, raw } from './util.js';
import * as store from './state.js';
import { mountWidget } from './widgets.js';
import { BEGINNER } from '../data/beginners.js';
import { simBlock, mountSimIn } from './simview.js';

// Chapters that get the input simulator, and which scenario.
const SIM = { 'grip-and-tyres': 'circle', 'weight-transfer': 'weight', 'braking-and-the-line': 'braking', 'drivetrains-and-handling': 'throttle', assists: 'throttle', 'racing-others': 'slipstream' };

const WIDGET = { grip: 'circle', 'weight-transfer': 'weight', braking: 'brake', 'racing-line': 'line' };
const widgetFor = (c) => WIDGET[c.id] || (/grip|tyre/.test(c.id) ? 'circle' : /weight/.test(c.id) ? 'weight' : /brak|line/.test(c.id) ? 'line' : null);

export function startView() {
  const s = store.get(), read = s.read || {};
  const n = BEGINNER.chapters.filter((c) => read[c.id]).length;
  const next = BEGINNER.chapters.find((c) => !read[c.id]) || BEGINNER.chapters[0];
  return html`
    <div class="kicker">Start Here · ${n}/${BEGINNER.chapters.length} chapters read</div><h1>How to Play<br>Gran Turismo</h1>
    <p class="muted" style="max-width:70ch;margin-top:12px;font-size:18px">${BEGINNER.intro}</p>
    <div class="bar red" style="height:10px;margin:18px 0;max-width:520px"><i style="width:${(n / BEGINNER.chapters.length) * 100}%"></i></div>
    <a class="btn red" href="#/start/${next.id}">${n ? 'Continue' : 'Begin'}: ${next.title} →</a>
    <section class="section"><div class="head"><h2>The Course</h2></div>
      <div class="grid" style="gap:10px">${BEGINNER.chapters.map((c, i) => html`<a class="card chap ${read[c.id] ? 'done' : ''}" href="#/start/${c.id}">
        <span class="n">${read[c.id] ? '✓' : String(i + 1).padStart(2, '0')}</span>
        <span><span class="kicker">${c.kicker} · ${c.minutes} min</span><h3 style="font-size:24px;margin:4px 0">${c.title}</h3><span class="muted small">${c.summary}</span></span>
        <span class="chip ${widgetFor(c) ? 'gold' : ''}">${widgetFor(c) ? 'Interactive' : 'Read'}</span></a>`)}</div>
    </section>
    <section class="section"><div class="head"><h2>Your First Week</h2></div>
      <div class="grid g4">${BEGINNER.firstWeek.map((d) => html`<div class="card pad"><div class="kicker">${d.day}</div><p style="margin:8px 0 0">${d.do}</p></div>`)}</div>
    </section>
    <section class="section"><div class="head"><h2>Glossary</h2></div>
      <div class="gloss-grid">${BEGINNER.glossary.map((g) => html`<div><b>${g.term}</b><p class="muted small" style="margin:4px 0 0">${g.def}</p></div>`)}</div>
    </section>
    <section class="section card pad"><div class="kicker">When you've finished</div><p style="margin-top:8px">Go to the <a href="#/academy" style="text-decoration:underline">Racecraft Academy</a> for advanced technique, then the <a href="#/roadmap" style="text-decoration:underline">Roadmap</a> for the endgame.</p></section>`;
}

export function chapterView(id) {
  const i = BEGINNER.chapters.findIndex((c) => c.id === id);
  if (i < 0) return html`<h1>Not found</h1>`;
  const c = BEGINNER.chapters[i], next = BEGINNER.chapters[i + 1], w = widgetFor(c);
  const done = (store.get().read || {})[id];
  return {
    html: html`
      <a class="back" href="#/start">← Start Here</a>
      <div class="kicker">${c.kicker} · ${c.minutes} min read</div><h1>${c.title}</h1>
      <p class="pull" style="margin-top:16px">${c.summary}</p>
      ${SIM[id] ? simBlock(SIM[id]) : ''}
      <div class="grid g2" style="align-items:start;margin-top:10px">
        <div class="prose">${c.sections.map((sec) => html`<h3 style="margin:18px 0 8px">${sec.h}</h3>${sec.p.map((p) => html`<p>${p}</p>`)}`)}</div>
        <div class="grid" style="gap:16px;align-content:start;position:sticky;top:84px">
          ${w && !SIM[id] ? raw('<div class="widget" id="bwidget"></div>') : ''}
          <div class="card pad"><div class="kicker">Tips</div><ul class="pts" style="margin-top:10px">${c.tips.map((t) => html`<li style="font-weight:500">${t}</li>`)}</ul></div>
          <div class="card pad" style="border-left:5px solid var(--red)"><div class="kicker">Try it now</div><p style="margin:8px 0 0">${c.try}</p></div>
        </div>
      </div>
      <div class="row" style="margin-top:26px">
        <button class="btn ${done ? 'ghost' : 'red'}" id="bdone">${done ? 'Read ✓' : 'Mark as read'}</button>
        ${next ? html`<a class="btn ghost" href="#/start/${next.id}">Next: ${next.title} →</a>` : html`<a class="btn ghost" href="#/academy">On to the Academy →</a>`}
      </div>`,
    wire(root) {
      const el = $('#bwidget', root); if (el) mountWidget(w, el);
      mountSimIn(root);
      $('#bdone', root).onclick = () => {
        store.set((s) => { s.read = { ...(s.read || {}), [id]: true }; });
        location.hash = next ? '#/start/' + next.id : '#/start';
      };
    },
  };
}
