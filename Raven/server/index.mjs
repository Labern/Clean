// Raven server: one Node process on your Mac behind Tailscale Funnel.
// HTTP (setup page, API, public live-share JSON) + WebSocket hub + WhatsApp.

import http from 'node:http';
import { readFileSync, existsSync } from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { timingSafeEqual } from 'node:crypto';
import { WebSocketServer } from 'ws';
import { openDb } from './db.mjs';
import { createHub } from './hub.mjs';
import { createLive } from './live.mjs';
import { createWhatsApp } from './wa.mjs';

const here = path.dirname(fileURLToPath(import.meta.url));

export function createServer(opts = {}) {
  const env = { ...process.env, ...opts.env };
  const cfg = {
    port: +(env.PORT || 8787),
    secret: env.APP_SECRET || (env.WA_DEMO ? 'dev' : ''),
    origins: (env.PAGES_ORIGIN || 'https://labern.github.io').split(',').map(s => s.trim()).concat(['http://localhost:8765', 'http://127.0.0.1:8765']),
    dataDir: env.DATA_DIR || path.join(here, 'data'),
    demo: !!env.WA_DEMO,
    livePage: env.LIVE_PAGE || 'https://labern.github.io/Clean/Raven/live/',
    publicUrl: env.PUBLIC_URL || '',
    owner: env.OWNER_NAME || 'Raven',   // the name recipients of a live link see
  };
  if (!cfg.secret) throw new Error('APP_SECRET is required (or WA_DEMO=1 for a demo)');

  const log = opts.log || console;
  const db = openDb(cfg.dataDir);
  const hub = createHub();
  const live = createLive({ db, owner: cfg.owner });
  const wa = createWhatsApp({ db, hub, dataDir: cfg.dataDir, demo: cfg.demo, log });

  const DEFAULT_CANNED = ['On my way', 'Driving — call you back', 'Running 10 minutes late', 'Yes', 'No', 'Call me'];
  const canned = () => db.kvGet('canned', DEFAULT_CANNED);

  // ---- auth
  function keyOk(k) {
    if (!k || k.length !== cfg.secret.length) return false;
    return timingSafeEqual(Buffer.from(k), Buffer.from(cfg.secret));
  }
  function authed(req, url) {
    const h = req.headers.authorization || '';
    const bearer = h.startsWith('Bearer ') ? h.slice(7) : '';
    return keyOk(bearer) || keyOk(url.searchParams.get('key') || '');
  }

  // ---- helpers
  function cors(req, res) {
    const o = req.headers.origin;
    if (o && cfg.origins.includes(o)) {
      res.setHeader('Access-Control-Allow-Origin', o);
      res.setHeader('Vary', 'Origin');
    }
    res.setHeader('Access-Control-Allow-Methods', 'GET,POST,OPTIONS');
    res.setHeader('Access-Control-Allow-Headers', 'Authorization, Content-Type');
  }
  function json(res, code, body) {
    res.writeHead(code, { 'Content-Type': 'application/json; charset=utf-8', 'Cache-Control': 'no-store' });
    res.end(JSON.stringify(body));
  }
  function readBody(req) {
    return new Promise((resolve, reject) => {
      let s = ''; req.on('data', c => { s += c; if (s.length > 1e6) req.destroy(); });
      req.on('end', () => { try { resolve(s ? JSON.parse(s) : {}); } catch (e) { reject(e); } });
      req.on('error', reject);
    });
  }
  function publicBase(req) {
    if (cfg.publicUrl) return cfg.publicUrl.replace(/\/$/, '');
    const proto = req.headers['x-forwarded-proto'] || 'http';
    return `${proto}://${req.headers.host}`;
  }

  // ---- positions and shares
  function acceptPos(p) {
    if (typeof p?.lat !== 'number' || typeof p?.lng !== 'number') return false;
    const pos = { ts: p.ts || Date.now(), lat: p.lat, lng: p.lng, speed: p.speed ?? null, heading: p.heading ?? null };
    db.posAdd(pos);
    hub.broadcast('car.pos', pos);
    return true;
  }
  function shareState() {
    const list = live.active().map(s => ({ token: s.token, name: s.name, chat: s.jid, expires: s.expires, refreshMin: s.refresh_min }));
    hub.broadcast('share.state', { shares: list });
    return list;
  }
  async function startShare(req, { chat, minutes = 60, refreshMin = 0 }) {
    const name = db.chats(100).find(c => c.jid === chat)?.name || db.contactName(chat) || chat;
    const s = live.create({ jid: chat, name, minutes, refreshMin });
    const url = `${cfg.livePage}#s=${encodeURIComponent(publicBase(req))}&t=${s.token}`;
    const p = db.posLast();
    if (p) await wa.sendLocation(chat, { lat: p.lat, lng: p.lng, name: 'Raven', address: 'Live: ' + url });
    await wa.sendText(chat, `Follow me live: ${url}`);
    shareState();
    return { token: s.token, url, expires: s.expires };
  }
  async function refreshPins() {
    const p = db.posLast();
    if (!p) return;
    for (const s of live.duePins()) {
      try { await wa.sendLocation(s.jid, { lat: p.lat, lng: p.lng, name: 'Raven' }); live.pinned(s.token); } catch (e) { log.warn('[share] pin failed', e.message); }
    }
    if (db.shareExpire()) shareState();
  }

  // ---- HTTP
  const setupHtml = () => readFileSync(path.join(here, 'setup.html'), 'utf8');
  const server = http.createServer(async (req, res) => {
    const url = new URL(req.url, 'http://x');
    cors(req, res);
    if (req.method === 'OPTIONS') { res.writeHead(204); return res.end(); }
    try {
      if (url.pathname === '/' || url.pathname === '/setup') {
        res.writeHead(200, { 'Content-Type': 'text/html; charset=utf-8', 'Cache-Control': 'no-store' });
        return res.end(setupHtml());
      }
      if (url.pathname === '/health') return json(res, 200, { ok: true, wa: wa.status.state, clients: hub.size, demo: cfg.demo });
      const m = url.pathname.match(/^\/api\/live\/([A-Za-z0-9_-]{8,})$/);
      if (m) { const v = live.view(m[1]); return v ? json(res, 200, v) : json(res, 404, { error: 'unknown share' }); }

      if (!url.pathname.startsWith('/api/')) return json(res, 404, { error: 'not found' });
      if (!authed(req, url)) return json(res, 401, { error: 'unauthorised' });
      const body = req.method === 'POST' ? await readBody(req) : {};

      switch (`${req.method} ${url.pathname}`) {
        case 'GET /api/state': return json(res, 200, Object.fromEntries(hub.last));
        case 'GET /api/wa/chats': return json(res, 200, { chats: db.chats(30) });
        case 'POST /api/wa/send': return json(res, 200, await wa.sendText(body.chat, body.text));
        case 'POST /api/wa/read': return json(res, 200, await wa.markRead(body.chat));
        case 'POST /api/wa/location': return json(res, 200, await wa.sendLocation(body.chat, body));
        case 'POST /api/pos': return json(res, acceptPos(body) ? 200 : 400, { ok: acceptPos(body) });
        case 'GET /api/share': return json(res, 200, { shares: shareState() });
        case 'POST /api/share': return json(res, 200, await startShare(req, body));
        case 'POST /api/share/stop': live.stop(body.token); return json(res, 200, { ok: true, shares: shareState() });
        case 'GET /api/canned': return json(res, 200, { canned: canned() });
        case 'POST /api/canned': db.kvSet('canned', (body.canned || []).map(String).filter(Boolean).slice(0, 12)); hub.broadcast('wa.canned', { canned: canned() }); return json(res, 200, { canned: canned() });
        case 'GET /api/open-link': return json(res, 200, { url: `https://labern.github.io/Clean/Raven/?key=${encodeURIComponent(cfg.secret)}&server=${encodeURIComponent(publicBase(req))}` });
        default: return json(res, 404, { error: 'no such route' });
      }
    } catch (e) {
      log.error('[http]', req.method, url.pathname, e.message);
      return json(res, 500, { error: e.message });
    }
  });

  // ---- WebSocket
  const wss = new WebSocketServer({ noServer: true });
  server.on('upgrade', (req, socket, head) => {
    const url = new URL(req.url, 'http://x');
    if (url.pathname !== '/ws' || !keyOk(url.searchParams.get('key') || '')) { socket.write('HTTP/1.1 401 Unauthorized\r\n\r\n'); return socket.destroy(); }
    wss.handleUpgrade(req, socket, head, (ws) => {
      hub.add(ws, { ua: req.headers['user-agent'] });
      hub.send(ws, 'wa.canned', { canned: canned() });
      hub.send(ws, 'share.state', { shares: live.active().map(s => ({ token: s.token, name: s.name, chat: s.jid, expires: s.expires, refreshMin: s.refresh_min })) });
      ws.__req = req;
    });
  });
  hub.onMessage(async (type, data, ws) => {
    const reply = (t, d) => hub.send(ws, t, d);
    try {
      switch (type) {
        case 'ping': return reply('pong', { t: Date.now() });
        case 'car.pos': return acceptPos(data);
        case 'wa.send': await wa.sendText(data?.chat, data?.text); return reply('wa.sent', { ok: true, chat: data.chat });
        case 'wa.read': return wa.markRead(data?.chat);
        case 'wa.share': { const r = await startShare(ws.__req, data || {}); return reply('wa.shared', { ok: true, ...r }); }
        case 'wa.share.stop': live.stop(data?.token); shareState(); return;
        case 'wa.location': await wa.sendLocation(data?.chat, data); return reply('wa.sent', { ok: true, chat: data.chat });
        default: return;
      }
    } catch (e) {
      reply('error', { of: type, message: e.message });
    }
  });

  let timers = [];
  return {
    cfg, db, hub, live, wa, server,
    async start(port = cfg.port) {
      await new Promise((r) => server.listen(port, r));
      await wa.start();
      timers.push(setInterval(refreshPins, 30000), setInterval(() => db.posPrune(Date.now() - 30 * 86400000), 3600000));
      log.log(`[raven] listening on ${server.address().port}${cfg.demo ? ' (WA demo)' : ''}`);
      return server.address().port;
    },
    async stop() {
      timers.forEach(clearInterval); timers = [];
      wa.stop(); hub.close();
      await new Promise((r) => server.close(r));
      db.close();
    },
  };
}

if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  const app = createServer();
  app.start().catch((e) => { console.error(e); process.exit(1); });
  const bye = () => app.stop().then(() => process.exit(0));
  process.on('SIGINT', bye); process.on('SIGTERM', bye);
}
