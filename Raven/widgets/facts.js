// Facts: the numbers the car never tells you, one at a time.

import { latest } from '../lib/bus.js';
import { stats } from '../lib/drives.js';
import { miles, speed, unitDist, unitSpeed, hm, thousands } from '../lib/fmt.js';

let idx = 0;
let rot = null;

function facts(ctx) {
  const h = latest('drives.history');
  if (!h || !h.drives.length) return [];
  const u = ctx.store.get('units');
  const s = stats(h.drives);
  const out = [
    { v: thousands(+miles(s.totalKm, u)), unit: unitDist(u), k: 'Driven since logging began', sub: `${s.count} drives` },
    { v: hm(s.totalMs), k: 'Time behind the wheel', sub: `${hm(s.totalMs / s.count)} per drive` },
    { v: speed(s.avgSpeed, u), unit: unitSpeed(u), k: 'Average moving speed' },
    { v: miles(s.longest.distanceKm, u), unit: unitDist(u), k: 'Longest drive', sub: new Date(s.longest.startTs).toLocaleDateString('en-GB', { day: 'numeric', month: 'short' }) },
    { v: speed(s.fastest.maxSpeed, u), unit: unitSpeed(u), k: 'Fastest you have gone' },
    { v: (s.moonFraction * 100).toFixed(1), unit: '%', k: 'Of the way to the Moon' },
    { v: (s.earthLaps * 100).toFixed(1), unit: '%', k: 'Of a lap of the Earth' },
  ];
  if (s.whPerKm) out.push({ v: Math.round(u === 'km' ? s.whPerKm : s.whPerKm / 0.621371), unit: `Wh/${unitDist(u)}`, k: 'Lifetime efficiency' });
  if (s.bestWhPerKm) out.push({ v: Math.round(u === 'km' ? s.bestWhPerKm : s.bestWhPerKm / 0.621371), unit: `Wh/${unitDist(u)}`, k: 'Your most efficient drive' });
  return out;
}

export default {
  id: 'facts',
  title: 'Facts',
  order: 50,
  events: ['drives.history', 'facts.next'],

  summary(el, _d, ctx) {
    const list = facts(ctx);
    if (!list.length) {
      el.innerHTML = `<div class="tile-head"><span class="label">Facts</span></div>
        <div class="tile-body"><div class="t-xl muted">No drives yet</div></div>`;
      return;
    }
    const f = list[idx % list.length];
    el.innerHTML = `
      <div class="tile-head"><span class="label">Facts</span><span class="t-sm faint num">${(idx % list.length) + 1}/${list.length}</span></div>
      <div class="tile-body">
        <div class="display big num">${f.v}<span class="unit">${f.unit || ''}</span></div>
        <div class="muted t-lg">${f.k}</div>
        ${f.sub ? `<div class="t-sm faint">${f.sub}</div>` : ''}
      </div>`;
    if (!rot) rot = setInterval(() => { idx++; ctx.emit('facts.next'); }, 12000);
  },

  detail(el, _d, ctx) {
    const list = facts(ctx);
    el.innerHTML = list.length
      ? `<div class="grid-3">${list.map(f => `<div class="card stat"><span class="label">${f.k}</span><span class="display v num">${f.v}<span class="unit">${f.unit || ''}</span></span>${f.sub ? `<span class="t-sm faint">${f.sub}</span>` : ''}</div>`).join('')}</div>`
      : `<div class="t-2xl muted">No drives yet</div>`;
  },
};
