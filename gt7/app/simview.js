// Input simulator player: follow-cam map with the line coloured by brake and
// throttle, a rotating wheel, pedals that press with vertical meters, speed,
// gear, revs, G-meter, tyre loads and data-logger traces with a draggable
// playhead. mountSim(el, scenarioId) renders into el and owns its animation.
import { SCENARIOS, runScenario } from './scenarios.js';
import { atTime, lerp } from './sim.js';
import { html } from './util.js';

const NS = 'http://www.w3.org/2000/svg';
const f1 = (v) => v.toFixed(1);
const svg = (tag, attrs = {}, parent) => { const e = document.createElementNS(NS, tag); for (const k in attrs) e.setAttribute(k, attrs[k]); if (parent) parent.appendChild(e); return e; };

// World (x right, y up, metres) → SVG (y down).
const P = (x, y) => `${f1(x)},${f1(-y)}`;

let defsDone = false;
function defs(map) {
  const d = svg('defs', {}, map);
  d.innerHTML = `
    <pattern id="simGrass" width="14" height="14" patternUnits="userSpaceOnUse" patternTransform="rotate(28)">
      <rect width="14" height="14" fill="#1d5a32"/><rect width="7" height="14" fill="#226639"/></pattern>
    <pattern id="simAsph" width="3" height="3" patternUnits="userSpaceOnUse">
      <rect width="3" height="3" fill="#454b57"/><circle cx=".6" cy=".7" r=".18" fill="#525967"/><circle cx="2.1" cy="1.9" r=".14" fill="#3b404b"/><circle cx="1.5" cy=".2" r=".1" fill="#5a6170"/><circle cx="2.6" cy="2.7" r=".12" fill="#4f5563"/></pattern>
    <pattern id="simGravel" width="2" height="2" patternUnits="userSpaceOnUse">
      <rect width="2" height="2" fill="#c9b48a"/><circle cx=".5" cy=".5" r=".25" fill="#b39d72"/><circle cx="1.5" cy="1.4" r=".2" fill="#d8c59c"/></pattern>
    <radialGradient id="simShadow"><stop offset="0" stop-color="#000" stop-opacity=".55"/><stop offset="1" stop-color="#000" stop-opacity="0"/></radialGradient>
    <linearGradient id="simBody" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#3b7bff"/><stop offset=".5" stop-color="#1f5bff"/><stop offset="1" stop-color="#1343c4"/></linearGradient>
    <linearGradient id="simBody2" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#c7ccd6"/><stop offset=".5" stop-color="#9aa3b5"/><stop offset="1" stop-color="#737c8e"/></linearGradient>
    <marker id="simArrow" viewBox="0 0 10 10" refX="7" refY="5" markerWidth="4" markerHeight="4" orient="auto-start-reverse"><path d="M0 0 L10 5 L0 10 z" fill="#ffc531"/></marker>`;
}

function band(road, off0, off1, i0 = 0, i1 = road.N - 1, step = 2) {
  const { x, y, h } = road, A = [], B = [];
  for (let i = Math.max(0, i0); i <= Math.min(road.N - 1, i1); i += step) {
    const nx = -Math.sin(h[i]), ny = Math.cos(h[i]);
    A.push(P(x[i] + nx * off0, y[i] + ny * off0)); B.push(P(x[i] + nx * off1, y[i] + ny * off1));
  }
  return A.concat(B.reverse()).join(' ');
}
function edge(road, off, i0 = 0, i1 = road.N - 1, step = 2) {
  const { x, y, h } = road, pts = [];
  for (let i = Math.max(0, i0); i <= Math.min(road.N - 1, i1); i += step) { const nx = -Math.sin(h[i]), ny = Math.cos(h[i]); pts.push(P(x[i] + nx * off, y[i] + ny * off)); }
  return pts.join(' ');
}

function roadSvg(g, road) {
  const { N, x, y, h, w } = road, W2 = w / 2;
  // grass everywhere under the road
  let x0 = 1e9, x1 = -1e9, y0 = 1e9, y1 = -1e9; for (let i = 0; i < N; i++) { x0 = Math.min(x0, x[i]); x1 = Math.max(x1, x[i]); y0 = Math.min(y0, y[i]); y1 = Math.max(y1, y[i]); }
  svg('rect', { x: f1(x0 - 400), y: f1(-y1 - 400), width: f1(x1 - x0 + 800), height: f1(y1 - y0 + 800), fill: 'url(#simGrass)' }, g);
  // gravel traps on the outside of every corner, tarmac run-off along both sides
  for (const c of road.corners) {
    const i0 = Math.round((c.s0 - 10) / 0.5), i1 = Math.round((c.s1 + 25) / 0.5), out = -c.dir;
    svg('polygon', { points: band(road, out * (W2 + 3), out * (W2 + 3 + Math.min(26, 6 + c.deg / 6)), i0, i1), fill: 'url(#simGravel)', class: 'sim-gravel' }, g);
  }
  svg('polygon', { points: band(road, W2 + 3, -(W2 + 3)), class: 'sim-runoff' }, g);
  svg('polygon', { points: band(road, W2, -W2), fill: 'url(#simAsph)', class: 'sim-road' }, g);
  // rubbered racing line hint down the middle of each corner is too subtle; white edge lines instead
  svg('polyline', { points: edge(road, W2 - 0.25), class: 'sim-edge' }, g);
  svg('polyline', { points: edge(road, -(W2 - 0.25)), class: 'sim-edge' }, g);
  for (const c of road.corners) {
    const kerb = (s0, s1, side) => {
      const pts = edge(road, side * (W2 + 0.55), Math.round(s0 / 0.5), Math.round(s1 / 0.5), 1);
      svg('polyline', { points: pts, class: 'sim-kerb-w' }, g);
      svg('polyline', { points: pts, class: 'sim-kerb-r' }, g);
    };
    kerb(c.sA - 10, c.sB + 10, c.dir);       // apex kerb
    kerb(c.s0 - 6, c.s0 + 8, -c.dir);        // turn-in kerb
    kerb(c.sB + 2, c.s1 + 28, -c.dir);       // exit kerb
    for (const d of [150, 100, 50]) {
      const i = Math.round((c.s0 - d) / 0.5); if (i < 0) continue;
      const nx = -Math.sin(h[i]), ny = Math.cos(h[i]), sx = x[i] - nx * c.dir * (W2 + 5), sy = y[i] - ny * c.dir * (W2 + 5);
      const bg = svg('g', { transform: `translate(${f1(sx)},${f1(-sy)})` }, g);
      svg('rect', { x: -0.15, y: 0.8, width: 0.3, height: 1.6, fill: '#2a2f3a' }, bg);
      svg('rect', { x: -2.4, y: -1.6, width: 4.8, height: 3, rx: 0.5, class: 'sim-board' }, bg);
      const t = svg('text', { x: 0, y: 0.75, class: 'sim-board-t' }, bg); t.textContent = d;
    }
  }
  // start/finish-style chequer at the start of the clip
  const i = 6, nx = -Math.sin(h[i]), ny = Math.cos(h[i]);
  for (let k = 0; k < 12; k++) { const off = -W2 + k * w / 12; svg('rect', { x: f1(x[i] + nx * off - 0.5), y: f1(-(y[i] + ny * off) - 0.5), width: f1(w / 12), height: 1, fill: k % 2 ? '#fff' : '#111', opacity: 0.8 }, g); }
}

