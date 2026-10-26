// Track studio: the interactive top of every track guide. Map with sectors and
// corners you can select, the reference lap (a physics-driven Gr.3 car on the
// real geometry: speed, gear, braking at every corner), a lap trace you can tap,
// a lap you can watch, and videos on the side with notes and per-corner moments.
import { html, raw, esc, toast } from './util.js';
import * as store from './state.js';
import { fullMap, lapStrip, pointAt, SECTOR_COLORS } from './map.js';
import { REFLAPS } from '../data/reflaps.js';
import { VIDEOS, VIDEO_KINDS } from '../data/videos.js';
import { hasKey, cached, fetchChapters, cornerMoments } from './ytchapters.js';

const fmt = (s) => `${Math.floor(s / 60)}:${(s % 60).toFixed(1).padStart(4, '0')}`;
const kindLabel = (k) => (VIDEO_KINDS.find(([x]) => x === k) || [, ''])[1];
const NOTE = {
  guide: 'Walks the lap: lines, braking points and gears.',
  hotlap: 'A fast reference lap to copy: watch the braking points and exits.',
  setup: 'Which car and tune to bring here, and why.',
  race: 'Racing in traffic here: starts, defending, where passes happen.',
  real: 'The real circuit from the cockpit: compare the lines with GT7.',
  history: 'The story of the circuit.',
};
const carOf = (title) => { const m = title.match(/\|\s*([^|]*?(Gr\.\s?\d|GT3|RSR|Supra|911|GT-R|NSX|M4|AMG|Ferrari|Porsche|McLaren|Mazda|Toyota|Nissan|Audi|BMW|Lexus|Honda|Hyundai)[^|]*)/i); return m ? m[1].trim() : ''; };
const commentary = (v) => [NOTE[v.kind], carOf(v.title) ? `Car: ${carOf(v.title)}.` : ''].filter(Boolean).join(' ');

function sectorTimes(t, r) {
  if (!r) return [];
  const L = t.km * 1000, n = r.v.length, dt = r.v.map((v) => (L / n) / Math.max(1, v / 3.6));
  const tot = dt.reduce((a, b) => a + b, 0), k = r.lap / tot;   // match the lap time exactly
  return t.sectors.map((s) => { let x = 0; for (let i = Math.floor(s.from * n); i < Math.min(n, Math.ceil(s.to * n)); i++) x += dt[i]; return x * k; });
}

function traceSvg(t, r, sel, sector) {
  if (!r) return '';
  const W = 1000, H = 150, n = r.v.length, vmax = Math.max(...r.v) * 1.05;
  const x = (f) => (f * W).toFixed(1), y = (v) => (H - 18 - (v / vmax) * (H - 34)).toFixed(1);
  const sec = t.sectors.map((s, i) => `<rect x="${x(s.from)}" y="0" width="${(x(s.to) - x(s.from)).toFixed(1)}" height="${H}" fill="${SECTOR_COLORS[i]}" opacity="${sector === i ? 0.22 : 0.07}"/>`).join('');
  const brk = r.brk.map((b, i) => b > 25 ? `<rect x="${x(i / n)}" y="${H - 14}" width="${(W / n + 0.6).toFixed(1)}" height="8" fill="#ff3b46" opacity="${(0.35 + b / 160).toFixed(2)}"/>` : '').join('');
  const line = r.v.map((v, i) => `${x(i / n)},${y(v)}`).join(' ');
  const ticks = t.corners.map((c, i) => `<g class="tr-c${i === sel ? ' on' : ''}" data-i="${i}"><line x1="${x(c.at)}" x2="${x(c.at)}" y1="0" y2="${H - 16}"/><text x="${x(c.at)}" y="13">${esc(String(c.n).replace(/^T(?=\d)/, ''))}</text></g>`).join('');
  return `<svg class="ts-trace" viewBox="0 0 ${W} ${H}" preserveAspectRatio="none">${sec}${brk}<polyline points="${line}" class="tr-v"/>${ticks}<line class="tr-head" x1="-10" x2="-10" y1="0" y2="${H}"/></svg>
    <div class="ts-trace-legend"><span><i class="lg-v"></i>speed</span><span><i class="lg-b"></i>braking</span><span>max ${Math.max(...r.v)} km/h</span></div>`;
}

