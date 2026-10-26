// GT7 Endgame: hash router + views. No framework: each view returns HTML and
// an optional `wire(root)` to attach behaviour after it is inserted.
import { $, $$, html, raw, esc, cr, crShort, hrs, toSec, fmtSec, toast, clsClass } from './util.js';
import * as store from './state.js';
import { CARS, carById } from '../data/cars.js';
import { TRACKS, trackById } from '../data/tracks.js';
import { PHASES, FOCUS } from '../data/roadmap.js';
import { BOOSTERS, CLEAN_BONUS } from '../data/grinds.js';
import { LESSONS } from '../data/academy.js';
import { SETTINGS, SOLVER } from '../data/tuning.js';
import { RATINGS, SPORT_GUIDE, BOP } from '../data/sport.js';
import { BASES, METHOD, PEDALS, SEATING } from '../data/wheel.js';
import { thumb, fullMap, lapStrip, SECTOR_COLORS } from './map.js';
import { nextSteps, progress, grindRows, hoursFor, priceOf, isDone, trackOfTheDay, bestRate } from './engine.js';
import { mountWidget } from './widgets.js';
import { TIMELINE, CHAPTERS } from '../data/heritage.js';
import { BUILD } from '../data/build.js';
import * as sync from './sync.js';
import { telemetryView, lapView } from './telemetry.js';
import { startView, chapterView } from './start.js';
import { apexIndex, apexView, apexOnTrack, nextApex } from './apex.js';
import { apexForTrack } from '../data/apex.js';
import { videosSection, wireVideos } from './videos.js';
import { studioHtml, wireStudio } from './trackstudio.js';
import { mountSim, simBlock } from './simview.js';
import { systemsIndex, systemView } from './systems.js';
import { psnWizard, wireWizard } from './psnwizard.js';
import { SCENARIOS } from './scenarios.js';
import * as connect from './connect.js';
import { isNative } from './platform.js';

const S = store.get;
const NO_IMG = new Set(['escudo']);
const img = (id, cls = '') => NO_IMG.has(id)
  ? `<div class="noimg ${cls}">${esc(carById[id]?.make || 'GT')}</div>`
  : `<img src="img/cars/${id}.jpg" alt="${esc(carById[id]?.name || '')}" loading="lazy" class="${cls}">`;
const stars = (n) => '★'.repeat(n) + '<span style="opacity:.25">' + '★'.repeat(5 - n) + '</span>';

// ── shared pieces ───────────────────────────────────────
function carCard(c) {
  const s = S();
  const own = s.owned.includes(c.id), wish = s.wish.includes(c.id);
  const p = priceOf(s, c.id);
  return html`<a class="card car-card gloss" href="#/car/${c.id}">
    <div class="ph">${raw(img(c.id))}
      <div class="tag"><span class="cls ${clsClass(c.cls)}">${c.cls}</span></div>
      <div class="own">${own ? raw('<span class="chip ok">✓ Owned</span>') : wish ? raw('<span class="chip gold">★ Wishlist</span>') : ''}</div>
    </div>
    <div class="body">
      <div class="muted small">${c.make} · ${c.year}</div>
      <h3>${c.name.replace(c.make + ' ', '')}</h3>
      <div class="row" style="justify-content:space-between;margin-top:6px"><span class="price">${cr(p)}</span><span class="chip">${c.where}</span></div>
    </div>
  </a>`;
}

function trackCard(t) {
  const pb = S().pbs[t.id] || {};
  const has = Object.keys(pb).length;
  return html`<a class="card track-card" href="#/track/${t.id}">
    <div class="mapbox"><span class="flag">${t.flag}</span><span class="km">${t.km.toFixed(3)} km</span>${raw(thumb(t))}</div>
    <div class="body">
      <div class="row" style="justify-content:space-between"><span class="stars">${raw(stars(t.fame))}</span>${has ? raw('<span class="chip ok">PB logged</span>') : t.country !== 'GT original' ? raw('<span class="chip blue">Real map</span>') : raw('<span class="chip">GT original</span>')}</div>
      <h3 style="margin-top:6px">${t.short}</h3>
      <div class="muted small">${t.country} · ${t.corners.length} key corners · ${t.layout}</div>
    </div>
  </a>`;
}

function wireNext(root) {
  $$('[data-done]', root).forEach((b) => (b.onclick = () => { store.set((s) => { s.done[b.dataset.done] = true; }); toast('Ticked off. Next move loaded.'); render(); }));
  $$('[data-snooze]', root).forEach((b) => (b.onclick = () => { store.set((s) => { s.snooze = { ...(s.snooze || {}), [b.dataset.snooze]: Date.now() + 864e5 }; }); toast('Snoozed until tomorrow'); render(); }));
}

function paintNextBar(name) {
  const bar = $('#nextbar');
  if (['home', 'setup', 'start', 'lap'].includes(name)) { bar.hidden = true; return; }
  const st = nextSteps(S(), 1)[0];
  if (!st) { bar.hidden = true; return; }
  bar.hidden = false;
  bar.innerHTML = String(html`<span class="nb-k">Next</span><a class="nb-t" href="${st.href}">${st.title}</a>${st.step ? html`<button class="nb-done" data-done="${st.step}" aria-label="Mark done">✓</button>` : ''}<a class="nb-go" href="${st.href}">Go →</a>`);
  wireNext(bar);
}

const back = (href, label) => html`<a class="back" href="${href}">← ${label}</a>`;

// ── views ───────────────────────────────────────────────
const views = {};

views.home = () => {
  const s = S();
  const steps = nextSteps(s, 3);
  const pr = progress(s);
  const tod = trackOfTheDay(s);
  const todApex = apexForTrack(tod.id).find(({ a }) => !(s.apex || {})[a.id]) || apexForTrack(tod.id)[0];
  const heroCar = carById[s.wish.find((id) => !s.owned.includes(id))] || carById.r34;
  const pbCount = Object.values(s.pbs).filter((x) => Object.keys(x).length).length;
  const rate = bestRate(s);
  return {
    html: html`
    ${(() => {
      const st = steps[0];
      const art = carById[st?.car] || heroCar;
      return html`<section class="next-hero fade-in">
        <div class="copy">
          <div class="stripe-big"><span></span><span></span></div>
          <div class="kicker">Your next move${st?.phase ? ' · ' + st.phase : ''}</div>
          <h1 class="next-title">${st ? st.title : 'Everything on the roadmap is done'}</h1>
          <p class="lede">${st ? st.why : 'Alien status. Pick a track and chase a benchmark.'}</p>
          <div class="row next-actions">
            ${st ? html`<a class="btn red xl" href="${st.href}">${st.cta === 'Go' ? 'Do it' : st.cta} →</a>` : ''}
            ${st?.step ? html`<button class="btn ghost-light xl" data-done="${st.step}">Done ✓</button>` : ''}
            ${st ? html`<button class="btn ghost-light xl" data-snooze="${st.id}">Not now</button>` : ''}
          </div>
        </div>
        <div class="art">${raw(img(art.id))}</div>
      </section>
      ${steps.length > 1 ? html`<section class="then"><div class="kicker" style="margin-bottom:10px">Then</div><div class="grid g2" style="gap:12px">
        ${steps.slice(1).map((x, i) => html`<a class="card then-card" href="${x.href}"><span class="num">0${i + 2}</span><span><span class="kicker">${x.phase || { buy: 'Buy now', grind: 'Credits', setup: 'Setup', connect: 'Accounts', trophy: 'Trophy' }[x.kind] || ''}</span><b>${x.title}</b></span><span class="go">→</span></a>`)}
      </div></section>` : ''}`;
    })()}

    <a class="card start-band" href="#/start">
      <span class="start-dot">NEW TO GT?</span>
      <span><b>Start Here</b> <span class="muted">How to play from zero: controls, car physics, licences, assists, racing clean.</span></span>
      <span class="btn sm red">Begin →</span>
    </a>

    <section class="section grid g4">
      <a class="card stat" href="#/credits"><div class="v">${s.credits == null ? '—' : crShort(s.credits)}</div><div class="l">Credits</div><div class="muted small" style="margin-top:6px">${rate ? `Best grind ≈ ${crShort(rate)}/hr` : 'Set payouts'}</div></a>
      <a class="card stat" href="#/roadmap"><div class="v">${pr.pct}%</div><div class="l">Roadmap · ${pr.done}/${pr.total}</div><div class="bar red"><i style="width:${pr.pct}%"></i></div></a>
      <a class="card stat" href="#/garage"><div class="v">${s.owned.length}</div><div class="l">Cars tracked · ${s.wish.length} wishlisted</div></a>
      <a class="card stat" href="#/tracks"><div class="v">${pbCount}/${TRACKS.length}</div><div class="l">Tracks with a PB</div><div class="bar"><i style="width:${(pbCount / TRACKS.length) * 100}%"></i></div></a>
    </section>

    <section class="section">
      <div class="head"><h2>Today's Track</h2><a class="btn sm ghost" href="#/tracks">All tracks</a></div>
      <div class="grid g2">
        ${trackCard(tod)}
        <div class="card pad">
          <div class="kicker">Why this one</div>
          <h3 style="margin:6px 0 10px">${tod.short}</h3>
          <p class="muted">${tod.blurb}</p>
          <ul class="pts">${tod.corners.filter((c) => c.key).slice(0, 3).map((c) => html`<li>${c.name}: ${c.line.split('. ')[0]}.</li>`)}</ul>
          ${todApex ? html`<p class="small" style="margin:12px 0 0"><b>Beyond the Apex here:</b> <a href="#/apex/${todApex.a.id}" style="text-decoration:underline">${todApex.a.title}</a></p>` : ''}
          <div class="row" style="margin-top:14px"><a class="btn" href="#/track/${tod.id}">Open the guide</a></div>
        </div>
      </div>
    </section>

    <section class="section">
      <div class="head"><h2>Explore</h2></div>
      <div class="grid g3">
        ${[['#/telemetry', 'Data Logger', 'Record your real laps from the PS5 and scrub through your racing line.'],
          ['#/academy', 'Racecraft Academy', 'From the racing line to alien technique, with interactive diagrams.'],
          ['#/apex', 'Beyond the Apex', 'Polyphony\'s official manual, demonstrated corner by corner on real tracks.'],
          ['#/systems', 'Race Systems', 'Pits, fuel maps, tyres, TCS, ABS, brake balance, the MFD, weather, penalties.'],
          ['#/wheel', 'Wheel Lab', 'Force feedback and pedals, tuned for your exact wheel base.'],
          ['#/tuning', 'Tuning Lab', 'What every setting does, plus a symptom → fix solver.'],
          ['#/sport', 'Sport Mode', 'How DR and SR really work, and how to climb.']].map(([h, t, d]) => html`<a class="card pad gloss" href="${h}"><div class="kicker">Open</div><h3 style="margin:6px 0">${t}</h3><div class="muted small">${d}</div></a>`)}
      </div>
    </section>`,
    wire(root) {
      wireNext(root);
    },
  };
};