// The line, coloured like a data logger: red = brake (by pressure), green = throttle, white = coasting.
function lineSvg(g, o) {
  const col = (i) => o.brk[i] > 0.04 ? `rgba(255,${Math.round(90 - 60 * o.brk[i])},${Math.round(90 - 60 * o.brk[i])},1)` : o.thr[i] > 0.9 ? '#36d399' : o.thr[i] > 0.08 ? '#a6f0cf' : '#f4f6fb';
  const runs = []; let start = 0;
  for (let i = 1; i <= o.N; i++) if (i === o.N || col(i) !== col(start) || i - start > 30) { const pts = []; for (let j = start; j <= Math.min(i, o.N - 1); j++) pts.push(P(o.x[j], o.y[j])); runs.push([pts.join(' '), col(start)]); start = i; }
  for (const [pts, c] of runs) svg('polyline', { points: pts, stroke: c, class: 'sim-line-glow' }, g);
  for (const [pts, c] of runs) svg('polyline', { points: pts, stroke: c, class: 'sim-line' }, g);
}

function carSvg(g, cls) {
  // top-down GT race car, nose along +x, 4.6 m x 2.0 m, origin at the centre
  const c = svg('g', { class: 'sim-car ' + cls }, g);
  svg('ellipse', { cx: 0.15, cy: 0.25, rx: 2.9, ry: 1.45, fill: 'url(#simShadow)' }, c);
  const wheels = [];
  for (const [wx, wy, front] of [[1.45, 0.92, 1], [1.45, -0.92, 1], [-1.35, 0.95, 0], [-1.35, -0.95, 0]]) {
    const wg = svg('g', { transform: `translate(${wx},${wy})` }, c);
    const r = svg('rect', { x: -0.38, y: -0.17, width: 0.76, height: 0.34, rx: 0.1, class: 'sim-wheel' }, wg);
    svg('rect', { x: -0.22, y: -0.17, width: 0.44, height: 0.34, fill: 'rgba(255,255,255,.12)' }, wg);
    wheels.push({ g: wg, r, wx, wy, front });
  }
  const fill = cls === 'other' ? 'url(#simBody2)' : 'url(#simBody)';
  svg('path', { d: 'M2.35 0 C2.3 .55 1.9 .78 1.2 .86 L-1.7 .9 C-2.15 .9 -2.3 .7 -2.3 .45 L-2.3 -.45 C-2.3 -.7 -2.15 -.9 -1.7 -.9 L1.2 -.86 C1.9 -.78 2.3 -.55 2.35 0 Z', fill, class: 'sim-body' }, c);
  svg('path', { d: 'M2.3 0 C2.2 .3 1.9 .42 1.5 .45 L1.5 -.45 C1.9 -.42 2.2 -.3 2.3 0 Z', fill: 'rgba(255,255,255,.18)' }, c);
  if (cls !== 'other') { svg('rect', { x: -2.25, y: -0.16, width: 4.4, height: 0.12, fill: '#e1131f' }, c); svg('rect', { x: -2.25, y: 0.04, width: 4.4, height: 0.12, fill: '#fff' }, c); }
  svg('path', { d: 'M.95 -.55 C.6 -.62 -.35 -.62 -.65 -.5 L-.65 .5 C-.35 .62 .6 .62 .95 .55 C1.1 .3 1.1 -.3 .95 -.55 Z', class: 'sim-glass' }, c);
  svg('rect', { x: -2.45, y: -0.98, width: 0.42, height: 1.96, rx: 0.08, class: 'sim-wing' }, c);
  svg('rect', { x: 2.05, y: -0.95, width: 0.28, height: 1.9, rx: 0.1, class: 'sim-splitter' }, c);
  svg('rect', { x: 2.12, y: 0.5, width: 0.16, height: 0.3, rx: 0.05, fill: '#fff8d6' }, c); svg('rect', { x: 2.12, y: -0.8, width: 0.16, height: 0.3, rx: 0.05, fill: '#fff8d6' }, c);
  const bl = [svg('rect', { x: -2.42, y: -0.85, width: 0.2, height: 0.42, rx: 0.05, class: 'sim-bl' }, c), svg('rect', { x: -2.42, y: 0.43, width: 0.2, height: 0.42, rx: 0.05, class: 'sim-bl' }, c)];
  return { c, wheels, bl };
}

