// Corner notes: a sheet that slides up (phone) or in from the side (desktop)
// for one corner of one Circuit Experience section. The corner drawn from the
// demo with your last attempt over it, the demo's numbers, your history there,
// your notes (with a verdict for the ones you're trying) and notes the data suggests.
import { $, $$, esc, toast } from './util.js';
import * as store from './state.js';
import * as L from './laps.js';
import * as CE from './ce.js';
import { series } from './compare.js';
import { trackById } from '../data/tracks.js';
import { sectionName } from '../data/ce.js';

const STATUS = { trying: ['Trying', 'try'], works: ['Works', 'ok'], nope: ['Didn\'t work', 'no'], note: ['Note', 'plain'] };
let open = null;

export function closeSheet() { if (!open) return; open.el.classList.remove('in'); const el = open.el; setTimeout(() => el.remove(), 220); document.body.classList.remove('sheet-open'); open = null; }
window.addEventListener('hashchange', closeSheet);
window.addEventListener('keydown', (e) => { if (e.key === 'Escape') closeSheet(); });

export function openCornerSheet(tid, n, cn) {
  closeSheet();
  const el = document.createElement('div');
  el.className = 'sheet-wrap';
  el.innerHTML = '<div class="sheet-back"></div><div class="sheet" role="dialog" aria-modal="true"><div class="sheet-body"></div></div>';
  document.body.appendChild(el);
  document.body.classList.add('sheet-open');
  open = { el, tid, n, cn };
  requestAnimationFrame(() => el.classList.add('in'));
  $('.sheet-back', el).onclick = closeSheet;
  paint();
}