views.setup = () => {
  const s = S();
  const groups = [['race', 'Race cars'], ['hyper', 'Hypercars'], ['legend', 'Legend cars'], ['heritage', 'Heritage']];
  return {
    html: html`
    ${back('#/', 'Command')}
    <div class="kicker">Setup</div><h1>Where You Are</h1>
    <p class="muted" style="max-width:60ch;margin-top:10px">Takes a minute. Everything stays on this device. Change it any time.</p>
    <a class="card start-band" href="#/connect" style="margin-top:18px;border-left-color:#0070d1">
      <span class="start-dot" style="color:#0070d1">FASTEST</span>
      <span><b>Connect PlayStation + GT7 instead</b> <span class="muted">Your real credits, licence, garage and trophies, filled in for you.</span></span>
      <span class="btn sm">Connect →</span>
    </a>
    <div class="grid g2 section" style="margin-top:20px">
      <div class="card pad">
        <h3>Credits</h3>
        <label class="f" style="margin-top:12px">Current credits (top right in GT7)<input type="number" id="su-cr" inputmode="numeric" placeholder="e.g. 4200000" value="${s.credits ?? ''}"></label>
        <h3 style="margin-top:24px">What are you chasing?</h3>
        <div class="grid" style="gap:8px;margin-top:12px">
          ${Object.entries(FOCUS).map(([k, v]) => html`<label class="opt ${s.focus.includes(k) ? 'on' : ''}"><input type="checkbox" data-focus="${k}" ${s.focus.includes(k) ? raw('checked') : ''}> ${v}</label>`)}
        </div>
      </div>
      <div class="card pad">
        <h3>Cars you own</h3>
        <p class="muted small">Tap to toggle. Owned cars drop out of the shopping list.</p>
        ${groups.map(([k, label]) => html`<div style="margin-top:14px"><div class="kicker" style="margin-bottom:8px">${label}</div><div class="chips">
          ${CARS.filter((c) => c.tier === k).map((c) => html`<button class="chip ${s.owned.includes(c.id) ? 'ok' : ''}" data-own="${c.id}" style="border:0">${s.owned.includes(c.id) ? '✓ ' : ''}${c.name.split(' (')[0]}</button>`)}
        </div></div>`)}
      </div>
    </div>
    <div class="row" style="margin-top:22px"><button class="btn red" id="su-save">Save & show my next moves</button></div>`,
    wire(root) {
      $$('[data-own]', root).forEach((b) => (b.onclick = () => {
        const id = b.dataset.own;
        store.set((s) => { s.owned = s.owned.includes(id) ? s.owned.filter((x) => x !== id) : [...s.owned, id]; });
        const on = S().owned.includes(id);
        b.classList.toggle('ok', on); b.textContent = (on ? '✓ ' : '') + carById[id].name.split(' (')[0];
      }));
      $$('[data-focus]', root).forEach((i) => (i.onchange = () => i.closest('.opt').classList.toggle('on', i.checked)));
      $('#su-save', root).onclick = () => {
        const v = $('#su-cr', root).value;
        store.set((s) => {
          s.credits = v === '' ? null : Math.max(0, +v);
          s.focus = $$('[data-focus]', root).filter((i) => i.checked).map((i) => i.dataset.focus);
          s.onboarded = true;
          if (!s.wish.length) s.wish = ['rsr991', 'porsche919', 'r34', 'mazda787b', 'mclarenf1', 'f250gto'].filter((id) => !s.owned.includes(id));
        });
        location.hash = '#/';
        toast('Saved. Your plan is ready.');
      };
    },
  };
};

let trackFilter = 'all', trackQuery = '';
views.tracks = () => {
  const list = TRACKS.filter((t) => (trackFilter === 'all' || (trackFilter === 'real' ? t.country !== 'GT original' : trackFilter === 'gt' ? t.country === 'GT original' : t.tags.some((x) => /sport|staple/i.test(x))))
    && (!trackQuery || (t.name + t.short + t.country).toLowerCase().includes(trackQuery.toLowerCase())))
    .sort((a, b) => b.fame - a.fame);
  return {
    html: html`
    <div class="kicker">${TRACKS.length} circuits · ${TRACKS.filter((t) => t.country !== 'GT original').length} real circuits · ${TRACKS.filter((t) => t.country === 'GT original').length} GT originals</div><h1>Track Guides</h1>
    <p class="muted" style="max-width:66ch;margin-top:10px">Corner by corner, sector by sector, with benchmark lap times and the car to bring. Real circuits use their actual geometry from OpenStreetMap; GT originals are traced from the in-game course maps.</p>
    <div class="row" style="margin:20px 0">
      <div class="seg">${[['all', 'All'], ['real', 'Real maps'], ['gt', 'GT originals'], ['sport', 'Sport staples']].map(([k, l]) => html`<button data-f="${k}" class="${trackFilter === k ? 'on' : ''}">${l}</button>`)}</div>
      <input type="search" id="tq" placeholder="Search tracks" value="${trackQuery}" style="max-width:260px">
    </div>
    <div class="grid g3">${list.map(trackCard)}</div>`,
    wire(root) {
      $$('[data-f]', root).forEach((b) => (b.onclick = () => { trackFilter = b.dataset.f; render(); }));
      const q = $('#tq', root);
      q.oninput = () => { trackQuery = q.value; const pos = q.selectionStart; render(); const n = $('#tq'); n.focus(); n.setSelectionRange(pos, pos); };
    },
  };
};

