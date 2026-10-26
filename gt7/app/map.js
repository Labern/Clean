// Track drawings. Real circuits: the OSM geometry from data/maps.js, with the
// sectors coloured and a pin per corner at its measured lap fraction. GT
// originals: a lap strip (distance along the lap), since there is no geometry.
import { MAPS } from '../data/allmaps.js';

export const SECTOR_COLORS = ['#3d7bff', '#ff3b46', '#ffc531', '#36d399'];

const at = (m, f) => m.pts[Math.min(m.pts.length - 1, Math.max(0, Math.round(f * m.pts.length) % m.pts.length))];

function box(m, pad) {
  return { x: -pad, y: -pad, w: m.w + pad * 2, h: m.h + pad * 2 };
}

function polyline(m, from, to) {
  const n = m.pts.length;
  const a = Math.round(from * n), b = Math.round(to * n);
  const out = [];
  for (let i = a; i <= b; i++) out.push(m.pts[i % n]);
  return out.map((p) => p.join(',')).join(' ');
}

// Small thumbnail for cards.
export function thumb(track) {
  const m = track.map && MAPS[track.map];
  if (!m) return stripThumb(track);
  const b = box(m, 40);
  const all = m.pts.map((p) => p.join(',')).join(' ');
  return `<svg viewBox="${b.x} ${b.y} ${b.w} ${b.h}" width="100%" height="100%" preserveAspectRatio="xMidYMid meet" aria-hidden="true">
    <polygon points="${all}" fill="none" stroke="rgba(0,0,0,.35)" stroke-width="54" stroke-linejoin="round" transform="translate(0 12)"/>
    <polygon points="${all}" fill="none" stroke="rgba(120,170,255,.22)" stroke-width="70" stroke-linejoin="round"/>
    <polygon points="${all}" fill="none" stroke="#fff" stroke-width="40" stroke-linejoin="round"/>
    <polygon points="${all}" fill="none" stroke="#3d4452" stroke-width="22" stroke-linejoin="round"/>
    <circle cx="${m.pts[0][0]}" cy="${m.pts[0][1]}" r="20" fill="#e1131f" stroke="#fff" stroke-width="6"/>
  </svg>`;
}

function stripThumb(track) {
  const ticks = track.corners.map((c) => `<circle cx="${40 + c.at * 920}" cy="250" r="${c.key ? 22 : 14}" fill="${c.key ? '#e1131f' : '#fff'}"/>`).join('');
  return `<svg viewBox="0 0 1000 500" aria-hidden="true">
    <text x="500" y="160" text-anchor="middle" font-family="Barlow Condensed" font-style="italic" font-weight="800" font-size="64" fill="rgba(255,255,255,.22)">GT ORIGINAL</text>
    <line x1="40" y1="250" x2="960" y2="250" stroke="#fff" stroke-width="10" stroke-linecap="round"/>${ticks}</svg>`;
}

// Full interactive map. `sel` = selected corner index, `sector` = highlighted sector index or -1.
// Drawn as a road (shadow, kerb-white edges, asphalt), sectors as a glowing centre
// stripe, a chequered start line, direction chevrons and raised corner pins.
export const pointAt = (track, f) => { const m = track.map && MAPS[track.map]; return m ? at(m, ((f % 1) + 1) % 1) : null; };

