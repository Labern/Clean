#!/usr/bin/env node
// GT7 Endgame bridge: reads Gran Turismo 7's telemetry stream from your PS5,
// records every lap, and serves the app on your Mac so phone and Mac can see
// live data and replay your racing line. Zero dependencies: Node 18+ only.
//
//   node gt7-bridge.mjs --ps5 192.168.1.23     # your PS5's IP (Settings → Network)
//   node gt7-bridge.mjs --ps5 auto             # broadcast; works on most home networks
//   node gt7-bridge.mjs --demo                 # no PS5: replays a synthetic Spa lap
//
// Then open http://localhost:8787 on the Mac, or http://<mac-ip>:8787 on your phone.
//
// Protocol (PDTools / gt7dashboard): send a one-byte heartbeat to the PS5 on
// UDP 33739 every 10 s; it streams packets at 60 Hz to UDP 33740. Packets are
// Salsa20-encrypted: key = first 32 bytes of "Simulator Interface Packet GT7
// ver 0.0", nonce = (iv ^ XOR) ‖ iv where iv = uint32 LE at 0x40. Heartbeat
// '~' gives the 344-byte packet (adds steering angle); XOR per type below.

import dgram from 'node:dgram';
import http from 'node:http';
import fs from 'node:fs';
import path from 'node:path';
import os from 'node:os';
import { fileURLToPath } from 'node:url';
import { SIZE, decrypt as dec, encrypt as enc, parse } from './protocol.mjs';
import * as psn from '../app/psn-core.js';

const HERE = path.dirname(fileURLToPath(import.meta.url));
const APP = path.resolve(HERE, '..');
const args = Object.fromEntries(process.argv.slice(2).map((a, i, all) => a.startsWith('--') ? [a.slice(2), all[i + 1] && !all[i + 1].startsWith('--') ? all[i + 1] : true] : null).filter(Boolean));
const PORT = +(args.port || 8787);
const LAPS = path.resolve(args.laps || path.join(os.homedir(), 'GT7Laps'));
const TYPE = args.type || '~';
const SEND_PORT = 33739, RECV_PORT = 33740;
fs.mkdirSync(LAPS, { recursive: true });

// ── lap recorder ──────────────────────────────────────────────────────────
// Samples at 20 Hz (every 3rd packet) while the car is on track and moving.
// A lap closes when the lap counter increments; GT7 reports its official time
// in `last` a moment later, so we wait for it before writing the file.
let cur = null, pending = null, live = null, lastPacket = 0, packets = 0, sinceBeat = 0;
const clients = new Set();
function lapId(meta) { return new Date(meta.t0).toISOString().replace(/[:.]/g, '-').slice(0, 19) + `-car${meta.car}-L${meta.lap}`; }
function onFrame(fr) {
  live = fr; packets++; lastPacket = Date.now();
  if (fr.paused || fr.loading || !fr.onTrack) return;
  if (!cur || fr.lap !== cur.lap) {
    if (cur && fr.lap === cur.lap + 1 && cur.pts.length > 100) pending = { ...cur, closedAt: Date.now(), bestBefore: fr.best };
    cur = { lap: fr.lap, car: fr.car, t0: Date.now(), pts: [] };
  }
  if (pending && (fr.last > 0 && Date.now() - pending.closedAt > 300 || Date.now() - pending.closedAt > 4000)) {
    saveLap(pending, fr.last > 0 ? fr.last : null); pending = null;
  }
  if (packets % 3 === 0) {
    const t = (Date.now() - cur.t0) / 1000;
    cur.pts.push([+t.toFixed(3), +fr.x.toFixed(2), +fr.z.toFixed(2), +fr.y.toFixed(2), +fr.v.toFixed(1), Math.round(fr.thr * 100), Math.round(fr.brk * 100), fr.gear, Math.round(fr.rpm), fr.steer == null ? 0 : +fr.steer.toFixed(3)]);
  }
}
function saveLap(l, ms) {
  const meta = { id: lapId(l), car: l.car, lap: l.lap, t0: l.t0, time: ms ?? Math.round(l.pts.at(-1)[0] * 1000), timeSource: ms ? 'gt7' : 'measured', n: l.pts.length };
  const doc = { ...meta, cols: ['t', 'x', 'z', 'y', 'kmh', 'thr', 'brk', 'gear', 'rpm', 'steer'], pts: l.pts };
  fs.writeFileSync(path.join(LAPS, meta.id + '.json'), JSON.stringify(doc));
  console.log(`lap ${meta.lap} saved  ${(meta.time / 1000).toFixed(3)} s  car ${meta.car}  → ${meta.id}.json`);
  broadcast('lap', meta);
}