views.track = (id) => {
  const t = trackById[id];
  if (!t) return views.notfound();
  const s = S();
  const car = carById[t.car];
  const pb = s.pbs[t.id] || {};
  const classes = Object.keys(t.laps);
  return {
    html: html`
    ${back('#/tracks', 'Tracks')}
    <div class="row" style="justify-content:space-between;align-items:end">
      <div><div class="kicker">${t.flag} ${t.country} · ${t.layout} · ${t.km.toFixed(3)} km</div><h1>${t.short}</h1></div>
      <div class="chips">${t.tags.map((x) => html`<span class="chip blue">${x}</span>`)}</div>
    </div>
    <p class="muted" style="max-width:80ch;margin:12px 0 22px;font-size:17px">${t.blurb}</p>

    ${studioHtml(t)}

    <section class="section grid g2 ts-below">
      <div class="grid" style="gap:16px;align-content:start;grid-column:1/-1;grid-template-columns:repeat(auto-fit,minmax(320px,1fr))">
        <div class="card pad laps">
          <div class="row" style="justify-content:space-between"><h3>Benchmark Laps</h3><span class="chip gold">estimates · dry</span></div>
          <table style="margin-top:8px"><tr><th>Class</th><th>Alien</th><th>Fast</th><th>Solid</th><th>Your PB</th></tr>
            ${classes.map((k) => {
              const [a, f, so] = t.laps[k];
              const mine = toSec(pb[k]);
              const tier = mine == null ? '' : mine <= toSec(a) ? 'alien' : mine <= toSec(f) ? 'fast' : mine <= toSec(so) ? 'solid' : '';
              return html`<tr><td><b>${k}</b></td><td class="t alien">${a}</td><td class="t fast">${f}</td><td class="t solid">${so}</td>
                <td><input type="text" data-pb="${k}" value="${pb[k] || ''}" placeholder="m:ss.s" style="width:92px;padding:6px 8px;font-weight:700" class="${tier}"></td></tr>`;
            })}
          </table>
          <p class="muted small" style="margin:10px 0 0">Your PB turns purple, blue or green as you pass each tier. Benchmarks are calibrated estimates for BoP cars in the dry. Your own times are the real measure.</p>
        </div>
        <a class="card car-card gloss" href="#/car/${car.id}" style="display:grid;grid-template-columns:150px 1fr">
          <div class="ph" style="aspect-ratio:auto;height:100%">${raw(img(car.id))}</div>
          <div class="body"><div class="kicker">Recommended car</div><h3 style="font-size:22px">${car.name}</h3><div class="muted small" style="margin-top:4px">${t.carWhy}</div></div>
        </a>
        <div class="row">${t.alt.map((cid) => carById[cid] ? html`<a class="chip" href="#/car/${cid}">Alt: ${carById[cid].name.split(' (')[0]}</a>` : '')}</div>
      </div>
    </section>

    <section class="section">
      <div class="head"><h2>Sectors</h2></div>
      <div class="grid g3">${t.sectors.map((x, i) => html`<div class="card sector click" data-sec="${i}" style="--c:${SECTOR_COLORS[i]}">
        <div class="kicker" style="color:${SECTOR_COLORS[i]}">Sector ${i + 1}</div><h3 style="margin:4px 0 8px">${x.name.replace(/^S\d · /, '')}</h3>
        <p class="muted small">${x.focus}</p><div class="small"><b>Where the time is:</b> ${x.gain}</div></div>`)}</div>
    </section>

    <section class="section">
      <div class="head"><h2>Corner by Corner</h2><span class="muted small">Tap a corner or a pin on the map</span></div>
      <div class="corner-list" id="corners">${t.corners.map((c, i) => html`<div class="corner" data-i="${i}">
        <div class="ch"><span class="n">${c.n}</span><span class="nm">${c.name}</span>${c.key ? raw('<span class="chip red key">Key corner</span>') : ''}</div>
        <div class="facts"><span class="chip">${c.dir}</span><span class="chip dark">Gear ${c.gear}</span><span class="chip">${c.speed}</span><span class="chip blue">Brake: ${c.brake}</span></div>
        <div class="more"><p><b>Line.</b> ${c.line}</p><p style="margin:0"><b>Common mistake.</b> ${c.mistake}</p></div>
      </div>`)}</div>
    </section>

    ${raw(String(apexOnTrack(t.id)))}

    ${videosSection(t)}

    <section class="section grid g3">
      <div class="card pad"><div class="kicker">Practice drill</div><p style="margin-top:8px">${t.drill}</p></div>
      <div class="card pad"><div class="kicker">On a wheel</div><p style="margin-top:8px">${t.wheel}</p></div>
      <div class="card pad"><div class="kicker">Weather & night</div><p style="margin-top:8px">${t.weather}</p></div>
    </section>
    <section class="section grid g2">
      <div class="card pad"><div class="kicker">Setup</div><p style="margin-top:8px">${t.setup}</p></div>
      <div class="card pad"><div class="kicker">History</div><p style="margin-top:8px">${t.history}</p></div>
    </section>
    <section class="section card pad">
      <div class="kicker">Your notes</div>
      <textarea id="tnotes" rows="4" placeholder="Braking markers, setup tweaks, what clicked…" style="margin-top:10px">${s.trackNotes[t.id] || ''}</textarea>
    </section>`,
    wire(root) {
      wireVideos(root);
      wireStudio(root, t);
      $$('[data-pb]', root).forEach((i) => (i.onchange = () => {
        const v = i.value.trim();
        if (v && toSec(v) == null) { toast('Use m:ss.s, e.g. 2:18.4'); return; }
        store.set((s) => { s.pbs[t.id] = { ...(s.pbs[t.id] || {}), [i.dataset.pb]: v }; if (!v) delete s.pbs[t.id][i.dataset.pb]; });
        toast(v ? 'PB saved' : 'PB cleared'); render();
      }));
      const n = $('#tnotes', root);
      n.oninput = () => store.set((s) => { s.trackNotes[t.id] = n.value; });
    },
  };
};

let garageTab = 'all';
views.garage = () => {
  const s = S();
  const tabs = [['all', 'All'], ['race', 'Race'], ['hyper', 'Hyper'], ['legend', 'Legends'], ['heritage', 'Heritage'], ['wish', 'Wishlist'], ['owned', 'Owned']];
  const list = CARS.filter((c) => garageTab === 'all' || (garageTab === 'wish' ? s.wish.includes(c.id) : garageTab === 'owned' ? s.owned.includes(c.id) : c.tier === garageTab));
  if (garageTab === 'wish') list.sort((a, b) => s.wish.indexOf(a.id) - s.wish.indexOf(b.id));
  const wishTotal = s.wish.filter((id) => !s.owned.includes(id)).reduce((a, id) => a + (priceOf(s, id) || 0), 0);
  return {
    html: html`
    <div class="kicker">${CARS.length} cars · the buying ladder</div><h1>The Garage</h1>
    <p class="muted" style="max-width:66ch;margin-top:10px">Race cars that win you credits first, then hypercars, then the Legend collection. Plus the heritage cars GT was built on.</p>
    <div class="grid g4" style="margin:20px 0">
      <div class="card stat"><div class="v">${crShort(wishTotal)}</div><div class="l">Wishlist cost (unowned)</div></div>
      <div class="card stat"><div class="v">${s.credits == null ? '—' : crShort(Math.max(0, wishTotal - s.credits))}</div><div class="l">Still to earn</div></div>
      <div class="card stat"><div class="v">${hrs(hoursFor(s, Math.max(0, wishTotal - (s.credits || 0))))}</div><div class="l">At your best grind</div></div>
    </div>
    <div class="seg" style="margin-bottom:20px">${tabs.map(([k, l]) => html`<button data-t="${k}" class="${garageTab === k ? 'on' : ''}">${l}</button>`)}</div>
    <div class="grid g4">${list.length ? list.map(carCard) : raw('<p class="muted">Nothing here yet.</p>')}</div>`,
    wire(root) { $$('[data-t]', root).forEach((b) => (b.onclick = () => { garageTab = b.dataset.t; render(); })); },
  };
};

