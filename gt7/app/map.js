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
  return `<svg viewBox="${b.x} ${b.y} ${b.w} ${b.h}" aria-hidden="true">
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
  return `<svg viewBox="${b.x} ${b.y} ${b.w} ${b.h}" role="img" aria-label="${track.short} map">
    <polygon points="${all}" fill="none" stroke="rgba(255,255,255,.10)" stroke-width="46" stroke-linejoin="round"/>
    <polygon points="${all}" fill="none" stroke="rgba(255,255,255,.35)" stroke-width="20" stroke-linejoin="round"/>
    ${secs}
    <g transform="translate(${p0[0]},${p0[1]})"><rect x="-26" y="-9" width="52" height="18" rx="3" fill="#fff" transform="rotate(${ang + 90})"/></g>
    <g transform="translate(${p1[0]},${p1[1]}) rotate(${ang})"><path d="M-14 -14 L14 0 L-14 14 Z" fill="#fff"/></g>
    ${pins}
  </svg>`;
}

// Lap strip for tracks without geometry (and as a secondary view for all).
export function lapStrip(track, sel = -1) {
  const secs = track.sectors.map((s, i) => `<div class="sec" style="left:${s.from * 100}%;width:${(s.to - s.from) * 100}%;background:${SECTOR_COLORS[i]}"></div>`).join('');
  const ticks = track.corners.map((c, i) => `<div class="tick${c.key ? ' k' : ''}" data-i="${i}" style="left:${c.at * 100}%"><span>${String(c.n)}</span><i style="${i === sel ? 'background:#e1131f' : ''}"></i></div>`).join('');
  return `<div class="strip"><div class="track"></div>${secs}${ticks}</div>`;
}