// ── UDP ───────────────────────────────────────────────────────────────────
const sock = dgram.createSocket({ type: 'udp4', reuseAddr: true });
let ps5 = args.ps5 && args.ps5 !== true ? args.ps5 : null;
sock.on('message', (buf, rinfo) => {
  if (buf.length !== SIZE[TYPE] && buf.length !== SIZE.A) return;
  const d = dec(buf, buf.length === SIZE.A ? 'A' : TYPE);
  if (!d) return;
  if (ps5 === 'auto' || ps5 === '255.255.255.255') { ps5 = rinfo.address; console.log('PS5 found at', ps5); }
  onFrame(parse(d));
  if (++sinceBeat > 600) beat();
});
function beat() {
  sinceBeat = 0;
  if (!ps5 || args.demo) return;
  const target = ps5 === 'auto' ? '255.255.255.255' : ps5;
  sock.send(Buffer.from(TYPE), SEND_PORT, target, () => {});
}
sock.bind(RECV_PORT, () => {
  sock.setBroadcast(true);
  if (!args.demo && !ps5) console.log('No --ps5 given: waiting. Pass --ps5 <ip> or --ps5 auto.');
  beat(); setInterval(beat, 10000);
});

// ── HTTP: the app + a tiny API ───────────────────────────────────────────
const MIME = { '.html': 'text/html', '.js': 'text/javascript', '.mjs': 'text/javascript', '.css': 'text/css', '.json': 'application/json', '.png': 'image/png', '.jpg': 'image/jpeg', '.svg': 'image/svg+xml', '.webmanifest': 'application/manifest+json' };
function broadcast(ev, data) { const s = `event: ${ev}\ndata: ${JSON.stringify(data)}\n\n`; clients.forEach((r) => r.write(s)); }
setInterval(() => {
  if (!clients.size) return;
  const age = Date.now() - lastPacket;
  broadcast('live', live && age < 2000 ? { ...live, recording: !!cur, lapPts: cur?.pts.length || 0 } : { offline: true, ps5, age });
}, 100);
function listLaps() {
  return fs.readdirSync(LAPS).filter((f) => f.endsWith('.json')).map((f) => {
    try { const d = JSON.parse(fs.readFileSync(path.join(LAPS, f), 'utf8')); delete d.pts; return d; } catch { return null; }
  }).filter(Boolean).sort((a, b) => b.t0 - a.t0);
}
// ── PSN + GT-Gridstats (accounts) ─────────────────────────────────────────
// The NPSSO / refresh token never leaves this Mac: it lives in a 0600 file
// next to your laps. The app only receives the summary.
const PSN_FILE = path.join(LAPS, '.psn-token.json');
const readTok = () => { try { return JSON.parse(fs.readFileSync(PSN_FILE, 'utf8')); } catch { return null; } };
const writeTok = (t) => { fs.writeFileSync(PSN_FILE, JSON.stringify(t)); fs.chmodSync(PSN_FILE, 0o600); };
async function psnAccess() {
  let t = readTok();
  if (!t) throw new Error('not connected');
  if (Date.now() > t.expiresAt) { t = await psn.refreshTokens(fetch, t.refresh); writeTok(t); }
  return t.access;
}
const body = (req) => new Promise((ok) => { let d = ''; req.on('data', (c) => (d += c)); req.on('end', () => { try { ok(JSON.parse(d || '{}')); } catch { ok({}); } }); });
async function accounts(req, res, u) {
  try {
    if (u.pathname === '/api/psn/connect' && req.method === 'POST') {
      const { npsso } = await body(req);
      if (!npsso || npsso.length < 40) return json(res, { ok: false, error: 'That doesn\'t look like an NPSSO (64 characters).' }, 400);
      writeTok(await psn.tokensFromCode(fetch, await psn.exchangeNpsso(fetch, npsso)));
      return json(res, { ok: true, summary: await psn.summary(fetch, await psnAccess()) });
    }
    if (u.pathname === '/api/psn/summary') return json(res, { ok: true, summary: await psn.summary(fetch, await psnAccess()) });
    if (u.pathname === '/api/psn/disconnect' && req.method === 'POST') { fs.rmSync(PSN_FILE, { force: true }); return json(res, { ok: true }); }
    if (u.pathname === '/api/psn/status') { const t = readTok(); return json(res, { ok: true, connected: !!t, refreshExpiresAt: t?.refreshExpiresAt || null }); }
    if (u.pathname.startsWith('/api/proxy/gridstats/')) { // GT-Gridstats doesn't promise CORS: relay it
      const r = await fetch('https://gtgridstats.com/api/' + u.pathname.slice('/api/proxy/gridstats/'.length) + u.search, { headers: { Authorization: 'Bearer ' + (req.headers['x-gg-token'] || ''), Accept: 'application/json' } });
      res.writeHead(r.status, { 'Content-Type': 'application/json' }); return res.end(await r.text());
    }
  } catch (e) { return json(res, { ok: false, error: String(e.message || e) }, e.message === 'not connected' ? 401 : 502); }
  return false;
}