export function fullMap(track, sel = -1, sector = -1, opts = {}) {
  const m = track.map && MAPS[track.map];
  if (!m) return null;
  const b = box(m, 70);
  const all = m.pts.map((p) => p.join(',')).join(' ');
  const heat = (v) => { const u = Math.max(0, Math.min(1, (v - 60) / 220)); return `hsl(${Math.round(u * 140)} 90% ${Math.round(50 + u * 6)}%)`; };
  const speedLine = opts.speed ? opts.speed.map((v, i, arr) => { const f0 = i / arr.length, f1 = (i + 1.6) / arr.length; return `<polyline points="${polyline(m, f0, Math.min(f1, 0.9999))}" fill="none" stroke="${heat(v)}" stroke-width="9" stroke-linecap="round"/>`; }).join('') : '';
  // the selected corner: a glowing stretch either side of its marker, the reference car's slowest point and braking point
  const c0 = sel >= 0 ? track.corners[sel] : null;
  const focus = c0 ? (() => {
    const w = 0.022, f0 = c0.at - w, f1 = c0.at + w;
    const seg = f0 < 0 ? [[f0 + 1, 0.9999], [0, f1]] : f1 > 1 ? [[f0, 0.9999], [0, f1 - 1]] : [[f0, f1]];
    let g = seg.map(([a2, b2]) => `<polyline points="${polyline(m, a2, b2)}" fill="none" stroke="#ffffff" stroke-width="46" stroke-linecap="round" stroke-linejoin="round" opacity=".35"/><polyline points="${polyline(m, a2, b2)}" fill="none" stroke="#ffffff" stroke-width="14" stroke-linecap="round" stroke-linejoin="round"/>`).join('');
    if (opts.brakeAt != null) { const p = at(m, opts.brakeAt); g += `<g transform="translate(${p[0]},${p[1]})"><rect x="-26" y="-14" width="52" height="28" rx="6" fill="#e1131f" stroke="#fff" stroke-width="4"/><text text-anchor="middle" dy="7" fill="#fff" style="font-size:19px">BRAKE</text></g>`; }
    if (opts.apexAt != null) { const p = at(m, opts.apexAt); g += `<g transform="translate(${p[0]},${p[1]})"><circle r="16" fill="#ffc531" stroke="#0b1f4b" stroke-width="5"/><circle r="5" fill="#0b1f4b"/></g>`; }
    return g;
  })() : '';
  const glow = opts.speed ? '' : track.sectors.map((s, i) => {
    const dim = sector >= 0 && sector !== i;
    const pl = polyline(m, s.from, s.to);
    return `<polyline points="${pl}" fill="none" stroke="${SECTOR_COLORS[i]}" stroke-width="${sector === i ? 30 : 22}" stroke-linejoin="round" stroke-linecap="round" opacity="${dim ? 0.06 : 0.28}"/>
      <polyline points="${pl}" fill="none" stroke="${SECTOR_COLORS[i]}" stroke-width="${sector === i ? 9 : 6}" stroke-linejoin="round" stroke-linecap="round" opacity="${dim ? 0.25 : 1}"/>`;
  }).join('');
  // chequered start line across the road
  const p0 = at(m, 0), p1 = at(m, 0.004);
  const ang0 = Math.atan2(p1[1] - p0[1], p1[0] - p0[0]) * 180 / Math.PI;
  let cheq = ''; for (let k = 0; k < 6; k++) for (let r = 0; r < 2; r++) cheq += `<rect x="${-6 + r * 6}" y="${-18 + k * 6}" width="6" height="6" fill="${(k + r) % 2 ? '#fff' : '#111'}"/>`;
  // direction chevrons every ~12% of the lap
  let chev = '';
  for (let f = 0.06; f < 1; f += 0.12) { const a = at(m, f), c = at(m, f + 0.006); const an = Math.atan2(c[1] - a[1], c[0] - a[0]) * 180 / Math.PI; chev += `<path d="M-7 -8 L5 0 L-7 8" transform="translate(${a[0]},${a[1]}) rotate(${an.toFixed(1)})" fill="none" stroke="#fff" stroke-width="3.5" stroke-linecap="round" stroke-linejoin="round" opacity=".85"/>`; }
  const pins = track.corners.map((c, i) => {
    const p = at(m, c.at);
    const on = i === sel;
    const label = String(c.n).replace(/^T(?=\d)/, '').slice(0, 5);
    const r = on ? 40 : c.key ? 34 : 29;
    return `<g class="pin${on ? ' on' : ''}" data-i="${i}" transform="translate(${p[0]},${p[1]})">
      <circle r="${r + 10}" fill="transparent"/>
      <circle r="${r + 3}" cy="5" fill="rgba(0,0,0,.45)"/>
      <circle class="dot" r="${r}" fill="${on ? '#fff' : c.key ? 'url(#pinRed)' : 'url(#pinNavy)'}" stroke="#fff" stroke-width="5"/>
      <text text-anchor="middle" dy="${label.length > 3 ? 8 : 10}" fill="${on ? '#0b1f4b' : '#fff'}" style="font-size:${label.length > 3 ? 22 : 30}px">${label}</text>
    </g>`;
  }).join('');
  return `<svg viewBox="${b.x} ${b.y} ${b.w} ${b.h}" width="100%" preserveAspectRatio="xMidYMid meet" role="img" aria-label="${track.short} map">
    <defs><radialGradient id="pinRed" cx=".35" cy=".3"><stop offset="0" stop-color="#ff5a63"/><stop offset="1" stop-color="#b10d18"/></radialGradient>
      <radialGradient id="pinNavy" cx=".35" cy=".3"><stop offset="0" stop-color="#2b4f9e"/><stop offset="1" stop-color="#0b1f4b"/></radialGradient></defs>
    <polygon points="${all}" fill="none" stroke="rgba(0,0,0,.45)" stroke-width="58" stroke-linejoin="round" transform="translate(0 8)"/>
    <polygon points="${all}" fill="none" stroke="#e9edf5" stroke-width="50" stroke-linejoin="round"/>
    <polygon points="${all}" fill="none" stroke="#3d4452" stroke-width="42" stroke-linejoin="round"/>
    <polygon points="${all}" fill="none" stroke="rgba(255,255,255,.07)" stroke-width="2" stroke-dasharray="14 18" stroke-linejoin="round"/>
    ${glow}
    ${speedLine}
    ${chev}
    ${focus}
    <g transform="translate(${p0[0]},${p0[1]}) rotate(${ang0.toFixed(1)})">${cheq}</g>
    ${pins}
    <g id="aidot" style="display:none"><circle r="22" fill="rgba(31,91,255,.35)"/><circle r="12" fill="#1f5bff" stroke="#fff" stroke-width="5"/></g>
  </svg>`;
}

