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

function roadSvg(g, road) {
  const { N, x, y, h, w } = road;
  const L = [], R = [];
  for (let i = 0; i < N; i += 2) {
    const nx = -Math.sin(h[i]), ny = Math.cos(h[i]);
    L.push(P(x[i] + nx * w / 2, y[i] + ny * w / 2)); R.push(P(x[i] - nx * w / 2, y[i] - ny * w / 2));
  }
  svg('polygon', { points: L.concat(R.reverse()).join(' '), class: 'sim-road' }, g);
  // kerbs on the inside of each corner and the outside at exit
  for (const c of road.corners) {
    const side = (s0, s1, sign) => {
      const pts = [];
      for (let i = Math.round(s0 / 0.5); i <= Math.round(s1 / 0.5) && i < N; i++) { const nx = -Math.sin(h[i]), ny = Math.cos(h[i]); pts.push(P(x[i] + nx * sign * (w / 2 - 0.4), y[i] + ny * sign * (w / 2 - 0.4))); }
      svg('polyline', { points: pts.join(' '), class: 'sim-kerb' }, g);
    };
    side(c.sA - 8, c.sB + 8, c.dir);
    side(c.sB + 4, c.s1 + 30, -c.dir);
    // distance boards before the corner, on the outside
    for (const d of [150, 100, 50]) {
      const i = Math.round((c.s0 - d) / 0.5); if (i < 0) continue;
      const nx = -Math.sin(h[i]), ny = Math.cos(h[i]), sx = x[i] - nx * c.dir * (w / 2 + 3), sy = y[i] - ny * c.dir * (w / 2 + 3);
      svg('rect', { x: f1(sx - 2.2), y: f1(-sy - 1.3), width: 4.4, height: 2.6, rx: 0.4, class: 'sim-board' }, g);
      const t = svg('text', { x: f1(sx), y: f1(-sy + 0.75), class: 'sim-board-t' }, g); t.textContent = d;
    }
  }
}

// The line, coloured like a data logger: red = brake (by pressure), green = throttle, white = coasting.
function lineSvg(g, o) {
  const col = (i) => o.brk[i] > 0.04 ? `rgba(255,59,70,${0.45 + 0.55 * o.brk[i]})` : o.thr[i] > 0.9 ? '#36d399' : o.thr[i] > 0.08 ? '#9be7c4' : '#ffffff';
  let start = 0;
  for (let i = 1; i <= o.N; i++) {
    if (i === o.N || col(i) !== col(start) || i - start > 40) {
      const pts = []; for (let j = start; j <= Math.min(i, o.N - 1); j++) pts.push(P(o.x[j], o.y[j]));
      svg('polyline', { points: pts.join(' '), stroke: col(start), class: 'sim-line' }, g);
      start = i;
    }
  }
}

function carSvg(g, cls) {
  const c = svg('g', { class: 'sim-car ' + cls }, g);
  // drawn pointing +x, origin at the centre; 4.6 m x 2.0 m
  const wheels = [];
  for (const [wx, wy, front] of [[1.4, 0.95, 1], [1.4, -0.95, 1], [-1.4, 0.95, 0], [-1.4, -0.95, 0]]) {
    const wg = svg('g', { transform: `translate(${wx},${wy})` }, c);
    const r = svg('rect', { x: -0.36, y: -0.13, width: 0.72, height: 0.26, rx: 0.08, class: 'sim-wheel' }, wg);
    wheels.push({ g: wg, r, wx, wy, front });
  }
  svg('rect', { x: -2.3, y: -1.0, width: 4.6, height: 2.0, rx: 0.7, class: 'sim-body' }, c);
  svg('rect', { x: -0.3, y: -0.8, width: 1.5, height: 1.6, rx: 0.4, class: 'sim-glass' }, c);
  const bl = [svg('rect', { x: -2.35, y: -0.85, width: 0.25, height: 0.5, class: 'sim-bl' }, c), svg('rect', { x: -2.35, y: 0.35, width: 0.25, height: 0.5, class: 'sim-bl' }, c)];
  return { c, wheels, bl };
}

function wheelSvg(box) {
  const s = svg('svg', { viewBox: '-110 -110 220 220', class: 'sim-wheel-svg' }, box);
  svg('circle', { r: 104, class: 'sw-arc-bg' }, s);
  const arc = svg('path', { class: 'sw-arc' }, s);
  const rot = svg('g', {}, s);
  svg('circle', { r: 86, class: 'sw-rim' }, rot);
  svg('path', { d: 'M -86 0 L -30 18 L 30 18 L 86 0 M 0 18 L 0 80', class: 'sw-spoke' }, rot);
  svg('circle', { r: 30, class: 'sw-hub' }, rot);
  svg('rect', { x: -6, y: -98, width: 12, height: 22, rx: 3, class: 'sw-mark' }, rot);
  const t = svg('text', { x: 0, y: 8, class: 'sw-logo' }, rot); t.textContent = 'G PRO';
  return { s, rot, arc };
}

