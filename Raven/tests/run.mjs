// Zero-dependency test harness (house convention). Run: node Raven/tests/run.mjs
import assert from 'node:assert/strict';
import { readdirSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import path from 'node:path';

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
let pass = 0, fail = 0;
async function test(name, fn) {
  try { await fn(); pass++; }
  catch (e) { fail++; console.error(`✗ ${name}\n  ${e.message}`); }
}

// ---- bus
const bus = await import(`${root}/lib/bus.js`);
await test('bus: emit reaches handlers, latest() remembers', () => {
  bus.reset();
  let got = null;
  const off = bus.on('x', (d) => { got = d; });
  assert.equal(bus.emit('x', 1), 1);
  assert.equal(got, 1);
  assert.equal(bus.latest('x'), 1);
  off();
  assert.equal(bus.emit('x', 2), 0);
});
await test('bus: a throwing handler does not stop the others', () => {
  bus.reset();
  let n = 0;
  const err = console.error; console.error = () => {};
  bus.on('y', () => { throw new Error('boom'); });
  bus.on('y', () => { n++; });
  bus.emit('y');
  console.error = err;
  assert.equal(n, 1);
});

// ---- store
const { createStore, merge, DEFAULTS } = await import(`${root}/lib/store.js`);
await test('store: merge hydrates over defaults and keeps unknown keys', () => {
  const m = merge({ a: 1, b: { c: 2, d: 3 }, list: [1] }, { b: { c: 9 }, extra: true, list: [5, 6] });
  assert.deepEqual(m, { a: 1, b: { c: 9, d: 3 }, list: [5, 6], extra: true });
});
await test('store: works without storage and persists with it', () => {
  const s = createStore(null);
  assert.equal(s.get('units'), DEFAULTS.units);
  const mem = new Map();
  const fake = { getItem: (k) => mem.get(k) ?? null, setItem: (k, v) => mem.set(k, v) };
  const s2 = createStore(fake);
  s2.set('ui', 2); s2.flush();
  assert.equal(JSON.parse(mem.get('raven_v1')).ui, 2);
  assert.equal(createStore(fake).get('ui'), 2);
});

// ---- fmt
const fmt = await import(`${root}/lib/fmt.js`);
await test('fmt: miles/speed/efficiency', () => {
  assert.equal(fmt.miles(100), '62');
  assert.equal(fmt.miles(100, 'km'), '100');
  assert.equal(fmt.speed(100), 62);
  assert.equal(fmt.whPer(10, 50), 322);     // 10 kWh over 31.07 mi
  assert.equal(fmt.whPer(10, 50, 'km'), 200);
  assert.equal(fmt.whPer(1, 0), null);
});
await test('fmt: durations and ago', () => {
  assert.equal(fmt.duration(5000), '0:05');
  assert.equal(fmt.duration(65 * 60000), '1:05:00');
  assert.equal(fmt.hm(135 * 60000), '2h 15m');
  assert.equal(fmt.ago(1000, 2000), 'now');
  assert.equal(fmt.ago(0, 5 * 60000), '5m');
  assert.equal(fmt.initials('Tom Bombadil'), 'TB');
  assert.equal(fmt.money(3.5), '£3.50');
});

// ---- sun
const { sunTimes, isNight } = await import(`${root}/lib/sun.js`);
await test('sun: London on 21 June, sunrise 03:43 UTC (04:43 BST), sunset 20:21 UTC', () => {
  const t = sunTimes(new Date(Date.UTC(2026, 5, 21, 12)), 51.5074, -0.1278);
  const h = (d) => d.getUTCHours() + d.getUTCMinutes() / 60;
  assert.ok(Math.abs(h(t.sunrise) - 3.72) < 0.2, `sunrise ${t.sunrise.toISOString()}`);
  assert.ok(Math.abs(h(t.sunset) - 20.35) < 0.2, `sunset ${t.sunset.toISOString()}`);
  assert.equal(isNight(new Date(Date.UTC(2026, 5, 21, 12)), 51.5, -0.13), false);
  assert.equal(isNight(new Date(Date.UTC(2026, 5, 21, 23)), 51.5, -0.13), true);
});

// ---- drives
const drives = await import(`${root}/lib/drives.js`);
await test('drives: haversine London→Brighton ≈ 76 km', () => {
  const d = drives.haversine({ lat: 51.5074, lng: -0.1278 }, { lat: 50.8225, lng: -0.1372 });
  assert.ok(Math.abs(d - 76.2) < 1, String(d));
});
await test('drives: segmenter starts on motion, ends after 5 min stopped', () => {
  const seg = drives.createSegmenter();
  let t = 0, lat = 51.5, lng = -0.1;
  const push = (speed, soc) => { seg.push({ ts: t, lat, lng, speed, soc }); t += 10000; };
  push(0, 80); push(0, 80);
  assert.equal(seg.current, null);
  for (let i = 0; i < 60; i++) { lng += 0.001; push(50, 80 - i * 0.1); }
  assert.ok(seg.current, 'drive should be open');
  for (let i = 0; i < 40; i++) push(0, 74);
  assert.equal(seg.drives.length, 1);
  const d = seg.drives[0];
  assert.ok(d.distanceKm > 4 && d.distanceKm < 5, String(d.distanceKm));
  assert.equal(d.maxSpeed, 50);
  assert.equal(d.endTs, 620000); // ended at the moment it stopped, not 5 min later
  assert.equal(seg.current, null);
});
await test('drives: stats', () => {
  const list = [
    { distanceKm: 100, durationMs: 3600000, maxSpeed: 110, startSoc: 80, endSoc: 60, startTs: 0 },
    { distanceKm: 20, durationMs: 1800000, maxSpeed: 60, startSoc: 60, endSoc: 57, startTs: 1 },
  ];
  const s = drives.stats(list, 100);
  assert.equal(s.count, 2);
  assert.equal(s.totalKm, 120);
  assert.equal(s.longest.distanceKm, 100);
  assert.equal(s.fastest.maxSpeed, 110);
  assert.ok(Math.abs(s.whPerKm - 191.67) < 0.1, String(s.whPerKm));
  assert.equal(s.bestDrive.distanceKm, 20);
});

// ---- link
const { createLink } = await import(`${root}/lib/link.js`);
await test('link: republishes server messages onto the bus', () => {
  bus.reset();
  let inst;
  class FakeWS { constructor(url) { this.url = url; inst = this; } send() {} close() {} }
  const l = createLink({ server: 'https://x.ts.net', key: 'k', WS: FakeWS });
  l.start();
  assert.equal(inst.url, 'wss://x.ts.net/ws?key=k');
  inst.onopen();
  assert.equal(l.state.status, 'on');
  let got; bus.on('wa.message', (d) => { got = d; });
  inst.onmessage({ data: JSON.stringify({ type: 'wa.message', data: { name: 'Dad' } }) });
  assert.equal(got.name, 'Dad');
  l.stop();
});
await test('link: no server → off, never constructs a socket', () => {
  let made = 0;
  class FakeWS { constructor() { made++; } }
  const l = createLink({ server: '', key: '', WS: FakeWS });
  l.start();
  assert.equal(made, 0);
  assert.equal(l.state.status, 'off');
});

// ---- demo
const demo = await import(`${root}/lib/demo.js`);
await test('demo: detection', () => {
  assert.equal(demo.isDemo({ hostname: 'localhost', search: '' }), true);
  assert.equal(demo.isDemo({ hostname: 'labern.github.io', search: '' }), false);
  assert.equal(demo.isDemo({ hostname: 'labern.github.io', search: '?demo=1' }), true);
  assert.equal(demo.isDemo({ hostname: 'localhost', search: '?demo=0' }), false);
});
await test('demo: emits a state for every widget', () => {
  bus.reset();
  const seen = new Set();
  for (const t of ['spotify.state', 'wa.chats', 'tesla.state', 'drive.update', 'drives.history']) bus.on(t, () => seen.add(t));
  const timers = [];
  const stop = demo.startDemo({ setInterval: (fn, ms) => { timers.push(fn); return 0; } });
  assert.equal(seen.size, 5, [...seen].join(','));
  stop();
});

// ---- widget contract
await test('widgets: every widget honours the contract', async () => {
  const files = readdirSync(`${root}/widgets`).filter(f => f.endsWith('.js') && f !== 'map.js');
  assert.ok(files.length >= 5);
  for (const f of files) {
    const w = (await import(`${root}/widgets/${f}`)).default;
    assert.equal(typeof w.id, 'string', f);
    assert.equal(typeof w.title, 'string', f);
    assert.equal(typeof w.order, 'number', f);
    assert.equal(typeof w.summary, 'function', f);
    assert.equal(typeof w.detail, 'function', f);
    assert.ok(Array.isArray(w.events), f);
    for (const [k, v] of Object.entries(w.actions || {})) assert.equal(typeof v, 'function', `${f} action ${k}`);
  }
});

// ---- geo
const geo = await import(`${root}/lib/geo.js`);
await test('geo: throttles to 1 Hz, suppresses parked repeats, reports status', () => {
  bus.reset();
  let cb; const fake = { watchPosition: (ok) => { cb = ok; return 7; }, clearWatch: () => {} };
  const sent = [];
  const stop = geo.startGeo({ send: (t, d) => sent.push(d), geo: fake, minMs: 1000 });
  const fix = (lat, lng, ts) => cb({ timestamp: ts, coords: { latitude: lat, longitude: lng, speed: 10, heading: 90, accuracy: 5 } });
  fix(51.5, -0.1, 1); fix(51.5, -0.1, 2);           // second one inside 1 s
  assert.equal(sent.length, 1);
  assert.equal(bus.latest('geo.status').ok, true);
  assert.equal(bus.latest('car.pos').speed, 36);     // m/s → km/h
  stop();
  assert.equal(geo.dist({ lat: 51.5, lng: -0.1 }, { lat: 51.5, lng: -0.1 }), 0);
  assert.ok(Math.abs(geo.dist({ lat: 51.5074, lng: -0.1278 }, { lat: 50.8225, lng: -0.1372 }) - 76.2) < 1);
});
await test('geo: no API → status only', () => {
  bus.reset();
  geo.startGeo({ send: () => { throw new Error('should not send'); }, geo: null });
  assert.equal(bus.latest('geo.status').ok, false);
});

// ---- trip from GPS
const trip = await import(`${root}/lib/trip.js`);
await test('trip: car.pos → drive.update while moving, history on stop', () => {
  bus.reset();
  const mem = new Map();
  const storage = { getItem: (k) => mem.get(k) ?? null, setItem: (k, v) => mem.set(k, v) };
  const updates = [];
  bus.on('drive.update', (d) => updates.push(d));
  const t = trip.startTrip({ storage });
  assert.deepEqual(bus.latest('drives.history').drives, []);
  let ts = 0, lng = -0.1;
  const fix = (speed) => { bus.emit('car.pos', { ts, lat: 51.5, lng, speed }); ts += 10000; };
  for (let i = 0; i < 60; i++) { lng += 0.001; fix(50); }
  assert.ok(t.current && updates.at(-1).distanceKm > 4 && updates.at(-1).kwh === null);
  for (let i = 0; i < 40; i++) fix(0);
  assert.equal(t.current, null);
  assert.equal(t.history.length, 1);
  assert.equal(updates.at(-1), null);
  assert.equal(JSON.parse(mem.get(trip.HISTORY_KEY)).length, 1);
  assert.equal(bus.latest('drives.history').drives[0].maxSpeed, 50);
  t.stop();
  // reload picks the history back up
  bus.reset();
  trip.startTrip({ storage });
  assert.equal(bus.latest('drives.history').drives.length, 1);
});

// ---- spotify api (fake fetch + storage)
const spapi = await import(`${root}/lib/spotify-api.js`);
await test('spotify: token refresh, 401 retry, 204 handling, state publish, commands', async () => {
  bus.reset();
  const mem = new Map();
  const storage = { getItem: (k) => mem.get(k) ?? null, setItem: (k, v) => mem.set(k, v), removeItem: (k) => mem.delete(k) };
  const calls = [];
  let t = 1_000_000;
  const player = { is_playing: true, progress_ms: 5000, shuffle_state: false, device: { id: 'dev1', name: 'iPhone', type: 'Smartphone' },
    item: { id: 'tr1', uri: 'spotify:track:tr1', name: 'Hunter', duration_ms: 254000, artists: [{ name: 'Björk' }], album: { name: 'Homogenic', images: [{ url: 'big' }, { url: 'mid' }] } } };
  const fetch = async (url, opts = {}) => {
    calls.push([opts.method || 'GET', url, opts.headers?.Authorization]);
    const json = (status, body) => ({ status, ok: status < 400, json: async () => body, text: async () => body == null ? '' : JSON.stringify(body) });
    if (url.endsWith('/api/token')) return json(200, { access_token: 'A2', expires_in: 3600, refresh_token: 'R2', scope: spapi.SCOPES });
    if (url.endsWith('/me/player')) return opts.headers.Authorization === 'Bearer A2' ? json(200, player) : json(401, {});
    if (url.includes('/me/tracks/contains')) return json(200, [true]);
    if (url.includes('/me/player/pause') || url.includes('/me/player/next')) return json(204, null);
    if (url.includes('/me/tracks?ids=')) return json(200, null);
    return json(404, { error: { message: 'nope' } });
  };
  const sp = spapi.createSpotify({ clientId: 'c', redirectUri: 'https://x/', storage, fetch, now: () => t, location: { search: '', pathname: '/', hash: '' } });
  assert.equal(sp.connected(), false);
  mem.set('sp_refresh_token', 'R1'); mem.set('sp_access_token', 'A1'); mem.set('sp_token_expiry', String(t + 3600000)); mem.set('sp_granted_scope', spapi.SCOPES);
  assert.equal(sp.connected(), true);
  assert.equal(sp.needsReconsent(), false);
  // A1 is rejected with 401 → refresh → retry with A2
  await sp.refreshNow();
  const st = bus.latest('spotify.state');
  assert.equal(st.track.name, 'Hunter'); assert.equal(st.art, 'mid'); assert.equal(st.device, 'iPhone');
  assert.ok(calls.some(c => c[1].endsWith('/api/token')), 'refreshed');
  assert.equal(mem.get('sp_access_token'), 'A2');
  await new Promise(r => setTimeout(r, 0));
  assert.equal(bus.latest('spotify.state').liked, true);
  t += 2000;
  assert.equal(sp.livePos(), 7000);
  // toggle → pause with the known device, optimistic state
  await sp.cmd('toggle');
  assert.ok(calls.some(c => c[0] === 'PUT' && c[1].includes('/me/player/pause?device_id=dev1')));
  assert.equal(bus.latest('spotify.state').playing, false);
  await sp.cmd('like');
  assert.ok(calls.some(c => c[0] === 'DELETE' && c[1].includes('/me/tracks?ids=tr1')));
  // a 404 from the player surfaces as the "no device" error, never throws
  let err; bus.on('spotify.error', (e) => { err = e; });
  await sp.cmd('shuffle');
  assert.ok(err && /No active Spotify device/.test(err.message), JSON.stringify(err));
  sp.stop();
});
await test('spotify: handleRedirect exchanges the code once and scrubs the URL', async () => {
  bus.reset();
  const mem = new Map([['sp_pkce_v', 'verifier']]);
  const storage = { getItem: (k) => mem.get(k) ?? null, setItem: (k, v) => mem.set(k, v), removeItem: (k) => mem.delete(k) };
  const loc = { search: '?code=abc&demo=0', pathname: '/Raven/', hash: '' };
  let replaced = null;
  globalThis.history = { replaceState: (_a, _b, url) => { replaced = url; } };
  const fetch = async (url, opts) => { assert.ok(String(opts.body).includes('code_verifier=verifier')); return { status: 200, ok: true, json: async () => ({ access_token: 'A', refresh_token: 'R', expires_in: 3600, scope: spapi.SCOPES }), text: async () => '' }; };
  const sp = spapi.createSpotify({ clientId: 'c', redirectUri: 'https://x/', storage, fetch, location: loc });
  assert.equal(await sp.handleRedirect(), true);
  assert.equal(replaced, '/Raven/?demo=0');
  assert.equal(sp.connected(), true);
  assert.equal(mem.has('sp_pkce_v'), false);
  assert.equal(bus.latest('spotify.auth').connected, true);
  delete globalThis.history;
});

// ---- whatsapp widget behaviour (DOM-free: summary into a fake element)
await test('whatsapp: summary reflects link/unread/share state', async () => {
  bus.reset();
  const w = (await import(`${root}/widgets/whatsapp.js`)).default;
  const el = { innerHTML: '' };
  w.summary(el);
  assert.ok(el.innerHTML.includes('Not linked') && el.innerHTML.includes('No server'));
  bus.emit('link.status', { status: 'on' }); bus.emit('wa.status', { state: 'qr' });
  w.summary(el); assert.ok(el.innerHTML.includes('Scan the QR'));
  bus.emit('wa.chats', { chats: [{ id: 'a', name: 'Dad', unread: 2, ts: Date.now() }], unread: 2 });
  w.summary(el); assert.ok(el.innerHTML.includes('Dad') && el.innerHTML.includes('badge">2'));
  bus.emit('wa.chats', { chats: [{ id: 'a', name: 'Dad', unread: 0, ts: Date.now() }], unread: 0 });
  bus.emit('share.state', { shares: [{ token: 't', name: 'Dad', chat: 'a', expires: Date.now() + 1000 }] });
  w.summary(el); assert.ok(el.innerHTML.includes('Sharing live'));
  const sent = [];
  w.actions.stopShares({ link: { send: (t, d) => sent.push([t, d]) } });
  assert.deepEqual(sent, [['wa.share.stop', { token: 't' }]]);
});

console.log(`${pass} passed, ${fail} failed`);
process.exit(fail ? 1 : 0);
