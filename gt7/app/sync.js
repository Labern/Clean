// Cloud save: sign in once per device with your PSN ID + a passphrase, and the
// whole save follows you between Mac and phone.
//
// Same proven pattern as kittens/ and cycle/: the save is AES-GCM encrypted on
// the device and published as a *retained* MQTT message on three public
// brokers. The brokers are a meeting point, not the source of truth: every
// device republishes its copy on connect, so the save survives as long as any
// device that has it opens the app. The newest `updatedAt` wins. The
// passphrase never leaves the device; the brokers only ever see ciphertext
// under a topic derived from the key.
import * as store from './state.js';
import * as laps from './laps.js';

const BROKERS = window.GT7_BROKERS || ['wss://broker.emqx.io:8084/mqtt', 'wss://broker.hivemq.com:8884/mqtt', 'wss://test.mosquitto.org:8081/'];
const LS = 'gt7-endgame-account';
// Set by signIn on a device: the first copy that arrives from the cloud is
// adopted regardless of timestamps, so a new device never overwrites the real
// save with whatever was tapped before signing in. If no copy arrives within
// ADOPT_MS, this device's data becomes the cloud save.
const ADOPT = 'gt7-endgame-adopt', ADOPT_MS = 7000;
let connectedAt = 0;
const te = new TextEncoder(), td = new TextDecoder();
const b64 = (u8) => btoa(String.fromCharCode(...u8));
const unb64 = (s) => Uint8Array.from(atob(s), (c) => c.charCodeAt(0));
const hex = (u8) => [...u8].map((b) => b.toString(16).padStart(2, '0')).join('');

let key = null, topic = null, conns = [], status = 'off', lastSync = 0, pubTimer = null;
const listeners = new Set();
const emit = () => listeners.forEach((f) => f(info()));
export const onStatus = (f) => (listeners.add(f), () => listeners.delete(f));
export function info() {
  const acct = account();
  return { status, user: acct?.user || null, lastSync, brokers: conns.filter((c) => c.connected).length };
}
function account() { try { return JSON.parse(localStorage.getItem(LS) || 'null'); } catch { return null; } }

async function derive(user, pass) {
  const base = await crypto.subtle.importKey('raw', te.encode(pass), 'PBKDF2', false, ['deriveBits']);
  const bits = new Uint8Array(await crypto.subtle.deriveBits({ name: 'PBKDF2', hash: 'SHA-256', salt: te.encode('gt7-endgame:' + user.trim().toLowerCase()), iterations: 210000 }, base, 512));
  return { enc: bits.slice(0, 32), id: hex(bits.slice(32, 48)) };
}

async function seal(obj) {
  const iv = crypto.getRandomValues(new Uint8Array(12));
  const ct = new Uint8Array(await crypto.subtle.encrypt({ name: 'AES-GCM', iv }, key, te.encode(JSON.stringify(obj))));
  const out = new Uint8Array(12 + ct.length); out.set(iv); out.set(ct, 12);
  return b64(out);
}
async function open(str) {
  const b = unb64(str);
  return JSON.parse(td.decode(await crypto.subtle.decrypt({ name: 'AES-GCM', iv: b.slice(0, 12) }, key, b.slice(12))));
}

async function publish() {
  if (!key || !store.get().updatedAt) return; // never let a pristine device clobber the cloud copy
  if (localStorage.getItem(ADOPT)) {
    if (Date.now() - connectedAt < ADOPT_MS) { setTimeout(publish, ADOPT_MS); return; } // still waiting for the cloud copy
    localStorage.removeItem(ADOPT); // nothing in the cloud: this device's save becomes it
  }
  const msg = JSON.stringify({ v: 1, at: store.get().updatedAt, box: await seal(store.get()) });
  conns.forEach((c) => c.connected && c.publish(topic, msg, { retain: true, qos: 1 }));
  lastSync = Date.now(); emit();
}
const schedule = () => { clearTimeout(pubTimer); pubTimer = setTimeout(publish, 1200); };

