// Battery and charging. Live from tesla.state (Phase 5), demo until then.

import { latest } from '../lib/bus.js';
import { miles, unitDist, pct } from '../lib/fmt.js';

export default {
  id: 'battery',
  title: 'Battery',
  order: 40,
  events: ['tesla.state'],

  summary(el, _d, ctx) {
    const s = latest('tesla.state');
    const u = ctx.store.get('units');
    if (!s) {
      el.innerHTML = `<div class="tile-head"><span class="label">Battery</span></div>
        <div class="tile-body"><div class="t-xl muted">Not linked</div><div class="t-sm faint">Tesla sign-in, once</div></div>`;
      return;
    }
    el.innerHTML = `
      <div class="tile-head"><span class="label">${s.charging ? 'Charging' : 'Battery'}</span><span class="t-sm faint num">${s.outside}° out · ${s.inside}° in</span></div>
      <div class="tile-body">
        <div class="display big num" style="${s.charging ? 'color:var(--good)' : ''}">${pct(s.soc)}</div>
        <div class="muted t-lg num">${miles(s.rangeKm, u)} ${unitDist(u)} ${s.charging ? `· ${s.chargeKw ?? '—'} kW` : 'rated'}</div>
        <div class="progress ${s.charging ? 'good' : ''}"><i style="width:${s.soc}%"></i></div>
      </div>`;
  },

  detail(el, _d, ctx) {
    const s = latest('tesla.state');
    const u = ctx.store.get('units');
    if (!s) { el.innerHTML = `<div class="t-2xl muted">Not linked</div>`; return; }
    el.innerHTML = `
      <div class="grid-3">
        ${stat('Charge', pct(s.soc))}
        ${stat('Range', miles(s.rangeKm, u), unitDist(u))}
        ${stat('Odometer', Math.round(+miles(s.odoKm, u)).toLocaleString('en-GB'), unitDist(u))}
        ${stat('Inside', s.inside, '°C')}
        ${stat('Outside', s.outside, '°C')}
        ${stat('State', s.charging ? 'Charging' : 'Idle')}
      </div>
      <div class="row" style="margin-top:2.4rem;gap:1.2rem">
        <button class="btn" data-act="climate">Climate on</button>
        <button class="btn" data-act="limit">Charge limit</button>
        <button class="btn quiet" data-act="flash">Flash lights</button>
      </div>
      <p class="t-sm faint" style="margin-top:1.6rem">Commands go live with the Tesla link (Phase 5).</p>`;
  },

  actions: {
    climate(ctx) { ctx.toast('Climate', 'Tesla link needed', 'bad'); },
    limit(ctx) { ctx.toast('Charge limit', 'Tesla link needed', 'bad'); },
    flash(ctx) { ctx.toast('Flash lights', 'Tesla link needed', 'bad'); },
  },
};

function stat(label, v, unit = '') {
  return `<div class="card stat"><span class="label">${label}</span><span class="display v num">${v}<span class="unit">${unit}</span></span></div>`;
}
