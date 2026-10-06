// Now playing: a strip on the dashboard, the full player in the sheet.
// Commands go through ctx.spotify (lib/spotify-api.js) or, in demo mode,
// straight to the demo state via the bus.

import { emit, latest } from '../lib/bus.js';
import { duration } from '../lib/fmt.js';
import { trackView } from '../lib/spotify-api.js';

const ICON = {
  play: '<svg viewBox="0 0 24 24"><path d="M8 5v14l11-7z"/></svg>',
  pause: '<svg viewBox="0 0 24 24"><path d="M6 5h4v14H6zM14 5h4v14h-4z"/></svg>',
  next: '<svg viewBox="0 0 24 24"><path d="M6 6l8 6-8 6zM16 6h2v12h-2z"/></svg>',
  prev: '<svg viewBox="0 0 24 24"><path d="M18 6l-8 6 8 6zM6 6h2v12H6z"/></svg>',
  heart: '<svg viewBox="0 0 24 24"><path d="M12 21s-7-4.5-9.5-9A5.5 5.5 0 0 1 12 6.5 5.5 5.5 0 0 1 21.5 12C19 16.5 12 21 12 21z"/></svg>',
  shuffle: '<svg viewBox="0 0 24 24" style="fill:none;stroke:currentColor;stroke-width:2;stroke-linecap:round;stroke-linejoin:round"><path d="M16 3h5v5M4 20 21 3M21 16v5h-5M15 15l6 6M4 4l5 5"/></svg>',
  spotify: '<svg viewBox="0 0 24 24"><path d="M12 2a10 10 0 1 0 0 20 10 10 0 0 0 0-20zm4.6 14.4a.6.6 0 0 1-.9.2c-2.4-1.5-5.4-1.8-9-1a.6.6 0 1 1-.3-1.2c3.9-.9 7.3-.5 10 1.1.3.2.4.6.2.9zm1.2-2.7a.8.8 0 0 1-1.1.3c-2.8-1.7-7-2.2-10.3-1.2a.8.8 0 1 1-.5-1.5c3.8-1.1 8.4-.6 11.6 1.4.4.2.5.7.3 1zm.1-2.9c-3.3-2-8.8-2.2-12-1.2a.9.9 0 1 1-.5-1.8c3.7-1.1 9.7-.9 13.5 1.4a.9.9 0 0 1-1 1.6z"/></svg>',
};

function livePos(s, ctx) {
  if (ctx?.spotify?.connected?.() && ctx.spotify.state()) return ctx.spotify.livePos();
  if (!s) return 0;
  return s.playing && s.at ? (s.progressMs || 0) + (Date.now() - s.at) : (s.progressMs || 0);
}
const cmd = (ctx, name, arg) => (ctx.spotify?.connected?.() ? ctx.spotify.cmd(name, arg) : emit('spotify.cmd', { cmd: name, arg }));