http.createServer(async (req, res) => {
  const u = new URL(req.url, 'http://x');
  res.setHeader('Access-Control-Allow-Origin', '*');
  res.setHeader('Access-Control-Allow-Headers', 'Content-Type, X-GG-Token');
  if (req.method === 'OPTIONS') { res.writeHead(204); return res.end(); }
  if (u.pathname.startsWith('/api/psn/') || u.pathname.startsWith('/api/proxy/')) { if ((await accounts(req, res, u)) !== false) return; }
  if (u.pathname === '/api/status') return json(res, { ok: true, ps5, packets, lastPacket, type: TYPE, laps: LAPS, demo: !!args.demo });
  if (u.pathname === '/api/laps') return json(res, listLaps());
  if (u.pathname.startsWith('/api/laps/')) {
    const id = path.basename(decodeURIComponent(u.pathname.slice(10)));
    const p = path.join(LAPS, id + '.json');
    if (!fs.existsSync(p)) { res.writeHead(404); return res.end(); }
    res.writeHead(200, { 'Content-Type': 'application/json' }); return fs.createReadStream(p).pipe(res);
  }
  if (u.pathname === '/api/live') {
    res.writeHead(200, { 'Content-Type': 'text/event-stream', 'Cache-Control': 'no-cache', Connection: 'keep-alive' });
    res.write('retry: 2000\n\n'); clients.add(res); req.on('close', () => clients.delete(res)); return;
  }
  let p = path.normalize(path.join(APP, u.pathname === '/' ? 'index.html' : u.pathname));
  if (!p.startsWith(APP) || p.includes(`${path.sep}tools${path.sep}`)) { res.writeHead(403); return res.end(); }
  if (fs.existsSync(p) && fs.statSync(p).isDirectory()) p = path.join(p, 'index.html');
  if (!fs.existsSync(p)) { res.writeHead(404); return res.end('not found'); }
  res.writeHead(200, { 'Content-Type': MIME[path.extname(p)] || 'application/octet-stream', 'Cache-Control': 'no-cache' });
  fs.createReadStream(p).pipe(res);
}).listen(PORT, () => {
  const ips = Object.values(os.networkInterfaces()).flat().filter((i) => i && i.family === 'IPv4' && !i.internal).map((i) => i.address);
  console.log(`GT7 Endgame bridge\n  app:   http://localhost:${PORT}` + ips.map((ip) => `\n  phone: http://${ip}:${PORT}`).join('') + `\n  laps → ${LAPS}`);
});
function json(res, o, code = 200) { res.writeHead(code, { 'Content-Type': 'application/json' }); res.end(JSON.stringify(o)); }

// ── --demo: encrypt a synthetic lap and send it to ourselves ──────────────
// Exercises the exact decode path a real PS5 uses. The lap comes from
// demo-lap.json (generated from real Spa geometry by tools/make_demo_lap.mjs).
if (args.demo) {
  const demo = JSON.parse(fs.readFileSync(path.join(APP, 'data', 'demo-lap.json'), 'utf8'));
  const C = Object.fromEntries(demo.cols.map((c, i) => [c, i]));
  const total = demo.pts.at(-1)[C.t];
  let lap = 1, t = 0, iv = 0x1234, pid = 0, best = -1, last = -1;
  setInterval(() => {
    t += 1 / 60;
    if (t > total) { t -= total; last = Math.round(total * 1000); best = best < 0 ? last : Math.min(best, last); lap++; }
    let i = demo.pts.findIndex((p) => p[C.t] >= t); if (i < 1) i = 1;
    const a = demo.pts[i - 1], b = demo.pts[i], k = (t - a[C.t]) / ((b[C.t] - a[C.t]) || 1);
    const L = (c) => a[C[c]] + (b[C[c]] - a[C[c]]) * k;
    const pk = Buffer.alloc(SIZE[TYPE]);
    pk.writeUInt32LE(0x47375330, 0);
    pk.writeFloatLE(L('x'), 0x04); pk.writeFloatLE(L('y'), 0x08); pk.writeFloatLE(L('z'), 0x0C);
    pk.writeFloatLE(L('rpm'), 0x3C); pk.writeFloatLE(60, 0x44); pk.writeFloatLE(100, 0x48);
    pk.writeFloatLE(L('kmh') / 3.6, 0x4C); pk.writeFloatLE(1, 0x50);
    [0x60, 0x64, 0x68, 0x6C].forEach((o) => pk.writeFloatLE(82 + Math.random() * 4, o));
    pk.writeInt32LE(pid++, 0x70); pk.writeInt16LE(lap, 0x74); pk.writeInt16LE(0, 0x76);
    pk.writeInt32LE(best, 0x78); pk.writeInt32LE(last, 0x7C);
    pk.writeInt16LE(-1, 0x84); pk.writeInt16LE(-1, 0x86); pk.writeInt16LE(8500, 0x8A);
    pk.writeInt16LE(1 | 8, 0x8E);
    pk[0x90] = a[C.gear] | (15 << 4); pk[0x91] = Math.round(a[C.thr] * 2.55); pk[0x92] = Math.round(a[C.brk] * 2.55);
    pk.writeInt32LE(3437, 0x124);
    if (pk.length >= 0x13C) pk.writeFloatLE(L('steer'), 0x128);
    sock.send(enc(pk, iv++, TYPE), RECV_PORT, '127.0.0.1');
  }, 1000 / 60);
  console.log(`demo: streaming a synthetic ${total.toFixed(1)} s Spa lap, looping`);
}