async function paint(keepDraft) {
  if (!open) return;
  const { el, tid, n, cn } = open, x = CE.sec(tid, n), cs = CE.corners(x), c = cs.find((y) => y.n === cn);
  const body = $('.sheet-body', el);
  if (!c) { body.innerHTML = '<p class="muted">Record the demo first: corners come from it.</p>'; return; }
  const draft = keepDraft ?? '';
  const h = CE.history(x, cn), notes = CE.notesFor(x, cn), sug = CE.suggest(x, cn).filter((s) => !notes.some((no) => no.text === s.text));
  const last = h.at(-1), best = h.length ? Math.min(...h.map((r) => r.mini)) : null, avg = h.length ? h.slice(-5).reduce((a, r) => a + r.mini, 0) / Math.min(5, h.length) : null;
  const idx = cs.indexOf(c), prev = cs[idx - 1], next = cs[idx + 1];
  const gap = (v) => (v == null ? '—' : `${v > 0 ? '+' : v < 0 ? '−' : '±'}${Math.abs(v).toFixed(3)}`);
  // history bars: one per attempt, up = slower than the demo here
  const hh = h.slice(-24), mx = Math.max(0.05, ...hh.map((r) => Math.abs(r.mini)));
  const noteTimes = (x.notes || []).filter((no) => CE.cornerOf(x, no.a)?.n === cn).map((no) => no.t);
  const bars = hh.map((r, i) => { const v = r.mini / mx, w = 100 / Math.max(8, hh.length); const marker = noteTimes.some((t) => t <= r.t0 && (i === 0 || hh[i - 1].t0 < t)) ? `<line x1="${i * w}" x2="${i * w}" y1="0" y2="60" stroke="#ffc531" stroke-width="0.8" stroke-dasharray="2 1.5"/>` : '';
    return `${marker}<rect x="${i * w + w * 0.15}" width="${w * 0.7}" y="${v > 0 ? 30 - v * 28 : 30}" height="${Math.max(0.8, Math.abs(v) * 28)}" rx="0.8" fill="${v > 0 ? '#ff6b73' : '#36d399'}"/>`; }).join('');
  body.innerHTML = `
    <div class="sheet-head">
      <button class="sh-nav" data-go="${prev?.n ?? ''}" ${prev ? '' : 'disabled'} aria-label="Previous corner">‹</button>
      <div class="sh-title"><div class="kicker">${esc(trackById[tid].short)} · ${esc(sectionName(tid, n))}</div><h2>Corner ${cn}</h2></div>
      <button class="sh-nav" data-go="${next?.n ?? ''}" ${next ? '' : 'disabled'} aria-label="Next corner">›</button>
      <button class="sh-close" aria-label="Close">✕</button>
    </div>
    <div class="sh-grid">
      <div class="sh-map" id="sh-map"><div class="muted small" style="padding:20px">Drawing…</div></div>
      <div class="sh-ref">
        <div class="sh-stat"><span>Demo brakes</span><b>${c.brakeAt == null ? 'no brake' : Math.round(c.a - c.brakeAt) + ' m'}</b><i>${c.brakeAt == null ? '' : 'before apex'}</i></div>
        <div class="sh-stat"><span>Demo apex</span><b>${c.min}</b><i>km/h · gear ${c.gear}</i></div>
        <div class="sh-stat"><span>Your last</span><b class="${last?.mini > 0 ? 'lose' : 'gain'}">${gap(last?.mini)}</b><i>${last ? `${last.you} km/h · ${last.brake == null ? '' : last.brake === 0 ? 'brake same' : Math.abs(last.brake) + ' m ' + (last.brake < 0 ? 'early' : 'late')}` : 'no attempt yet'}</i></div>
        <div class="sh-stat"><span>Avg · best</span><b>${gap(avg)}</b><i>best ${gap(best)}</i></div>
      </div>
    </div>
    ${hh.length ? `<div class="sh-hist"><div class="kicker">Every attempt here vs the demo <span class="muted small" style="letter-spacing:0;text-transform:none;font-style:normal">· yellow line = you wrote a note</span></div><svg viewBox="0 0 100 60" preserveAspectRatio="none"><line x1="0" x2="100" y1="30" y2="30" stroke="#c4cde0" stroke-width="0.4"/>${bars}</svg></div>` : ''}
    ${last?.tips?.length ? `<div class="sh-last"><b>Last attempt:</b> ${last.tips.map(esc).join('; ')}</div>` : ''}
    <div class="sh-add">
      <textarea id="sh-text" rows="3" placeholder="What will you do differently here? e.g. brake at the 100 board, trail off to the apex kerb">${esc(draft)}</textarea>
      <div class="row" style="justify-content:space-between"><div class="seg" id="sh-kind"><button data-k="trying" class="on">Try it</button><button data-k="note">Just a note</button></div><button class="btn red" id="sh-save">Add note</button></div>
    </div>
    <div class="sh-notes">${notes.length ? notes.map((no) => noteHtml(x, no)).join('') : '<p class="muted small">No notes for this corner yet. Write one, drive, and the app tells you whether it worked.</p>'}</div>
    ${sug.length ? `<div class="sh-sug"><div class="kicker">The data says</div>${sug.map((s, i) => `<button class="sug" data-s="${i}"><span>${esc(s.text)}</span><b>＋</b></button>`).join('')}</div>` : ''}`;
  $('.sh-close', body).onclick = closeSheet;
  $$('[data-go]', body).forEach((b) => (b.onclick = () => { if (!b.dataset.go) return; open.cn = +b.dataset.go; paint(); }));
  let kind = 'trying';
  $$('#sh-kind button', body).forEach((b) => (b.onclick = () => { kind = b.dataset.k; $$('#sh-kind button', body).forEach((y) => y.classList.toggle('on', y === b)); }));
  $('#sh-save', body).onclick = () => { const t = $('#sh-text', body).value; if (!t.trim()) return $('#sh-text', body).focus(); CE.addNote(tid, n, cn, t, kind); toast(kind === 'trying' ? 'Noted. Drive it and see' : 'Noted'); paint(); changed(); };
  $$('.sug', body).forEach((b) => (b.onclick = () => { const s = sug[+b.dataset.s]; CE.addNote(tid, n, cn, s.text, s.kind === 'demo' ? 'note' : 'trying'); paint(); changed(); }));
  $$('[data-st]', body).forEach((b) => (b.onclick = () => { CE.editNote(tid, n, b.dataset.id, { status: b.dataset.st }); paint(); changed(); }));
  $$('[data-del]', body).forEach((b) => (b.onclick = () => { if (confirm('Delete this note?')) { CE.delNote(tid, n, b.dataset.del); paint(); changed(); } }));
  $$('[data-edit]', body).forEach((b) => (b.onclick = () => {
    const no = (x.notes || []).find((y) => y.id === b.dataset.edit), card = b.closest('.note');
    $('.note-text', card).outerHTML = `<textarea class="note-edit" rows="3">${esc(no.text)}</textarea>`;
    b.textContent = 'Save'; b.onclick = () => { CE.editNote(tid, n, no.id, { text: $('.note-edit', card).value.trim() || no.text }); paint(); changed(); };
  }));
  drawMap($('#sh-map', body), x, c);
}
const changed = () => window.dispatchEvent(new CustomEvent('gt7-notes-changed'));

