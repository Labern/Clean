// Messages. Names and counts only — never content. Replies are typed with
// the car's own dictation (hold the right wheel button in the field) and
// sent through the server's linked device. "Share where I am" sends a pin
// plus a live link the recipient can open anywhere.

import { latest } from '../lib/bus.js';
import { ago, initials } from '../lib/fmt.js';

let openChat = null; // jid of the chat whose composer is open in the sheet

const SHARE_OPTIONS = [
  { label: '15 min', minutes: 15 },
  { label: '1 hour', minutes: 60 },
  { label: 'Until I stop', minutes: 0 },
];

export default {
  id: 'whatsapp',
  title: 'Messages',
  order: 20,
  events: ['wa.chats', 'wa.message', 'wa.status', 'wa.canned', 'share.state', 'link.status'],

  summary(el) {
    const s = latest('wa.chats');
    const st = latest('wa.status');
    if (!s) {
      const why = !latest('link.status') || latest('link.status').status !== 'on' ? 'No server' : st?.state === 'qr' ? 'Scan the QR on your phone' : 'Linking…';
      el.innerHTML = `<div class="tile-head"><span class="label">Messages</span></div>
        <div class="tile-body"><div class="t-xl muted">Not linked</div><div class="t-sm faint">${why}</div></div>`;
      return;
    }
    const top = s.chats.slice(0, 3);
    const shares = latest('share.state')?.shares?.length || 0;
    el.innerHTML = `
      <div class="tile-head"><span class="label">Messages</span>${s.unread ? `<span class="badge">${s.unread}</span>` : shares ? `<span class="t-sm" style="color:var(--good)">Sharing live</span>` : `<span class="t-sm faint">No unread</span>`}</div>
      <div class="tile-body" style="justify-content:flex-start;gap:1rem">
        ${top.map(c => `<div class="row between">
          <div class="row"><span class="avatar" style="width:3.6rem;height:3.6rem;font-size:1.4rem">${initials(c.name)}</span>
          <span class="t-lg ellip" style="${c.unread ? 'font-weight:500' : ''}">${esc(c.name)}</span></div>
          <span class="row" style="gap:0.8rem">${c.unread ? `<span class="badge">${c.unread}</span>` : ''}<span class="t-sm faint num">${ago(c.ts)}</span></span>
        </div>`).join('') || '<div class="t-lg muted">No messages yet</div>'}
      </div>`;
  },

  detail(el, _d, ctx) {
    const s = latest('wa.chats');
    if (!s) { el.innerHTML = `<div class="t-2xl muted">Not linked</div><p class="muted" style="margin-top:1.2rem">Open the setup page on your phone and scan the QR code. Once.</p>`; return; }
    const chat = openChat && s.chats.find(c => c.id === openChat);
    if (chat) return composer(el, chat, ctx);
    const shares = latest('share.state')?.shares || [];
    el.innerHTML = `
      ${shares.length ? `<div class="card" style="margin-bottom:2.4rem"><div class="row between">
        <div class="stack"><span class="label" style="color:var(--good)">Sharing live</span>
          <span class="t-lg">${shares.map(x => esc(x.name)).join(', ')}</span></div>
        <button class="btn" data-act="stopShares">Stop</button></div></div>` : ''}
      <div class="list">
        ${s.chats.map(c => `<div data-chat="${esc(c.id)}" style="cursor:pointer">
          <span class="avatar">${initials(c.name)}</span>
          <div class="stack" style="flex:1;min-width:0">
            <div class="t-xl ellip" style="${c.unread ? 'font-weight:500' : ''}">${esc(c.name)}</div>
            <div class="t-sm faint">${c.unread ? `${c.unread} new` : 'Read'}</div>
          </div>
          <span class="t-base faint num">${ago(c.ts)}</span>
          ${c.unread ? `<span class="badge">${c.unread}</span>` : ''}
        </div>`).join('') || '<div class="t-xl muted">No messages yet</div>'}
      </div>
      <p class="t-sm faint" style="margin-top:2.4rem">Names only. Message content stays on your phone.</p>`;
    el.querySelectorAll('[data-chat]').forEach(row => row.addEventListener('click', () => {
      openChat = row.dataset.chat;
      ctx.link?.send('wa.read', { chat: openChat });
      ctx.emit('wa.open', openChat); // the shell re-renders the sheet
    }));
  },

  actions: {
    back(ctx) { openChat = null; ctx.emit('wa.open', null); },
    stopShares(ctx) {
      for (const sh of latest('share.state')?.shares || []) ctx.link?.send('wa.share.stop', { token: sh.token });
    },
  },
};