// Lap strip for tracks without geometry: a vertical ribbon of lap distance
// (start at the top), sectors coloured, a numbered badge at each corner's
// estimated position and its name beside it. Vertical so names stay full-size
// on a phone; badges are pushed apart when corners sit close together.
export function lapStrip(track, sel = -1) {
  const X = 70, Y0 = 50, Y1 = 50 + Math.max(640, track.corners.length * 62), MIN = 50;
  const y = (f) => Y0 + f * (Y1 - Y0);
  const ys = [];
  track.corners.forEach((c, i) => ys.push(Math.max(y(c.at), i ? ys[i - 1] + MIN : -1e9)));
  const over = ys.length ? ys.at(-1) - (Y1 - 20) : 0;
  if (over > 0) for (let i = ys.length - 1; i >= 0; i--) ys[i] = Math.min(ys[i], (i === ys.length - 1 ? Y1 - 20 : ys[i + 1] - MIN));
  const secs = track.sectors.map((s, i) => `<line x1="${X}" y1="${y(s.from)}" x2="${X}" y2="${y(s.to)}" stroke="${SECTOR_COLORS[i]}" stroke-width="12" stroke-linecap="round"/>
    <text x="${X - 34}" y="${(y(s.from) + y(s.to)) / 2}" text-anchor="middle" fill="${SECTOR_COLORS[i]}" style="font-size:16px" transform="rotate(-90 ${X - 34} ${(y(s.from) + y(s.to)) / 2})">S${i + 1}</text>`).join('');
  const esc = (t) => t.replace(/&/g, '&amp;').replace(/</g, '&lt;');
  const pins = track.corners.map((c, i) => {
    const on = i === sel, cy = ys[i], ty = y(c.at);
    const raw = String(c.n).replace(/^T(?=\d)/, '');
    const label = raw.length <= 5 ? raw : raw.slice(0, 3);
    return `<g class="pin${on ? ' on' : ''}" data-i="${i}">
      <rect x="${X + 30}" y="${cy - 24}" width="${400 - X - 34}" height="48" rx="10" fill="${on ? 'rgba(255,255,255,.14)' : 'transparent'}"/>
      ${Math.abs(cy - ty) > 2 ? `<path d="M${X} ${ty} L${X + 20} ${cy}" stroke="rgba(255,255,255,.4)" stroke-width="2"/>` : ''}
      <circle class="dot" cx="${X + 24}" cy="${cy}" r="${on ? 22 : 19}" fill="${on ? '#fff' : c.key ? '#e1131f' : '#0b1f4b'}" stroke="#fff" stroke-width="3.5"/>
      <text x="${X + 24}" y="${cy + 6}" text-anchor="middle" fill="${on ? '#0b1f4b' : '#fff'}" style="font-size:${label.length > 3 ? 12 : 16}px">${esc(label)}</text>
      <text x="${X + 56}" y="${cy + 7}" fill="${on ? '#ffc531' : '#fff'}" style="font-size:20px;font-style:normal;font-weight:600;font-family:Archivo,sans-serif">${esc(c.name.length > 22 ? c.name.slice(0, 21) + '…' : c.name)}</text>
    </g>`;
  }).join('');
  return `<svg class="strip-v" viewBox="0 0 400 ${Y1 + 40}" width="100%" preserveAspectRatio="xMidYMin meet" role="img" aria-label="${track.short} lap strip">
    <line x1="${X}" y1="${Y0}" x2="${X}" y2="${Y1}" stroke="#2a447f" stroke-width="20" stroke-linecap="round"/>
    ${secs}
    <rect x="${X - 22}" y="${Y0 - 4}" width="44" height="8" rx="2" fill="#fff"/>
    <text x="${X}" y="${Y0 - 16}" text-anchor="middle" fill="#9fb3e6" style="font-size:13px;font-style:normal;font-family:Archivo,sans-serif">START</text>
    <text x="${X}" y="${Y1 + 30}" text-anchor="middle" fill="#9fb3e6" style="font-size:13px;font-style:normal;font-family:Archivo,sans-serif">FINISH</text>
    ${pins}
  </svg>`;
}

