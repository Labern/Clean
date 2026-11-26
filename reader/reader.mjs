#!/usr/bin/env node
// Reader — a local shelf that reflows your own PDFs into a readable page.
// Zero dependencies. Everything stays on this Mac: PDFs in library/, reading
// positions in library/state.json, examples you open in examples/.
//
//   node reader.mjs                 start and open the shelf
//   node reader.mjs book.pdf ...    add PDFs to the shelf, then start
//   node reader.mjs --no-open       start without opening a browser

import http from 'node:http';
import fs from 'node:fs';
import fsp from 'node:fs/promises';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { spawn } from 'node:child_process';

const ROOT = path.dirname(fileURLToPath(import.meta.url));
const LIB = path.join(ROOT, 'library');
const CACHE = path.join(LIB, '.cache');
const EXAMPLES = path.join(ROOT, 'examples');
const STATE = path.join(LIB, 'state.json');
const PORT = Number(process.env.PORT) || 4177;
const HOSTS = new Set([`127.0.0.1:${PORT}`, `localhost:${PORT}`]);

const MIME = {
  '.html': 'text/html; charset=utf-8',
  '.js': 'text/javascript; charset=utf-8',
  '.json': 'application/json',
  '.pdf': 'application/pdf',
};
const EXT = {
  cpp: 'cpp', c: 'c', python: 'py', javascript: 'js', typescript: 'ts', java: 'java',
  rust: 'rs', go: 'go', bash: 'sh', shell: 'sh', json: 'json', xml: 'xml', sql: 'sql',
  swift: 'swift', csharp: 'cs', kotlin: 'kt', ruby: 'rb', php: 'php', css: 'css',
};

fs.mkdirSync(CACHE, { recursive: true });
fs.mkdirSync(EXAMPLES, { recursive: true });