function pedalSvg(box, label, cls) {
  const s = svg('svg', { viewBox: '0 0 120 190', class: 'sim-pedal ' + cls }, box);
  svg('rect', { x: 6, y: 10, width: 22, height: 150, rx: 6, class: 'pm-bg' }, s);
  const bar = svg('rect', { x: 6, y: 160, width: 22, height: 0, rx: 6, class: 'pm-fill' }, s);
  const pct = svg('text', { x: 17, y: 182, class: 'pm-pct' }, s);
  const arm = svg('g', {}, s);
  svg('rect', { x: 66, y: 4, width: 10, height: 60, rx: 4, class: 'pd-arm' }, arm);
  const face = svg('g', {}, arm);
  svg('rect', { x: 44, y: 60, width: 54, height: 92, rx: 12, class: 'pd-face' }, face);
  for (let i = 0; i < 5; i++) svg('rect', { x: 52, y: 72 + i * 15, width: 38, height: 5, rx: 2.5, class: 'pd-grip' }, face);
  const t = svg('text', { x: 71, y: 176, class: 'pd-label' }, s); t.textContent = label;
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
  const gRoad = svg('g', {}, map), gGhost = svg('g', {}, map), gLine = svg('g', {}, map), gMarks = svg('g', {}, map), gDyn = svg('g', {}, map);
  const gMiniRoad = svg('g', {}, mini);
  const leader = carSvg(gDyn, 'other'); leader.c.style.display = 'none';
  const eye = svg('line', { class: 'sim-eye' }, gDyn); const eyeDot = svg('circle', { r: 1.2, class: 'sim-eyedot' }, gDyn);
  const me = carSvg(gDyn, 'me');
  const gvec = svg('line', { class: 'sim-gvec' }, gDyn);
  const miniDot = svg('circle', { r: 6, class: 'sim-minidot' }, mini);

  const wheel = wheelSvg($('.sim-wheelbox'));
  const brakeP = pedalSvg($('.sim-pedals'), 'BRAKE', 'brake'), thrP = pedalSvg($('.sim-pedals'), 'THROTTLE', 'thr');
  const gg = $('.sim-gg');
  svg('circle', { r: 50, class: 'gg-ring' }, gg); svg('circle', { r: 25, class: 'gg-ring2' }, gg);
  svg('line', { x1: -55, y1: 0, x2: 55, y2: 0, class: 'gg-ax' }, gg); svg('line', { x1: 0, y1: -55, x2: 0, y2: 55, class: 'gg-ax' }, gg);
  const ggT = svg('text', { x: 0, y: -40, class: 'gg-t' }, gg); ggT.textContent = 'brake';
  const ggTrail = svg('polyline', { class: 'gg-trail' }, gg), ggDot = svg('circle', { r: 6, class: 'gg-dot' }, gg);
  const loads = $('.sim-loads');
  svg('rect', { x: -16, y: -40, width: 32, height: 80, rx: 12, class: 'ld-body' }, loads);
  const ldC = [[-20, -26], [20, -26], [-20, 26], [20, 26]].map(([x, y]) => svg('circle', { cx: x, cy: y, r: 8, class: 'ld-c' }, loads));
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
      svg('circle', { cx: f1(o.x[i]), cy: f1(-o.y[i]), r: 1.6, class: 'sim-mk' + (lab === 'Brake' ? ' brk' : '') }, gMarks);
      const t = svg('text', { x: f1(o.x[i] + 2.6), y: f1(-o.y[i] - 2.2), class: 'sim-mk-t' }, gMarks); t.textContent = lab;
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
    xs = (s) => 40 + (s / sMax) * (TW - 45);
    const yv = (v) => lanes.spd[1] - (v / vMax) * (lanes.spd[1] - lanes.spd[0]);
    const yp = (p) => lanes.ped[1] - p * (lanes.ped[1] - lanes.ped[0]);
    const mid = (lanes.str[0] + lanes.str[1]) / 2, ys = (d) => mid + (d / strMax) * (lanes.str[1] - lanes.str[0]) / 2;
    for (const [k, [a, b]] of Object.entries(lanes)) {
      svg('rect', { x: 40, y: a, width: TW - 45, height: b - a, class: 'tr-lane' }, trace);
      const t = svg('text', { x: 4, y: (a + b) / 2 + 4, class: 'tr-lab' }, trace); t.textContent = { spd: 'SPEED', ped: 'PEDALS', str: 'STEER', dlt: 'GAP' }[k];
    }
    svg('line', { x1: 40, y1: mid, x2: TW - 5, y2: mid, class: 'tr-zero' }, trace);
    const poly = (o2, f, cls, step = 2) => { const p = []; for (let i = 0; i < o2.N; i += step) p.push(`${f1(xs(o2.st[i]))},${f1(f(o2, i))}`); return svg('polyline', { points: p.join(' '), class: cls }, trace); };
    const area = (o2, arr, cls) => { const p = [`${f1(xs(o2.st[0]))},${yp(0)}`]; for (let i = 0; i < o2.N; i += 2) p.push(`${f1(xs(o2.st[i]))},${f1(yp(arr[i]))}`); p.push(`${f1(xs(o2.st[o2.N - 1]))},${yp(0)}`); return svg('polygon', { points: p.join(' '), class: cls }, trace); };
    runs.forEach((r, k) => { if (k === cur) return; poly(r.o, (q, i) => yv(q.v[i]), 'tr-ghost'); poly(r.o, (q, i) => yp(q.brk[i]), 'tr-ghost'); poly(r.o, (q, i) => yp(q.thr[i]), 'tr-ghost'); poly(r.o, (q, i) => ys(q.steer[i]), 'tr-ghost'); });
    area(o, o.thr, 'tr-thr'); area(o, o.brk, 'tr-brk');
    poly(o, (q, i) => yv(q.v[i]), 'tr-spd'); poly(o, (q, i) => ys(q.steer[i]), 'tr-str');
    // gap to the reference, by station
    const dl = svg('text', { x: 46, y: lanes.dlt[0] + 14, class: 'tr-note' }, trace);
    if (cur !== (sc.ref ?? 0)) {
      const tAtS = (q, s) => { let i = q.st.findIndex((v) => v >= s); if (i <= 0) return q.t[Math.max(0, i < 0 ? q.N - 1 : 0)]; const u = (s - q.st[i - 1]) / Math.max(1e-6, q.st[i] - q.st[i - 1]); return q.t[i - 1] + (q.t[i] - q.t[i - 1]) * u; };
      const D = []; let dMax = 0.05;
      for (let i = 0; i < o.N; i += 4) { const d = o.t[i] - tAtS(ref, o.st[i]); D.push([o.st[i], d]); dMax = Math.max(dMax, Math.abs(d)); }
      const dm = (lanes.dlt[0] + lanes.dlt[1]) / 2, yd = (d) => dm + (d / dMax) * (lanes.dlt[1] - lanes.dlt[0]) / 2;
      svg('line', { x1: 40, y1: dm, x2: TW - 5, y2: dm, class: 'tr-zero' }, trace);
      svg('polyline', { points: D.map(([s, d]) => `${f1(xs(s))},${f1(yd(d))}`).join(' '), class: 'tr-dlt' }, trace);
      dl.textContent = `vs ${sc.variants[sc.ref ?? 0].label}: up = slower, down = faster (±${dMax.toFixed(2)} s)`;
    } else dl.textContent = 'Reference lap. Pick another option below to see where it gains and loses.';
    for (const [s, lab] of marks) { svg('line', { x1: xs(s), y1: 4, x2: xs(s), y2: 326, class: 'tr-mk' }, trace); const t = svg('text', { x: xs(s) + 3, y: 14, class: 'tr-mk-t' }, trace); t.textContent = lab; }
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
    const sc2 = overview ? 3 : 1;
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
    $('.sim-deg b').textContent = `${Math.abs(st).toFixed(0)}°${st > 1 ? ' R' : st < -1 ? ' L' : ''}`;
    // pedals
    for (const [p, v] of [[brakeP, lerp(o.brk, f)], [thrP, lerp(o.thr, f)]]) {
      p.bar.setAttribute('y', f1(160 - v * 150)); p.bar.setAttribute('height', f1(v * 150));
      p.pct.textContent = Math.round(v * 100) + '%';
      p.arm.setAttribute('transform', `translate(0 ${f1(v * 16)}) rotate(${f1(v * 9)} 71 4)`);
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
    [o.fl, o.fr, o.rl, o.rr].forEach((arr, k) => ldC[k].setAttribute('r', f1(4 + arr[i] * 40)));
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
  const scrubAt = (ev) => { const r = trace.getBoundingClientRect(), W = trace._w || 1000; const px = ((ev.clientX - r.left) / r.width) * W; const sMax = Math.max(...runs.map((q) => q.o.st[q.o.N - 1])); seekStation(Math.max(0, Math.min(1, (px - 40) / (W - 45))) * sMax); };
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
