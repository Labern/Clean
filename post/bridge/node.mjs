// Local bridge: `node post/bridge/node.mjs` then open http://localhost:8787.
// Serves the app and the API from one origin, exactly like the Worker.
//
// POST_IMAP / POST_SMTP = host:port override Apple's servers (tests use this
// with POST_INSECURE=1 to talk plain TCP to fake servers).

import http from 'node:http';
import net from 'node:net';
import tls from 'node:tls';
import { readFile } from 'node:fs/promises';
import { fileURLToPath } from 'node:url';
import path from 'node:path';
import { handle, ICLOUD } from './api.js';

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');

function wrap(sock) {
  const chunks = [];
  let waiting = null, ended = false, error = null;
  const wake = () => { if (waiting) { const w = waiting; waiting = null; w(); } };
  sock.on('data', (d) => { chunks.push(new Uint8Array(d.buffer, d.byteOffset, d.byteLength)); wake(); });
  sock.on('end', () => { ended = true; wake(); });
  sock.on('close', () => { ended = true; wake(); });
  sock.on('error', (e) => { error = e; ended = true; wake(); });
  return {
    async read() {
      while (!chunks.length && !ended) await new Promise((r) => (waiting = r));
      if (chunks.length) return chunks.shift();
      if (error) throw error;
      return null;
    },
    write: (u8) => new Promise((res, rej) => sock.write(u8, (e) => (e ? rej(e) : res()))),
    startTls() {
      sock.removeAllListeners('data');
      return new Promise((res, rej) => {
        const t = tls.connect({ socket: sock, servername: sock.remoteHost }, () => res(wrap(t)));
        t.once('error', rej);
      });
    },
    close() { sock.destroy(); },
  };
}

export function makeOpen({ insecure = false } = {}) {
  return (host, port, mode) => new Promise((res, rej) => {
    const secure = mode === 'implicit' && !insecure;
    const s = secure ? tls.connect({ host, port, servername: host }) : net.connect({ host, port });
    s.remoteHost = host;
    s.setTimeout(30000, () => s.destroy(new Error('Timed out talking to the mail server')));
    s.once(secure ? 'secureConnect' : 'connect', () => res(wrap(s)));
    s.once('error', rej);
  });
}

const hp = (v, d) => { if (!v) return d; const [host, port] = v.split(':'); return { ...d, host, port: +port }; };
export function bridgeEnv(e = process.env) {
  const insecure = e.POST_INSECURE === '1';
  return { open: makeOpen({ insecure }), insecure, imap: hp(e.POST_IMAP, ICLOUD.imap), smtp: hp(e.POST_SMTP, ICLOUD.smtp) };
}

const TYPES = { '.html': 'text/html; charset=utf-8', '.js': 'text/javascript', '.json': 'application/json', '.png': 'image/png', '.svg': 'image/svg+xml', '.webmanifest': 'application/manifest+json' };
const PUBLIC = new Set(['/index.html', '/manifest.webmanifest', '/icon.svg', '/sw.js']);

export function createServer(env = bridgeEnv()) {
  return http.createServer(async (req, res) => {
    try {
      const url = new URL(req.url, `http://${req.headers.host || 'localhost'}`);
      if (url.pathname.startsWith('/api/')) {
        const body = req.method === 'POST' ? await new Promise((r) => { const b = []; req.on('data', (c) => b.push(c)); req.on('end', () => r(Buffer.concat(b))); }) : undefined;
        const out = await handle(new Request(url, { method: req.method, headers: req.headers, body }), env);
        res.writeHead(out.status, Object.fromEntries(out.headers));
        res.end(Buffer.from(await out.arrayBuffer()));
        return;
      }
      const p = url.pathname === '/' ? '/index.html' : url.pathname;
      if (!PUBLIC.has(p)) { res.writeHead(404); res.end('Not found'); return; }
      const data = await readFile(path.join(ROOT, p));
      res.writeHead(200, { 'Content-Type': TYPES[path.extname(p)] || 'application/octet-stream', 'Cache-Control': 'no-cache' });
      res.end(data);
    } catch (e) {
      res.writeHead(500); res.end(String(e?.message || e));
    }
  });
}

if (process.argv[1] === fileURLToPath(import.meta.url)) {
  const port = +process.env.PORT || 8787;
  createServer().listen(port, () => console.log(`Post bridge on http://localhost:${port}`));
}