views.car = (id) => {
  const c = carById[id];
  if (!c) return views.notfound();
  const s = S();
  const own = s.owned.includes(id), wish = s.wish.includes(id);
  const p = priceOf(s, id);
  const gap = Math.max(0, (p || 0) - (s.credits || 0));
  return {
    html: html`
    ${back('#/garage', 'Garage')}
    <div class="car-hero">
      <div class="ph">${raw(img(c.id))}</div>
      <div>
        <div class="row"><span class="cls ${clsClass(c.cls)}">${c.cls}</span><span class="chip">${c.where}</span>${own ? raw('<span class="chip ok">✓ Owned</span>') : ''}</div>
        <div class="kicker" style="margin-top:14px">${c.make} · ${c.year}</div>
        <h1 style="font-size:clamp(36px,5vw,64px)">${c.name}</h1>
        <div class="price" style="font-family:var(--display);font-style:italic;font-weight:800;font-size:34px;color:var(--navy);margin:10px 0">${cr(p)}</div>
        ${!own && p ? html`<div class="muted">${s.credits == null ? 'Set your credits to see the gap.' : gap === 0 ? 'You can afford it now.' : `${cr(gap)} to go · about ${hrs(hoursFor(s, gap))} of grinding`}</div>` : ''}
        <div class="row" style="margin-top:16px">
          <button class="btn ${own ? 'ghost' : 'red'}" id="own">${own ? 'Owned ✓' : 'Mark owned'}</button>
          <button class="btn ${wish ? '' : 'ghost'}" id="wish">${wish ? '★ On wishlist' : '☆ Add to wishlist'}</button>
        </div>
        <label class="f" style="margin-top:16px;max-width:280px">Price you see in game<input type="number" id="price" value="${s.prices[id] ?? ''}" placeholder="${c.price}"></label>
      </div>
    </div>
    <section class="section grid g2">
      <div class="card pad">
        <div class="kicker">Why this car</div>
        <p class="pull" style="margin-top:10px">${c.why}</p>
        <ul class="pts">${c.strengths.map((x) => html`<li>${x}</li>`)}</ul>
      </div>
      <div class="card pad">
        <dl class="spec"><dt>Drivetrain</dt><dd>${c.drive}</dd><dt>Power</dt><dd>${c.power}</dd><dt>Class</dt><dd>${c.cls}</dd><dt>Where</dt><dd>${c.where}</dd></dl>
        <div class="kicker" style="margin-top:18px">Setup note</div><p style="margin-top:6px">${c.tune}</p>
        <div class="kicker" style="margin-top:14px">Best at</div>
        <div class="chips" style="margin-top:8px">${c.bestAt.map((tid) => trackById[tid] ? html`<a class="chip blue" href="#/track/${tid}">${trackById[tid].flag} ${trackById[tid].short}</a>` : '')}</div>
      </div>
    </section>`,
    wire(root) {
      $('#own', root).onclick = () => { store.set((s) => { s.owned = own ? s.owned.filter((x) => x !== id) : [...s.owned, id]; if (!own && typeof s.credits === 'number' && p && confirm(`Deduct ${cr(p)} from your credits?`)) s.credits = Math.max(0, s.credits - p); }); render(); };
      $('#wish', root).onclick = () => { store.set((s) => { s.wish = wish ? s.wish.filter((x) => x !== id) : [...s.wish, id]; }); render(); };
      $('#price', root).onchange = (e) => { store.set((s) => { if (e.target.value === '') delete s.prices[id]; else s.prices[id] = +e.target.value; }); render(); };
    },
  };
};

views.credits = () => {
  const s = S();
  const rows = grindRows(s);
  const target = s.wish.find((id) => !s.owned.includes(id));
  return {
    html: html`
    <div class="kicker">Credit Engine</div><h1>Make It Rain</h1>
    <p class="muted" style="max-width:66ch;margin-top:10px">Payouts change with patches. Every number below is editable and your edits win. Log runs and the bank updates.</p>
    <div class="card pad" style="margin-top:20px">
        <label class="f">Your credits<input type="number" id="cr" value="${s.credits ?? ''}" placeholder="e.g. 4200000"></label>
        <label class="opt ${s.grind.clean ? 'on' : ''}" style="margin-top:12px"><input type="checkbox" id="clean" ${s.grind.clean ? raw('checked') : ''}> Count the clean race bonus (+${CLEAN_BONUS * 100}%)</label>
        ${s.creditsSource === 'gt7' ? html`<p class="muted small" style="margin:10px 0 0">Credits come from your GT7 stats (GT-Gridstats) and refresh automatically.</p>` : ''}
    </div>
    <div class="grid g3" style="margin-top:16px">
      <div class="card stat"><div class="v">${rows[0]?.perHour ? crShort(rows[0].perHour) : '—'}<span style="font-size:20px">/hr</span></div><div class="l">Best grind · ${rows[0]?.name || ''}</div></div>
      ${target ? html`<a class="card stat" href="#/car/${target}"><div class="v">${hrs(hoursFor(s, Math.max(0, priceOf(s, target) - (s.credits || 0))))}</div><div class="l">To ${carById[target].name.split(' (')[0]}</div></a>` : raw('<a class="card stat" href="#/garage"><div class="v">★</div><div class="l">Add a wishlist target</div></a>')}
    </div>
    <section class="section">
      <div class="head"><h2>Grinds</h2><span class="muted small">Ranked by credits per hour${s.grind.clean ? ', clean race bonus included' : ''}</span></div>
      <div class="grid g2">
        ${rows.map((r, i) => html`<div class="card pad grind ${i === 0 && r.perHour ? 'best' : ''}">
          <div class="row" style="justify-content:space-between;align-items:start">
            <div><div class="kicker">${i === 0 && r.perHour ? 'Best right now' : r.track && trackById[r.track] ? trackById[r.track].short : r.layout}</div><h3 style="margin-top:4px">${r.name}</h3>
              <div class="muted small">${r.track && trackById[r.track] ? raw(`<a href="#/track/${r.track}" style="text-decoration:underline">${esc(trackById[r.track].short)}</a> · `) : ''}${r.layout}${r.pp ? ` · ${r.pp} PP` : ''} · ${r.minutes} min</div></div>
            <div class="grind-rate"><b>${r.perHour ? crShort(r.perHour) : '—'}</b><span>per hour</span></div>
          </div>
          <p style="margin:12px 0 6px">${r.why}</p>
          <p class="muted small" style="margin:0 0 14px"><b>How:</b> ${r.how}</p>
          <div class="grind-inputs">
            <label class="f">Win payout<input type="number" inputmode="numeric" data-pay="${r.id}" value="${r.payout ?? ''}" placeholder="enter"></label>
            <label class="f">Minutes<input type="number" inputmode="numeric" data-min="${r.id}" value="${r.minutes}"></label>
          </div>
          <div class="row" style="justify-content:space-between;margin-top:14px">
            <span class="muted">Per race <b style="color:var(--navy);font-family:var(--display);font-style:italic;font-size:22px">${r.per ? crShort(r.per) : '—'}</b></span>
            ${r.per ? html`<button class="btn red" data-log="${r.id}">+ Log a run</button>` : html`<span class="chip gold">Enter the payout</span>`}
          </div>
        </div>`)}
      </div>
    </section>
    <section class="section">
      <div class="head"><h2>Boosters</h2></div>
      <div class="grid g3">${BOOSTERS.map((b) => html`<div class="card pad"><h3 style="font-size:22px">${b.name}</h3><p class="muted small" style="margin:6px 0">${b.what}</p><div class="small"><b>Value:</b> ${b.value}</div></div>`)}</div>
    </section>
    ${s.grind.log.length ? html`<section class="section card pad"><h3>Run log</h3><div class="muted small" style="margin-top:8px">${s.grind.log.slice(-12).reverse().map((l) => html`<div>${new Date(l.t).toLocaleString()} · ${l.name} · +${cr(l.amount)}</div>`)}</div></section>` : ''}`,
    wire(root) {
      $('#cr', root).onchange = (e) => { store.set((s) => { s.credits = e.target.value === '' ? null : +e.target.value; }); render(); };
      $('#clean', root).onchange = (e) => { store.set((s) => { s.grind.clean = e.target.checked; }); render(); };
      $$('[data-pay]', root).forEach((i) => (i.onchange = () => { store.set((s) => { if (i.value === '') delete s.grind.payouts[i.dataset.pay]; else s.grind.payouts[i.dataset.pay] = +i.value; }); render(); }));
      $$('[data-min]', root).forEach((i) => (i.onchange = () => { store.set((s) => { s.grind.minutes[i.dataset.min] = Math.max(1, +i.value); }); render(); }));
      $$('[data-log]', root).forEach((b) => (b.onclick = () => {
        const r = rows.find((x) => x.id === b.dataset.log);
        store.set((s) => { s.credits = (s.credits || 0) + r.per; s.grind.log.push({ t: Date.now(), id: r.id, name: r.name, amount: r.per }); });
        toast(`+${cr(r.per)}`); render();
      }));
    },
  };
};