function wheelSvg(box) {
  const s = svg('svg', { viewBox: '-120 -120 240 240', class: 'sim-wheel-svg' }, box);
  const d = svg('defs', {}, s);
  d.innerHTML = `<linearGradient id="swRim" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#3a3d46"/><stop offset=".5" stop-color="#1c1e24"/><stop offset="1" stop-color="#2c2f37"/></linearGradient>
    <linearGradient id="swPlate" x1="0" y1="0" x2="1" y2="1"><stop offset="0" stop-color="#2d3039"/><stop offset="1" stop-color="#15171c"/></linearGradient>
    <pattern id="swCarbon" width="6" height="6" patternUnits="userSpaceOnUse" patternTransform="rotate(45)"><rect width="6" height="6" fill="#1a1c22"/><rect width="3" height="3" fill="#24272e"/><rect x="3" y="3" width="3" height="3" fill="#24272e"/></pattern>`;
  svg('circle', { r: 114, class: 'sw-arc-bg' }, s);
  const arc = svg('path', { class: 'sw-arc' }, s);
  const rot = svg('g', {}, s);
  // paddles behind the rim
  svg('path', { d: 'M -70 -20 L -104 -46 L -110 -20 L -76 4 Z', class: 'sw-paddle' }, rot);
  svg('path', { d: 'M 70 -20 L 104 -46 L 110 -20 L 76 4 Z', class: 'sw-paddle' }, rot);
  // flat-bottomed rim with grips
  const rim = 'M -62 74 A 96 96 0 1 1 62 74 Q 52 86 36 86 L -36 86 Q -52 86 -62 74 Z';
  svg('path', { d: rim, fill: 'none', stroke: '#0b0c10', 'stroke-width': 26, 'stroke-linejoin': 'round' }, rot);
  svg('path', { d: rim, fill: 'none', stroke: '#262931', 'stroke-width': 21, 'stroke-linejoin': 'round' }, rot);
  svg('path', { d: rim, fill: 'none', stroke: 'rgba(255,255,255,.12)', 'stroke-width': 3, 'stroke-linejoin': 'round', transform: 'translate(0 -4)' }, rot);
  svg('path', { d: 'M -92 -26 A 96 96 0 0 1 -80 -54 M 92 -26 A 96 96 0 0 0 80 -54', class: 'sw-grip' }, rot);
  // centre plate
  svg('path', { d: 'M -78 -6 C -78 -36 -50 -44 0 -44 C 50 -44 78 -36 78 -6 L 70 30 C 60 52 34 62 0 62 C -34 62 -60 52 -70 30 Z', fill: 'url(#swCarbon)', stroke: '#3a3f4b', 'stroke-width': 2 }, rot);
  svg('path', { d: 'M -78 -6 L -96 4 M 78 -6 L 96 4 M 0 62 L 0 80', stroke: '#1c1e24', 'stroke-width': 14, 'stroke-linecap': 'round' }, rot);
  for (const [bx, by, col] of [[-48, -14, '#4c8dff'], [-48, 8, '#e1131f'], [-30, 26, '#ffc531'], [48, -14, '#36d399'], [48, 8, '#fff'], [30, 26, '#9aa3b5']]) svg('circle', { cx: bx, cy: by, r: 6.5, fill: col, stroke: '#0b0c10', 'stroke-width': 2 }, rot);
  svg('rect', { x: -26, y: -26, width: 52, height: 30, rx: 6, fill: '#0b0c10', stroke: '#3a3f4b' }, rot);
  const disp = svg('text', { x: 0, y: -5, class: 'sw-disp' }, rot); disp.textContent = '1';
  const t = svg('text', { x: 0, y: 46, class: 'sw-logo' }, rot); t.textContent = 'G PRO';
  // rev LEDs across the top
  const leds = [];
  for (let k = 0; k < 10; k++) { const a = (-50 + k * 100 / 9) * Math.PI / 180; leds.push(svg('circle', { cx: f1(Math.sin(a) * 64), cy: f1(-Math.cos(a) * 64 + 26), r: 4.2, class: 'sw-led' }, rot)); }
  svg('rect', { x: -5, y: -110, width: 10, height: 22, rx: 3, class: 'sw-mark' }, rot);
  return { s, rot, arc, leds, disp };
}

function pedalSvg(box, label, cls) {
  const s = svg('svg', { viewBox: '0 0 130 200', class: 'sim-pedal ' + cls }, box);
  const id = 'pd' + cls;
  const d = svg('defs', {}, s);
  d.innerHTML = `<linearGradient id="${id}M" x1="0" y1="0" x2="1" y2="0"><stop offset="0" stop-color="#9aa1ad"/><stop offset=".45" stop-color="#e9ecf1"/><stop offset="1" stop-color="#8b929f"/></linearGradient>
    <linearGradient id="${id}F" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="${cls === 'brake' ? '#ff6a73' : '#5cf0b6'}"/><stop offset="1" stop-color="${cls === 'brake' ? '#c80f1c' : '#139a68'}"/></linearGradient>`;
  // meter with ticks
  svg('rect', { x: 6, y: 10, width: 24, height: 154, rx: 7, class: 'pm-bg' }, s);
  for (let k = 0; k <= 4; k++) svg('line', { x1: 32, x2: 38, y1: 162 - k * 37.5, y2: 162 - k * 37.5, class: 'pm-tick' }, s);
  const bar = svg('rect', { x: 8, y: 162, width: 20, height: 0, rx: 5, fill: `url(#${id}F)`, class: 'pm-fill' }, s);
  const pct = svg('text', { x: 18, y: 188, class: 'pm-pct' }, s);
  // base plate + pedal arm and face
  svg('rect', { x: 46, y: 150, width: 76, height: 14, rx: 4, class: 'pd-base' }, s);
  const arm = svg('g', {}, s);
  svg('rect', { x: 79, y: 2, width: 10, height: 70, rx: 4, fill: `url(#${id}M)` }, arm);
  svg('rect', { x: 52, y: 64, width: 64, height: 86, rx: 14, fill: `url(#${id}M)`, stroke: '#5c6373', 'stroke-width': 1.5 }, arm);
  for (let k = 0; k < 6; k++) svg('rect', { x: 60, y: 74 + k * 12, width: 48, height: 4, rx: 2, class: 'pd-grip' }, arm);
  const t = svg('text', { x: 84, y: 188, class: 'pd-label' }, s); t.textContent = label;
  return { s, bar, pct, arm };
}