export default {
  id: 'spotify',
  title: 'Now playing',
  order: 10,
  events: ['spotify.state', 'spotify.auth', 'tick'],

  summary(el, _d, ctx) {
    const s = latest('spotify.state');
    const connected = ctx?.spotify?.connected?.() || !!s;
    if (!connected) {
      el.innerHTML = `<div class="strip">
        <div class="art" style="display:grid;place-items:center;color:var(--fg-3)"><span style="width:3.2rem;height:3.2rem">${ICON.spotify}</span></div>
        <div class="meta"><div class="t-xl muted">Spotify</div><div class="t-sm faint">Tap to connect — once</div></div>
        <div class="controls"><button class="btn primary" data-act="connect">Connect</button></div></div>`;
      return;
    }
    if (!s || !s.track) {
      el.innerHTML = `<div class="strip">
        <div class="art"></div>
        <div class="meta"><div class="t-xl muted">Nothing playing</div><div class="t-sm faint">Play on your phone — control it here</div></div>
        <div class="controls"><button class="btn quiet round sm" data-act="prev">${ICON.prev}</button><button class="btn primary round big-icon" data-act="toggle">${ICON.play}</button><button class="btn quiet round sm" data-act="next">${ICON.next}</button></div></div>`;
      return;
    }
    const pos = Math.min(livePos(s, ctx), s.track.ms);
    el.innerHTML = `<div class="strip">
      ${s.art ? `<img class="art" src="${s.art}" alt="">` : `<div class="art"></div>`}
      <div class="meta">
        <div class="display t-xl ellip">${esc(s.track.name)}</div>
        <div class="muted t-base ellip">${esc(s.track.artist)} <span class="faint num">· ${duration(pos)} / ${duration(s.track.ms)}</span></div>
        <div class="progress accent"><i style="width:${(pos / s.track.ms * 100).toFixed(1)}%"></i></div>
      </div>
      <div class="controls">
        <button class="btn quiet round sm" data-act="prev" aria-label="Previous">${ICON.prev}</button>
        <button class="btn primary round big-icon" data-act="toggle" aria-label="${s.playing ? 'Pause' : 'Play'}">${s.playing ? ICON.pause : ICON.play}</button>
        <button class="btn quiet round sm" data-act="next" aria-label="Next">${ICON.next}</button>
        <button class="btn quiet round sm ${s.liked ? 'on' : ''}" data-act="like" aria-label="Like">${ICON.heart}</button>
      </div></div>`;
  },

  detail(el, _d, ctx) {
    const s = latest('spotify.state');
    const sp = ctx.spotify;
    const connected = sp?.connected?.() || !!s;
    if (!connected) {
      el.innerHTML = `<div class="card stack" style="gap:1.2rem"><div class="display t-2xl">Spotify</div>
        <p class="muted">Sign in once on this screen. The car keeps the session; you won't see the login again.</p>
        <div><button class="btn primary" data-act="connect">Connect Spotify</button></div></div>`;
      return;
    }
    const pos = s?.track ? Math.min(livePos(s, ctx), s.track.ms) : 0;
    el.innerHTML = `
      <div class="row" style="gap:1.6rem;align-items:flex-start">
        ${s?.art ? `<img class="art" src="${s.art}" alt="" style="width:16rem">` : `<div class="art" style="width:16rem"></div>`}
        <div class="stack" style="flex:1;min-width:0;gap:0.6rem">
          <div class="display t-2xl" style="white-space:normal">${esc(s?.track?.name || 'Nothing playing')}</div>
          <div class="t-lg muted ellip">${esc(s?.track?.artist || '')}</div>
          <div class="t-sm faint ellip">${esc(s?.track?.album || '')}</div>
          ${s?.track ? `<div class="progress accent" data-seek style="margin-top:0.8rem;height:0.8rem;cursor:pointer"><i style="width:${(pos / s.track.ms * 100).toFixed(1)}%"></i></div>
          <div class="row between t-sm faint num"><span>${duration(pos)}</span><span>-${duration(s.track.ms - pos)}</span></div>` : ''}
        </div>
      </div>
      <div class="row" style="gap:1.2rem;margin-top:1.6rem;justify-content:center">
        <button class="btn quiet round ${s?.shuffle ? 'on' : ''}" data-act="shuffle">${ICON.shuffle}</button>
        <button class="btn round" data-act="prev">${ICON.prev}</button>
        <button class="btn primary round big-icon" data-act="toggle" style="width:6.8rem;height:6.8rem">${s?.playing ? ICON.pause : ICON.play}</button>
        <button class="btn round" data-act="next">${ICON.next}</button>
        <button class="btn quiet round ${s?.liked ? 'on' : ''}" data-act="like">${ICON.heart}</button>
      </div>
      <div class="t-sm faint" style="text-align:center;margin-top:0.8rem">${s?.device ? `Playing on ${esc(s.device)}` : ''}</div>

      <div class="section"><span class="label">Search — hold the wheel button to dictate</span>
        <label id="search" style="position:static;flex:none"><svg viewBox="0 0 24 24"><circle cx="11" cy="11" r="7"/><path d="m20 20-3.5-3.5"/></svg>
        <input id="sp-q" type="search" placeholder="Song, artist, album" autocomplete="off" enterkeyhint="search"></label>
        <div class="list" id="sp-results"></div></div>
      <div class="section"><span class="label">Up next</span><div class="list" id="sp-queue"><div class="faint">Loading…</div></div></div>
      <div class="section"><span class="label">Playlists</span><div class="row wrap" id="sp-playlists" style="gap:0.8rem"><span class="faint">Loading…</span></div></div>
      <div class="section"><span class="label">Devices</span><div class="list" id="sp-devices"><div class="faint">Loading…</div></div></div>`;

    el.querySelector('[data-seek]')?.addEventListener('click', (e) => {
      const r = e.currentTarget.getBoundingClientRect();
      cmd(ctx, 'seek', Math.max(0, Math.min(1, (e.clientX - r.left) / r.width)) * s.track.ms);
    });

    const q = el.querySelector('#sp-q'), results = el.querySelector('#sp-results');
    let t = null;
    q.addEventListener('input', () => { clearTimeout(t); t = setTimeout(() => runSearch(q.value.trim()), 350); });
    q.addEventListener('keydown', (e) => { if (e.key === 'Enter') { clearTimeout(t); runSearch(q.value.trim()); } });
    async function runSearch(text) {
      if (!text) { results.innerHTML = ''; return; }
      if (!sp?.connected?.()) { results.innerHTML = `<div class="faint">Demo — search needs Spotify</div>`; return; }
      results.innerHTML = `<div class="faint">Searching…</div>`;
      try {
        const items = (await sp.search(text)).map(trackView);
        results.innerHTML = items.map(tr => trackRow(tr, true)).join('') || `<div class="faint">No results</div>`;
      } catch (e) { results.innerHTML = `<div class="faint">${esc(e.message)}</div>`; }
    }

    if (!sp?.connected?.()) {
      el.querySelector('#sp-queue').innerHTML = `<div class="faint">Demo data</div>`;
      el.querySelector('#sp-playlists').innerHTML = ['Drive', 'Late night', 'Discover Weekly'].map(n => `<span class="chip">${n}</span>`).join('');
      el.querySelector('#sp-devices').innerHTML = `<div><span class="t-lg">iPhone</span><span class="t-sm faint" style="margin-left:auto">active</span></div>`;
      return;
    }
    sp.queue().then(items => { el.querySelector('#sp-queue').innerHTML = items.map(tr => trackRow(trackView(tr), false)).join('') || `<div class="faint">Queue is empty</div>`; }).catch(() => {});
    sp.playlists().then(items => { el.querySelector('#sp-playlists').innerHTML = items.map(p => `<button class="chip" data-act="playContext" data-uri="${esc(p.uri)}">${esc(p.name)}</button>`).join('') || `<span class="faint">None</span>`; }).catch(() => {});
    sp.devices().then(devs => { el.querySelector('#sp-devices').innerHTML = devs.map(d => `<button data-act="transfer" data-id="${esc(d.id)}" style="width:100%;text-align:left">
        <span class="t-lg" style="flex:1">${esc(d.name)}</span><span class="t-sm faint">${esc(d.type)}${d.is_active ? ' · active' : ''}</span></button>`).join('') || `<div class="faint">Open Spotify on your phone</div>`; }).catch(() => {});
  },

  actions: {
    connect(ctx) { if (ctx.spotify) ctx.spotify.authorize(); else ctx.toast('Spotify', 'No client id in config.js', 'bad'); },
    toggle(ctx) { cmd(ctx, 'toggle'); },
    next(ctx) { cmd(ctx, 'next'); },
    prev(ctx) { cmd(ctx, 'prev'); },
    like(ctx) { cmd(ctx, 'like'); },
    shuffle(ctx) { cmd(ctx, 'shuffle'); },
    playTrack(ctx, b) { cmd(ctx, 'play', { uri: b.dataset.uri }); ctx.toast(b.dataset.name || 'Playing', 'Spotify', 'good', 2500); },
    queueTrack(ctx, b) { cmd(ctx, 'queue', { uri: b.dataset.uri }); ctx.toast('Added to queue', 'Spotify', 'good', 2500); },
    playContext(ctx, b) { cmd(ctx, 'play', { context: b.dataset.uri }); },
    transfer(ctx, b) { cmd(ctx, 'transfer', { id: b.dataset.id }); },
  },
};

function trackRow(tr, withQueue) {
  return `<div>
    ${tr.art ? `<img class="thumb" src="${tr.art}" alt="">` : `<div class="thumb"></div>`}
    <button data-act="playTrack" data-uri="${esc(tr.uri)}" data-name="${esc(tr.name)}" style="flex:1;min-width:0;text-align:left" class="stack">
      <span class="t-lg ellip" style="display:block">${esc(tr.name)}</span><span class="t-sm faint ellip" style="display:block">${esc(tr.artist)}</span></button>
    ${withQueue ? `<button class="btn quiet" data-act="queueTrack" data-uri="${esc(tr.uri)}" style="min-height:4rem">Queue</button>` : `<span class="t-sm faint num">${duration(tr.ms)}</span>`}
  </div>`;
}

function esc(s) { return String(s ?? '').replace(/[&<>"]/g, c => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;' }[c])); }