views.roadmap = () => {
  const s = S();
  const pr = progress(s);
  return {
    html: html`
    <div class="kicker">${pr.done}/${pr.total} complete</div><h1>The Roadmap</h1>
    <p class="muted" style="max-width:66ch;margin-top:10px">From "Café finished" to alien pace. Tick things off and the Command Centre re-plans.</p>
    <div class="bar red" style="height:12px;margin:18px 0 8px;max-width:520px"><i style="width:${pr.pct}%"></i></div>
    <div class="grid" style="gap:18px;margin-top:22px">
      ${PHASES.map((ph) => {
        const d = ph.steps.filter((st) => isDone(s, st)).length;
        return html`<div class="card phase">
          <div class="ph-h"><div><div class="kicker">${ph.kicker}</div><h2>${ph.title}</h2></div><span class="chip ${d === ph.steps.length ? 'ok' : 'blue'}">${d}/${ph.steps.length}</span></div>
          <p class="muted" style="margin:10px 0 14px;max-width:80ch">${ph.blurb}</p>
          <div class="grid" style="gap:8px">${ph.steps.map((st) => html`<div class="check ${isDone(s, st) ? 'done' : ''}" data-step="${st.id}">
            <span class="box"></span><div><div class="t">${st.title}</div><div class="d">${st.how}</div></div>
            ${st.car ? raw(`<a class="chip" href="#/car/${st.car}" style="margin-left:auto" onclick="event.stopPropagation()">Car →</a>`) : ''}
          </div>`)}</div>
        </div>`;
      })}
    </div>`,
    wire(root) {
      $$('[data-step]', root).forEach((el) => (el.onclick = () => {
        const id = el.dataset.step;
        store.set((s) => { if (s.done[id]) delete s.done[id]; else s.done[id] = true; });
        render();
      }));
    },
  };
};

views.academy = () => {
  const s = S();
  return {
    html: html`
    <div class="kicker">Racecraft Academy</div><h1>Go Faster</h1>
    <p class="muted" style="max-width:66ch;margin-top:10px">Twelve lessons from the racing line to alien technique. Every one has an input simulator: the wheel, pedals and G-forces of a fast lap, frame by frame.</p>
    <a class="card pad gloss apex-band" href="#/systems" style="display:block;margin-top:12px"><div class="kicker">Race Systems</div><h3 style="margin:6px 0">Pits, fuel, tyres, TCS, ABS, brake balance, the MFD</h3><div class="muted small">What each one does and exactly how to use it in a race.</div></a>
    <a class="card pad gloss apex-band" href="#/apex" style="display:block;margin-top:18px"><div class="kicker">Beyond the Apex · the official GT7 manual</div><h3 style="margin:6px 0">${nextApex() ? 'Next concept: ' + nextApex().title : 'All concepts driven ✓'}</h3><div class="muted small">Polyphony's own explanations, each demonstrated on the corners where you feel it.</div></a>
    <div class="grid g3" style="margin-top:22px">${LESSONS.map((l) => html`<a class="card pad lesson-card gloss" href="#/lesson/${l.id}">
      <span class="n">${String(l.n).padStart(2, '0')}</span>
      <div class="row"><span class="chip ${l.level === 'Alien' ? 'red' : l.level === 'Core' ? 'blue' : ''}">${l.level}</span>${l.widget ? raw('<span class="chip gold">Interactive</span>') : ''}${s.lessons[l.id] ? raw('<span class="chip ok">✓</span>') : ''}</div>
      <h3 style="margin:12px 0 8px;max-width:80%">${l.title}</h3><p class="muted small" style="margin:0">${l.hook}</p></a>`)}</div>`,
  };
};

views.lesson = (id) => {
  const l = LESSONS.find((x) => x.id === id);
  if (!l) return views.notfound();
  const i = LESSONS.indexOf(l), next = LESSONS[i + 1];
  const done = S().lessons[id];
  return {
    html: html`
    ${back('#/academy', 'Academy')}
    <div class="kicker">Lesson ${l.n} · ${l.level}</div><h1>${l.title}</h1>
    ${SCENARIOS[id] ? simBlock(id) : ''}
    <div class="grid g2" style="margin-top:22px;align-items:start">
      <div class="prose"><p class="pull">${l.hook}</p>${l.body.map((p) => html`<p>${p}</p>`)}</div>
      <div class="grid" style="gap:16px">
        ${l.widget && !SCENARIOS[id] ? raw('<div class="widget" id="widget"></div>') : ''}
        <div class="card pad"><div class="kicker">Remember</div><ul class="pts" style="margin-top:10px">${l.points.map((p) => html`<li>${p}</li>`)}</ul></div>
      </div>
    </div>
    <section class="section grid g2">
      <div class="card pad"><div class="kicker">Drill</div><p style="margin-top:8px">${l.drill}</p></div>
      <div class="card pad"><div class="kicker">On a wheel</div><p style="margin-top:8px">${l.wheel}</p></div>
    </section>
    <div class="row" style="margin-top:22px">
      <button class="btn ${done ? 'ghost' : 'red'}" id="ldone">${done ? 'Completed ✓' : 'Mark lesson complete'}</button>
      ${next ? html`<a class="btn ghost" href="#/lesson/${next.id}">Next: ${next.title} →</a>` : ''}
    </div>`,
    wire(root) {
      const w = $('#widget', root);
      if (w) mountWidget(l.widget, w);
      const sm = $('#sim', root); if (sm) mountSim(sm, id);
      $('#ldone', root).onclick = () => {
        store.set((s) => { s.lessons[id] = !s.lessons[id]; if (LESSONS.every((x) => s.lessons[x.id])) s.done.academy = true; });
        render();
      };
    },
  };
};

let solverSel = null;
views.tuning = () => html`
  <div class="kicker">Tuning Lab</div><h1>Read the Car</h1>
  <p class="muted" style="max-width:66ch;margin-top:10px">Driver first, setup second. Tell the solver what the car is doing.</p>
  <section class="section card pad">
    <h3>Symptom → Fix</h3>
    <div class="chips" style="margin:12px 0">${SOLVER.map((x) => html`<button class="chip ${solverSel === x.id ? 'dark' : ''}" data-sol="${x.id}" style="border:0;font-size:14px;padding:8px 14px">${x.symptom}</button>`)}</div>
    ${solverSel ? (() => { const x = SOLVER.find((y) => y.id === solverSel); return html`<ol style="margin:8px 0 0;padding-left:22px;display:grid;gap:6px">${x.fixes.map((f, i) => html`<li style="${i === 0 ? 'font-weight:700' : ''}">${f}</li>`)}</ol><p class="muted small" style="margin-top:10px">Change one thing at a time, then run three laps.</p>`; })() : raw('<p class="muted">Pick a symptom.</p>')}
  </section>
  <section class="section"><div class="head"><h2>Every Setting</h2></div>
    <div class="grid g3">${SETTINGS.map((x) => html`<div class="card pad"><h3 style="font-size:22px">${x.name}</h3><p class="muted small" style="margin:6px 0">${x.what}</p><div class="small"><b>Tip:</b> ${x.tip}</div></div>`)}</div>
  </section>`;
const tuningWire = (root) => $$('[data-sol]', root).forEach((b) => (b.onclick = () => { solverSel = solverSel === b.dataset.sol ? null : b.dataset.sol; render(); }));

views.sport = () => html`
  <div class="kicker">Sport Mode</div><h1>Race People</h1>
  <p class="muted" style="max-width:66ch;margin-top:10px">${BOP}</p>
  <section class="section grid g2">${Object.values(RATINGS).map((r) => html`<div class="card pad">
    <h3>${r.name}</h3>
    <div class="row" style="margin:14px 0;gap:6px">${r.ladder.map((x, i) => html`<span style="flex:1;text-align:center;padding:10px 0;border-radius:8px;font-family:var(--display);font-style:italic;font-weight:800;font-size:22px;color:#fff;background:hsl(${220 - i * 8} 70% ${22 + i * 7}%)">${x}</span>`)}</div>
    <p class="muted" style="margin:0">${r.what}</p></div>`)}</section>
  <section class="section"><div class="head"><h2>How to Climb</h2></div>
    <div class="grid g3">${SPORT_GUIDE.map((x, i) => html`<div class="card pad"><div class="kicker">${String(i + 1).padStart(2, '0')}</div><h3 style="font-size:22px;margin:4px 0 8px">${x.t}</h3><p class="muted small" style="margin:0">${x.d}</p></div>`)}</div>
  </section>`;

