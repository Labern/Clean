/* ═══════════════════════════════════════════════════════════════════
   kittens/shared/core.js — the data layer every version shares.
   v1 (kittens/index.html) keeps its own inline copy and is left as it was;
   v2 (kittens/v2/) and the weight app (kittens/weight/) load this file.
   Everything here is extracted verbatim from v1 so the saved format is
   identical: same localStorage keys, same records, same seed ids, same
   encrypted sync topic. Two deliberate upgrades, both forward-compatible:
     1. merge() keeps collections it doesn't know (a future version's data
        is never dropped by an older one);
     2. save() merges with what is on disk first, so two versions open in
        two tabs can't overwrite each other's edits.
   Pages provide: renderAll(), and optionally #toast, #syncpill/#synctext.
   ═══════════════════════════════════════════════════════════════════ */
'use strict';

/* ═════════════ basics ═════════════ */
const $ = s => document.querySelector(s);
const DAY = 86400000;
const esc = s => String(s == null ? '' : s).replace(/[&<>"']/g, c => ({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
const uid = () => Math.random().toString(36).slice(2, 9) + Date.now().toString(36).slice(-5);
const pad = n => String(n).padStart(2, '0');
const ymd = d => d.getFullYear() + '-' + pad(d.getMonth() + 1) + '-' + pad(d.getDate());
const parseYmd = s => { const [y, m, d] = String(s).split('-').map(Number); return new Date(y, m - 1, d); };
const todayYmd = () => ymd(new Date());
const daysBetween = (a, b) => Math.round((parseYmd(b) - parseYmd(a)) / DAY);
const addDays = (s, n) => { const d = parseYmd(s); d.setDate(d.getDate() + n); return ymd(d); };
const nice = s => parseYmd(s).toLocaleDateString('en-GB', { weekday: 'short', day: 'numeric', month: 'short' });
const niceY = s => parseYmd(s).toLocaleDateString('en-GB', { day: 'numeric', month: 'short', year: 'numeric' });
const LEMON_G = 110;   // a medium lemon
const KIDS = ['misato', 'penpen'];
const LS = 'kittens.state.v1', LS_IMG = 'kittens.img.', LS_ME = 'kittens.me', LS_SECRET = 'kittens.secret';
const lsGet = k => { try { return localStorage.getItem(k); } catch (e) { return null; } };
const lsSet = (k, v) => { try { localStorage.setItem(k, v); return true; } catch (e) { return false; } };
const lsDel = k => { try { localStorage.removeItem(k); } catch (e) {} };

function toast(msg) { const t = $('#toast'); if (!t) return; t.textContent = msg; t.classList.add('on'); clearTimeout(toast.t); toast.t = setTimeout(() => t.classList.remove('on'), 2600); }
function rain(chars = ['🍋', '🐾', '💛', '🌙'], n = 22) {
  for (let i = 0; i < n; i++) {
    const r = document.createElement('span'); r.className = 'rain';
    r.textContent = chars[Math.floor(Math.random() * chars.length)];
    r.style.left = Math.random() * 100 + 'vw';
    r.style.animationDuration = (3 + Math.random() * 3.5) + 's';
    r.style.animationDelay = (Math.random() * 1.6) + 's';
    document.body.appendChild(r); setTimeout(() => r.remove(), 9000);
  }
}

/* ═════════════ the document ═════════════ */
const COLS = ['kittens', 'weights', 'events', 'foods', 'todos', 'shop', 'cams', 'care', 'photos', 'meta', 'msgs', 'costs', 'health', 'skills', 'bond'];
function seed() {
  const d = {}; COLS.forEach(c => d[c] = {});
  // ~6 weeks old when weighed on Wed 30 Sep 2026 → born ~19 Aug (estimate, editable)
  d.kittens.misato = { name: 'Misato', coat: 'white with black patches', sex: '', dob: '2026-08-19', dobEst: true, eye: '#8ec5ea', bio: '', chip: '', vet: '', ins: '', marks: 'black ears, patch over one eye, black tail · peach collar', photo: '', u: 2 };
  d.kittens.penpen = { name: 'Pen Pen', coat: 'black tuxedo', sex: '', dob: '2026-08-19', dobEst: true, eye: '#8ec5ea', bio: '', chip: '', vet: '', ins: '', marks: 'white blaze, moustache spot, white bib + paws · blue collar', photo: '', u: 2 };
  d.weights['w-seed-misato'] = { k: 'misato', date: '2026-09-30', g: 700, approx: true, by: 'lemon', u: 1 };
  d.weights['w-seed-penpen'] = { k: 'penpen', date: '2026-09-30', g: 600, approx: true, by: 'lemon', u: 1 };
  d.events['e-seed-weigh'] = { date: '2026-09-30', k: 'both', type: 'milestone', text: 'First weigh-in — Misato ~700g, Pen Pen ~600g. About six weeks old.', by: 'lemon', u: 1 };
  // UK kitten schedule — dueAge = days after birthday; due date follows DOB edits
  const T = [
    ['vet', 'Register with a vet', 'both', 0, 0, 'health'],
    ['ins', 'Pet insurance — before anything goes wrong', 'both', 0, 0, 'health'],
    ['worm', 'Worming (every 2 weeks until 12 weeks, then monthly)', 'both', 56, 14, 'health'],
    ['flea', 'Flea treatment — kitten-safe, from the vet', 'both', 56, 30, 'health'],
    ['vax1', '1st vaccination — cat flu + enteritis (8–9 weeks)', 'both', 63, 0, 'health'],
    ['vax2', '2nd vaccination (3–4 weeks after the 1st)', 'both', 86, 0, 'health'],
    ['chip', 'Microchip — the law in England by 20 weeks', 'both', 120, 0, 'health'],
    ['spay', 'Neuter / spay (from ~4 months)', 'both', 122, 0, 'health'],
    ['out', 'First supervised garden time (after vax + neuter)', 'both', 135, 0, 'home'],
    ['food', 'Switch from kitten food to adult food', 'both', 365, 0, 'home'],
    ['boost', 'First annual booster', 'both', 450, 0, 'health'],
    ['teeth', 'Start tooth-brushing practice (tiny bits, lots of praise)', 'both', 70, 0, 'home'],
    ['proof', 'Kitten-proof: cables, blind cords, toilet lid, washing machine door', 'both', 0, 0, 'home'],
  ];
  T.forEach(([id, title, k, dueAge, rep, cat]) => d.todos['t-seed-' + id] = { title, k, dueAge, rep, cat, done: false, u: 1 });
  const S = ['Kitten food — wet + dry, labelled "kitten"', 'Wide shallow food & water bowls', 'Water fountain (cats drink more from moving water)',
    'Litter trays ×3 (one per cat + one)', 'Kitten-safe litter + scoop', 'Tall, sturdy scratching post', 'Flat cardboard scratcher',
    'Top-opening carrier (vet trips get easier)', 'Cosy bed / cave', 'Wand toy + crinkle balls', 'Soft kitten brush', 'Cat nail clippers',
    'Feliway diffuser (settling in)', 'Cat toothbrush + cat toothpaste', 'Window / balcony screens', 'Quick-release collars (after microchip)'];
  S.forEach((t, i) => d.shop['s-seed-' + i] = { title: t, note: '', done: false, u: 1 });
  seedExtras(d);
  return d;
}

function seedExtras(d) {
  const S = [['name', 'Comes to their name'], ['carrier', 'Happy going into the carrier'], ['paws', 'Lets you hold paws'], ['nails', 'Nail trim without drama'],
    ['brush', 'Enjoys being brushed'], ['teeth', 'Tooth-brushing (a few seconds)'], ['shake', 'Comes to the treat-bag shake'], ['scratch', 'Scratches the post, not the sofa'],
    ['gentle', 'Plays with toys, not hands'], ['harness', 'Wears a harness for 5 minutes'], ['ears', 'Lets you look in ears & mouth'], ['handled', 'Calm being picked up']];
  S.forEach(([id, t], i) => d.skills['k-seed-' + id] = { title: t, order: i, lv: { misato: 0, penpen: 0 }, u: 1 });
}

function load() {
  let d = null; try { d = JSON.parse(lsGet(LS)); } catch (e) {}
  const s = seed();
  if (!d || typeof d !== 'object') return s;
  COLS.forEach(c => { d[c] = Object.assign({}, s[c], d[c] || {}); });   // hydrate over defaults, never drop keys
  return merge(d, s).out;   // a newer seed revision (higher u) updates untouched seed records; user edits always win
}
// per record, newest u wins — over EVERY collection either side has, known or not
// one record from each side → the kept record. Newest u wins each field it has;
// fields only the older side has are KEPT (a newer version's additions are never
// dropped by an older version's edit). Deletes are whole: a tombstone stays a
// tombstone, and a record revived after a delete starts clean.
function mergeRec(A, B) {
  if (!B) return A; if (!A) return B;
  const bNewer = (B.u || 0) > (A.u || 0), newer = bNewer ? B : A, older = bNewer ? A : B;
  const res = (newer.del || older.del) ? newer : Object.assign({}, older, newer);
  const ka = Object.keys(A), kr = Object.keys(res);
  return ka.length === kr.length && kr.every(k => k in A && JSON.stringify(res[k]) === JSON.stringify(A[k])) ? A : res;
}
function merge(a, b) {
  const out = {}; let changedA = false;
  const keys = new Set([...COLS, ...Object.keys(a || {}), ...Object.keys(b || {})]);
  keys.forEach(c => {
    const A = a && a[c], B = b && b[c];
    if ((A && typeof A !== 'object') || (B && typeof B !== 'object')) { out[c] = A !== undefined ? A : B; return; }
    out[c] = Object.assign({}, A || {});
    for (const [id, rec] of Object.entries(B || {})) {
      const res = mergeRec(out[c][id], rec);
      if (res !== out[c][id]) { out[c][id] = res; if (a) changedA = true; }
    }
  });
  return { out, changedA };
}
let doc = load();
const SITTER = false;
function save() {
  let disk = null; try { disk = JSON.parse(lsGet(LS)); } catch (e) {}
  if (disk && typeof disk === 'object') doc = merge(doc, disk).out;     // never clobber another tab / version
  if (!lsSet(LS, JSON.stringify(doc))) toast('⚠️ couldn\'t save — phone storage is full. Download a backup.');
}
function put(col, id, rec) { if (!doc[col]) doc[col] = {}; doc[col][id] = Object.assign({}, doc[col][id] || {}, rec, { u: Date.now() }); save(); changed(); }
function del(col, id) { if (!doc[col]) doc[col] = {}; doc[col][id] = { del: true, u: Date.now() }; save(); changed(); }
const live = col => Object.entries(doc[col] || {}).filter(([, r]) => r && !r.del);
function changed() { if (typeof renderAll === 'function') renderAll(); schedulePublish(); }
// another tab (any version) saved — pull it in
window.addEventListener('storage', e => { if (e.key === LS) { doc = merge(doc, load()).out; if (typeof renderAll === 'function') renderAll(); } });

let me = lsGet(LS_ME) || 'lemon';
const WHO = { lemon: '🍋', girl: '🌙' };
function setMe(v) { me = v; lsSet(LS_ME, v); }
const hhmm = ms => new Date(ms).toLocaleTimeString('en-GB', { hour: '2-digit', minute: '2-digit' });
const agoMs = ms => { const s = Math.round((Date.now() - ms) / 1000); if (s < 60) return 'just now'; const m = Math.round(s / 60); if (m < 60) return m + ' min ago';
  const h = Math.floor(m / 60), mm = m % 60; if (h < 24) return h + 'h' + (mm ? ' ' + mm + 'm' : '') + ' ago'; return Math.floor(h / 24) + ' day' + (h >= 48 ? 's' : '') + ' ago'; };
const meta = k => (doc.meta[k] && !doc.meta[k].del) ? doc.meta[k] : {};
/* ═════════════ kitten maths ═════════════ */
const K = id => doc.kittens[id];
const kname = id => id === 'both' ? 'Both' : (K(id) ? K(id).name : id);
function ageDays(id, at = todayYmd()) { const k = K(id); return k && k.dob ? daysBetween(k.dob, at) : null; }
function ageStr(days) {
  if (days == null) return '?';
  if (days < 0) return 'not born yet';
  if (days < 7 * 16) { const w = Math.floor(days / 7), d = days % 7; return w + ' wk' + (d ? ' ' + d + ' d' : ''); }
  const m = Math.floor(days / 30.44); if (m < 24) return m + ' months';
  return (days / 365.25).toFixed(1) + ' years';
}
function humanYears(days) {   // the usual vet-chart curve, interpolated
  const P = [[0, 0], [1, 1], [2, 2], [3, 4], [4, 6], [6, 10], [8, 13], [12, 15], [24, 24]];
  const m = days / 30.44;
  if (m >= 24) return 24 + (m - 24) / 12 * 4;
  for (let i = 1; i < P.length; i++) if (m <= P[i][0]) { const [x0, y0] = P[i - 1], [x1, y1] = P[i]; return y0 + (y1 - y0) * (m - x0) / (x1 - x0); }
  return 0;
}
function weightsOf(id) { return live('weights').map(([wid, w]) => Object.assign({ id: wid }, w)).filter(w => w.k === id).sort((a, b) => a.date.localeCompare(b.date) || a.u - b.u); }
function latest(id) { const w = weightsOf(id); return w[w.length - 1] || null; }
// typical healthy kitten: ~100g at birth, gaining ~10–17g a day for the first few months
const guide = days => { const d = Math.max(0, Math.min(days, 180)); return [Math.round(95 + 10 * d - (d > 120 ? (d - 120) * 3 : 0)), Math.round(115 + 17 * d - (d > 120 ? (d - 120) * 5 : 0))]; };
function rate(id) {   // g/day from the last few points, or from birth if only one
  const w = weightsOf(id); if (!w.length) return null;
  const pts = w.slice(-4);
  if (pts.length >= 2) {
    const a = pts[0], b = pts[pts.length - 1], dd = daysBetween(a.date, b.date);
    if (dd >= 2) return (b.g - a.g) / dd;
  }
  const ad = ageDays(id, w[w.length - 1].date); return ad > 0 ? (w[w.length - 1].g - 100) / ad : null;
}
function projectDate(id, target) { const l = latest(id), r = rate(id); if (!l || !r || r <= 0 || l.g >= target) return null; return addDays(l.date, Math.ceil((target - l.g) / r)); }
function projectAt(id, date) { const l = latest(id), r = rate(id); if (!l || r == null) return null; return Math.round(l.g + r * daysBetween(l.date, date)); }
function estNow(id) { const l = latest(id); if (!l) return null; const p = projectAt(id, todayYmd()); return daysBetween(l.date, todayYmd()) > 0 && p ? p : l.g; }
/* ═════════════ cartoons ═════════════ */
/* drawn from their photos:
   Pen Pen — black tuxedo: white blaze between the eyes, white muzzle with a
   black "moustache" spot under the nose, white bib + paws, pale-blue collar w/ bell.
   Misato — white with black patches: black ears, black patch over her left eye,
   black blotches on the back, black tail, peach collar. */
let svgN = 0;
function kittenSVG(id, opt = {}) {
  const k = K(id) || {}; const pen = id === 'penpen'; const n = ++svgN;
  const BLK = '#2b2b30', WHT = '#fbfaf6', O = '#111';
  const F = pen ? BLK : WHT;                                  // base coat
  const eye = k.eye || '#8ec5ea';
  const tail = opt.still ? '' : ' class="k-tail"';
  const head = 'M36 86 a64 53 0 1 0 128 0 a64 53 0 1 0 -128 0 Z', body = 'M43 160 a57 47 0 1 0 114 0 a57 47 0 1 0 -114 0 Z';
  const earL = 'M44 74 L50 16 L94 46 Z', earR = 'M156 74 L150 16 L106 46 Z';
  const bodyMarks = pen
    ? `<path d="M74 116 Q100 108 126 116 Q124 158 100 184 Q76 158 74 116 Z" fill="${WHT}"/>`
    : `<ellipse cx="136" cy="146" rx="34" ry="26" fill="${BLK}"/><ellipse cx="62" cy="180" rx="20" ry="13" fill="${BLK}"/><ellipse cx="150" cy="190" rx="16" ry="10" fill="${BLK}"/>`;
  const headMarks = pen
    ? `<path d="M100 50 C 95 66, 92 80, 87 94 C 74 104, 70 126, 100 134 C 130 126, 126 104, 113 94 C 108 80, 105 66, 100 50 Z" fill="${WHT}"/>`
    : `<path d="M30 52 C 44 30, 78 26, 98 38 C 96 56, 98 76, 94 102 C 74 110, 46 104, 30 94 Z" fill="${BLK}"/><path d="M118 34 C 134 34, 158 44, 166 64 C 150 64, 132 58, 118 48 Z" fill="${BLK}"/>`;
  const mouth = O;                                            // both have white muzzles
  const paw = WHT, toe = '#bbb';
  const collar = pen ? '#9fd3e8' : '#ffb38a';
  return `<svg viewBox="0 0 210 220" width="${opt.w || 150}" aria-label="${esc(k.name)} cartoon">
  <defs><clipPath id="hc${n}"><path d="${head}"/></clipPath><clipPath id="bc${n}"><path d="${body}"/></clipPath></defs>
  <path${tail} d="M150 182 C 205 182, 214 120, 182 100 C 172 94, 163 106, 172 112 C 192 126, 186 168, 146 168 Z" fill="${BLK}" stroke="${O}" stroke-width="5" stroke-linejoin="round"/>
  <path d="${body}" fill="${F}"/><g clip-path="url(#bc${n})">${bodyMarks}</g><path d="${body}" fill="none" stroke="${O}" stroke-width="5"/>
  <ellipse cx="78" cy="203" rx="17" ry="10" fill="${paw}" stroke="${O}" stroke-width="4.5"/>
  <ellipse cx="122" cy="203" rx="17" ry="10" fill="${paw}" stroke="${O}" stroke-width="4.5"/>
  <path d="M72 200 v6 M80 200 v7 M116 200 v7 M124 200 v6" stroke="${toe}" stroke-width="2.4" stroke-linecap="round"/>
  <path d="${earL}" fill="${BLK}" stroke="${O}" stroke-width="5" stroke-linejoin="round"/>
  <path d="${earR}" fill="${BLK}" stroke="${O}" stroke-width="5" stroke-linejoin="round"/>
  <path d="M55 60 L58 32 L80 48 Z" fill="#c97a9a"/><path d="M145 60 L142 32 L120 48 Z" fill="#c97a9a"/>
  <path d="${head}" fill="${F}"/><g clip-path="url(#hc${n})">${headMarks}</g><path d="${head}" fill="none" stroke="${O}" stroke-width="5"/>
  <ellipse cx="72" cy="60" rx="14" ry="7" fill="rgba(255,255,255,.13)" transform="rotate(-18 72 60)"/>
  <g class="k-eyes">
    <ellipse cx="74" cy="86" rx="14" ry="16" fill="#fff" stroke="${O}" stroke-width="3"/>
    <ellipse cx="126" cy="86" rx="14" ry="16" fill="#fff" stroke="${O}" stroke-width="3"/>
    <circle cx="75" cy="88" r="10.5" fill="${eye}"/><circle cx="125" cy="88" r="10.5" fill="${eye}"/>
    <ellipse cx="75" cy="89" rx="4.5" ry="7.5" fill="#111"/><ellipse cx="125" cy="89" rx="4.5" ry="7.5" fill="#111"/>
    <circle cx="71" cy="82" r="3.8" fill="#fff"/><circle cx="121" cy="82" r="3.8" fill="#fff"/>
    <circle cx="79" cy="94" r="1.8" fill="#fff"/><circle cx="129" cy="94" r="1.8" fill="#fff"/>
  </g>
  <ellipse cx="56" cy="110" rx="9" ry="5" fill="#ff8fab" opacity="${pen ? .4 : .55}"/>
  <ellipse cx="144" cy="110" rx="9" ry="5" fill="#ff8fab" opacity=".55"/>
  <path d="M93 103 L107 103 L100 111 Z" fill="#f49ac1" stroke="${O}" stroke-width="2.4" stroke-linejoin="round"/>
  ${pen ? '<ellipse cx="96" cy="118" rx="7.5" ry="4.2" fill="#2b2b30"/>' : ''}
  <path d="M100 111 Q100 120 91 120 M100 111 Q100 120 109 120" fill="none" stroke="${mouth}" stroke-width="2.6" stroke-linecap="round"/>
  <path d="M62 104 L16 96 M62 110 L14 112" stroke="${pen ? '#e8e8e8' : '#555'}" stroke-width="2.2" stroke-linecap="round"/>
  <path d="M138 104 L184 96 M138 110 L186 112" stroke="${pen ? '#e8e8e8' : '#555'}" stroke-width="2.2" stroke-linecap="round"/>
  <path d="M60 130 Q100 150 140 130" fill="none" stroke="${O}" stroke-width="10" stroke-linecap="round"/>
  <path d="M60 130 Q100 150 140 130" fill="none" stroke="${collar}" stroke-width="5.5" stroke-linecap="round"/>
  ${pen ? `<circle cx="100" cy="146" r="7" fill="#9fd3e8" stroke="${O}" stroke-width="3"/><path d="M95 147 h10" stroke="${O}" stroke-width="2"/>` : `<circle cx="100" cy="145" r="5" fill="#f4c93c" stroke="${O}" stroke-width="2.5"/>`}
</svg>`;
}
function girlSVG(w) {
  return `<svg viewBox="0 0 160 250" width="${w}" aria-label="the girl">
  <path d="M30 78 C 22 140, 34 168, 52 172 L108 172 C 126 168, 138 140, 130 78 C 124 30, 36 30, 30 78 Z" fill="#3b2a24" stroke="#000" stroke-width="5"/>
  <path d="M58 150 L102 150 L128 228 L32 228 Z" fill="#b15ee3" stroke="#000" stroke-width="5" stroke-linejoin="round"/>
  <text x="62" y="200" font-size="18">⭐</text><text x="84" y="216" font-size="12">✨</text>
  <path d="M60 162 Q 38 180 46 204" fill="none" stroke="#000" stroke-width="12" stroke-linecap="round"/><path d="M60 162 Q 38 180 46 204" fill="none" stroke="#ffd9bf" stroke-width="6" stroke-linecap="round"/>
  <path d="M100 162 Q 124 176 116 200" fill="none" stroke="#000" stroke-width="12" stroke-linecap="round"/><path d="M100 162 Q 124 176 116 200" fill="none" stroke="#ffd9bf" stroke-width="6" stroke-linecap="round"/>
  <path d="M62 228 v16 M98 228 v16" stroke="#000" stroke-width="8" stroke-linecap="round"/>
  <ellipse cx="58" cy="245" rx="12" ry="5" fill="#ff595e" stroke="#000" stroke-width="3"/><ellipse cx="102" cy="245" rx="12" ry="5" fill="#ff595e" stroke="#000" stroke-width="3"/>
  <rect x="72" y="128" width="16" height="26" fill="#ffd9bf" stroke="#000" stroke-width="4"/>
  <ellipse cx="80" cy="92" rx="44" ry="46" fill="#ffe2cc" stroke="#000" stroke-width="5"/>
  <path d="M36 88 C 36 50, 60 40, 80 42 C 104 42, 126 52, 124 88 C 112 70, 96 64, 84 56 C 74 70, 52 76, 36 88 Z" fill="#3b2a24" stroke="#000" stroke-width="4.5" stroke-linejoin="round"/>
  <path d="M112 46 a 14 14 0 1 0 14 20 a 11 11 0 1 1 -14 -20 Z" fill="#ffca3a" stroke="#000" stroke-width="3"/>
  <ellipse cx="64" cy="98" rx="5" ry="6.5" fill="#111"/><ellipse cx="96" cy="98" rx="5" ry="6.5" fill="#111"/>
  <circle cx="62" cy="95.5" r="1.8" fill="#fff"/><circle cx="94" cy="95.5" r="1.8" fill="#fff"/>
  <ellipse cx="54" cy="112" rx="8" ry="4.5" fill="#ff8fab" opacity=".6"/><ellipse cx="106" cy="112" rx="8" ry="4.5" fill="#ff8fab" opacity=".6"/>
  <path d="M68 116 Q 80 128 92 116" fill="none" stroke="#000" stroke-width="3.5" stroke-linecap="round"/>
</svg>`;
}

/* stage — kittens drawn to scale with each other (size ∝ ∛weight) */
const photoURL = id => id ? lsGet(LS_IMG + id) : null;
function dueOf(t) {
  if (t.due) return t.due;
  if (t.dueAge == null) return null;
  const dobs = (t.k === 'both' ? KIDS : [t.k]).map(id => K(id) && K(id).dob).filter(Boolean).sort();
  if (!dobs.length) return null;
  const d = addDays(dobs[0], t.dueAge);
  return t.dueAge === 0 ? (daysBetween(d, todayYmd()) > 0 ? todayYmd() : d) : d;
}
function todos() { return live('todos').map(([id, t]) => Object.assign({ id }, t, { due: dueOf(t) })); }
function nextTodo() { return todos().filter(t => !t.done && t.due).sort((a, b) => a.due.localeCompare(b.due))[0] || null; }
function shrink(file, max) {
  return new Promise((ok, no) => {
    const url = URL.createObjectURL(file), img = new Image();
    img.onload = () => { const s = Math.min(1, max / Math.max(img.width, img.height)); const c = document.createElement('canvas');
      c.width = Math.round(img.width * s); c.height = Math.round(img.height * s); c.getContext('2d').drawImage(img, 0, 0, c.width, c.height);
      URL.revokeObjectURL(url); ok(c.toDataURL('image/jpeg', 0.72)); };
    img.onerror = () => { URL.revokeObjectURL(url); toast("couldn't read that image"); no(); };
    img.src = url;
  });
}
function addPhoto(data, meta) {
  const id = 'p' + uid();
  if (!lsSet(LS_IMG + id, data)) toast('⚠️ phone storage full — download a backup and remove some photos');
  put('photos', id, Object.assign({ by: me }, meta));
  publishImg(id, data);
  return id;
}
const STAGES = [
  [0, 42, 'Tiny babies', ['Mostly sleeping and feeding', 'Eyes open ~1–2 weeks, ears ~2–3 weeks', 'Wobbly walking at ~3–4 weeks']],
  [42, 56, 'Weaning wild things', ['Nearly fully on solid kitten food — 4 small meals a day', 'Play-fighting, pouncing, climbing everything', 'Socialisation window closing: lots of gentle handling, new sounds, kind visitors', 'Eye colour starting to change']],
  [56, 84, 'Vaccine season', ['1st vaccination from 8–9 weeks, 2nd 3–4 weeks later', 'Worming every 2 weeks until 12 weeks', 'Indoors only until vaccinated', 'Start handling paws, ears and mouth for future nail trims & teeth']],
  [84, 120, 'Little explorers', ['Vaccinations done ~a week after the 2nd jab', 'Baby teeth start falling out from ~3–4 months — chew toys!', 'Book neutering (~4 months)', 'Microchip by 20 weeks (law in England)']],
  [120, 182, 'Teenagers in training', ['Neutering around now', 'Adult teeth coming through — gums may be sore', 'First supervised garden trips once neutered + vaccinated + chipped', '3–4 meals a day']],
  [182, 365, 'Adolescents', ['Peak chaos: night zoomies are normal', 'Down to 2–3 meals a day', 'Keep up flea & worm treatment', 'Adult size by about 12 months']],
  [365, 99999, 'Grown-ups', ['Switch to adult food around 12 months', 'Annual booster + health check', 'Still kittens at heart']],
];
/* ═════════════ sync — encrypted, retained, on public MQTT relays ═════════════
   Same relay trick as cycle/: a retained message is a tiny keyed store.
   Difference: everything is AES-GCM encrypted with a key that only lives in
   the pairing link's #fragment, and the topic is a hash of it — the relays
   (and anyone listening on '#') only see noise. Photos ride on their own
   retained topics so the main doc stays small. Every phone keeps a full
   copy and re-publishes the merged doc on connect, so the relays are just
   a meeting point — the data lives on both phones. */
const BROKERS = window.KT_BROKERS || ['wss://broker.emqx.io:8084/mqtt', 'wss://broker.hivemq.com:8884/mqtt', 'wss://test.mosquitto.org:8081/'];
let secret = lsGet(LS_SECRET), cryptoKey = null, topic = null, conns = [], pubTimer = null, lastSync = 0;
const seenImg = new Set();
const te = new TextEncoder(), td = new TextDecoder();
const b64 = buf => { let s = ''; const b = new Uint8Array(buf); for (let i = 0; i < b.length; i += 0x8000) s += String.fromCharCode.apply(null, b.subarray(i, i + 0x8000)); return btoa(s); };
const unb64 = s => Uint8Array.from(atob(s), c => c.charCodeAt(0));
async function sha(s) { return new Uint8Array(await crypto.subtle.digest('SHA-256', te.encode(s))); }
async function enc(obj) { const iv = crypto.getRandomValues(new Uint8Array(12)); const ct = await crypto.subtle.encrypt({ name: 'AES-GCM', iv }, cryptoKey, te.encode(JSON.stringify(obj))); const out = new Uint8Array(12 + ct.byteLength); out.set(iv); out.set(new Uint8Array(ct), 12); return b64(out); }
async function dec(str) { const b = unb64(str); const pt = await crypto.subtle.decrypt({ name: 'AES-GCM', iv: b.slice(0, 12) }, cryptoKey, b.slice(12)); return JSON.parse(td.decode(pt)); }

function syncLabel() {
  const n = conns.filter(c => c.connected).length;
  if (!window.crypto || !crypto.subtle || typeof mqtt === 'undefined') return setSync('warn', 'saved on this phone (sync unavailable)');
  if (!n) return setSync('warn', 'saved here · connecting…');
  const ago = lastSync ? Math.round((Date.now() - lastSync) / 1000) : null;
  setSync('ok', `synced${ago != null ? (ago < 5 ? ' just now' : ago < 60 ? ` ${ago}s ago` : ` ${Math.round(ago / 60)} min ago`) : ''} · ${n}/${BROKERS.length} relays`);
}
setInterval(syncLabel, 5000);

async function initSync() {
  if (SITTER) { setSync('', 'read-only sitter view'); return; }
  // adopt a pairing key from the link
  const m = location.hash.match(/pair=([A-Za-z0-9_-]{16,})/);
  if (m) { secret = m[1]; lsSet(LS_SECRET, secret); history.replaceState(null, '', location.pathname); setTimeout(() => { toast('📲 paired! syncing with the other phone…'); rain(['💛', '📲', '🐾']); }, 600); }
  if (!secret) { const r = crypto.getRandomValues(new Uint8Array(18)); secret = b64(r).replace(/\+/g, '-').replace(/\//g, '_').replace(/=/g, ''); lsSet(LS_SECRET, secret); }
  if (!window.crypto || !crypto.subtle || typeof mqtt === 'undefined') { syncLabel(); return; }
  cryptoKey = await crypto.subtle.importKey('raw', await sha('kittens-key:' + secret), 'AES-GCM', false, ['encrypt', 'decrypt']);
  topic = 'kittens/v1/' + [...(await sha('kittens-topic:' + secret))].slice(0, 12).map(x => x.toString(16).padStart(2, '0')).join('');
  conns.forEach(c => { try { c.end(true); } catch (e) {} }); conns = [];
  BROKERS.forEach(url => {
    let c; try { c = mqtt.connect(url, { clientId: 'kt_' + Math.random().toString(36).slice(2, 10), clean: true, reconnectPeriod: 5000, connectTimeout: 10000, keepalive: 45 }); } catch (e) { return; }
    conns.push(c);
    c.on('connect', () => {
      c.subscribe([topic, topic + '/img/+'], { qos: 1 });
      syncLabel();
      // after retained copies arrive, push our merged doc + any photos this relay is missing
      setTimeout(async () => { await publishDoc(c); for (const [id] of live('photos')) if (!seenImg.has(url + id)) { const d = lsGet(LS_IMG + id); if (d) publishImgTo(c, id, d); } }, 3500);
    });
    c.on('close', syncLabel);
    c.on('message', async (t, payload) => {
      const s = payload.toString(); if (!s) return;
      try {
        if (t === topic) {
          const remote = await dec(s); lastSync = Date.now();
          const { out, changedA } = merge(doc, remote);
          if (changedA) { doc = out; save(); renderAll(); }
          if (merge(remote, doc).changedA) schedulePublish();   // they're missing something of ours
          syncLabel();
        } else if (t.startsWith(topic + '/img/')) {
          const id = t.slice(topic.length + 5); seenImg.add(url + id);
          if (!lsGet(LS_IMG + id)) { const { data } = await dec(s); if (data && lsSet(LS_IMG + id, data)) renderAll(); }
        }
      } catch (e) { /* wrong key or garbage — ignore */ }
    });
  });
}
async function publishDoc(c) { if (!cryptoKey || !c.connected) return; try { c.publish(topic, await enc(doc), { retain: true, qos: 1 }); lastSync = Date.now(); syncLabel(); } catch (e) {} }
async function publishImgTo(c, id, data) { if (!cryptoKey || !c.connected) return; try { c.publish(topic + '/img/' + id, await enc({ data }), { retain: true, qos: 1 }); } catch (e) {} }
function publishImg(id, data) { conns.forEach(c => publishImgTo(c, id, data)); }
function clearImg(id) { conns.forEach(c => { try { if (c.connected) c.publish(topic + '/img/' + id, '', { retain: true, qos: 1 }); } catch (e) {} }); }
function schedulePublish() { clearTimeout(pubTimer); pubTimer = setTimeout(() => conns.forEach(publishDoc), 700); }
function pairLink() { return location.origin + location.pathname + '#pair=' + secret; }
function setSync(cls, txt) { const p = document.getElementById('syncpill'), t = document.getElementById('synctext'); if (!p || !t) return; p.classList.remove('ok', 'warn'); if (cls) p.classList.add(cls); t.textContent = txt; }
function exportBackup() {
  const imgs = {}; live('photos').forEach(([id]) => { const d = lsGet(LS_IMG + id); if (d) imgs[id] = d; });
  const blob = new Blob([JSON.stringify({ kittensBackup: 1, at: new Date().toISOString(), doc, imgs })], { type: 'application/json' });
  const a = document.createElement('a'); a.href = URL.createObjectURL(blob); a.download = `misato-penpen-backup-${todayYmd()}.json`; a.click(); setTimeout(() => URL.revokeObjectURL(a.href), 4000);
}


/* ═════════════ long-range growth model (v2 + weight app) ═════════════
   A reference curve for a typical domestic kitten: the middle of guide()'s
   band to 6 months, then easing out to ~4 kg at a year and a little after.
   A kitten's projection = their own latest weight × how much the reference
   curve grows from their age then to the target age — so big kittens stay
   big, small stay small, and growth slows the way real kittens' does. */
function refCurve(d) {
  if (d <= 180) { const [lo, hi] = guide(Math.max(0, d)); return (lo + hi) / 2; }
  const r180 = refCurve(180), A = 4000;
  if (d >= 365) return A + Math.min(300, (d - 365) * 300 / 180);
  const t = (d - 180) / 185; return r180 + (A - r180) * (1 - (1 - t) * (1 - t));
}
function projCurve(id, date) {
  const l = latest(id); if (!l) return null;
  const a = ageDays(id, l.date), b = ageDays(id, date);
  if (a == null || b == null) return projectAt(id, date);
  return Math.round(l.g * refCurve(b) / refCurve(a));
}
function whenReaches(id, target, maxDays = 900) {
  const l = latest(id); if (!l) return null; if (l.g >= target) return null;
  for (let i = 1; i <= maxDays; i++) { const d = addDays(l.date, i); if (projCurve(id, d) >= target) return d; }
  return null;
}
function firstWeigh(id) { return weightsOf(id)[0] || null; }

/* ═════════════ the archive — everything in one plain-text file ═════════════
   An OPTION for keeping a copy outside the phone; nothing depends on it.
   Format "misato-penpen-archive" v1 (JSON, UTF-8):
     { format, version, exportedAt, exportedBy, from,
       doc,            ← the complete dataset, every collection, tombstones too
       imgs,           ← { photoId: "data:image/jpeg;base64,…" } every photo on this phone
       counts, summary,← human-readable overview (ignored on restore)
       check }         ← SHA-256 of JSON.stringify({doc, imgs}) — detects damage
   `doc` + `imgs` keep the same names as the original backup, so v1's own
   Restore button reads these files too. The .html variant is a self-contained
   viewer page with the identical JSON inside <script id="kittens-archive">. */
const ARCHIVE_FORMAT = 'misato-penpen-archive';
async function sha256hex(str) { try { return [...new Uint8Array(await crypto.subtle.digest('SHA-256', new TextEncoder().encode(str)))].map(b => b.toString(16).padStart(2, '0')).join(''); } catch (e) { return null; } }
function allImages() {
  const imgs = {}; try { for (let i = 0; i < localStorage.length; i++) { const k = localStorage.key(i); if (k && k.startsWith(LS_IMG)) { const v = localStorage.getItem(k); if (v) imgs[k.slice(LS_IMG.length)] = v; } } } catch (e) {}
  return imgs;
}
async function buildArchive() {
  save();                                                    // pull in anything another tab wrote
  const imgs = allImages(), d = JSON.parse(JSON.stringify(doc));
  const liveOf = c => Object.values(d[c] || {}).filter(r => r && !r.del);
  const wanted = Object.keys(d.photos || {}).filter(id => d.photos[id] && !d.photos[id].del);
  const counts = {}; Object.keys(d).forEach(c => { if (d[c] && typeof d[c] === 'object') counts[c] = liveOf(c).length; });
  counts.images = Object.keys(imgs).length; counts.imagesMissingOnThisPhone = wanted.filter(id => !imgs[id]).length;
  const summary = {
    kittens: KIDS.map(id => ({ id, name: (d.kittens[id] || {}).name, born: (d.kittens[id] || {}).dob, coat: (d.kittens[id] || {}).coat })),
    weights: liveOf('weights').sort((a, b) => a.date.localeCompare(b.date)).map(w => `${w.date}${w.time ? ' ' + w.time : ''}  ${((d.kittens[w.k] || {}).name || w.k).padEnd(8)} ${w.g} g${w.note ? '  — ' + w.note : ''}`),
  };
  const check = await sha256hex(JSON.stringify({ doc: d, imgs }));
  return { format: ARCHIVE_FORMAT, version: 1, exportedAt: new Date().toISOString(), exportedBy: me, from: location.pathname, kittensBackup: 1, counts, summary, doc: d, imgs, check };
}
function downloadText(name, text, type) { const a = document.createElement('a'); a.href = URL.createObjectURL(new Blob([text], { type })); a.download = name; document.body.appendChild(a); a.click(); a.remove(); setTimeout(() => URL.revokeObjectURL(a.href), 8000); }
async function exportArchive(kind = 'json') {
  const A = await buildArchive(), json = JSON.stringify(A), stamp = new Date().toISOString().slice(0, 16).replace(/[:T]/g, '-');
  const mb = (json.length / 1048576).toFixed(1);
  if (kind === 'html') downloadText(`misato-penpen-archive-${stamp}.html`, archiveHTML(A, json), 'text/html');
  else downloadText(`misato-penpen-archive-${stamp}.json`, json, 'application/json');
  toast(`💾 saved ${A.counts.weights || 0} weigh-ins, ${A.counts.images} photos, everything else · ${mb} MB${A.counts.imagesMissingOnThisPhone ? ` · ⚠️ ${A.counts.imagesMissingOnThisPhone} photos still syncing` : ''}`);
  return A;
}
function exportBackup() { return exportArchive('json'); }   // old name, kept for callers
// read either file kind (or v1's older backups) → append-only merge; never deletes or overwrites newer data
async function importArchive(file) {
  let text = await file.text(), j;
  if (/^\s*</.test(text)) { const m = text.match(/<script type="application\/json" id="kittens-archive">([\s\S]*?)<\/script>/); if (!m) throw new Error('no archive inside this page'); text = m[1].replace(/<\\\//g, '</'); }
  j = JSON.parse(text); if (!j || !j.doc) throw new Error("that isn't a Misato & Pen Pen archive");
  let damaged = false; if (j.check) { const c = await sha256hex(JSON.stringify({ doc: j.doc, imgs: j.imgs || {} })); damaged = c && c !== j.check; }
  if (damaged && !confirm('This file looks damaged or edited (its checksum doesn\'t match). Merge what can be read anyway?')) return null;
  let newImgs = 0; Object.entries(j.imgs || {}).forEach(([id, d]) => { if (!lsGet(LS_IMG + id) && typeof d === 'string' && d.startsWith('data:image')) { if (lsSet(LS_IMG + id, d)) { newImgs++; publishImg(id, d); } } });
  const before = JSON.stringify(doc); doc = merge(doc, j.doc).out; save(); changed();
  const res = { newImgs, changed: before !== JSON.stringify(doc), damaged, exportedAt: j.exportedAt };
  toast(`📂 restored — ${newImgs} new photos${res.changed ? ', new data merged in' : ', nothing new in the data'}${damaged ? ' (file was damaged)' : ''}`);
  return res;
}
// the self-contained, browser-viewable archive page
function archiveHTML(A, json) {
  const e = s => String(s == null ? '' : s).replace(/[&<>"]/g, c => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;' }[c]));
  const d = A.doc, name = id => (d.kittens[id] || {}).name || id, L = c => Object.entries(d[c] || {}).filter(([, r]) => r && !r.del).map(([id, r]) => Object.assign({ id }, r));
  const W = L('weights').sort((a, b) => a.date.localeCompare(b.date));
  const P = L('photos').sort((a, b) => (a.date || '').localeCompare(b.date || ''));
  const rows = W.map(w => `<tr><td>${e(w.date)}${w.time ? ' ' + e(w.time) : ''}</td><td>${e(name(w.k))}</td><td><b>${e(w.g)} g</b>${w.approx ? ' ~' : ''}</td><td>${e(w.note || '')}</td>${w.photo && A.imgs[w.photo] ? `<td><img src="${A.imgs[w.photo]}" style="width:56px;height:56px;object-fit:cover;border-radius:50%;border:2px solid #000"></td>` : '<td></td>'}</tr>`).join('');
  const gal = P.filter(p => A.imgs[p.id]).map(p => `<figure><img src="${A.imgs[p.id]}" alt=""><figcaption>${e(p.k === 'both' ? 'Both' : name(p.k))} · ${e(p.date || '')}${p.caption ? ' · ' + e(p.caption) : ''}</figcaption></figure>`).join('');
  const list = (c, f) => L(c).sort((a, b) => (b.date || '').localeCompare(a.date || '')).map(f).join('');
  const ev = list('events', x => `<li><b>${e(x.date)}</b> ${e(x.text)}</li>`), td = list('todos', x => `<li>${x.done ? '✅' : '⬜'} ${e(x.title)}${x.due ? ' · ' + e(x.due) : ''}</li>`), bd = list('bond', x => `<li><b>${e(x.date)}</b> ${x.by === 'girl' ? '🌙' : '🍋'} + ${e(name(x.k))} ${'💗'.repeat(x.score || 0)} ${e(x.text || '')}</li>`);
  const kit = A.summary.kittens.map(k => `<div class="k"><b>${e(k.name)}</b><br>born ${e(k.born || '?')}<br>${e(k.coat || '')}</div>`).join('');
  return `<!DOCTYPE html><html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>Misato &amp; Pen Pen — archive ${e(A.exportedAt.slice(0, 10))}</title>
<style>html{min-height:100%;background:linear-gradient(180deg,#ff595e,#ff924c 16%,#ffca3a 33%,#8ac926 50%,#1982c4 67%,#6a4c93 84%,#b15ee3) fixed}body{font-family:"Comic Sans MS","Chalkboard SE",system-ui,sans-serif;margin:0;padding:20px 16px 60px;color:#111}
main{max-width:980px;margin:0 auto}h1{color:#fff;text-shadow:3px 3px 0 #6a4c93;text-align:center;font-size:clamp(2rem,8vw,3.4rem);margin:0}
.sub{color:#fff;text-align:center;font-weight:900;text-shadow:1px 1px 0 rgba(0,0,0,.3)}section{background:#fffdf5;border:4px solid #000;border-radius:24px;box-shadow:6px 7px 0 #000;padding:16px 18px;margin:22px 0}
h2{margin:0 0 10px;color:#6a4c93}.ks{display:flex;gap:10px;flex-wrap:wrap}.k{background:#fff;border:3px solid #000;border-radius:16px;padding:8px 14px}
table{border-collapse:collapse;width:100%;font-size:.92rem}td{border-bottom:2px dashed #ddd;padding:6px}.g{display:grid;grid-template-columns:repeat(auto-fill,minmax(160px,1fr));gap:10px}
figure{margin:0;background:#fff;border:3px solid #000;border-radius:12px;padding:6px}figure img{width:100%;border-radius:8px;display:block;cursor:zoom-in}figcaption{font-size:.78rem;font-weight:700;margin-top:4px}
li{margin:4px 0}button{font:inherit;font-weight:900;border:3px solid #000;border-radius:999px;background:#ffca3a;padding:.4em 1em;cursor:pointer}code{background:#eee;padding:1px 5px;border-radius:5px}</style></head>
<body><main><h1>Misato &amp; Pen Pen</h1><div class="sub">🍋 archive saved ${e(new Date(A.exportedAt).toLocaleString('en-GB'))} 🌙</div>
<section><h2>📦 What's in here</h2><p><b>${W.length}</b> weigh-ins · <b>${Object.keys(A.imgs).length}</b> photos · <b>${L('events').length}</b> moments · <b>${L('todos').length}</b> to-dos · <b>${L('bond').length}</b> bond notes · and every other record the app has, in full.</p>
<p>This page needs no internet and no app. The complete data lives inside it as JSON — open it in any version of the tracker and use <b>📂 Restore</b> to put it all back.</p>
<button onclick="const a=document.createElement('a');a.href=URL.createObjectURL(new Blob([document.getElementById('kittens-archive').textContent],{type:'application/json'}));a.download='misato-penpen-archive.json';a.click()">⬇️ Download the JSON inside</button>
<p style="font-size:.8rem">Checksum (SHA-256): <code>${e(A.check || 'n/a')}</code></p><div class="ks">${kit}</div></section>
<section><h2>⚖️ Every weigh-in</h2><table>${rows || '<tr><td>none yet</td></tr>'}</table></section>
<section><h2>📸 Every photo</h2><div class="g">${gal || 'none yet'}</div></section>
${ev ? `<section><h2>📅 Moments</h2><ul>${ev}</ul></section>` : ''}${bd ? `<section><h2>💞 Winning them over</h2><ul>${bd}</ul></section>` : ''}${td ? `<section><h2>✅ To-do</h2><ul>${td}</ul></section>` : ''}
</main><script>document.querySelectorAll('figure img').forEach(i=>i.onclick=()=>window.open().document.write('<img src="'+i.src+'" style="max-width:100%">'))<\/script>
<script type="application/json" id="kittens-archive">${json.replace(/<\//g, '<\\/')}</script></body></html>`;
}