function composer(el, chat, ctx) {
  const canned = latest('wa.canned')?.canned || [];
  const sharing = (latest('share.state')?.shares || []).find(x => x.chat === chat.id);
  el.innerHTML = `
    <div class="row" style="gap:1.6rem;margin-bottom:2.4rem">
      <button class="btn quiet" id="wa-back">‹ All</button>
      <span class="avatar">${initials(chat.name)}</span>
      <div class="stack"><span class="display t-2xl">${esc(chat.name)}</span><span class="t-sm faint">${chat.unread ? `${chat.unread} new · ` : ''}${ago(chat.ts) === 'now' ? 'just now' : `${ago(chat.ts)} ago`}</span></div>
    </div>
    <div class="grid-2" style="align-items:start;gap:2.4rem">
      <div class="stack" style="gap:1.6rem">
        <span class="label">Reply — hold the wheel button to dictate</span>
        <div class="row">
          <input class="text" id="wa-text" placeholder="Message ${esc(chat.name)}" autocomplete="off" enterkeyhint="send" style="flex:1;height:5.6rem;font-size:1.7rem">
          <button class="btn primary" id="wa-send" style="height:5.6rem">Send</button>
        </div>
        <div class="row" style="flex-wrap:wrap;gap:0.8rem">
          ${canned.map(t => `<button class="chip" data-canned="${esc(t)}">${esc(t)}</button>`).join('')}
        </div>
      </div>
      <div class="card stack" style="gap:1.2rem">
        <span class="label">Share where I am</span>
        ${sharing
          ? `<div class="t-lg" style="color:var(--good)">Sharing live until ${new Date(sharing.expires).toLocaleTimeString('en-GB', { hour: '2-digit', minute: '2-digit' })}</div>
             <button class="btn" id="wa-share-stop">Stop sharing</button>`
          : `<div class="row" style="flex-wrap:wrap;gap:0.8rem">${SHARE_OPTIONS.map(o => `<button class="btn" data-share="${o.minutes}">${o.label}</button>`).join('')}</div>
             <div class="t-sm faint">Sends a pin and a live link they can open in any browser. The pin refreshes every 5 minutes while sharing.</div>`}
      </div>
    </div>`;
  const input = el.querySelector('#wa-text');
  const send = (text) => {
    text = (text || '').trim();
    if (!text) return;
    if (!ctx.link?.send('wa.send', { chat: chat.id, text })) { ctx.toast('Not sent', 'No server', 'bad'); return; }
    input.value = '';
  };
  el.querySelector('#wa-back').addEventListener('click', () => { openChat = null; ctx.emit('wa.open', null); });
  el.querySelector('#wa-send').addEventListener('click', () => send(input.value));
  input.addEventListener('keydown', (e) => { if (e.key === 'Enter') send(input.value); });
  el.querySelectorAll('[data-canned]').forEach(b => b.addEventListener('click', () => send(b.dataset.canned)));
  el.querySelectorAll('[data-share]').forEach(b => b.addEventListener('click', () => {
    if (!ctx.link?.send('wa.share', { chat: chat.id, minutes: +b.dataset.share, refreshMin: 5 })) ctx.toast('Not shared', 'No server', 'bad');
  }));
  el.querySelector('#wa-share-stop')?.addEventListener('click', () => ctx.link?.send('wa.share.stop', { token: sharing.token }));
  setTimeout(() => input.focus(), 50);
}

function esc(s) { return String(s ?? '').replace(/[&<>"]/g, c => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;' }[c])); }