views.wheel = () => {
  const s = S();
  const b = BASES.find((x) => x.id === s.wheelBase);
  return {
    html: html`
    <div class="kicker">Wheel Lab</div><h1>Dial It In</h1>
    <p class="muted" style="max-width:70ch;margin-top:10px">GT7 has two steering FFB sliders: <b>Max Torque</b> and <b>Sensitivity</b>. Everything else lives on your wheel base. The sources disagree, so here are tested starting points plus the method to find your own.</p>
    <section class="section card pad">
      <h3>Your wheel base</h3>
      <div class="grid g2" style="gap:8px;margin-top:12px">${BASES.map((x) => html`<label class="opt ${s.wheelBase === x.id ? 'on' : ''}"><input type="radio" name="wb" value="${x.id}" ${s.wheelBase === x.id ? raw('checked') : ''}> <span>${x.name}<br><span class="muted small">${x.kind}</span></span></label>`)}</div>
    </section>
    ${b ? html`<section class="section grid g2">
      <div class="card pad" style="background:linear-gradient(135deg,#0b1f4b,#13306e);color:#fff">
        <div class="kicker" style="color:#ff8a90">In GT7 · Options → Controller → Steering wheel</div>
        <div class="row" style="gap:28px;margin-top:14px">
          <div><div style="font-family:var(--display);font-style:italic;font-weight:900;font-size:56px;line-height:1">${b.ingame.torque}</div><div style="color:#9fb3e6;font-weight:600">FFB Max Torque</div></div>
          <div><div style="font-family:var(--display);font-style:italic;font-weight:900;font-size:56px;line-height:1">${b.ingame.sens}</div><div style="color:#9fb3e6;font-weight:600">FFB Sensitivity</div></div>
        </div>
        <p style="color:#c8d2ea;margin:16px 0 0">${b.notes}</p>
      </div>
      <div class="card pad"><h3>On the base</h3><table class="tbl" style="margin-top:8px">${b.base.map(([k, v]) => html`<tr><td><b>${k}</b></td><td class="num" style="font-size:17px">${v}</td></tr>`)}</table></div>
    </section>` : ''}
    <section class="section grid g2">
      <div class="card pad"><h3>The method</h3><ol style="margin:12px 0 0;padding-left:22px;display:grid;gap:8px">${METHOD.map((m) => html`<li>${m}</li>`)}</ol></div>
      <div class="card pad"><h3>Your numbers</h3><textarea id="wnotes" rows="8" placeholder="Torque 9, Sens 1, NDP 40 — Gr.3 feels right, Gr.1 a touch strong…" style="margin-top:12px">${s.wheelNotes}</textarea></div>
    </section>
    <section class="section"><div class="head"><h2>Pedals & Assists</h2></div>
      <div class="grid g3">${PEDALS.map((p) => html`<div class="card pad"><h3 style="font-size:21px">${p.t}</h3><p class="muted small" style="margin:6px 0 0">${p.d}</p></div>`)}</div>
    </section>
    <section class="section card pad"><h3>Seating & view</h3><ul class="pts" style="margin-top:12px">${SEATING.map((x) => html`<li style="font-weight:500">${x}</li>`)}</ul></section>`,
    wire(root) {
      $$('input[name=wb]', root).forEach((i) => (i.onchange = () => { store.set((s) => { s.wheelBase = i.value; }); render(); }));
      const n = $('#wnotes', root);
      n.oninput = () => store.set((s) => { s.wheelNotes = n.value; if (n.value.trim()) s.done['wheel-setup'] = true; });
    },
  };
};

views.more = () => html`
  <div class="kicker">More</div><h1>Everything Else</h1>
  <div class="grid g3" style="margin-top:22px">
    ${[['#/academy', 'Racecraft Academy', 'Lessons + interactive diagrams'], ['#/apex', 'Beyond the Apex', 'The official manual, on specific corners'], ['#/systems', 'Race Systems', 'Pits, fuel, tyres, TCS, ABS, MFD'], ['#/wheel', 'Wheel Lab', 'FFB, pedals, seating'], ['#/tuning', 'Tuning Lab', 'Settings + solver'], ['#/sport', 'Sport Mode', 'DR, SR and how to climb'], ['#/start', 'Start Here', 'How to play GT from zero'], ['#/roadmap', 'Roadmap', 'Post-Café to alien pace'], ['#/heritage', 'Heritage', '30 years of GT: the cars and the story'], ['#/setup', 'Setup', 'Credits, owned cars, goals'], ['#/connect', 'PlayStation + GT7', 'Your real credits, licence, DR/SR, trophies'], ['#/account', 'Cloud save', 'Sign in once, same save everywhere'], ['#/telemetry', 'Data Logger', 'Record laps, replay your racing line'], ['#/status', 'Build status', 'What\'s done and what\'s next']].map(([h, t, d]) => html`<a class="card pad gloss" href="${h}"><h3>${t}</h3><div class="muted small" style="margin-top:6px">${d}</div></a>`)}
  </div>
  <section class="section card pad">
    <h3>Your data</h3>
    <p class="muted small">Saved on this device only. Export to move it to another device.</p>
    <div class="row"><button class="btn sm" id="exp">Export</button><button class="btn sm ghost" id="imp">Import</button><button class="btn sm ghost" id="rst" style="color:var(--red);box-shadow:inset 0 0 0 2px var(--red)">Reset everything</button></div>
  </section>
  <section class="section card pad small muted">
    <h3 style="color:var(--ink)">Sources & credits</h3>
    <p style="margin-top:8px">Track geometry © OpenStreetMap contributors (ODbL). Car photos: Wikimedia Commons (see data/credits.json for each file and licence). Credit payouts: racinggames.gg, Coach Dave Academy. Wheel settings: GTPlanet, Fanatec forum, Coach Dave, dg-edge, simracingsetup. GT original layouts: traced from the in-game course maps (via the Gran Turismo Wiki); descriptions from GTPlanet, Traxion. Gran Turismo and the GT logo are trademarks of Sony Interactive Entertainment. Fan-made, personal use.</p>
  </section>`;
const moreWire = (root) => {
  $('#exp', root).onclick = async () => { const t = store.exportJSON(); try { await navigator.clipboard.writeText(t); toast('Copied to clipboard'); } catch { prompt('Copy this:', t); } };
  $('#imp', root).onclick = () => { const t = prompt('Paste exported data'); if (t) { try { store.importJSON(t); toast('Imported'); render(); } catch { toast('That didn\'t parse'); } } };
  $('#rst', root).onclick = () => { if (confirm('Erase all your data on this device?')) { store.reset(); toast('Reset'); location.hash = '#/'; } };
};

let heritageSel = TIMELINE.length - 1;
views.heritage = () => {
  const e = TIMELINE[heritageSel];
  return {
    html: html`
    <div class="kicker">Heritage · 1997–${new Date().getFullYear()}</div><h1>30 Years of GT</h1>
    <p class="muted" style="max-width:66ch;margin-top:10px">The Real Driving Simulator: where it came from, the cars that built it, and why it matters to the brands in your garage. Tap through the years.</p>
    <section class="section">
      <div class="timeline" id="tl">${TIMELINE.map((x, i) => html`<button class="tl-dot ${i === heritageSel ? 'on' : ''} ${x.big ? 'big' : ''}" data-i="${i}"><b>${x.year}</b><span>${x.title}</span></button>`)}</div>
      <div class="card pad tl-card fade-in" style="margin-top:16px">
        <div class="row" style="justify-content:space-between"><div class="kicker">${e.year} · ${e.platform}</div><div class="row"><button class="btn sm ghost" data-step="-1">←</button><button class="btn sm ghost" data-step="1">→</button></div></div>
        <h2 style="margin:8px 0 12px">${e.title}</h2>
        <p style="font-size:18px;color:var(--ink-2);max-width:75ch;margin:0">${e.text}</p>
      </div>
    </section>
    ${CHAPTERS.map((c) => html`<section class="section">
      <div class="head"><h2>${c.title}</h2></div>
      <div class="prose">${c.text.map((t) => html`<p>${t}</p>`)}</div>
      ${c.cars ? html`<div class="grid g4" style="margin-top:14px">${c.cars.filter((id) => carById[id]).map((id) => carCard(carById[id]))}</div>` : ''}
    </section>`)}`,
    wire(root) {
      $$('.tl-dot', root).forEach((b) => (b.onclick = () => { heritageSel = +b.dataset.i; render(); }));
      $$('[data-step]', root).forEach((b) => (b.onclick = () => { heritageSel = (heritageSel + +b.dataset.step + TIMELINE.length) % TIMELINE.length; render(); }));
      $('.tl-dot.on', root)?.scrollIntoView({ inline: 'center', block: 'nearest' });
    },
  };
};



