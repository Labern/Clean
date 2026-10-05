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

console.log(`${pass} passed, ${fail} failed`);
process.exit(fail ? 1 : 0);