function noteHtml(x, no) {
  const v = no.status === 'trying' ? CE.verdict(x, no) : null, [label, cls] = STATUS[no.status] || STATUS.note;
  return `<div class="note ${cls}">
    <div class="row" style="justify-content:space-between;gap:8px"><span class="npill ${cls}">${label}</span><span class="muted small">${new Date(no.t).toLocaleDateString(undefined, { day: 'numeric', month: 'short' })}</span></div>
    <div class="note-text">${esc(no.text)}</div>
    ${v ? `<div class="verdict ${v.state}">${esc(v.text)}</div>` : ''}
    <div class="note-acts">${no.status === 'trying' ? `<button data-st="works" data-id="${no.id}">✓ Works</button><button data-st="nope" data-id="${no.id}">✗ Didn't</button>` : `<button data-st="trying" data-id="${no.id}">Try again</button>`}<button data-edit="${no.id}">Edit</button><button data-del="${no.id}">Delete</button></div>
  </div>`;
}

// the corner itself: the demo's line, your last attempt, both brake points, the apex
async function drawMap(box, x, c) {
  const demo = await L.getLap(x.demo), lastId = (x.runs || []).find((r) => r.complete && !r.demo && r.cs)?.id, you = lastId && (await L.getLap(lastId));
  if (!demo || !box.isConnected) { box.innerHTML = ''; return; }
  const d = series(demo), yu = you && series(you);
  const a0 = Math.max(c.zone?.[0] ?? c.a - 150, (c.brakeAt ?? c.a) - 60), a1 = Math.min(c.zone?.[1] ?? c.a + 120, c.a + 110);
  const seg = [], pt = (s) => { let i = d.d.findIndex((v) => v >= s); if (i < 0) i = d.n - 1; return [d.x[i], d.z[i], i]; };
  for (let i = 0; i < d.n; i++) if (d.d[i] >= a0 && d.d[i] <= a1) seg.push([d.x[i], d.z[i]]);
  if (seg.length < 2) { box.innerHTML = ''; return; }
  const xs = seg.map((p) => p[0]), zs = seg.map((p) => p[1]), cx = (Math.min(...xs) + Math.max(...xs)) / 2, cz = (Math.min(...zs) + Math.max(...zs)) / 2;
  const r = Math.max(45, Math.max(...xs) - Math.min(...xs), Math.max(...zs) - Math.min(...zs)) / 2 + 34, sw = r / 60;
  const near = (p) => Math.abs(p[0] - cx) < r * 1.3 && Math.abs(p[1] - cz) < r * 1.3;
  const line = (S, col, w, dash = '') => { const pts = []; for (let i = 0; i < S.n; i++) { const p = [S.x[i], S.z[i]]; if (near(p)) pts.push(p.map((v) => v.toFixed(1)).join(',')); } return pts.length > 1 ? `<polyline points="${pts.join(' ')}" fill="none" stroke="${col}" stroke-width="${w}" stroke-linecap="round" stroke-linejoin="round" ${dash}/>` : ''; };
  const tick = (s, col, label) => { const [px, pz, i] = pt(s), j = Math.max(1, i), dx = d.x[j] - d.x[j - 1], dz = d.z[j] - d.z[j - 1], Lh = Math.hypot(dx, dz) || 1, nx = -dz / Lh * sw * 9, nz = dx / Lh * sw * 9;
    return `<line x1="${px - nx}" y1="${pz - nz}" x2="${px + nx}" y2="${pz + nz}" stroke="${col}" stroke-width="${sw * 1.6}" stroke-linecap="round"/><text x="${px + nx * 1.5}" y="${pz + nz * 1.5}" fill="${col}" text-anchor="middle" dominant-baseline="middle" style="font-size:${sw * 5}px;font-weight:800">${label}</text>`; };
  const lastRec = CE.history(x, c.n).at(-1);
  const [ax, az] = pt(c.a);
  box.innerHTML = `<svg viewBox="${cx - r} ${cz - r} ${2 * r} ${2 * r}" preserveAspectRatio="xMidYMid meet">
    ${line(d, 'rgba(255,255,255,.10)', sw * 14)}
    ${yu ? line(yu, '#ff6b73', sw * 2.4) : ''}
    ${line(d, '#fff', sw * 1.4, `stroke-dasharray="${sw * 3} ${sw * 2}"`)}
    ${c.brakeAt != null ? tick(c.brakeAt, '#fff', 'DEMO') : ''}
    ${lastRec?.brake != null && c.brakeAt != null ? tick(c.brakeAt + lastRec.brake, '#ff6b73', 'YOU') : ''}
    <circle cx="${ax}" cy="${az}" r="${sw * 4}" fill="#ffc531" stroke="#0b1f4b" stroke-width="${sw}"/>
  </svg><div class="sh-maplegend"><span><i style="background:#fff"></i>demo</span>${yu ? '<span><i style="background:#ff6b73"></i>your last</span>' : ''}<span><i style="background:#ffc531;border-radius:50%;width:9px;height:9px"></i>apex</span></div>`;
}

// the corner chips: one per corner, coloured by your recent time there, with a note count
export function cornerChips(tid, n) {
  const x = CE.sec(tid, n); if (!x?.corners?.length) return '';
  return `<div class="cchips" data-tid="${tid}" data-n="${n}"><span class="muted small">Corner notes</span>${CE.cornerStrip(x).map((c) => `<button class="cchip ${c.avg == null ? '' : c.avg > 0.03 ? 'bad' : c.avg < -0.01 ? 'good' : 'ok'}" data-cn="${c.n}"><b>${c.n}</b>${c.avg == null ? '' : `<span>${c.avg > 0 ? '+' : '−'}${Math.abs(c.avg).toFixed(2)}</span>`}${c.notes ? `<i class="${c.trying ? 'try' : ''}">${c.notes}</i>` : ''}</button>`).join('')}</div>`;
}
export function wireChips(root) {
  $$('.cchips', root).forEach((w) => $$('.cchip', w).forEach((b) => (b.onclick = (e) => { e.stopPropagation(); openCornerSheet(w.dataset.tid, +w.dataset.n, +b.dataset.cn); })));
}