views.account = () => {
  const i = sync.info();
  const when = i.lastSync ? new Date(i.lastSync).toLocaleTimeString() : 'not yet';
  return {
    html: html`
    ${back('#/more', 'More')}
    <div class="kicker">Cloud save</div><h1>${i.user ? 'Signed In' : 'Sign In Once'}</h1>
    ${i.user ? html`
      <div class="grid g3" style="margin-top:20px">
        <div class="card stat"><div class="v" style="font-size:30px">${i.user}</div><div class="l">PSN ID</div></div>
        <div class="card stat"><div class="v" style="font-size:30px;color:${i.status === 'live' ? 'var(--ok)' : 'var(--warn)'}">${i.status === 'live' ? 'Live' : i.status === 'connecting' ? 'Connecting…' : i.status}</div><div class="l">${i.brokers}/3 relays connected</div></div>
        <div class="card stat"><div class="v" style="font-size:30px">${when}</div><div class="l">Last synced</div></div>
      </div>
      <p class="muted" style="max-width:70ch;margin-top:18px">Open the app on any other device, sign in with the same PSN ID and passphrase, and your whole save follows: credits, garage, wishlist, PBs, roadmap, notes, wheel settings and laps. Changes sync within seconds while both are open.</p>
      <div class="row" style="margin-top:12px"><button class="btn" id="snow">Sync now</button><button class="btn ghost" id="sout">Sign out on this device</button></div>`
    : html`
      <div class="grid g2" style="margin-top:20px;align-items:start">
        <div class="card pad">
          <label class="f">PSN ID<input type="text" id="au" autocomplete="username" placeholder="e.g. your PSN online ID"></label>
          <label class="f" style="margin-top:12px">Passphrase (pick one, remember it)<input type="password" id="ap" autocomplete="current-password" placeholder="at least 8 characters"></label>
          <div class="row" style="margin-top:16px"><button class="btn red" id="ain">Sign in & sync</button></div>
          <p class="muted small" style="margin-top:12px">First sign-in creates your cloud save from what's on this device. Every other device: same two fields, once.</p>
        </div>
        <div class="card pad">
          <h3>How it works</h3>
          <ul class="pts" style="margin-top:10px">
            <li style="font-weight:500">Your save is encrypted on the device with a key made from your PSN ID + passphrase. The passphrase never leaves the device.</li>
            <li style="font-weight:500">The encrypted copy is kept on three public relays. Every device you sign in on re-uploads it, so it persists.</li>
            <li style="font-weight:500">Lose the passphrase and the cloud copy can't be opened. Your devices still have it, and Export in More is a backup.</li>
          </ul>
        </div>
      </div>`}
    <section class="section card pad">
      <div class="kicker">Why not "Sign in with PlayStation"?</div>
      <p style="margin-top:8px;max-width:80ch">Sony doesn't offer PSN sign-in to third-party apps, and GT7 has no public API for your garage, credits or results. Nothing outside the game can read them, so here you type credits once and tick cars off. The real live data GT7 does publish is its <b>telemetry</b> stream from the PS5 (speed, revs, throttle, brake, gear, tyres, position on track). The Data Logger reads that: it records your laps and replays your actual racing line. <a href="#/telemetry" style="text-decoration:underline">Open the Data Logger →</a></p>
    </section>
    <section class="section card pad">
      <div class="kicker">Optional · per-corner video moments</div><h3 style="margin:6px 0 8px">YouTube API key</h3>
      <p class="muted" style="max-width:72ch">With a free key, track pages read each video's chapter list straight from YouTube and link every corner to the exact second it's explained. The key stays on this device. Get one at <a href="https://console.cloud.google.com/apis/library/youtube.googleapis.com" target="_blank" rel="noopener" style="text-decoration:underline">Google Cloud → YouTube Data API v3</a> → Credentials → Create API key.</p>
      <label class="f" style="max-width:520px;margin-top:10px">API key<input type="password" id="ytkey" autocomplete="off" placeholder="AIza…" value="${S().ytKey || ''}"></label>    </section>`,
    wire(root) {
      $('#ytkey', root).onchange = (e) => { store.set((s) => { s.ytKey = e.target.value.trim(); }); toast(e.target.value.trim() ? 'YouTube key saved' : 'YouTube key removed'); };
      const ain = $('#ain', root);
      if (ain) ain.onclick = async () => {
        const u = $('#au', root).value.trim(), p = $('#ap', root).value;
        if (!u || p.length < 8) { toast('PSN ID and an 8+ character passphrase'); return; }
        ain.disabled = true; ain.textContent = 'Signing in…';
        try { await sync.signIn(u, p); toast('Signed in. Syncing.'); } catch (e) { toast(e.message); }
        render();
      };
      const so = $('#sout', root); if (so) so.onclick = () => { if (confirm('Sign out on this device? Your data stays here and in the cloud.')) { sync.signOut(); render(); } };
      const sn = $('#snow', root); if (sn) sn.onclick = async () => { await sync.syncNow(); toast('Synced'); render(); };
    },
  };
};

views.status = () => {
  const col = { done: 'ok', doing: 'gold', next: 'blue', later: '' };
  const lab = { done: 'Done', doing: 'In progress', next: 'Next', later: 'Later' };
  const n = BUILD.filter((b) => b.s === 'done').length;
  return html`
    ${back('#/more', 'More')}
    <div class="kicker">${n}/${BUILD.length} shipped</div><h1>Build Status</h1>
    <div class="bar red" style="height:12px;margin:18px 0 22px;max-width:520px"><i style="width:${(n / BUILD.length) * 100}%"></i></div>
    <div class="grid" style="gap:8px;max-width:820px">${BUILD.map((b) => html`<div class="check ${b.s === 'done' ? 'done' : ''}" style="cursor:default"><span class="box"></span><div class="t" style="flex:1">${b.t}</div><span class="chip ${col[b.s]}">${lab[b.s]}</span></div>`)}</div>`;
};

views.start = (arg) => (arg ? chapterView(arg) : startView());
views.apex = (arg) => (arg ? apexView(arg) : apexIndex());
views.systems = (arg) => (arg ? systemView(arg) : systemsIndex());

