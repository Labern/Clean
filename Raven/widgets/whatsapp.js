// Messages. Names and counts only — never content — until you say otherwise.

import { latest } from '../lib/bus.js';
import { ago, initials } from '../lib/fmt.js';

export default {
  id: 'whatsapp',
  title: 'Messages',
  order: 20,
  events: ['wa.chats', 'wa.message', 'link.status'],

  summary(el) {
    const s = latest('wa.chats');
    if (!s) {
      el.innerHTML = `<div class="tile-head"><span class="label">Messages</span></div>
        <div class="tile-body"><div class="t-xl muted">Not linked</div>
        <div class="t-sm faint">Scan the QR once on your phone</div></div>`;
      return;
    }
    const top = s.chats.slice(0, 3);
    el.innerHTML = `
      <div class="tile-head"><span class="label">Messages</span>${s.unread ? `<span class="badge">${s.unread}</span>` : `<span class="t-sm faint">No unread</span>`}</div>
      <div class="tile-body" style="justify-content:flex-start;gap:1rem">
        ${top.map(c => `<div class="row between">
          <div class="row"><span class="avatar" style="width:3.6rem;height:3.6rem;font-size:1.4rem">${initials(c.name)}</span>
          <span class="t-lg ellip" style="${c.unread ? 'font-weight:500' : ''}">${esc(c.name)}</span></div>
          <span class="row" style="gap:0.8rem">${c.unread ? `<span class="badge">${c.unread}</span>` : ''}<span class="t-sm faint num">${ago(c.ts)}</span></span>
        </div>`).join('')}
      </div>`;
  },

  detail(el) {
    const s = latest('wa.chats');
    if (!s) { el.innerHTML = `<div class="t-2xl muted">Not linked</div><p class="muted">Open the setup page on your phone and scan the QR code. Once.</p>`; return; }
    el.innerHTML = `
      <div class="list">
        ${s.chats.map(c => `<div>
          <span class="avatar">${initials(c.name)}</span>
          <div class="stack" style="flex:1;min-width:0">
            <div class="t-xl ellip" style="${c.unread ? 'font-weight:500' : ''}">${esc(c.name)}</div>
            <div class="t-sm faint">${c.unread ? `${c.unread} new` : 'Read'}</div>
          </div>
          <span class="t-base faint num">${ago(c.ts)}</span>
          ${c.unread ? `<span class="badge">${c.unread}</span>` : ''}
        </div>`).join('')}
      </div>
      <p class="t-sm faint" style="margin-top:2.4rem">Names only. Message content stays on your phone.</p>`;
  },
};

function esc(s) { return String(s ?? '').replace(/[&<>"]/g, c => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;' }[c])); }
