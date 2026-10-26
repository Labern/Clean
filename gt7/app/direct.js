// Direct connection to Gran Turismo 7, no bridge. Native shells only: browsers
// can't open UDP sockets or call Sony's servers, a phone app can.
//  - Telemetry: the Gt7Direct plugin heartbeats the PS5 (UDP 33739) and hands
//    every packet (UDP 33740) to us; we decrypt + record laps here, on the phone.
//  - Your GT7 account: the plugin signs in to gran-turismo.com in a web view
//    (your PSN login, Sony's page) and returns the site's own API token; we then
//    call GT7's web API directly (native HTTP, no CORS) for your stats.
import * as store from './state.js';
import * as L from './laps.js';
import { decrypt, parse, createRecorder } from './gt7proto.js';
import { isNative, nativeFetch } from './platform.js';
import { trackById } from '../data/tracks.js';

const plugin = () => (isNative() ? window.Capacitor?.Plugins?.Gt7Direct || window.Capacitor?.registerPlugin?.('Gt7Direct') : null);
export const available = () => !!plugin();

const b64 = (s) => { const bin = atob(s), u = new Uint8Array(bin.length); for (let i = 0; i < bin.length; i++) u[i] = bin.charCodeAt(i); return u; };
let listeners = [], live = null, state = { status: 'off' }, subs = new Set();
const emit = () => subs.forEach((f) => f(live, state));
export const onLive = (f) => (subs.add(f), () => subs.delete(f));
export const status = () => state;

// Every finished lap: store it (track identified from its shape) and keep the best per track.
async function saveLap(lap) {
  await L.putLap(lap);
  if (lap.track && lap.timeSource === 'gt7') {
    store.set((s) => {
      s.logged = s.logged || {};
      const cur = s.logged[lap.track];
      if (!cur || lap.time < cur.ms) s.logged[lap.track] = { ms: lap.time, car: lap.car, t: lap.t0, id: lap.id };
    });
  }
  window.dispatchEvent(new CustomEvent('gt7-lap-saved', { detail: lap }));
}

export async function startTelemetry(ps5 = store.get().ps5Ip || 'auto') {
  const P = plugin(); if (!P) throw new Error('The direct connection needs the iOS or Android app.');
  await stopTelemetry();
  const rec = createRecorder({ onLap: saveLap, onLive: (fr) => { live = fr; } });
  let last = 0;
  listeners.push(await P.addListener('packet', (e) => {
    const d = decrypt(b64(e.data), '~'); if (!d) return;
    rec(parse(d));
    if (e.from && state.ps5 !== e.from) { state = { ...state, status: 'live', ps5: e.from }; store.set((s) => { s.ps5Ip = e.from; }); }
    const now = Date.now(); if (now - last > 66) { last = now; emit(); }   // repaint at ~15 Hz
  }));
  listeners.push(await P.addListener('status', (e) => { state = { ...state, ...e }; emit(); }));
  state = { status: 'searching', ps5: ps5 === 'auto' ? null : ps5 }; emit();
  await P.startTelemetry({ ps5 });
}
export async function stopTelemetry() {
  for (const l of listeners) await l.remove?.();
  listeners = []; await plugin()?.stopTelemetry?.(); state = { status: 'off' }; emit();
}

// ── GT7 account (gran-turismo.com) ──
const API = 'https://web-api.gt7.game.gran-turismo.com';
async function token(interactive) {
  const P = plugin(); if (!P) throw new Error('Signing in to GT7 needs the iOS or Android app.');
  const t = store.get().gt7web?.tok;
  if (t && t.expires > Date.now() + 60e3) return t;
  let r;
  try { r = await P.gt7Token(); } catch { r = null; }          // silent: cookies from last sign-in (~a week)
  if (!r?.access_token) { if (!interactive) throw new Error('signin'); r = await P.gt7SignIn(); }
  const tok = { access: r.access_token, user: r.user_id, expires: +r.access_token_expire || Date.now() + 55 * 60e3 };
  store.set((s) => { s.gt7web = { ...(s.gt7web || {}), tok }; });
  return tok;
}
async function call(path, body, tok) {
  const r = await nativeFetch(API + path, { method: 'POST', headers: { Authorization: 'Bearer ' + tok.access, 'Content-Type': 'application/json', Referer: 'https://www.gran-turismo.com/' }, body });
  if (r.status === 401) throw new Error('signin');
  if (r.status >= 400) throw new Error('GT7 web API ' + r.status);
  return r.json();
}
// Walk a JSON tree for the first number under a key matching rx.
const find = (o, rx, d = 0) => { if (!o || typeof o !== 'object' || d > 6) return null; for (const [k, v] of Object.entries(o)) { if (rx.test(k) && typeof v === 'number') return v; const r = find(v, rx, d + 1); if (r != null) return r; } return null; };

export async function syncGT7(interactive = false) {
  const tok = await token(interactive), now = new Date();
  const out = { fetchedAt: Date.now(), user: tok.user, raw: {} };
  for (const [name, path, body] of [
    ['stats', '/stats/get', { user_id: tok.user, year: now.getFullYear(), month: now.getMonth() + 1 }],
    ['profile', '/profile/get', { user_id: tok.user }],
    ['sport', '/sport/get_sport_profile', { user_id: tok.user }],
  ]) { try { out.raw[name] = await call(path, body, tok); } catch (e) { if (e.message === 'signin') throw e; out.raw[name] = { error: e.message }; } }
  const credits = find(out.raw, /credit/i), dr = find(out.raw, /^driver_rating$/i), drRatio = find(out.raw, /dr_point_ratio/i);
  out.credits = credits; out.dr = dr; out.drRatio = drRatio;
  out.garage = find(out.raw, /garage|car_count|owned/i);
  store.set((s) => {
    s.gt7web = { ...(s.gt7web || {}), ...out };
    if (credits != null) { s.credits = credits; s.creditsSource = 'gt7'; }
  });
  return out;
}
export const signedIn = () => !!store.get().gt7web?.user;
export const DR = ['', 'E', 'D', 'C', 'B', 'A', 'A+'];
export const loggedBest = (tid) => store.get().logged?.[tid] || null;
export const trackName = (tid) => trackById[tid]?.short || tid;