function connect() {
  disconnect();
  if (typeof mqtt === 'undefined') { status = 'error'; emit(); return; }
  status = 'connecting'; emit();
  for (const url of BROKERS) {
    let c;
    try { c = mqtt.connect(url, { clientId: 'gt7_' + Math.random().toString(36).slice(2, 10), clean: true, connectTimeout: 8000, reconnectPeriod: 15000 }); } catch { continue; }
    conns.push(c);
    c.on('connect', () => { connectedAt ||= Date.now(); c.subscribe([topic, topic + '/laps/+'], { qos: 1 }); status = 'live'; emit(); setTimeout(publish, 1500); setTimeout(() => publishAllLaps(c), 4000); });
    c.on('message', async (t, buf) => {
      try {
        const m = JSON.parse(buf.toString());
        if (t !== topic) { // a lap
          if (!m.box || (await laps.getLap(m.id))) return;
          const lap = await open(m.box);
          await laps.putLap(lap);
          window.dispatchEvent(new CustomEvent('gt7-lap-saved', { detail: lap }));
          return;
        }
        const adopting = !!localStorage.getItem(ADOPT);
        if (!m.box || (!adopting && (m.at || 0) <= (store.get().updatedAt || 0))) return; // ours is as new or newer
        const doc = await open(m.box);
        if (adopting) localStorage.removeItem(ADOPT);
        store.replace(doc);
        lastSync = Date.now(); emit();
      } catch { /* wrong key or junk: ignore */ }
    });
    c.on('close', () => { if (!conns.some((x) => x.connected)) { status = key ? 'connecting' : 'off'; emit(); } });
    c.on('error', () => {});
  }
}
function disconnect() { conns.forEach((c) => { try { c.end(true); } catch { /* ignore */ } }); conns = []; }

// One-time sign-in on a device. Returns after keys are ready; data arrives async.
export async function signIn(user, pass) {
  if (!window.crypto?.subtle) throw new Error('This browser has no WebCrypto (needs https).');
  const d = await derive(user, pass);
  localStorage.setItem(LS, JSON.stringify({ user: user.trim(), k: b64(d.enc), id: d.id }));
  localStorage.setItem(ADOPT, '1');
  connectedAt = 0;
  await start();
}

export function signOut() {
  localStorage.removeItem(LS); key = null; topic = null; disconnect(); status = 'off'; emit();
}

export async function start() {
  const a = account();
  if (!a) { status = 'off'; emit(); return; }
  key = await crypto.subtle.importKey('raw', unb64(a.k), 'AES-GCM', false, ['encrypt', 'decrypt']);
  topic = 'gt7endgame/v1/' + a.id;
  connect();
}

export const syncNow = () => publish();

// Laps: one retained, encrypted message each (thinned to ~10 Hz, ~30–60 KB).
const lapTopic = async (id) => topic + '/laps/' + hex(new Uint8Array(await crypto.subtle.digest('SHA-256', te.encode(id)))).slice(0, 24);
export async function publishLap(lap, only) {
  if (!key || lap.demo) return;
  const msg = JSON.stringify({ v: 1, id: lap.id, box: await seal(laps.thin(lap)) });
  const t = await lapTopic(lap.id);
  (only ? [only] : conns).forEach((c) => c.connected && c.publish(t, msg, { retain: true, qos: 1 }));
}
async function publishAllLaps(c) {
  const list = (await laps.allLaps()).filter((l) => !l.demo).slice(0, 40);
  for (const meta of list) { const lap = await laps.getLap(meta.id); if (lap) await publishLap(lap, c); }
}
window.addEventListener('gt7-lap-saved', (e) => { if (e.detail && !e.detail.thinned) publishLap(e.detail); });

store.subscribe((_s, why) => { if (why === 'local' && key) schedule(); });
