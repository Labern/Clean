// Now playing. Phase 0: renders bus state; Phase 2 ports SpotifyDrive's
// PKCE + player core into lib/spotify-api.js and wires the actions.

import { emit, latest } from '../lib/bus.js';
import { duration } from '../lib/fmt.js';

const ICON = {
  play: '<svg viewBox="0 0 24 24"><path d="M8 5v14l11-7z"/></svg>',
  pause: '<svg viewBox="0 0 24 24"><path d="M6 5h4v14H6zM14 5h4v14h-4z"/></svg>',
  next: '<svg viewBox="0 0 24 24"><path d="M6 6l8 6-8 6zM16 6h2v12h-2z"/></svg>',
  prev: '<svg viewBox="0 0 24 24"><path d="M18 6l-8 6 8 6zM6 6h2v12H6z"/></svg>',
  heart: '<svg viewBox="0 0 24 24"><path d="M12 21s-7-4.5-9.5-9A5.5 5.5 0 0 1 12 6.5 5.5 5.5 0 0 1 21.5 12C19 16.5 12 21 12 21z"/></svg>',
};

function livePos(s) {
  if (!s) return 0;
  const base = s.progressMs || 0;
  return s.playing && s.at ? base + (Date.now() - s.at) : base;
}

export default {
  id: 'spotify',
  title: 'Now playing',
  order: 10,
  events: ['spotify.state'],

  summary(el, s = latest('spotify.state')) {
    if (!s || !s.track) {
      el.innerHTML = `<div class="tile-head"><span class="label">Now playing</span></div>
        <div class="tile-body"><div class="t-xl muted">Nothing playing</div>
        <div class="t-sm faint">Play on your phone — control it here</div></div>`;
      return;
    }
    const pos = Math.min(livePos(s), s.track.ms);
    el.innerHTML = `
      <div class="tile-head"><span class="label">Now playing</span><span class="t-sm faint num">${duration(pos)} / ${duration(s.track.ms)}</span></div>
      <div class="tile-body">
        <div class="display t-2xl ellip">${esc(s.track.name)}</div>
        <div class="muted t-lg ellip">${esc(s.track.artist)}</div>
        <div class="progress accent"><i style="width:${(pos / s.track.ms * 100).toFixed(1)}%"></i></div>
      </div>
      <div class="tile-foot">
        <button class="btn quiet round" data-act="prev" aria-label="Previous">${ICON.prev}</button>
        <button class="btn primary round big-icon" data-act="toggle" aria-label="${s.playing ? 'Pause' : 'Play'}">${s.playing ? ICON.pause : ICON.play}</button>
        <button class="btn quiet round" data-act="next" aria-label="Next">${ICON.next}</button>
        <span style="flex:1"></span>
        <button class="btn quiet round ${s.liked ? 'on' : ''}" data-act="like" aria-label="Like" style="${s.liked ? 'color:var(--accent)' : ''}">${ICON.heart}</button>
      </div>`;
  },

  detail(el, s = latest('spotify.state')) {
    if (!s || !s.track) { el.innerHTML = `<div class="t-2xl muted">Nothing playing</div>`; return; }
    el.innerHTML = `
      <div class="grid-2 stack-portrait" style="align-items:start">
        <div class="stack">
          ${s.art ? `<img class="art" src="${s.art}" alt="">` : `<div class="art"></div>`}
        </div>
        <div class="stack" style="gap:1.6rem">
          <div class="display t-4xl">${esc(s.track.name)}</div>
          <div class="t-2xl muted">${esc(s.track.artist)}</div>
          <div class="t-lg faint">${esc(s.track.album || '')}</div>
          <div class="row" style="gap:1.6rem;margin-top:2.4rem">
            <button class="btn round" data-act="prev">${ICON.prev}</button>
            <button class="btn primary round big-icon" data-act="toggle" style="width:7.2rem;height:7.2rem">${s.playing ? ICON.pause : ICON.play}</button>
            <button class="btn round" data-act="next">${ICON.next}</button>
          </div>
          <div class="label">Playing on ${esc(s.device || '—')}</div>
          <div class="card" style="margin-top:1.6rem">
            <div class="label">Phase 2</div>
            <div class="muted">Queue, search, playlists, devices — ported from SpotifyDrive.</div>
          </div>
        </div>
      </div>`;
  },

  actions: {
    toggle() { emit('spotify.cmd', { cmd: 'toggle' }); },
    next() { emit('spotify.cmd', { cmd: 'next' }); },
    prev() { emit('spotify.cmd', { cmd: 'prev' }); },
    like() { emit('spotify.cmd', { cmd: 'like' }); },
  },
};

function esc(s) { return String(s ?? '').replace(/[&<>"]/g, c => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;' }[c])); }
