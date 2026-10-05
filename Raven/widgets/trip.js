// Current drive, live.

import { latest } from '../lib/bus.js';
import { miles, speed, unitDist, unitSpeed, whPer, duration } from '../lib/fmt.js';

export default {
  id: 'trip',
  title: 'Trip',
  order: 30,
  events: ['drive.update', 'tick'],

  summary(el, _d, ctx) {
    const d = latest('drive.update');
    const u = ctx.store.get('units');
    if (!d) {
      el.innerHTML = `<div class="tile-head"><span class="label">Trip</span></div>
        <div class="tile-body"><div class="t-xl muted">Parked</div></div>`;
      return;
    }
    const w = whPer(d.kwh, d.distanceKm, u);
    el.innerHTML = `
      <div class="tile-head"><span class="label">Trip</span><span class="t-sm faint num">${duration(Date.now() - d.startTs)}</span></div>
      <div class="tile-body">
        <div class="display big num">${miles(d.distanceKm, u, 1)}<span class="unit">${unitDist(u)}</span></div>
        <div class="row" style="gap:2.4rem">
          <span class="display t-2xl num">${speed(d.speed, u)}<span class="unit">${unitSpeed(u)}</span></span>
          <span class="display t-2xl num">${w ?? '—'}<span class="unit">Wh/${unitDist(u)}</span></span>
        </div>
      </div>`;
  },

  detail(el, _d, ctx) {
    const d = latest('drive.update');
    const u = ctx.store.get('units');
    if (!d) { el.innerHTML = `<div class="t-2xl muted">Parked</div>`; return; }
    const ms = Date.now() - d.startTs;
    const avg = ms ? d.distanceKm / (ms / 3600000) : 0;
    el.innerHTML = `
      <div class="grid-4">
        ${stat('Distance', miles(d.distanceKm, u, 1), unitDist(u))}
        ${stat('Time', duration(ms))}
        ${stat('Average', speed(avg, u), unitSpeed(u))}
        ${stat('Top speed', speed(d.maxSpeed, u), unitSpeed(u))}
        ${stat('Energy', d.kwh.toFixed(1), 'kWh')}
        ${stat('Efficiency', whPer(d.kwh, d.distanceKm, u) ?? '—', `Wh/${unitDist(u)}`)}
        ${stat('Now', speed(d.speed, u), unitSpeed(u))}
      </div>`;
  },
};

function stat(label, v, unit = '') {
  return `<div class="card stat"><span class="label">${label}</span><span class="display v num">${v}<span class="unit">${unit}</span></span></div>`;
}