export function studioHtml(t) {
  const r = REFLAPS[t.id];
  const vids = (VIDEOS[t.id] || []).filter((v) => v.kind !== 'history').slice(0, 8);
  return html`<section class="ts" id="studio">
    <div class="ts-main">
      <div class="mapstage ts-map" id="mapstage">
        <div class="note">${t.country === 'GT original' ? 'Layout traced from the in-game course map' : 'Geometry © OpenStreetMap contributors'}</div>
        <div id="mapsvg"></div>
        <div class="ts-tools">
          <div class="legend">${t.sectors.map((x, i) => html`<button data-sec="${i}" style="border-left:4px solid ${SECTOR_COLORS[i]}">S${i + 1}</button>`)}</div>
          ${r ? raw('<button class="ts-btn" id="ts-speed" type="button">Speed map</button><button class="ts-btn red" id="ts-play" type="button">▶ Watch the lap</button>') : ''}
        </div>
        <div class="ts-hud" id="ts-hud" hidden><b id="ts-kmh">0</b><span>km/h</span><b id="ts-gear" class="g">1</b><span>gear</span><b id="ts-time" class="t">0:00.0</b></div>
      </div>
      <div class="ts-tracebox" id="ts-trace"></div>
    </div>
    <aside class="ts-side">
      <div class="card pad ts-panel" id="ts-panel"></div>
      <div class="card pad ts-vids">
        <div class="row" style="justify-content:space-between;align-items:baseline"><h3 style="font-size:22px">Videos</h3><a class="muted small" href="#videos" style="text-decoration:underline">all ${(VIDEOS[t.id] || []).length}</a></div>
        <div class="ts-vlist">${vids.map((v) => html`<a class="ts-v" href="https://www.youtube.com/watch?v=${v.id}" target="_blank" rel="noopener" data-vid="${v.id}">
          <span class="th"><img loading="lazy" src="https://i.ytimg.com/vi/${v.id}/mqdefault.jpg" alt=""><i>${v.dur}</i></span>
          <span class="tx"><b>${v.title}</b><span class="k">${kindLabel(v.kind)} · ${v.channel}</span><span class="c">${commentary(v)}</span></span></a>`)}</div>
        ${hasKey() ? '' : html`<p class="muted small" style="margin:10px 0 0">Add a free YouTube API key in <a href="#/account" style="text-decoration:underline">Cloud save &amp; settings</a> and each corner links to the exact second it's explained.</p>`}
      </div>
    </aside>
  </section>`;
}

export function wireStudio(root, t) {
  const $ = (s) => root.querySelector(s), $$ = (s) => [...root.querySelectorAll(s)];
  const r = REFLAPS[t.id], vids = VIDEOS[t.id] || [];
  let sel = -1, sector = -1, speed = false, chapters = cached(), playing = false, raf = 0;
  const secT = sectorTimes(t, r);

  const drawMap = () => {
    const c = r && sel >= 0 ? r.corners[sel] : null;
    $('#mapsvg').innerHTML = fullMap(t, sel, sector, { speed: speed && r ? r.v : null, apexAt: c?.apexAt, brakeAt: c && c.brake > 0 ? c.brakeAt : null }) || lapStrip(t, sel);
    $$('#mapsvg .pin').forEach((p) => (p.onclick = () => select(+p.dataset.i)));
  };
  const drawTrace = () => { $('#ts-trace').innerHTML = traceSvg(t, r, sel, sector); $$('#ts-trace .tr-c').forEach((g) => (g.onclick = (e) => { e.stopPropagation(); select(+g.dataset.i); })); const sv = $('#ts-trace svg'); if (sv) sv.onclick = (e) => { const b = sv.getBoundingClientRect(), f = (e.clientX - b.left) / b.width; let best = 0; t.corners.forEach((c, i) => { if (Math.abs(c.at - f) < Math.abs(t.corners[best].at - f)) best = i; }); select(best); }; };
  const stat = (v, l, cls = '') => `<div class="ts-stat ${cls}${String(v).length > 12 ? ' long' : ''}"><b>${v}</b><span>${l}</span></div>`;

  const drawPanel = () => {
    const P = $('#ts-panel');
    if (sel >= 0) {
      const c = t.corners[sel], a = r?.corners[sel], moments = cornerMoments(c, vids, chapters);
      const q = encodeURIComponent(`GT7 ${t.short} ${c.name}`);
      P.innerHTML = `
        <div class="row" style="justify-content:space-between;align-items:start;gap:8px">
          <div><div class="kicker">Corner ${sel + 1} of ${t.corners.length} · ${esc(c.dir)}</div><h3 class="ts-h">${esc(c.n)} ${esc(c.name)}</h3></div>
          <div class="row" style="gap:6px"><button class="ts-nav" data-step="-1" aria-label="Previous corner">‹</button><button class="ts-nav" data-step="1" aria-label="Next corner">›</button></div>
        </div>
        ${a ? `<div class="kicker" style="margin-top:12px;color:var(--blue)">Reference lap · simulated Gr.3</div>
          <div class="ts-stats">${stat(a.gear, 'gear', 'g')}${stat(a.min, 'km/h at apex')}${stat(a.entry, 'km/h entry')}${stat(a.brake ? a.brake + ' m' : 'flat', a.brake ? 'braking' : 'no braking')}</div>` : ''}
        <div class="kicker" style="margin-top:12px">Guide</div>
        <div class="ts-stats sm">${stat('G' + esc(c.gear), 'gear')}${stat(esc(c.speed), 'speed')}${stat(esc(c.brake), 'brake')}</div>
        <p style="margin:12px 0 6px"><b>Line.</b> ${esc(c.line)}</p>
        <p class="muted" style="margin:0"><b>Common mistake.</b> ${esc(c.mistake)}</p>
        <div class="kicker" style="margin-top:14px">Watch this corner</div>
        <div class="ts-moments">${moments.map((m) => `<a class="ts-m" href="https://www.youtube.com/watch?v=${m.id}&t=${m.sec}s" target="_blank" rel="noopener"><b>${Math.floor(m.sec / 60)}:${String(m.sec % 60).padStart(2, '0')}</b> ${esc(m.title)}<span>${esc(m.video.channel)}</span></a>`).join('') || (hasKey() ? '<p class="muted small" style="margin:4px 0">No video chapter names this corner yet.</p>' : '')}
          <a class="ts-m search" href="https://www.youtube.com/results?search_query=${q}" target="_blank" rel="noopener">Search YouTube for "${esc(t.short)} ${esc(c.name)}" ↗</a></div>`;
      P.querySelectorAll('[data-step]').forEach((b) => (b.onclick = () => select((sel + +b.dataset.step + t.corners.length) % t.corners.length)));
    } else if (sector >= 0) {
      const s = t.sectors[sector], cs = t.corners.map((c, i) => [c, i]).filter(([c]) => c.at >= s.from && c.at < s.to);
      P.innerHTML = `<div class="kicker" style="color:${SECTOR_COLORS[sector]}">Sector ${sector + 1}</div><h3 class="ts-h">${esc(s.name.replace(/^S\d · /, ''))}</h3>
        ${r ? `<div class="ts-stats">${stat(fmt(secT[sector]).replace(/^0:/, ''), 'reference time')}${stat(Math.round((s.to - s.from) * t.km * 1000) + ' m', 'length')}${stat(cs.length, 'corners')}</div>` : ''}
        <p style="margin:12px 0 6px">${esc(s.focus)}</p><p class="muted" style="margin:0"><b>Where the time is:</b> ${esc(s.gain)}</p>
        <div class="ts-cl">${cs.map(([c, i]) => `<button data-c="${i}">${esc(c.n)} ${esc(c.name)}${r ? ` <span>${r.corners[i].min} km/h · G${r.corners[i].gear}</span>` : ''}</button>`).join('')}</div>`;
      P.querySelectorAll('[data-c]').forEach((b) => (b.onclick = () => select(+b.dataset.c)));
    } else {
      P.innerHTML = `<div class="kicker">Reference lap · simulated Gr.3</div><h3 class="ts-h">${r ? fmt(r.lap) : t.short}</h3>
        ${r ? `<div class="ts-stats">${secT.map((x, i) => stat(fmt(x).replace(/^0:/, ''), 'S' + (i + 1), 's' + i)).join('')}${stat(r.top, 'km/h top')}</div>` : ''}
        <p style="margin:12px 0 0">Tap a <b>sector</b> to light it up on the map, or a <b>corner</b> (map pin, lap trace or the list below) for its gear, speed and braking, the line, and videos of it.</p>
        <p class="muted small" style="margin:10px 0 0">${r ? 'The reference lap is our physics model of a Gr.3 car on this circuit\'s real geometry: grip, downforce, braking and power on a minimum-curvature line, calibrated to Gr.3 lap times. GT7 doesn\'t publish its AI\'s speeds; this is the closest honest equivalent. No elevation or camber, so treat corner speeds as ±10%.' : ''}${t.country === 'GT original' && r ? ' Traced layouts lose some tight detail, so this lap runs quick.' : ''}</p>`;
    }
  };

  const select = (i) => {
    sel = i === sel ? -1 : i;
    if (sel >= 0) { const c = t.corners[sel]; const si = t.sectors.findIndex((s) => c.at >= s.from && c.at < s.to); if (si >= 0) sector = -1; }
    drawMap(); drawTrace(); drawPanel(); syncList();
  };
  const syncList = () => $$('.corner').forEach((el) => el.classList.toggle('on', +el.dataset.i === sel));

  $$('[data-sec]').forEach((b) => (b.onclick = () => {
    sector = sector === +b.dataset.sec ? -1 : +b.dataset.sec; sel = -1;
    $$('.legend [data-sec]').forEach((x) => x.classList.toggle('on', +x.dataset.sec === sector));
    drawMap(); drawTrace(); drawPanel(); syncList();
    if (b.classList.contains('sector')) $('#studio').scrollIntoView({ behavior: 'smooth', block: 'start' });
  }));
  $$('.corner').forEach((el) => (el.onclick = () => { select(+el.dataset.i); $('#studio').scrollIntoView({ behavior: 'smooth', block: 'start' }); }));
  $('#ts-speed')?.addEventListener('click', (e) => { speed = !speed; e.target.classList.toggle('on', speed); e.target.textContent = speed ? 'Sectors' : 'Speed map'; drawMap(); });

  // watch the reference lap: a dot round the map, speed + gear + time, playhead on the trace
  const watch = () => {
    if (!r) return;
    const n = r.v.length, L = t.km * 1000, dt = r.v.map((v) => (L / n) / Math.max(1, v / 3.6)), tot = dt.reduce((a, b) => a + b, 0), k = r.lap / tot;
    const cum = [0]; for (let i = 0; i < n; i++) cum.push(cum[i] + dt[i] * k);
    let T = 0, last = 0; playing = true; $('#ts-play').textContent = '❚❚ Pause'; $('#ts-hud').hidden = false;
    const step = (now) => {
      if (!playing || !root.isConnected) return;
      T += Math.min(0.1, (now - (last || now)) / 1000) * 3; last = now;   // 3x speed
      if (T >= r.lap) T = 0;
      let i = 0; while (i < n - 1 && cum[i + 1] < T) i++;
      const f = (i + (T - cum[i]) / (cum[i + 1] - cum[i])) / n;
      const p = pointAt(t, f), dot = $('#aidot');
      if (p && dot) { dot.style.display = ''; dot.setAttribute('transform', `translate(${p[0]},${p[1]})`); }
      $('#ts-kmh').textContent = r.v[i]; $('#ts-gear').textContent = r.g[i]; $('#ts-time').textContent = fmt(T);
      const h = $('#ts-trace .tr-head'); if (h) { h.setAttribute('x1', f * 1000); h.setAttribute('x2', f * 1000); }
      raf = requestAnimationFrame(step);
    };
    raf = requestAnimationFrame(step);
  };
  $('#ts-play')?.addEventListener('click', () => { if (playing) { playing = false; cancelAnimationFrame(raf); $('#ts-play').textContent = '▶ Watch the lap'; } else watch(); });

  drawMap(); drawTrace(); drawPanel();
  if (hasKey()) fetchChapters(vids.map((v) => v.id)).then((c) => { chapters = c; if (sel >= 0) drawPanel(); }).catch((e) => toast('YouTube: ' + e.message));
}
