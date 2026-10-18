// Track drawings. Real circuits: the OSM geometry from data/maps.js, with the
// sectors coloured and a pin per corner at its measured lap fraction. GT
// originals: a lap strip (distance along the lap), since there is no geometry.
import { MAPS } from '../data/maps.js';

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
    <polyline points="${all}" fill="none" stroke="rgba(255,255,255,.14)" stroke-width="34" stroke-linejoin="round" stroke-linecap="round"/>
    <polygon points="${all}" fill="none" stroke="#fff" stroke-width="12" stroke-linejoin="round"/>
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
export function fullMap(track, sel = -1, sector = -1) {
  const m = track.map && MAPS[track.map];
  if (!m) return null;
  const b = box(m, 70);
  const all = m.pts.map((p) => p.join(',')).join(' ');
  const secs = track.sectors.map((s, i) => {
    const dim = sector >= 0 && sector !== i;
    return `<polyline points="${polyline(m, s.from, s.to)}" fill="none" stroke="${SECTOR_COLORS[i]}" stroke-width="${sector === i ? 20 : 13}" stroke-linejoin="round" stroke-linecap="round" opacity="${dim ? 0.25 : 1}"/>`;
  }).join('');
  // direction arrow a little after the start line
  const p0 = at(m, 0), p1 = at(m, 0.012), p2 = at(m, 0.02);
  const ang = Math.atan2(p2[1] - p1[1], p2[0] - p1[0]) * 180 / Math.PI;
  const pins = track.corners.map((c, i) => {
    const p = at(m, c.at);
    const on = i === sel;
    const label = String(c.n).replace(/^T/, '').slice(0, 5);
    const r = on ? 40 : c.key ? 34 : 29;
    return `<g class="pin${on ? ' on' : ''}" data-i="${i}" transform="translate(${p[0]},${p[1]})">
      <circle r="${r + 10}" fill="transparent"/>
      <circle class="dot" r="${r}" fill="${on ? '#fff' : c.key ? '#e1131f' : '#0b1f4b'}" stroke="#fff" stroke-width="5"/>
      <text text-anchor="middle" dy="${label.length > 3 ? 8 : 10}" fill="${on ? '#0b1f4b' : '#fff'}" style="font-size:${label.length > 3 ? 22 : 30}px">${label}</text>
    </g>`;
  }).join('');
  return `<svg viewBox="${b.x} ${b.y} ${b.w} ${b.h}" width="100%" preserveAspectRatio="xMidYMid meet" role="img" aria-label="${track.short} map">
    <polygon points="${all}" fill="none" stroke="rgba(255,255,255,.10)" stroke-width="46" stroke-linejoin="round"/>
    <polygon points="${all}" fill="none" stroke="rgba(255,255,255,.35)" stroke-width="20" stroke-linejoin="round"/>
    ${secs}
    <g transform="translate(${p0[0]},${p0[1]})"><rect x="-26" y="-9" width="52" height="18" rx="3" fill="#fff" transform="rotate(${ang + 90})"/></g>
    <g transform="translate(${p1[0]},${p1[1]}) rotate(${ang})"><path d="M-14 -14 L14 0 L-14 14 Z" fill="#fff"/></g>
    ${pins}
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
      <text x="${X + 56}" y="${cy + 7}" fill="${on ? '#ffc531' : '#fff'}" style="font-size:20px;font-style:normal;font-weight:600;font-family:Barlow,sans-serif">${esc(c.name.length > 22 ? c.name.slice(0, 21) + '…' : c.name)}</text>
    </g>`;
  }).join('');
  return `<svg class="strip-v" viewBox="0 0 400 ${Y1 + 40}" width="100%" preserveAspectRatio="xMidYMin meet" role="img" aria-label="${track.short} lap strip">
    <line x1="${X}" y1="${Y0}" x2="${X}" y2="${Y1}" stroke="#2a447f" stroke-width="20" stroke-linecap="round"/>
    ${secs}
    <rect x="${X - 22}" y="${Y0 - 4}" width="44" height="8" rx="2" fill="#fff"/>
    <text x="${X}" y="${Y0 - 16}" text-anchor="middle" fill="#9fb3e6" style="font-size:13px;font-style:normal;font-family:Barlow,sans-serif">START</text>
    <text x="${X}" y="${Y1 + 30}" text-anchor="middle" fill="#9fb3e6" style="font-size:13px;font-style:normal;font-family:Barlow,sans-serif">FINISH</text>
    ${pins}
  </svg>`;
}
