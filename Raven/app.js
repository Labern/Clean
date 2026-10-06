// Raven shell: header, map stage, widget rail, sheet, toasts, theme, scale.
// Widgets are plug-ins (see widgets/*.js); the shell never knows their internals.

import { on, emit, latest } from './lib/bus.js';
import { createStore } from './lib/store.js';
import { createLink } from './lib/link.js';
import { isDemo, startDemo } from './lib/demo.js';
import { isNight } from './lib/sun.js';
import { clock, miles, unitDist, pct } from './lib/fmt.js';
import { startGeo } from './lib/geo.js';
import { startTrip } from './lib/trip.js';
import { mountMap } from './widgets/map.js';

import spotify from './widgets/spotify.js';
import whatsapp from './widgets/whatsapp.js';
import trip from './widgets/trip.js';
import battery from './widgets/battery.js';
import facts from './widgets/facts.js';

const WIDGETS = [spotify, whatsapp, trip, battery, facts].sort((a, b) => a.order - b.order);

const $ = (s, r = document) => r.querySelector(s);
const store = createStore();
let link = null;
const ctx = { store, emit, on, latest, toast, theme: () => document.documentElement.dataset.theme === 'day' ? 'day' : 'night', map: null, get link() { return link; } };

// ---- One-time key from the URL (?key=…) → localStorage, then scrub the URL.
(() => {
  const q = new URLSearchParams(location.search);
  if (q.get('key')) store.set('key', q.get('key'));
  if (q.get('server')) store.set('server', q.get('server').replace(/\/$/, ''));
  if (q.get('key') || q.get('server')) {
    q.delete('key'); q.delete('server');
    history.replaceState(null, '', location.pathname + (q.toString() ? `?${q}` : '') + location.hash);
  }
})();

// ---- Theme and scale
function applyScale() { document.documentElement.style.setProperty('--ui', store.get('ui')); }
function applyTheme() {
  const pref = store.get('theme');
  let t = pref;
  if (pref === 'auto') {
    const pos = latest('tesla.state') || store.get('home');
    t = isNight(new Date(), pos.lat, pos.lng) ? 'night' : 'day';
  }
  if (document.documentElement.dataset.theme !== t) {
    document.documentElement.dataset.theme = t;
    emit('theme', t);
  }
}
applyScale(); applyTheme();
store.onChange((k) => { if (k === 'ui') applyScale(); if (k === 'theme') applyTheme(); });
setInterval(applyTheme, 60000);

// ---- Header
function renderClock() { $('#clock').textContent = clock(); }
renderClock(); setInterval(renderClock, 1000);

on('tesla.state', (s) => {
  const u = store.get('units');
  const pill = $('#car-pill');
  pill.classList.toggle('is-charging', !!s.charging);
  pill.innerHTML = `<span class="bar"><i style="width:${s.soc}%"></i></span>${pct(s.soc)} · ${miles(s.rangeKm, u)} ${unitDist(u)}`;
  $('#temp-pill').textContent = `${Math.round(s.outside)}°`;
});
on('wa.chats', (s) => { const el = $('#unread-pill'); el.textContent = s.unread ? `${s.unread} new` : ''; });
on('link.status', (s) => {
  const d = $('#dot-server'); d.className = 'dot ' + (s.status === 'on' ? 'on' : s.status === 'off' ? '' : 'warn');
  if (s.status === 'on' && latest('car.pos')) link.send('car.pos', latest('car.pos')); // catch the server up
});
on('spotify.state', (s) => { $('#dot-spotify').className = 'dot ' + (s?.track ? 'on' : ''); });
on('tesla.state', () => { $('#dot-car').className = 'dot on'; });

// ---- Rail
const rail = $('#rail');
const tiles = new Map();
for (const w of WIDGETS) {
  const b = document.createElement('button');
  b.className = 'tile'; b.dataset.widget = w.id; b.setAttribute('aria-label', w.title);
  rail.appendChild(b);
  tiles.set(w.id, b);
  const render = (d) => { try { w.summary(b, d, ctx); } catch (e) { console.error(`[${w.id}] summary`, e); } };
  render();
  for (const ev of w.events || []) on(ev, render);
  b.addEventListener('click', (e) => {
    const act = e.target.closest('[data-act]')?.dataset.act;
    if (act && w.actions?.[act]) { e.stopPropagation(); w.actions[act](ctx); return; }
    openSheet(w);
  });
}
setInterval(() => emit('tick', Date.now()), 1000);