views.connect = () => {
  const s = S(), p = s.psn, g = s.gt, st = g?.stats || {};
  const ago = (t) => { if (!t) return 'never'; const m = Math.round((Date.now() - t) / 60000); return m < 1 ? 'just now' : m < 60 ? m + ' min ago' : m < 1440 ? Math.round(m / 60) + ' h ago' : Math.round(m / 1440) + ' days ago'; };
  const tro = p?.gt7?.trophies || [];
  const nextT = connect.nextTrophies(s, 6);
  const ec = p?.gt7?.earnedCounts || {}, dc = p?.gt7?.definedCounts || {};
  const icon = { platinum: '💎', gold: '🥇', silver: '🥈', bronze: '🥉' };
  return {
    html: html`
    ${back('#/more', 'More')}
    <div class="kicker">Accounts</div><h1>Connect Your Game</h1>
    <p class="muted" style="max-width:72ch;margin-top:10px">Two connections. Once they're in, the app reads where you really are (credits, licence, garage, ratings, trophies) and every next move is built on it.</p>

    <section class="section grid g2" style="align-items:start">
      <div class="card pad acct">
        <div class="acct-h"><span class="acct-logo psn">PS</span><div><div class="kicker">PlayStation Network</div><h2 style="font-size:34px">${p?.profile?.onlineId || (p ? 'Connected' : 'Not connected')}</h2></div>
          ${p?.profile?.avatar ? html`<img src="${p.profile.avatar}" alt="" class="avatar">` : ''}</div>
        ${p ? html`
          <div class="grid g3" style="gap:10px;margin-top:16px">
            <div class="mini"><b>${p.gt7 ? p.gt7.progress + '%' : '—'}</b><span>GT7 trophies</span></div>
            <div class="mini"><b>${p.play?.hours != null ? Math.round(p.play.hours) + ' h' : '—'}</b><span>GT7 played</span></div>
            <div class="mini"><b>${p.profile?.level ?? '—'}</b><span>Trophy level</span></div>
          </div>
          ${p.gt7 ? html`<div class="row" style="margin-top:12px">${['platinum', 'gold', 'silver', 'bronze'].map((k) => html`<span class="chip">${icon[k]} ${ec[k] ?? 0}/${dc[k] ?? 0}</span>`)}</div>` : ''}
          <p class="muted small" style="margin-top:12px">Updated ${ago(p.fetchedAt)}${p.errors?.length ? ' · some parts unavailable: ' + p.errors.join('; ') : ''}</p>
          <div class="row" style="margin-top:12px"><button class="btn" id="psn-refresh">Refresh</button><button class="btn ghost" id="psn-off">Disconnect</button></div>`
        : html`
          ${psnWizard()}`}
      </div>

      <div class="card pad acct">
        <div class="acct-h"><span class="acct-logo gt">GT</span><div><div class="kicker">Gran Turismo 7 stats</div><h2 style="font-size:34px">${g ? (g.Nickname || g.PSN_ID) : 'Not connected'}</h2></div></div>
        ${g ? html`
          <div class="grid g3" style="gap:10px;margin-top:16px">
            <div class="mini"><b>${crShort(st.total_credits)}</b><span>Credits</span></div>
            <div class="mini"><b>${g.DR || '—'} / ${g.SR || '—'}</b><span>DR / SR</span></div>
            <div class="mini"><b>${st.license || '—'}</b><span>Licence</span></div>
            <div class="mini"><b>${st.garage_count ?? '—'}</b><span>Cars · ${st.collection_progress || '—'}</span></div>
            <div class="mini"><b>${st.victories ?? 0}/${st.total_races ?? 0}</b><span>Wins / races</span></div>
            <div class="mini"><b>${st.clean_races ?? 0}</b><span>Clean races</span></div>
          </div>
          <p class="muted small" style="margin-top:12px">${st.play_time_readable || ''}${st.distance_km ? ' · ' + st.distance_km + ' km driven' : ''} · GT-Gridstats synced ${g.last_sync || '—'} · fetched ${ago(g.fetchedAt)}</p>
          <div class="row" style="margin-top:12px"><button class="btn" id="gt-refresh">Refresh</button><button class="btn ghost" id="gt-off">Disconnect</button></div>`
        : html`
          <ol class="steps">
            <li>Make a free account at <a href="https://gtgridstats.com" target="_blank" rel="noopener">GT-Gridstats</a> and create a personal API token.</li>
            <li>Enter your PSN ID and the token. The app pulls your GT7 profile: credits, licence, garage, DR/SR, races.</li>
          </ol>
          <label class="f" style="margin-top:8px">PSN ID<input type="text" id="gt-id" value="${s.gtLink?.psnId || p?.profile?.onlineId || sync.info().user || ''}" autocomplete="off"></label>
          <label class="f" style="margin-top:12px">GT-Gridstats token<input type="password" id="gt-tok" value="${s.gtLink?.token || ''}" autocomplete="off"></label>
          <div class="row" style="margin-top:14px"><button class="btn red xl" id="gt-go">Connect GT7 stats</button></div>
          <p class="muted small" style="margin-top:12px">GT-Gridstats is an unofficial third-party service (not Polyphony). Its data is as fresh as its last sync of your profile. The token is stored in your encrypted save.</p>`}
      </div>
    </section>

    ${nextT.length ? html`<section class="section"><div class="head"><h2>Your Next Trophies</h2><span class="muted small">Easiest unearned first, by % of players</span></div>
      <div class="grid g3">${nextT.map((t) => html`<div class="card pad trophy"><div class="row" style="gap:12px">${t.icon ? html`<img src="${t.icon}" alt="" class="t-icon">` : ''}<div><div class="kicker">${icon[t.type] || ''} ${t.type}${t.rate != null ? ' · ' + t.rate + '% have it' : ''}</div><h3 style="font-size:22px;margin-top:4px">${t.name}</h3></div></div><p class="muted" style="margin:10px 0 0">${t.detail}</p></div>`)}</div></section>` : ''}

    ${tro.length ? html`<section class="section"><div class="head"><h2>All GT7 Trophies</h2><span class="muted small">${tro.filter((t) => t.earned).length}/${tro.length} earned</span></div>
      <div class="grid" style="gap:8px">${tro.slice().sort((a, b) => (a.earned - b.earned) || ((b.rate ?? -1) - (a.rate ?? -1))).map((t) => html`<div class="check ${t.earned ? 'done' : ''}" style="cursor:default"><span class="box"></span><div style="flex:1"><div class="t">${t.hidden && !t.earned ? 'Hidden trophy' : t.name}</div><div class="d">${t.hidden && !t.earned ? '' : t.detail}</div></div><span class="chip">${icon[t.type] || ''}${t.rate != null ? ' ' + t.rate + '%' : ''}</span></div>`)}</div></section>` : ''}`,
    wire(root) {
      const busy = (b, label) => { b.disabled = true; b.dataset.l = b.textContent; b.textContent = label; };
      const done = (b) => { b.disabled = false; b.textContent = b.dataset.l; };
      const run = (id, label, fn) => { const b = $(id, root); if (b) b.onclick = async () => { busy(b, label); try { await fn(); render(); } catch (e) { toast(e.message); done(b); } }; };
      wireWizard(root, render);
      run('#psn-refresh', 'Refreshing…', async () => { await connect.refreshPSN(); toast('PSN refreshed'); });
      run('#psn-off', '…', async () => { await connect.disconnectPSN(); });
      run('#gt-go', 'Fetching…', async () => { await connect.fetchGT($('#gt-id', root).value, $('#gt-tok', root).value.trim()); toast('GT7 stats connected'); });
      run('#gt-refresh', 'Fetching…', async () => { await connect.fetchGT(S().gtLink.psnId, S().gtLink.token); toast('GT7 stats refreshed'); });
      run('#gt-off', '…', async () => { store.set((s) => { delete s.gt; s.creditsSource = null; }); });
    },
  };
};

views.telemetry = telemetryView;
views.lap = lapView;

views.notfound = () => html`<h1>Off track</h1><p class="muted">That page doesn't exist. <a href="#/" style="text-decoration:underline">Back to the Command Centre</a>.</p>`;

// ── router ──────────────────────────────────────────────
const WIRES = { tuning: tuningWire, more: moreWire };

function route() {
  const [, name = '', arg] = (location.hash || '#/').split('/');
  return { name: name || 'home', arg: arg && decodeURIComponent(arg) };
}

function render() {
  const { name, arg } = route();
  const v = views[name] || views.notfound;
  const out = v(arg);
  const root = $('#view');
  const res = out && out.html !== undefined && !(out instanceof Object && out.s) ? out : { html: out };
  root.innerHTML = String(res.html);
  (res.wire || WIRES[name])?.(root);
  const navKey = { track: 'tracks', car: 'garage', lesson: 'academy', apex: 'academy', systems: 'academy', setup: 'home', wheel: 'more', tuning: 'more', sport: 'more', heritage: 'more', account: 'more', status: 'more', connect: 'more', telemetry: 'telemetry', lap: 'telemetry', start: 'start' }[name] || name;
  $$('#nav a').forEach((a) => a.classList.toggle('on', a.dataset.r === navKey));
  paintNextBar(name);
  const s = S();
  $('#credits-pill').textContent = s.credits == null ? 'Cr. —' : 'Cr. ' + crShort(s.credits);
  paintSync();
}

let lastName = null;
window.addEventListener('hashchange', () => {
  const { name } = route();
  render();
  if (name !== lastName || ['track', 'car', 'lesson', 'lap', 'start', 'apex', 'systems'].includes(name)) window.scrollTo({ top: 0 });
  lastName = name;
});
function paintSync() {
  const i = sync.info(), el = $('#sync-pill');
  el.className = 'sync-pill ' + i.status + (i.user ? '' : ' out');
  $('.slabel', el).textContent = i.user ? (i.status === 'live' ? 'Synced' : 'Syncing…') : 'Sign in';
}
sync.onStatus(() => { paintSync(); if (route().name === 'account') render(); });
store.subscribe((_s, why) => { if (why === 'remote') { render(); toast('Synced from your other device'); } });
render();
lastName = route().name;
sync.start();
connect.autoRefresh();

if ('serviceWorker' in navigator && location.protocol === 'https:') navigator.serviceWorker.register('sw.js').catch(() => {});
