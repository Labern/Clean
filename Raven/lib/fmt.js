// Formatting for the car: miles by default, tabular numbers, short strings.

const MI_PER_KM = 0.621371;

export function miles(km, units = 'mi', digits = 0) {
  const v = units === 'km' ? km : km * MI_PER_KM;
  return v.toFixed(digits);
}
export function speed(kmh, units = 'mi') {
  return Math.round(units === 'km' ? kmh : kmh * MI_PER_KM);
}
export function unitDist(units = 'mi') { return units === 'km' ? 'km' : 'mi'; }
export function unitSpeed(units = 'mi') { return units === 'km' ? 'km/h' : 'mph'; }

// Efficiency: Wh per mile (or per km).
export function whPer(kwh, km, units = 'mi') {
  if (!km) return null;
  const dist = units === 'km' ? km : km * MI_PER_KM;
  return Math.round((kwh * 1000) / dist);
}

export function money(amount, currency = 'GBP') {
  const sym = { GBP: '£', EUR: '€', USD: '$' }[currency] || '';
  return `${sym}${amount.toFixed(2)}`;
}

export function pad2(n) { return String(n).padStart(2, '0'); }

export function clock(d = new Date()) {
  return `${pad2(d.getHours())}:${pad2(d.getMinutes())}`;
}

// 5s → "0:05", 65min → "1:05:00"; compact for the trip tile.
export function duration(ms) {
  const s = Math.max(0, Math.round(ms / 1000));
  const h = Math.floor(s / 3600), m = Math.floor((s % 3600) / 60), r = s % 60;
  return h ? `${h}:${pad2(m)}:${pad2(r)}` : `${m}:${pad2(r)}`;
}

// "2h 14m" style for stats.
export function hm(ms) {
  const m = Math.round(ms / 60000);
  const h = Math.floor(m / 60);
  return h ? `${h}h ${pad2(m % 60)}m` : `${m}m`;
}

export function ago(ts, now = Date.now()) {
  const s = Math.round((now - ts) / 1000);
  if (s < 60) return 'now';
  const m = Math.round(s / 60);
  if (m < 60) return `${m}m`;
  const h = Math.round(m / 60);
  if (h < 24) return `${h}h`;
  return `${Math.round(h / 24)}d`;
}

export function initials(name = '') {
  return name.trim().split(/\s+/).slice(0, 2).map(w => w[0] || '').join('').toUpperCase() || '?';
}

export function pct(n) { return `${Math.round(n)}%`; }

export function thousands(n) { return Math.round(n).toLocaleString('en-GB'); }