const PHASE = (o, i, sc) => {
  const b = o.brk[i], th = o.thr[i], st = o.steer[i], s = o.st[i];
  const deg = `${Math.abs(st).toFixed(0)}° ${st > 0.5 ? 'right' : st < -0.5 ? 'left' : ''}`.trim();
  const near = o.marks.find(([ms]) => Math.abs(ms - s) < 3.5);
  if (o.slip && o.slip[i] > 1.5) return ['Wheelspin!', `Too much throttle for the rear tyres while they're cornering. Opposite lock: ${deg}.`];
  if (near) {
    const [, lab] = near;
    if (/Turn-in/.test(lab)) return ['Turn-in', `Steering starts winding on from 0°.${b > 0.05 ? ` Brake still at ${Math.round(b * 100)}% and bleeding off.` : ''}`];
    if (/Apex/.test(lab)) return [lab, `Clipping the inside kerb. Steering ${deg}.${th > 0.05 ? ` Throttle ${Math.round(th * 100)}%.` : b > 0.05 ? ` Brake ${Math.round(b * 100)}%.` : ''}`];
    if (/Track-out/.test(lab)) return ['Track-out', `Wheel back to ${deg || 'straight'}, using the full width. Throttle ${Math.round(th * 100)}%.`];
    if (/Pull out/.test(lab)) return ['Pull out', 'Leave the tow now: the extra speed carries you alongside.'];
  }
  if (o.tow && o.tow[i] > 0.04) return ['In the tow', `${Math.round(o.tow[i] * 100)}% less drag from the car ahead. Gap ${o.gap[i].toFixed(1)} m.`];
  if (b > 0.6 && Math.abs(st) < 12) return ['Threshold braking', `${Math.round(b * 100)}% brake, wheel straight, right at the limit of grip.`];
  if (b > 0.05 && Math.abs(st) >= 12) return ['Trail braking', `Brake ${Math.round(b * 100)}% fading as steering builds to ${deg}.`];
  if (b > 0.05) return ['Braking', `${Math.round(b * 100)}% brake.`];
  if (th > 0.93 && Math.abs(st) < 10) return ['Full throttle', `${Math.round(o.v[i] * 3.6)} km/h in ${o.gear[i]}${['', 'st', 'nd', 'rd'][o.gear[i]] || 'th'}.`];
  if (th > 0.05 && Math.abs(st) >= 10) return ['Unwinding + throttle', `Throttle ${Math.round(th * 100)}% as steering comes off (${deg}).`];
  if (Math.abs(st) >= 10) return ['Mid-corner', `Balancing the car: ${deg}, maintenance throttle ${Math.round(th * 100)}%.`];
  return ['Coasting', 'Off both pedals.'];
};

