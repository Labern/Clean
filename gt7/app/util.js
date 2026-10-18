export const $ = (sel, root = document) => root.querySelector(sel);
export const $$ = (sel, root = document) => [...root.querySelectorAll(sel)];

// Tagged template that escapes interpolations; nest with raw() for trusted HTML.
const ESC = { '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' };
export const esc = (v) => String(v ?? '').replace(/[&<>"']/g, (c) => ESC[c]);
class Raw { constructor(s) { this.s = s; } toString() { return this.s; } }
export const raw = (s) => new Raw(s);
export function html(strings, ...vals) {
  let out = strings[0];
  vals.forEach((v, i) => {
    if (Array.isArray(v)) out += v.map((x) => (x instanceof Raw ? x.s : esc(x))).join('');
    else out += v instanceof Raw ? v.s : esc(v);
    out += strings[i + 1];
  });
  return raw(out);
}

export const cr = (n) => (n == null || Number.isNaN(n) ? '—' : 'Cr. ' + Math.round(n).toLocaleString('en-GB'));
export const crShort = (n) => {
  if (n == null) return '—';
  if (n >= 1e6) return (n / 1e6).toFixed(n >= 1e7 ? 0 : 1).replace(/\.0$/, '') + 'M';
  if (n >= 1e3) return Math.round(n / 1e3) + 'k';
  return String(n);
};
export const hrs = (h) => (h < 1 ? Math.round(h * 60) + ' min' : h < 10 ? h.toFixed(1) + ' h' : Math.round(h) + ' h');

// 'm:ss.s' <-> seconds
export function toSec(t) {
  if (!t) return null;
  const m = String(t).trim().replace(/^~/, '').match(/^(?:(\d+):)?(\d+(?:\.\d+)?)$/);
  return m ? (+(m[1] || 0)) * 60 + +m[2] : null;
}
export function fmtSec(s) {
  if (s == null) return '—';
  const m = Math.floor(s / 60);
  return `${m}:${(s - m * 60).toFixed(1).padStart(4, '0')}`;
}

export function toast(msg) {
  let el = $('.toast');
  if (!el) { el = document.createElement('div'); el.className = 'toast'; document.body.append(el); }
  el.textContent = msg;
  el.classList.add('show');
  clearTimeout(el._t);
  el._t = setTimeout(() => el.classList.remove('show'), 1800);
}

export const clsClass = (c) => ({ 'Gr.1': 'gr1', 'Gr.3': 'gr3', 'Gr.4': 'gr4', N: 'n', X: 'x' }[c] || '');