// Concept map for Beyond the Apex: the whole lap dimmed, the demonstrated
// corners lit (a short stretch either side of each) and only their pins drawn.
export function focusMap(track, idxs = [], small = false) {
  const m = track.map && MAPS[track.map];
  if (!m) return lapStrip(track, idxs[0] ?? -1);
  const b = box(m, 70);
  const all = m.pts.map((p) => p.join(',')).join(' ');
  const W = 0.035;
  const lit = idxs.map((i) => track.corners[i]).filter(Boolean).map((c) => {
    const from = c.at - W, to = c.at + W;
    const seg = from < 0 ? [[from + 1, 1], [0, to]] : to > 1 ? [[from, 1], [0, to - 1]] : [[from, to]];
    return seg.map(([f, t]) => `<polyline points="${polyline(m, f, t)}" fill="none" stroke="#ffc531" stroke-width="${small ? 30 : 24}" stroke-linejoin="round" stroke-linecap="round"/>`).join('');
  }).join('');
  const p0 = at(m, 0);
  const pins = idxs.map((i) => track.corners[i]).filter(Boolean).map((c) => {
    const p = at(m, c.at);
    const label = String(c.n).replace(/^T(?=\d)/, '').slice(0, 5);
    const r = small ? 52 : 38;
    return `<g transform="translate(${p[0]},${p[1]})"><circle r="${r}" fill="#e1131f" stroke="#fff" stroke-width="6"/>
      <text text-anchor="middle" dy="${label.length > 3 ? 8 : 11}" fill="#fff" style="font-family:'Barlow Condensed';font-weight:800;font-style:italic;font-size:${(label.length > 3 ? 22 : 32) * (small ? 1.4 : 1)}px">${label}</text></g>`;
  }).join('');
  return `<svg viewBox="${b.x} ${b.y} ${b.w} ${b.h}" width="100%" height="100%" preserveAspectRatio="xMidYMid meet" role="img" aria-label="${track.short}: highlighted corners">
    <polygon points="${all}" fill="none" stroke="rgba(255,255,255,.10)" stroke-width="46" stroke-linejoin="round"/>
    <polygon points="${all}" fill="none" stroke="rgba(255,255,255,.5)" stroke-width="${small ? 16 : 12}" stroke-linejoin="round"/>
    ${lit}
    <circle cx="${p0[0]}" cy="${p0[1]}" r="${small ? 22 : 16}" fill="#fff"/>
    ${pins}
  </svg>`;
}