export function mountSim(el, id) {
  const sc = SCENARIOS[id];
  if (!sc) return () => {};
  el.classList.add('sim');
  el.innerHTML = `
    <div class="sim-top">
      <div class="sim-mapbox"><svg class="sim-map"></svg><svg class="sim-mini"></svg>
        <button class="sim-cam" type="button">Overview</button></div>
      <div class="sim-cockpit">
        <div class="sim-wheelbox"><div class="sim-deg"><b>0°</b><span>steering</span></div></div>
        <div class="sim-pedals"></div>
        <div class="sim-hud">
          <div class="sim-speed"><b>0</b><span>km/h</span></div>
          <div class="sim-gear"><b>1</b><span>gear</span></div>
          <div class="sim-rpm"><i></i></div>
          <svg class="sim-gg" viewBox="-60 -60 120 120"></svg>
          <svg class="sim-loads" viewBox="-40 -60 80 120"></svg>
          <div class="sim-extra"></div>
        </div>
      </div>
    </div>
    <div class="sim-caption"><b></b><span></span></div>
    <svg class="sim-trace" viewBox="0 0 1000 330" preserveAspectRatio="none"></svg>
    <div class="sim-ctrl">
      <button class="sim-play btn" type="button" aria-label="Play">❚❚</button>
      <input class="sim-scrub" type="range" min="0" max="1000" value="0" aria-label="Scrub">
      <div class="seg sim-rate"><button data-r="0.25">¼×</button><button data-r="0.5">½×</button><button data-r="1" class="on">1×</button></div>
    </div>
    <div class="sim-vars seg"></div>
    <div class="sim-delta muted small"></div>`;
  const $ = (s) => el.querySelector(s);
  const runs = runScenario(id);
  let cur = 0, T = 0, playing = true, rate = 1, overview = false, raf = 0, last = 0, hold = 0;

  // ── static layers per variant ──
  const map = $('.sim-map'), mini = $('.sim-mini');
  defs(map);
  const gRoad = svg('g', {}, map), gGhost = svg('g', {}, map), gLine = svg('g', {}, map), gMarks = svg('g', {}, map), gDyn = svg('g', {}, map);
  const gMiniRoad = svg('g', {}, mini);
  const leader = carSvg(gDyn, 'other'); leader.c.style.display = 'none';
  const eye = svg('line', { class: 'sim-eye' }, gDyn); const eyeDot = svg('circle', { r: 1.2, class: 'sim-eyedot' }, gDyn);
  const me = carSvg(gDyn, 'me');
  const gvec = svg('line', { class: 'sim-gvec', 'marker-end': 'url(#simArrow)' }, gDyn);
  const miniDot = svg('circle', { r: 6, class: 'sim-minidot' }, mini);

  const wheel = wheelSvg($('.sim-wheelbox'));
  const brakeP = pedalSvg($('.sim-pedals'), 'BRAKE', 'brake'), thrP = pedalSvg($('.sim-pedals'), 'THROTTLE', 'thr');
  const gg = $('.sim-gg');
  svg('circle', { r: 50, class: 'gg-ring' }, gg); svg('circle', { r: 25, class: 'gg-ring2' }, gg);
  svg('line', { x1: -55, y1: 0, x2: 55, y2: 0, class: 'gg-ax' }, gg); svg('line', { x1: 0, y1: -55, x2: 0, y2: 55, class: 'gg-ax' }, gg);
  const ggT = svg('text', { x: 0, y: -40, class: 'gg-t' }, gg); ggT.textContent = 'brake';
  const ggTrail = svg('polyline', { class: 'gg-trail' }, gg), ggDot = svg('circle', { r: 6, class: 'gg-dot' }, gg);
  const loads = $('.sim-loads');
  svg('path', { d: 'M0 -46 C12 -46 16 -36 16 -22 L16 30 C16 40 12 44 0 44 C-12 44 -16 40 -16 30 L-16 -22 C-16 -36 -12 -46 0 -46 Z', class: 'ld-body' }, loads);
  svg('rect', { x: -12, y: -20, width: 24, height: 22, rx: 6, class: 'ld-glass' }, loads);
  const ldC = [[-21, -26], [21, -26], [-21, 26], [21, 26]].map(([x, y]) => svg('rect', { x: x - 6, y: y - 11, width: 12, height: 22, rx: 3, class: 'ld-c' }, loads));
  const ldP = [[-21, -26], [21, -26], [-21, 26], [21, 26]].map(([x, y]) => { const t = svg('text', { x: x + (x < 0 ? -9 : 9), y: y + 4, class: 'ld-p', 'text-anchor': x < 0 ? 'end' : 'start' }, loads); return t; });
  const ldT = svg('text', { x: 0, y: 56, class: 'ld-t' }, loads); ldT.textContent = 'tyre load';

  const trace = $('.sim-trace');
  const lanes = { spd: [8, 92], ped: [104, 176], str: [188, 258], dlt: [270, 322] };

  let built = -1, xs = null;
  function build() {
    const o = runs[cur].o, ref = runs[sc.ref ?? 0].o;
    [gRoad, gGhost, gLine, gMarks, gMiniRoad].forEach((g) => (g.innerHTML = ''));
    roadSvg(gRoad, o.road);
    runs.forEach((r, k) => { if (k === cur) return; const pts = []; for (let i = 0; i < r.o.N; i += 2) pts.push(P(r.o.x[i], r.o.y[i])); svg('polyline', { points: pts.join(' '), class: 'sim-ghost' }, gGhost); });
    lineSvg(gLine, o);
    const ib = o.brk.findIndex((b) => b > 0.05);
    const marks = o.marks.slice(); if (ib > 0) marks.unshift([o.st[ib], 'Brake']);
    for (const [s, lab] of marks) {
      let i = o.st.findIndex((v) => v >= s); if (i < 0) i = o.N - 1;
      const mg = svg('g', { transform: `translate(${f1(o.x[i])},${f1(-o.y[i])})` }, gMarks);
      svg('circle', { r: 2.4, class: 'sim-mk-halo' + (lab === 'Brake' ? ' brk' : '') }, mg);
      svg('circle', { r: 1.3, class: 'sim-mk' + (lab === 'Brake' ? ' brk' : '') }, mg);
      const wTxt = lab.length * 1.45 + 2.4;
      svg('rect', { x: 2.6, y: -6.4, width: f1(wTxt), height: 3.6, rx: 1.8, class: 'sim-mk-bg' + (lab === 'Brake' ? ' brk' : '') }, mg);
      const t = svg('text', { x: f1(2.6 + wTxt / 2), y: -3.75, class: 'sim-mk-t' }, mg); t.textContent = lab.toUpperCase();
      svg('line', { x1: 0.9, y1: -0.9, x2: 3.2, y2: -3, class: 'sim-mk-stem' }, mg);
    }
    // mini overview
    const bx = bounds(o.road);
    mini.setAttribute('viewBox', `${f1(bx.x0 - 20)} ${f1(-bx.y1 - 20)} ${f1(bx.x1 - bx.x0 + 40)} ${f1(bx.y1 - bx.y0 + 40)}`);
    const pts = []; for (let i = 0; i < o.road.N; i += 4) pts.push(P(o.road.x[i], o.road.y[i]));
    svg('polyline', { points: pts.join(' '), class: 'sim-mini-road' }, gMiniRoad);
    miniDot.setAttribute('r', (bx.x1 - bx.x0 + bx.y1 - bx.y0) / 90);
    // traces vs station
    trace.innerHTML = '';
    const TW = Math.max(420, Math.round((trace.clientWidth || 1000) / (trace.clientHeight || 240) * 330));
    trace.setAttribute('viewBox', `0 0 ${TW} 330`); trace._w = TW;
    const sMax = Math.max(...runs.map((r) => r.o.st[r.o.N - 1])), vMax = Math.max(...runs.map((r) => Math.max(...r.o.v))) * 1.05;
    const strMax = Math.max(30, ...runs.map((r) => Math.max(...Array.from(r.o.steer, Math.abs)))) * 1.1;
    xs = (s) => 70 + (s / sMax) * (TW - 75);
    const yv = (v) => lanes.spd[1] - (v / vMax) * (lanes.spd[1] - lanes.spd[0]);
    const yp = (p) => lanes.ped[1] - p * (lanes.ped[1] - lanes.ped[0]);
    const mid = (lanes.str[0] + lanes.str[1]) / 2, ys = (d) => mid + (d / strMax) * (lanes.str[1] - lanes.str[0]) / 2;
    for (const [k, [a, b]] of Object.entries(lanes)) {
      svg('rect', { x: 70, y: a, width: TW - 75, height: b - a, class: 'tr-lane' }, trace);
      const t = svg('text', { x: 4, y: (a + b) / 2 + 4, class: 'tr-lab' }, trace); t.textContent = { spd: 'SPEED', ped: 'PEDALS', str: 'STEER', dlt: 'GAP' }[k];
    }
    svg('line', { x1: 70, y1: mid, x2: TW - 5, y2: mid, class: 'tr-zero' }, trace);
    const poly = (o2, f, cls, step = 2) => { const p = []; for (let i = 0; i < o2.N; i += step) p.push(`${f1(xs(o2.st[i]))},${f1(f(o2, i))}`); return svg('polyline', { points: p.join(' '), class: cls }, trace); };
    const area = (o2, arr, cls) => { const p = [`${f1(xs(o2.st[0]))},${yp(0)}`]; for (let i = 0; i < o2.N; i += 2) p.push(`${f1(xs(o2.st[i]))},${f1(yp(arr[i]))}`); p.push(`${f1(xs(o2.st[o2.N - 1]))},${yp(0)}`); return svg('polygon', { points: p.join(' '), class: cls }, trace); };
    runs.forEach((r, k) => { if (k === cur) return; poly(r.o, (q, i) => yv(q.v[i]), 'tr-ghost'); poly(r.o, (q, i) => yp(q.brk[i]), 'tr-ghost'); poly(r.o, (q, i) => yp(q.thr[i]), 'tr-ghost'); poly(r.o, (q, i) => ys(q.steer[i]), 'tr-ghost'); });
    area(o, o.thr, 'tr-thr'); area(o, o.brk, 'tr-brk');
    poly(o, (q, i) => yv(q.v[i]), 'tr-spd'); poly(o, (q, i) => ys(q.steer[i]), 'tr-str');
    // gap to the reference, by station
    const dl = svg('text', { x: 78, y: lanes.dlt[0] + 16, class: 'tr-note' }, trace);
    if (cur !== (sc.ref ?? 0)) {
      const tAtS = (q, s) => { let i = q.st.findIndex((v) => v >= s); if (i <= 0) return q.t[Math.max(0, i < 0 ? q.N - 1 : 0)]; const u = (s - q.st[i - 1]) / Math.max(1e-6, q.st[i] - q.st[i - 1]); return q.t[i - 1] + (q.t[i] - q.t[i - 1]) * u; };
      const D = []; let dMax = 0.05;
      for (let i = 0; i < o.N; i += 4) { const d = o.t[i] - tAtS(ref, o.st[i]); D.push([o.st[i], d]); dMax = Math.max(dMax, Math.abs(d)); }
      const dm = (lanes.dlt[0] + lanes.dlt[1]) / 2, yd = (d) => dm + (d / dMax) * (lanes.dlt[1] - lanes.dlt[0]) / 2;
      svg('line', { x1: 70, y1: dm, x2: TW - 5, y2: dm, class: 'tr-zero' }, trace);
      svg('polyline', { points: D.map(([s, d]) => `${f1(xs(s))},${f1(yd(d))}`).join(' '), class: 'tr-dlt' }, trace);
      dl.textContent = `vs ${sc.variants[sc.ref ?? 0].label}: up = slower, down = faster (±${dMax.toFixed(2)} s)`;
    } else dl.textContent = 'Reference lap. Pick another option below to see where it gains and loses.';
    for (const [s, lab] of marks) { svg('line', { x1: xs(s), y1: 4, x2: xs(s), y2: 326, class: 'tr-mk' }, trace); const t = svg('text', { x: xs(s) + 4, y: 17, class: 'tr-mk-t' }, trace); t.textContent = lab; }
    trace._head = svg('line', { y1: 2, y2: 328, class: 'tr-head' }, trace);
    trace._dots = ['tr-d-spd', 'tr-d-str'].map((c) => svg('circle', { r: 5, class: c }, trace));
    trace._yv = yv; trace._ys = ys;
    leader.c.style.display = o.other ? '' : 'none';
    $('.sim-extra').innerHTML = sc.extra === 'tow' ? '<div class="sim-tow"><span>TOW</span><i></i></div>' : sc.extra === 'spin' ? '<div class="sim-spin">WHEELSPIN</div>' : '';
    // variant summary
    const tEnd = o.t[o.N - 1], tRef = ref.t[ref.N - 1];
    let mn = 1e9; for (let i = 0; i < o.N; i++) mn = Math.min(mn, o.v[i]);
    $('.sim-delta').textContent = `${sc.variants[cur].label}: ${tEnd.toFixed(2)} s · min ${Math.round(mn * 3.6)} km/h · braking at ${ib > 0 ? Math.round(o.st[ib]) + ' m' : 'no braking'}${cur !== (sc.ref ?? 0) ? ` · ${tEnd - tRef >= 0 ? '+' : '−'}${Math.abs(tEnd - tRef).toFixed(2)} s vs ${sc.variants[sc.ref ?? 0].label}` : ''}`;
    built = cur;
  }

  const bounds = (road) => { let x0 = 1e9, x1 = -1e9, y0 = 1e9, y1 = -1e9; for (let i = 0; i < road.N; i++) { x0 = Math.min(x0, road.x[i]); x1 = Math.max(x1, road.x[i]); y0 = Math.min(y0, road.y[i]); y1 = Math.max(y1, road.y[i]); } return { x0, x1, y0, y1 }; };

  function frame() {
    const o = runs[cur].o;
    if (built !== cur) build();
    const f = atTime(o, T), i = Math.round(f);
    const x = lerp(o.x, f), y = lerp(o.y, f), hd = o.h[i] + (o.slip ? o.slip[i] * Math.PI / 180 * Math.sign(o.k[i] || 1) * 0.9 : 0);
    // camera
    const box = map.getBoundingClientRect(), asp = box.width / Math.max(1, box.height);
    if (overview) { const b = bounds(o.road); const W = Math.max(b.x1 - b.x0, (b.y1 - b.y0) * asp) + 40; map.setAttribute('viewBox', `${f1((b.x0 + b.x1) / 2 - W / 2)} ${f1(-(b.y0 + b.y1) / 2 - W / asp / 2)} ${f1(W)} ${f1(W / asp)}`); }
    else { const W = box.width < 500 ? 70 : 95; map.setAttribute('viewBox', `${f1(x - W / 2 + Math.cos(o.h[i]) * W * 0.18)} ${f1(-y - W / asp / 2 - Math.sin(o.h[i]) * W * 0.18)} ${f1(W)} ${f1(W / asp)}`); }
    const sc2 = overview ? 3.2 : 1.6;   // drawn larger than life so it reads at a glance
    me.c.setAttribute('transform', `translate(${f1(x)},${f1(-y)}) rotate(${(-hd * 180 / Math.PI).toFixed(1)}) scale(${sc2})`);
    const road = o.steer[i] / o.car.ratio * 2.2;   // front wheels, exaggerated x2.2 to be visible
    me.wheels.forEach((w) => { if (w.front) w.g.setAttribute('transform', `translate(${w.wx},${w.wy}) rotate(${road.toFixed(1)})`); w.r.classList.toggle('spin', !!(o.slip && o.slip[i] > 1.5 && !w.front)); });
    me.bl.forEach((b) => b.setAttribute('opacity', o.brk[i] > 0.03 ? 0.4 + 0.6 * o.brk[i] : 0.1));
    if (o.other) { const ox = lerp(o.other.x, f), oy = lerp(o.other.y, f); leader.c.setAttribute('transform', `translate(${f1(ox)},${f1(-oy)}) rotate(${(-o.other.h[i] * 180 / Math.PI).toFixed(1)}) scale(${sc2})`); }
    // look point
    if (o.look) { const ti = atTime(o, T + o.look), j = Math.round(ti); eye.setAttribute('x1', f1(x)); eye.setAttribute('y1', f1(-y)); eye.setAttribute('x2', f1(o.x[j])); eye.setAttribute('y2', f1(-o.y[j])); eyeDot.setAttribute('cx', f1(o.x[j])); eyeDot.setAttribute('cy', f1(-o.y[j])); eye.style.display = eyeDot.style.display = ''; }
    else eye.style.display = eyeDot.style.display = 'none';
    // G vector in world frame: lateral along the normal, longitudinal along heading (1 g = 7 m)
    const lat = o.latG[i], lon = o.lonG[i], hx = Math.cos(o.h[i]), hy = Math.sin(o.h[i]);
    const gx = (hx * lon - hy * lat) * 7 * sc2, gy = (hy * lon + hx * lat) * 7 * sc2;
    gvec.setAttribute('x1', f1(x)); gvec.setAttribute('y1', f1(-y)); gvec.setAttribute('x2', f1(x + gx)); gvec.setAttribute('y2', f1(-(y + gy)));
    miniDot.setAttribute('cx', f1(x)); miniDot.setAttribute('cy', f1(-y));
    // wheel
    const st = lerp(o.steer, f);
    wheel.rot.setAttribute('transform', `rotate(${st.toFixed(1)})`);
    const a = Math.max(-180, Math.min(180, st)) * Math.PI / 180, r = 104;
    wheel.arc.setAttribute('d', Math.abs(a) < 0.01 ? '' : `M 0 ${-r} A ${r} ${r} 0 ${Math.abs(a) > Math.PI ? 1 : 0} ${a > 0 ? 1 : 0} ${f1(Math.sin(a) * r)} ${f1(-Math.cos(a) * r)}`);
    const lit = Math.round(Math.max(0, (o.rpm[i] - 0.6) / 0.38) * 10);
    wheel.leds.forEach((l, k) => l.setAttribute('class', 'sw-led' + (k < lit ? (k < 4 ? ' g' : k < 7 ? ' y' : ' r') : '') + (o.rpm[i] > 0.96 ? ' flash' : '')));
    wheel.disp.textContent = o.gear[i];
    $('.sim-deg b').textContent = `${Math.abs(st).toFixed(0)}°${st > 1 ? ' R' : st < -1 ? ' L' : ''}`;
    // pedals
    for (const [p, v] of [[brakeP, lerp(o.brk, f)], [thrP, lerp(o.thr, f)]]) {
      p.bar.setAttribute('y', f1(162 - v * 150)); p.bar.setAttribute('height', f1(v * 150));
      p.pct.textContent = Math.round(v * 100) + '%';
      p.arm.setAttribute('transform', `translate(0 ${f1(v * 12)}) rotate(${f1(v * 10)} 84 2)`); p.s.classList.toggle('hot', v > 0.9);
    }
    // HUD
    $('.sim-speed b').textContent = Math.round(lerp(o.v, f) * 3.6);
    $('.sim-gear b').textContent = o.gear[i];
    $('.sim-rpm i').style.width = (o.rpm[i] * 100).toFixed(1) + '%';
    $('.sim-rpm').classList.toggle('shift', o.rpm[i] > 0.96);
    // G-G: right turn plots right, braking plots up (1 g = 30 units, ring = 1.67 g)
    const clamp = (v) => Math.max(-1.7, Math.min(1.7, v));
    ggDot.setAttribute('cx', f1(-clamp(lat) * 30)); ggDot.setAttribute('cy', f1(clamp(lon) * 30));
    const tr = []; for (let k = 0; k < 45; k++) { const q = Math.round(atTime(o, T - k * 0.05)); tr.push(`${f1(-clamp(o.latG[q]) * 30)},${f1(clamp(o.lonG[q]) * 30)}`); }
    ggTrail.setAttribute('points', tr.join(' '));
    [o.fl, o.fr, o.rl, o.rr].forEach((arr, k) => { const v = arr[i], u = Math.max(0, Math.min(1, (v - 0.1) / 0.3)); ldC[k].setAttribute('fill', `hsl(${Math.round(210 - 210 * u)} 90% ${Math.round(55 + 5 * u)}%)`); ldC[k].setAttribute('transform', `scale(${(0.85 + v * 0.8).toFixed(2)})`); ldC[k].style.transformOrigin = 'center'; ldC[k].style.transformBox = 'fill-box'; ldP[k].textContent = Math.round(v * 100) + '%'; });
    if (sc.extra === 'tow') { const t = el.querySelector('.sim-tow i'); if (t) t.style.width = Math.min(100, (o.tow[i] || 0) * 250) + '%'; }
    if (sc.extra === 'spin') { const t = el.querySelector('.sim-spin'); if (t) t.classList.toggle('on', !!(o.slip && o.slip[i] > 1.5)); }
    // caption + trace head
    const [ph, txt] = PHASE(o, i, sc);
    $('.sim-caption b').textContent = ph; $('.sim-caption span').textContent = txt;
    const hx2 = xs(o.st[i]);
    trace._head.setAttribute('x1', f1(hx2)); trace._head.setAttribute('x2', f1(hx2));
    trace._dots[0].setAttribute('cx', f1(hx2)); trace._dots[0].setAttribute('cy', f1(trace._yv(o.v[i])));
    trace._dots[1].setAttribute('cx', f1(hx2)); trace._dots[1].setAttribute('cy', f1(trace._ys(o.steer[i])));
    $('.sim-scrub').value = Math.round((T / o.t[o.N - 1]) * 1000);
  }

  function tick(now) {
    raf = 0;
    if (!el.isConnected) return;
    const dt = Math.min(0.1, (now - (last || now)) / 1000); last = now;
    const o = runs[cur].o, end = o.t[o.N - 1];
    if (playing) {
      if (T >= end) { hold += dt; if (hold > 1.4) { T = 0; hold = 0; } }
      else T = Math.min(end, T + dt * rate);
    }
    frame();
    if (playing) raf = requestAnimationFrame(tick);
  }
  const play = (on) => { playing = on; $('.sim-play').textContent = on ? '❚❚' : '▶'; $('.sim-play').setAttribute('aria-label', on ? 'Pause' : 'Play'); if (on && !raf) { last = 0; raf = requestAnimationFrame(tick); } };
  const seekStation = (s) => { const o = runs[cur].o; let i = o.st.findIndex((v) => v >= s); if (i < 0) i = o.N - 1; T = o.t[i]; frame(); };

  // controls
  $('.sim-vars').innerHTML = sc.variants.map((v, k) => `<button data-v="${k}" class="${k === cur ? 'on' : ''}">${v.label}</button>`).join('');
  el.querySelectorAll('[data-v]').forEach((b) => (b.onclick = () => {
    const s = runs[cur].o.st[Math.round(atTime(runs[cur].o, T))];
    cur = +b.dataset.v; el.querySelectorAll('[data-v]').forEach((x) => x.classList.toggle('on', x === b));
    build(); seekStation(s);
  }));
  $('.sim-play').onclick = () => play(!playing);
  el.querySelectorAll('[data-r]').forEach((b) => (b.onclick = () => { rate = +b.dataset.r; el.querySelectorAll('[data-r]').forEach((x) => x.classList.toggle('on', x === b)); }));
  $('.sim-scrub').oninput = (e) => { play(false); T = (e.target.value / 1000) * runs[cur].o.t[runs[cur].o.N - 1]; frame(); };
  $('.sim-cam').onclick = () => { overview = !overview; $('.sim-cam').textContent = overview ? 'Follow car' : 'Overview'; frame(); };
  // drag on the traces = scrub by distance
  const scrubAt = (ev) => { const r = trace.getBoundingClientRect(), W = trace._w || 1000; const px = ((ev.clientX - r.left) / r.width) * W; const sMax = Math.max(...runs.map((q) => q.o.st[q.o.N - 1])); seekStation(Math.max(0, Math.min(1, (px - 70) / (W - 75))) * sMax); };
  trace.addEventListener('pointerdown', (ev) => { play(false); trace.setPointerCapture(ev.pointerId); scrubAt(ev); trace.onpointermove = scrubAt; });
  trace.addEventListener('pointerup', () => { trace.onpointermove = null; });
  // tap the mini map: jump to the nearest point
  mini.addEventListener('pointerdown', (ev) => {
    const o = runs[cur].o, pt = mini.createSVGPoint(); pt.x = ev.clientX; pt.y = ev.clientY;
    const q = pt.matrixTransform(mini.getScreenCTM().inverse()); let best = 0, bd = 1e18;
    for (let i = 0; i < o.N; i += 2) { const d = (o.x[i] - q.x) ** 2 + (-o.y[i] - q.y) ** 2; if (d < bd) { bd = d; best = i; } }
    play(false); T = o.t[best]; frame();
  });
  // pause when scrolled out of view, resume when back
  const io = 'IntersectionObserver' in window ? new IntersectionObserver(([e]) => { if (!e.isIntersecting && playing) { cancelAnimationFrame(raf); raf = 0; } else if (e.isIntersecting && playing && !raf) { last = 0; raf = requestAnimationFrame(tick); } }) : null;
  io?.observe(el);
  let rw = 0; const ro = 'ResizeObserver' in window ? new ResizeObserver(() => { const w = trace.clientWidth; if (w && Math.abs(w - rw) > 20) { rw = w; built = -1; frame(); } }) : null; ro?.observe(trace);
  build(); frame(); play(true);
  return () => { playing = false; cancelAnimationFrame(raf); io?.disconnect(); ro?.disconnect(); };
}

// The input simulator section: intro, the player mount point, what to watch.
export const simBlock = (id, title = 'See the inputs') => { const sc = SCENARIOS[id]; if (!sc) return ''; return html`<section class="section sim-section">
  <div class="head"><h2>${title}</h2><span class="muted small">Play, scrub the traces, switch options</span></div>
  <p class="muted" style="max-width:80ch;margin:0 0 12px">${sc.intro}</p>
  <div id="sim" data-sim="${id}"></div>
  <ul class="pts sim-watch" style="margin-top:12px">${sc.watch.map((w) => html`<li>${w}</li>`)}</ul></section>`; };
export const mountSimIn = (root) => { const el = root.querySelector('#sim[data-sim]'); if (el) mountSim(el, el.dataset.sim); };