// ---- Sheet (expanded widget over the map)
const sheet = $('#sheet'), sheetTitle = $('#sheet-title'), sheetBody = $('#sheet-body');
let openWidget = null, sheetOff = [];
function openSheet(w) {
  openWidget = w; sheetTitle.textContent = w.title;
  const render = (d) => { try { w.detail(sheetBody, d, ctx); } catch (e) { console.error(`[${w.id}] detail`, e); } };
  render();
  sheetOff.forEach(f => f()); sheetOff = (w.events || []).map(ev => on(ev, render));
  sheet.classList.add('open');
  location.hash = w.id;
}
function closeSheet() {
  sheet.classList.remove('open'); openWidget = null;
  sheetOff.forEach(f => f()); sheetOff = [];
  if (location.hash) history.replaceState(null, '', location.pathname + location.search);
}
$('#sheet-close').addEventListener('click', closeSheet);
sheetBody.addEventListener('click', (e) => {
  const act = e.target.closest('[data-act]')?.dataset.act;
  if (act && openWidget?.actions?.[act]) openWidget.actions[act](ctx);
});
window.addEventListener('hashchange', () => {
  const w = WIDGETS.find(x => x.id === location.hash.slice(1));
  if (w) openSheet(w); else if (location.hash === '#settings') openSettings(); else closeSheet();
});

// ---- Toasts: name only, six seconds, optional chime
const toasts = $('#toasts');
let audioCtx = null;
function chime() {
  if (!store.get('chime')) return;
  try {
    audioCtx = audioCtx || new (window.AudioContext || window.webkitAudioContext)();
    const o = audioCtx.createOscillator(), g = audioCtx.createGain();
    o.type = 'sine'; o.frequency.value = 880;
    g.gain.setValueAtTime(0.0001, audioCtx.currentTime);
    g.gain.exponentialRampToValueAtTime(0.2, audioCtx.currentTime + 0.01);
    g.gain.exponentialRampToValueAtTime(0.0001, audioCtx.currentTime + 0.35);
    o.connect(g).connect(audioCtx.destination); o.start(); o.stop(audioCtx.currentTime + 0.4);
  } catch {}
}
function toast(who, what = 'WhatsApp', kind = '', ms = 6000) {
  const t = document.createElement('div');
  t.className = `toast ${kind}`;
  t.innerHTML = `<div class="stack"><span class="what">${esc(what)}</span><span class="who">${esc(who)}</span></div>`;
  toasts.prepend(t);
  requestAnimationFrame(() => t.classList.add('in'));
  const kill = () => { t.classList.remove('in'); setTimeout(() => t.remove(), 350); };
  t.addEventListener('click', kill);
  setTimeout(kill, ms);
  while (toasts.children.length > 4) toasts.lastChild.remove();
}
on('wa.message', (m) => { toast(m.name, 'WhatsApp'); chime(); });
on('notify', (n) => toast(n.title, n.source || 'Raven', n.kind || ''));
on('wa.sent', () => toast('Sent', 'WhatsApp', 'good', 2500));
on('wa.shared', (s) => toast('Sharing live', 'WhatsApp', 'good'));
on('error', (e) => toast(e.message || 'Something failed', e.of || 'Server', 'bad'));
on('wa.open', (chat) => { if (openWidget?.id === 'whatsapp') openWidget.detail(sheetBody, undefined, ctx); });

