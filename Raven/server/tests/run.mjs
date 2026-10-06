// Server tests: real HTTP + WebSocket against a demo instance on a random
// port, plus the units. Run: node Raven/server/tests/run.mjs
import assert from 'node:assert/strict';
import { mkdtempSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import path from 'node:path';
import { WebSocket } from 'ws';
import { createServer } from '../index.mjs';
import { createHub } from '../hub.mjs';
import { createLive } from '../live.mjs';
import { openDb } from '../db.mjs';

let pass = 0, fail = 0;
async function test(name, fn) {
  if (process.env.V) console.log('·', name);
  try { await fn(); pass++; }
  catch (e) { fail++; console.error(`✗ ${name}\n  ${e.stack?.split('\n').slice(0, 3).join('\n  ')}`); }
}
const quiet = { log() {}, warn() {}, error() {} };
const tmp = () => mkdtempSync(path.join(tmpdir(), 'raven-'));

// ---- db
await test('db: chats bump/touch/read, kv, positions', () => {
  const dir = tmp(); const db = openDb(dir);
  db.chatBump('a@s', 'A', 10); db.chatBump('a@s', 'A', 20); db.chatTouch('b@s', 'B', 15);
  const c = db.chats();
  assert.deepEqual(c.map(x => [x.jid, x.unread, x.last_ts]), [['a@s', 2, 20], ['b@s', 0, 15]]);
  db.chatRead('a@s'); assert.equal(db.chats()[0].unread, 0);
  db.kvSet('x', { y: 1 }); assert.deepEqual(db.kvGet('x'), { y: 1 }); assert.equal(db.kvGet('nope', 7), 7);
  db.posAdd({ ts: 1, lat: 1, lng: 2 }); db.posAdd({ ts: 2, lat: 3, lng: 4, speed: 9 });
  assert.equal(db.posLast().lat, 3); assert.equal(db.posSince(2).length, 1);
  assert.equal(db.posPrune(2), 1);
  db.close(); rmSync(dir, { recursive: true, force: true });
});

// ---- hub
await test('hub: replays last state to a late client; remember:false does not', () => {
  const hub = createHub();
  const sent = [];
  const fake = { readyState: 1, send: (s) => sent.push(JSON.parse(s)), on() {} };
  hub.broadcast('a', 1); hub.broadcast('b', 2, { remember: false });
  hub.add(fake);
  assert.deepEqual(sent, [{ type: 'a', data: 1 }]);
  assert.equal(hub.broadcast('c', 3), 1);
});

// ---- live
await test('live: token lifecycle, view hides the chat id, due pins', () => {
  const dir = tmp(); const db = openDb(dir);
  let t = 1000; const live = createLive({ db, now: () => t });
  const s = live.create({ jid: 'a@s', name: 'A', minutes: 10, refreshMin: 5 });
  assert.equal(live.active().length, 1);
  db.posAdd({ ts: 900, lat: 51.5, lng: -0.1 });
  const v = live.view(s.token);
  assert.equal(v.name, 'Raven'); assert.equal(v.active, true); assert.equal(v.pos.lat, 51.5); assert.ok(!('jid' in v) && !('chat' in v));
  assert.equal(live.duePins().length, 0);
  t = 1000 + 5 * 60000; assert.equal(live.duePins().length, 1); live.pinned(s.token); assert.equal(live.duePins().length, 0);
  t = 1000 + 11 * 60000; assert.equal(live.active().length, 0); assert.equal(live.view(s.token).active, false);
  assert.equal(live.view('nope'), null);
  db.close(); rmSync(dir, { recursive: true, force: true });
});

// ---- full server, demo mode
const dir = tmp();
const app = createServer({ env: { WA_DEMO: '1', APP_SECRET: 'k', DATA_DIR: dir, PUBLIC_URL: 'https://mac.ts.net', PAGES_ORIGIN: 'https://labern.github.io', OWNER_NAME: 'Luke' }, log: quiet });
const port = await app.start(0);
const base = `http://127.0.0.1:${port}`;
const api = (p, body, key = 'k') => fetch(base + p, { method: body ? 'POST' : 'GET', headers: { Authorization: 'Bearer ' + key, 'Content-Type': 'application/json' }, body: body ? JSON.stringify(body) : undefined });

await test('http: setup page, health, auth', async () => {
  assert.equal((await fetch(base + '/setup')).status, 200);
  assert.deepEqual((await (await fetch(base + '/health')).json()).wa, 'open');
  assert.equal((await api('/api/state', null, 'wrong')).status, 401);
  assert.equal((await api('/api/state')).status, 200);
  const r = await fetch(base + '/api/state', { headers: { Origin: 'https://labern.github.io', Authorization: 'Bearer k' } });
  assert.equal(r.headers.get('access-control-allow-origin'), 'https://labern.github.io');
  const r2 = await fetch(base + '/api/state', { headers: { Origin: 'https://evil.example', Authorization: 'Bearer k' } });
  assert.equal(r2.headers.get('access-control-allow-origin'), null);
});

await test('http: demo chats, send, read, canned, open link', async () => {
  const chats = (await (await api('/api/wa/chats')).json()).chats;
  assert.ok(chats.length >= 5);
  const sam = chats.find(c => c.name === 'Sam'); assert.equal(sam.unread, 1);
  assert.equal((await (await api('/api/wa/send', { chat: sam.jid, text: 'hi' })).json()).ok, true);
  assert.equal((await api('/api/wa/send', { chat: sam.jid })).status, 500);
  await api('/api/wa/read', { chat: sam.jid });
  assert.equal((await (await api('/api/wa/chats')).json()).chats.find(c => c.jid === sam.jid).unread, 0);
  const c = await (await api('/api/canned', { canned: ['Yes', '', 'No'] })).json();
  assert.deepEqual(c.canned, ['Yes', 'No']);
  const link = (await (await api('/api/open-link')).json()).url;
  assert.ok(link.includes('key=k') && link.includes(encodeURIComponent('https://mac.ts.net')), link);
});

await test('ws: rejects bad key, replays state, car.pos round-trips, share creates a public live view', async () => {
  const bad = new WebSocket(`ws://127.0.0.1:${port}/ws?key=nope`);
  await new Promise((r) => { bad.on('error', r); bad.on('close', r); });

  const ws = new WebSocket(`ws://127.0.0.1:${port}/ws?key=k`);
  // Replayed state can arrive in the same tick as 'open', so buffer everything
  // and let waitFor consume from the buffer first.
  const buffer = [], waiters = [];
  ws.on('message', (raw) => {
    const m = JSON.parse(raw);
    const i = waiters.findIndex(w => w.type === m.type);
    if (i >= 0) waiters.splice(i, 1)[0].res(m.data); else buffer.push(m);
  });
  const waitFor = (type) => {
    const i = buffer.findIndex(m => m.type === type);
    if (i >= 0) return Promise.resolve(buffer.splice(i, 1)[0].data);
    return new Promise((res) => waiters.push({ type, res }));
  };
  await new Promise((r) => ws.on('open', r));
  const chats = waitFor('wa.chats'); const canned = waitFor('wa.canned');
  assert.ok((await chats).chats.length >= 5); assert.deepEqual((await canned).canned, ['Yes', 'No']);

  const echo = waitFor('car.pos');
  ws.send(JSON.stringify({ type: 'car.pos', data: { lat: 51.5, lng: -0.12, speed: 20, heading: 90 } }));
  assert.equal((await echo).lat, 51.5);

  const shared = waitFor('wa.shared');
  ws.send(JSON.stringify({ type: 'wa.share', data: { chat: 'demo1@s.whatsapp.net', minutes: 15 } }));
  const s = await shared;
  assert.ok(s.url.startsWith('https://labern.github.io/Clean/Raven/live/#s=https%3A%2F%2Fmac.ts.net&t='), s.url);
  const v = await (await fetch(`${base}/api/live/${s.token}`)).json();
  assert.equal(v.name, 'Luke'); assert.equal(v.active, true); assert.equal(v.pos.lat, 51.5); assert.equal(v.trail.length, 1);
  assert.ok(!JSON.stringify(v).includes('Sam'), 'recipient name must not leak into the public view');
  assert.equal((await fetch(`${base}/api/live/zzzzzzzzzzzz`)).status, 404);

  const state = waitFor('share.state');
  ws.send(JSON.stringify({ type: 'wa.share.stop', data: { token: s.token } }));
  assert.equal((await state).shares.length, 0);

  const err = waitFor('error');
  ws.send(JSON.stringify({ type: 'wa.send', data: { chat: 'x' } }));
  assert.equal((await err).of, 'wa.send');
  ws.close();
});

await app.stop();
rmSync(dir, { recursive: true, force: true });
console.log(`${pass} passed, ${fail} failed`);
process.exit(fail ? 1 : 0);