const safeId = (name) => {
  let id = path.basename(String(name || '')).replace(/[^\w .()+,&'\-]/g, '_').replace(/^\.+/, '');
  if (!/\.pdf$/i.test(id)) id += '.pdf';
  return id.length > 5 ? id : null;
};
const slug = (s) => s.replace(/\.pdf$/i, '').replace(/[^\w]+/g, '-').replace(/^-+|-+$/g, '').toLowerCase().slice(0, 60) || 'book';

const readState = async () => {
  try { return JSON.parse(await fsp.readFile(STATE, 'utf8')); } catch { return {}; }
};
let writing = Promise.resolve();
const writeState = (fn) => (writing = writing.then(async () => {
  const s = await readState();
  fn(s);
  await fsp.writeFile(STATE + '.tmp', JSON.stringify(s, null, 1));
  await fsp.rename(STATE + '.tmp', STATE);
}).catch((e) => console.error('state:', e.message)));

const body = (req, limit) => new Promise((resolve, reject) => {
  const chunks = []; let n = 0;
  req.on('data', (c) => { n += c.length; if (n > limit) { reject(new Error('too large')); req.destroy(); } else chunks.push(c); });
  req.on('end', () => resolve(Buffer.concat(chunks)));
  req.on('error', reject);
});
const send = (res, code, data, type = 'application/json') => {
  const buf = Buffer.isBuffer(data) ? data : Buffer.from(typeof data === 'string' ? data : JSON.stringify(data));
  res.writeHead(code, { 'Content-Type': type, 'Content-Length': buf.length, 'Cache-Control': 'no-store' });
  res.end(buf);
};

function openInCode(dir, file) {
  return new Promise((resolve) => {
    const tryOpen = () => {
      const p = spawn('open', ['-a', 'Visual Studio Code', file], { stdio: 'ignore' });
      p.on('error', () => resolve(false));
      p.on('exit', (c) => resolve(c === 0));
    };
    const p = spawn('code', [dir, file], { stdio: 'ignore' });
    p.on('error', tryOpen);
    p.on('exit', (c) => (c === 0 ? resolve(true) : tryOpen()));
  });
}

const server = http.createServer(async (req, res) => {
  try {
    // Local only: refuse anything not addressed to, or coming from, this server.
    if (!HOSTS.has(req.headers.host)) return send(res, 403, { error: 'forbidden' });
    const origin = req.headers.origin;
    if (origin && !HOSTS.has(origin.replace(/^http:\/\//, ''))) return send(res, 403, { error: 'forbidden' });

    const url = new URL(req.url, `http://${req.headers.host}`);
    const p = url.pathname;
    const id = url.searchParams.has('id') ? safeId(url.searchParams.get('id')) : null;

    if (req.method === 'GET' && (p === '/' || p === '/index.html')) {
      return send(res, 200, await fsp.readFile(path.join(ROOT, 'index.html')), MIME['.html']);
    }
    if (req.method === 'GET' && /^\/vendor\/[\w.\-]+\.js$/.test(p)) {
      return send(res, 200, await fsp.readFile(path.join(ROOT, p)), MIME['.js']);
    }

    if (p === '/api/books' && req.method === 'GET') {
      const state = await readState();
      const out = [];
      for (const f of (await fsp.readdir(LIB)).filter((f) => /\.pdf$/i.test(f)).sort()) {
        const st = await fsp.stat(path.join(LIB, f));
        out.push({ id: f, title: f.replace(/\.pdf$/i, ''), size: st.size, pos: state[f] || null });
      }
      return send(res, 200, out);
    }
    if (p === '/api/books' && req.method === 'POST') {
      const name = safeId(url.searchParams.get('name'));
      if (!name) return send(res, 400, { error: 'bad name' });
      const data = await body(req, 600 * 1024 * 1024);
      if (data.subarray(0, 5).toString() !== '%PDF-') return send(res, 400, { error: 'not a PDF' });
      await fsp.writeFile(path.join(LIB, name), data);
      return send(res, 200, { id: name });
    }
    if (p === '/api/pdf' && req.method === 'GET' && id) {
      const file = path.join(LIB, id);
      const st = await fsp.stat(file);
      res.writeHead(200, { 'Content-Type': MIME['.pdf'], 'Content-Length': st.size });
      return fs.createReadStream(file).pipe(res);
    }
    if (p === '/api/cache' && id) {
      const file = path.join(CACHE, id + '.json');
      if (req.method === 'GET') {
        if (!fs.existsSync(file)) return send(res, 404, { error: 'none' });
        return send(res, 200, await fsp.readFile(file));
      }
      if (req.method === 'PUT') {
        await fsp.writeFile(file, await body(req, 300 * 1024 * 1024));
        return send(res, 200, { ok: true });
      }
    }
    if (p === '/api/pos' && req.method === 'POST' && id) {
      const pos = JSON.parse((await body(req, 4096)).toString());
      await writeState((s) => { s[id] = { ...pos, t: Date.now() }; });
      return send(res, 200, { ok: true });
    }
    if (p === '/api/open' && req.method === 'POST') {
      const { book, n, lang, code } = JSON.parse((await body(req, 2 * 1024 * 1024)).toString());
      const dir = path.join(EXAMPLES, slug(safeId(book) || 'book'));
      await fsp.mkdir(dir, { recursive: true });
      const file = path.join(dir, `example-${String(Number(n) || 0).padStart(4, '0')}.${EXT[lang] || 'txt'}`);
      // Never clobber something you've edited: only write when the file is new.
      if (!fs.existsSync(file)) await fsp.writeFile(file, String(code).replace(/\s+$/, '') + '\n');
      const ok = await openInCode(dir, file);
      return send(res, ok ? 200 : 500, { ok, file: path.relative(ROOT, file) });
    }
    send(res, 404, { error: 'not found' });
  } catch (e) {
    send(res, e.code === 'ENOENT' ? 404 : 500, { error: e.message });
  }
});

const args = process.argv.slice(2);
for (const a of args.filter((a) => !a.startsWith('--'))) {
  const name = safeId(a);
  if (name && fs.existsSync(a)) { fs.copyFileSync(a, path.join(LIB, name)); console.log('› added', name); }
  else console.log('› skipped (not found):', a);
}
server.on('error', (e) => {
  if (e.code === 'EADDRINUSE') { console.log(`› already running at http://127.0.0.1:${PORT}`); spawn('open', [`http://127.0.0.1:${PORT}`]); }
  else throw e;
});
server.listen(PORT, '127.0.0.1', () => {
  console.log(`› Reader at http://127.0.0.1:${PORT}`);
  if (!args.includes('--no-open')) spawn('open', [`http://127.0.0.1:${PORT}`], { stdio: 'ignore' });
});