// ---- Map chrome
$('#recenter').addEventListener('click', () => emit('map.recenter'));
$('#send-nav').addEventListener('click', () => {
  if (!link.send('tesla.nav', { query: $('#search input').value })) toast('Send to nav', 'Tesla link needed', 'bad');
});
function renderPlaces() {
  $('#places').innerHTML = store.get('places').map(p =>
    `<button class="chip" data-place="${p.id}" ${p.lat == null ? 'style="opacity:.5"' : ''}>${esc(p.name)}</button>`).join('');
}
renderPlaces();
$('#places').addEventListener('click', (e) => {
  const id = e.target.closest('[data-place]')?.dataset.place; if (!id) return;
  const p = store.get('places').find(x => x.id === id);
  if (p?.lat == null) { toast(p.name, 'Set this place on the setup page', 'bad'); return; }
  emit('map.goto', p);
});

// ---- Settings sheet (theme, scale, units, server)
const settings = { id: 'settings', title: 'Settings', events: [],
  detail(el) {
    const s = store.state;
    el.innerHTML = `
      <div class="stack" style="gap:3.2rem;max-width:72rem">
        <div class="stack"><span class="label">Appearance</span>
          <div class="seg" data-set="theme">${['auto', 'night', 'day'].map(v => `<button data-v="${v}" class="${s.theme === v ? 'on' : ''}">${v[0].toUpperCase() + v.slice(1)}</button>`).join('')}</div></div>
        <div class="stack"><span class="label">Size</span>
          <div class="seg" data-set="ui">${[1.25, 1.5, 1.75, 2].map(v => `<button data-v="${v}" class="${+s.ui === v ? 'on' : ''}">${v}×</button>`).join('')}</div></div>
        <div class="stack"><span class="label">Units</span>
          <div class="seg" data-set="units">${['mi', 'km'].map(v => `<button data-v="${v}" class="${s.units === v ? 'on' : ''}">${v === 'mi' ? 'Miles' : 'Kilometres'}</button>`).join('')}</div></div>
        <div class="stack"><span class="label">Chime on messages</span>
          <div class="seg" data-set="chime">${[true, false].map(v => `<button data-v="${v}" class="${s.chime === v ? 'on' : ''}">${v ? 'On' : 'Off'}</button>`).join('')}</div></div>
        <div class="stack"><span class="label">Screen</span>
          <div class="row"><button class="btn" id="fs-btn">${document.fullscreenElement ? 'Leave fullscreen' : 'Fullscreen'}</button></div></div>
        <div class="stack"><span class="label">Server</span>
          <input class="text" id="server-in" placeholder="https://mac.tailnet.ts.net" value="${esc(s.server)}">
          <div class="t-sm faint">${s.key ? 'Key set.' : 'No key. Open once with ?key=… from the setup page.'}</div></div>
        <div class="t-sm faint">Raven · ${isDemo() ? 'demo data' : 'live'} · ${location.hostname}</div>
      </div>`;
    el.querySelectorAll('.seg').forEach(seg => seg.addEventListener('click', (e) => {
      const b = e.target.closest('[data-v]'); if (!b) return;
      const k = seg.dataset.set; let v = b.dataset.v;
      if (k === 'ui') v = +v; if (k === 'chime') v = v === 'true';
      store.set(k, v); settings.detail(el);
      if (k === 'units') for (const w of WIDGETS) { try { w.summary(tiles.get(w.id), undefined, ctx); } catch {} }
    }));
    el.querySelector('#fs-btn').addEventListener('click', () => {
      (document.fullscreenElement ? document.exitFullscreen() : document.documentElement.requestFullscreen()).then(() => settings.detail(el)).catch(() => toast('Fullscreen', 'Not allowed here', 'bad'));
    });
    el.querySelector('#server-in').addEventListener('change', (e) => { store.set('server', e.target.value.trim().replace(/\/$/, '')); link.stop(); link = createLink({ server: store.get('server'), key: store.get('key') }); link.start(); });
  } };
function openSettings() { openSheet(settings); }
$('#settings-btn').addEventListener('click', openSettings);

// ---- Map, link, geolocation, demo
mountMap($('#map-host'), ctx);
link = createLink({ server: store.get('server'), key: store.get('key') });
link.start();
startGeo({ send: (t, d) => link.send(t, d) });
if (isDemo()) startDemo(); else startTrip();

if (location.hash) window.dispatchEvent(new Event('hashchange'));

function esc(s) { return String(s ?? '').replace(/[&<>"]/g, c => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;' }[c])); }
