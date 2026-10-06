// Spotify for the car: PKCE sign-in once, tokens in localStorage, a 3 s
// poll while the page is visible, commands against whatever device is
// active (the phone over Bluetooth). Ported from SpotifyDrive/variants/pure.

import { emit } from './bus.js';

export const SCOPES = [
  'user-read-playback-state', 'user-modify-playback-state', 'user-read-currently-playing',
  'user-read-recently-played', 'playlist-read-private', 'playlist-read-collaborative',
  'user-library-read', 'user-library-modify', 'user-top-read',
].join(' ');

const K = { access: 'sp_access_token', expiry: 'sp_token_expiry', refresh: 'sp_refresh_token', scope: 'sp_granted_scope', verifier: 'sp_pkce_v', device: 'sp_device' };

function rndStr(n) {
  const chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~';
  const bytes = crypto.getRandomValues(new Uint8Array(n));
  return Array.from(bytes, b => chars[b % chars.length]).join('');
}
async function codeChallenge(v) {
  const digest = await crypto.subtle.digest('SHA-256', new TextEncoder().encode(v));
  return btoa(String.fromCharCode(...new Uint8Array(digest))).replace(/\+/g, '-').replace(/\//g, '_').replace(/=/g, '');
}

export function createSpotify({ clientId, redirectUri, storage = globalThis.localStorage, fetch = globalThis.fetch, location = globalThis.location, now = Date.now } = {}) {
  const ls = (k) => storage.getItem(k);
  const set = (k, v) => storage.setItem(k, String(v));
  const del = (k) => storage.removeItem(k);

  const S = { playing: false, trackId: null, deviceId: ls(K.device) || null, progressMs: 0, at: 0, durationMs: 0, liked: false, lastState: null };
  let pollTimer = null, tickTimer = null;

  // ---- tokens
  function storeTokens(d) {
    if (!d.access_token) return;
    set(K.access, d.access_token);
    set(K.expiry, now() + d.expires_in * 1000);
    if (d.refresh_token) set(K.refresh, d.refresh_token);
    if (d.scope) set(K.scope, d.scope);
  }
  function forget() { [K.access, K.expiry, K.refresh, K.scope].forEach(del); emit('spotify.auth', { connected: false }); }
  async function refresh() {
    const rt = ls(K.refresh);
    if (!rt) { forget(); return null; }
    const res = await fetch('https://accounts.spotify.com/api/token', {
      method: 'POST', headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
      body: new URLSearchParams({ grant_type: 'refresh_token', refresh_token: rt, client_id: clientId }),
    });
    const d = await res.json().catch(() => ({}));
    if (!res.ok || !d.access_token) { forget(); return null; }
    storeTokens(d);
    return d.access_token;
  }
  async function token() {
    if (now() > (+ls(K.expiry) || 0) - 60000) return refresh();
    return ls(K.access);
  }
  function missingScopes() {
    const have = new Set((ls(K.scope) || '').split(/\s+/).filter(Boolean));
    return SCOPES.split(' ').filter(s => !have.has(s));
  }

  // ---- API
  async function api(path, method = 'GET', body = null, retried = false) {
    const t = await token();
    if (!t) throw Object.assign(new Error('Not connected'), { status: 401 });
    const opts = { method, headers: { Authorization: 'Bearer ' + t } };
    if (body !== null) { opts.headers['Content-Type'] = 'application/json'; opts.body = JSON.stringify(body); }
    const res = await fetch('https://api.spotify.com/v1' + path, opts);
    if (res.status === 204 || res.status === 202) return null;
    if (res.status === 401 && !retried) {
      const nt = await refresh();
      if (nt) return api(path, method, body, true);
      throw Object.assign(new Error('Session expired'), { status: 401 });
    }
    if (!res.ok) {
      const err = await res.json().catch(() => ({}));
      throw Object.assign(new Error(err?.error?.message || String(res.status)), { status: res.status });
    }
    const text = await res.text();
    if (!text) return null;
    try { return JSON.parse(text); } catch { return null; }
  }

  // ---- devices and commands
  async function ensureDevice() {
    if (S.deviceId) return S.deviceId;
    try {
      const d = await api('/me/player/devices');
      const devs = d?.devices || [];
      const dev = devs.find(x => x.is_active) || devs[0];
      if (dev) { S.deviceId = dev.id; return dev.id; }
    } catch {}
    return null;
  }
  async function playerCmd(pathFor, method, body = null) {
    let dev = await ensureDevice();
    try { await api(pathFor(dev), method, body); }
    catch (e) {
      if (e?.status === 404) {
        S.deviceId = null; dev = await ensureDevice();
        if (dev) { await api(pathFor(dev), method, body); return; }
      }
      throw e;
    }
  }
  const q = (d) => d ? `?device_id=${d}` : '';
  function fail(e, what) {
    if (e?.status === 401) return;
    const msg = e?.status === 404 ? 'No active Spotify device — play something on your phone'
      : e?.status === 403 ? 'Spotify Premium needed' : `${what} failed: ${e?.message || 'error'}`;
    emit('spotify.error', { message: msg, status: e?.status });
  }

  // ---- state
  function publish(d) {
    if (!d || !d.item) { S.lastState = { playing: false, track: null, at: now() }; emit('spotify.state', S.lastState); return; }
    const t = d.item;
    const newTrack = t.id !== S.trackId;
    S.playing = !!d.is_playing; S.progressMs = d.progress_ms || 0; S.at = now(); S.durationMs = t.duration_ms;
    if (d.device?.id) { S.deviceId = d.device.id; set(K.device, d.device.id); }
    if (newTrack) { S.trackId = t.id; S.liked = false; checkLiked(); }
    S.lastState = {
      playing: S.playing, progressMs: S.progressMs, at: S.at, liked: S.liked,
      track: { id: t.id, uri: t.uri, name: t.name, artist: (t.artists || []).map(a => a.name).join(', '), album: t.album?.name || '', ms: t.duration_ms },
      art: t.album?.images?.[1]?.url || t.album?.images?.[0]?.url || null,
      device: d.device?.name || null, deviceType: d.device?.type || null, shuffle: !!d.shuffle_state, contextUri: d.context?.uri || null,
    };
    emit('spotify.state', S.lastState);
  }
  async function fetchState() {
    try { publish(await api('/me/player')); } catch (e) { if (e?.status !== 401) console.warn('[spotify]', e.message); }
  }
  async function checkLiked() {
    if (!S.trackId) return;
    try {
      const d = await api(`/me/tracks/contains?ids=${S.trackId}`);
      S.liked = Array.isArray(d) ? !!d[0] : false;
      if (S.lastState?.track?.id === S.trackId) { S.lastState = { ...S.lastState, liked: S.liked }; emit('spotify.state', S.lastState); }
    } catch {}
  }
  function livePos() {
    let p = S.progressMs || 0;
    if (S.playing && S.at) p += now() - S.at;
    return Math.max(0, Math.min(p, S.durationMs || p));
  }
  function tick() {
    if (!S.playing || !S.durationMs) return;
    if (S.durationMs - livePos() < 1200 && now() - (S._endSync || 0) > 4000) { S._endSync = now(); fetchState(); }
  }

  const self = {
    connected: () => !!ls(K.refresh),
    needsReconsent: () => self.connected() && missingScopes().length > 0,
    state: () => S.lastState,

    async authorize() {
      const v = rndStr(128);
      set(K.verifier, v);
      const params = new URLSearchParams({ client_id: clientId, response_type: 'code', redirect_uri: redirectUri, code_challenge_method: 'S256', code_challenge: await codeChallenge(v), scope: SCOPES });
      location.href = 'https://accounts.spotify.com/authorize?' + params;
    },
    // Call on boot: finishes the redirect if ?code= is present. Returns true when it handled one.
    async handleRedirect() {
      const sp = new URLSearchParams(location.search);
      const code = sp.get('code'), err = sp.get('error');
      if (!code && !err) return false;
      sp.delete('code'); sp.delete('error'); sp.delete('state');
      history.replaceState(null, '', location.pathname + (sp.toString() ? `?${sp}` : '') + location.hash);
      if (err) { emit('spotify.error', { message: 'Spotify sign-in cancelled' }); return true; }
      const res = await fetch('https://accounts.spotify.com/api/token', {
        method: 'POST', headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
        body: new URLSearchParams({ grant_type: 'authorization_code', code, redirect_uri: redirectUri, client_id: clientId, code_verifier: ls(K.verifier) || '' }),
      });
      const d = await res.json().catch(() => ({}));
      del(K.verifier);
      if (!res.ok || !d.access_token) { emit('spotify.error', { message: 'Spotify sign-in failed' }); return true; }
      storeTokens(d);
      emit('spotify.auth', { connected: true });
      return true;
    },
    disconnect: forget,

    start() {
      this.stop();
      if (!this.connected()) return;
      fetchState();
      pollTimer = setInterval(() => { if (document.visibilityState !== 'hidden') fetchState(); }, 3000);
      tickTimer = setInterval(tick, 1000);
      emit('spotify.auth', { connected: true });
    },
    stop() { clearInterval(pollTimer); clearInterval(tickTimer); pollTimer = tickTimer = null; },
    refreshNow: fetchState,
    livePos,
    api,

    async cmd(name, arg) {
      try {
        switch (name) {
          case 'toggle': await playerCmd(d => `/me/player/${S.playing ? 'pause' : 'play'}${q(d)}`, 'PUT'); S.playing = !S.playing; S.progressMs = livePos(); S.at = now(); break;
          case 'next': await playerCmd(d => `/me/player/next${q(d)}`, 'POST'); break;
          case 'prev': await playerCmd(d => `/me/player/previous${q(d)}`, 'POST'); break;
          case 'shuffle': await playerCmd(d => `/me/player/shuffle?state=${!S.lastState?.shuffle}${d ? `&device_id=${d}` : ''}`, 'PUT'); break;
          case 'seek': await playerCmd(d => `/me/player/seek?position_ms=${Math.round(arg)}${d ? `&device_id=${d}` : ''}`, 'PUT'); S.progressMs = arg; S.at = now(); break;
          case 'like': {
            if (!S.trackId) return;
            await api(`/me/tracks?ids=${S.trackId}`, S.liked ? 'DELETE' : 'PUT');
            S.liked = !S.liked;
            break;
          }
          case 'play': { // arg: { uri } (track) or { context, offset }
            const body = arg?.context ? { context_uri: arg.context, ...(arg.offset != null ? { offset: { position: arg.offset } } : {}) } : { uris: [arg.uri] };
            await playerCmd(d => `/me/player/play${q(d)}`, 'PUT', body);
            break;
          }
          case 'queue': await playerCmd(d => `/me/player/queue?uri=${encodeURIComponent(arg.uri)}${d ? `&device_id=${d}` : ''}`, 'POST'); break;
          case 'transfer': S.deviceId = arg.id; set(K.device, arg.id); await api('/me/player', 'PUT', { device_ids: [arg.id], play: true }); break;
          default: return;
        }
        if (S.lastState) emit('spotify.state', { ...S.lastState, playing: S.playing, progressMs: S.progressMs, at: S.at, liked: S.liked });
        setTimeout(fetchState, 600);
      } catch (e) { fail(e, name); }
    },

    devices: () => api('/me/player/devices').then(d => d?.devices || []),
    queue: () => api('/me/player/queue').then(d => (d?.queue || []).slice(0, 8)),
    search: (text) => api(`/search?type=track&limit=8&q=${encodeURIComponent(text)}`).then(d => d?.tracks?.items || []),
    playlists: () => api('/me/playlists?limit=10').then(d => d?.items || []),
    recent: () => api('/me/player/recently-played?limit=8').then(d => (d?.items || []).map(i => i.track)),
    get deviceId() { return S.deviceId; },
  };
  return self;
}

export function trackView(t) {
  return { id: t.id, uri: t.uri, name: t.name, artist: (t.artists || []).map(a => a.name).join(', '), album: t.album?.name || '', art: t.album?.images?.[2]?.url || t.album?.images?.[0]?.url || null, ms: t.duration_ms };
}
