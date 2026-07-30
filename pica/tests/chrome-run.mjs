// Runs a JS probe against the app in headless Chromium over CDP.
//
// Why this exists: a windowless WKWebView is treated as a hidden page — requestAnimationFrame
// never fires and every timer is throttled to ~460ms, so canvas rendering and any
// timing-dependent test simply hang there. Headless Chromium is unthrottled, opens no
// window, and uses a throwaway profile, so it disturbs nothing.
//
//   node chrome-run.mjs <probe.js> <fnName> [args-json]
import { spawn } from 'node:child_process';
import http from 'node:http';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const here = path.dirname(fileURLToPath(import.meta.url));
const root = path.join(here, '..');
const [probeFile, fnName, argsJson] = process.argv.slice(2);
if (!probeFile || !fnName) { console.error('usage: chrome-run.mjs <probe.js> <fnName> [args-json]'); process.exit(1); }
const probe = fs.readFileSync(path.isAbsolute(probeFile) ? probeFile : path.join(here, probeFile), 'utf8');
const args = argsJson ? JSON.parse(argsJson) : [];

// -- a tiny static server over pica/ plus anything the probe needs from $HOME/Downloads
const MIME = { '.html': 'text/html; charset=utf-8', '.js': 'text/javascript', '.mjs': 'text/javascript',
  '.pdf': 'application/pdf', '.ttf': 'font/ttf', '.json': 'application/json' };
const server = http.createServer((req, res) => {
  const url = decodeURIComponent(req.url.split('?')[0]);
  const base = url.startsWith('/dl/') ? path.join(process.env.HOME, 'Downloads') : root;
  const rel = url.startsWith('/dl/') ? url.slice(4) : url;
  const f = path.join(base, rel === '/' ? 'index.html' : rel);
  if (!f.startsWith(base)) { res.writeHead(403).end(); return; }
  fs.readFile(f, (e, d) => {
    if (e) { res.writeHead(404).end(); return; }
    res.writeHead(200, { 'Content-Type': MIME[path.extname(f)] || 'application/octet-stream' });
    res.end(d);
  });
});
await new Promise(r => server.listen(0, '127.0.0.1', r));
const PORT = server.address().port;

// -- headless Chromium, throwaway profile, no window
const CHROME = ['/Applications/Google Chrome.app/Contents/MacOS/Google Chrome',
  '/Applications/Chromium.app/Contents/MacOS/Chromium'].find(p => fs.existsSync(p));
if (!CHROME) { console.error('FAIL: no Chrome found'); process.exit(1); }
const profile = fs.mkdtempSync('/tmp/pica-chrome-');
const DP = 9500 + (process.pid % 400);
const chrome = spawn(CHROME, [
  '--headless=new', '--disable-gpu', '--no-first-run', '--no-default-browser-check',
  '--disable-extensions', '--mute-audio', '--window-size=1440,1000', `--user-data-dir=${profile}`,
  `--remote-debugging-port=${DP}`, `http://127.0.0.1:${PORT}/index.html`,
], { stdio: 'ignore' });

const sleep = ms => new Promise(r => setTimeout(r, ms));
async function targets() {
  for (let i = 0; i < 80; i++) {
    try {
      const r = await fetch(`http://127.0.0.1:${DP}/json/list`);
      const list = await r.json();
      const pg = list.find(t => t.type === 'page' && t.webSocketDebuggerUrl);
      if (pg) return pg;
    } catch {}
    await sleep(150);
  }
  throw new Error('Chrome never came up');
}

let code = 1;
try {
  const target = await targets();
  const ws = new WebSocket(target.webSocketDebuggerUrl);
  await new Promise((res, rej) => { ws.onopen = res; ws.onerror = rej; });
  let id = 0;
  const pending = new Map();
  ws.onmessage = ev => {
    const m = JSON.parse(ev.data);
    if (m.id && pending.has(m.id)) { pending.get(m.id)(m); pending.delete(m.id); }
  };
  const send = (method, params = {}) => new Promise(res => {
    const n = ++id; pending.set(n, res);
    ws.send(JSON.stringify({ id: n, method, params }));
  });
  await send('Runtime.enable');
  await send('Page.enable');
  // the app boots on load; give it a moment
  await sleep(1200);
  await send('Runtime.evaluate', { expression: probe, awaitPromise: false });
  const call = `window.${fnName}(${args.map(a => JSON.stringify(a)).join(',')})`;
  const out = await send('Runtime.evaluate', {
    expression: call, awaitPromise: true, returnByValue: true, timeout: 900000,
  });
  if (out.result?.exceptionDetails) {
    console.error('probe threw:', JSON.stringify(out.result.exceptionDetails.exception?.description
      || out.result.exceptionDetails.text));
  } else {
    const val = out.result?.result?.value ?? JSON.stringify(out.result);
    console.log(val);
    // if the probe handed back a clip rect and SHOT is set, photograph it
    try {
      const parsed = JSON.parse(val);
      if (parsed && parsed.clip && process.env.SHOT) {
        await send('Emulation.setDeviceMetricsOverride', { width: 1400,
          height: Math.ceil(parsed.clip.height + parsed.clip.y + 40), deviceScaleFactor: 2, mobile: false });
        const shot = await send('Page.captureScreenshot', { format: 'png', clip: { ...parsed.clip, scale: 2 },
          captureBeyondViewport: true });
        fs.writeFileSync(process.env.SHOT, Buffer.from(shot.result.data, 'base64'));
        console.log('wrote ' + process.env.SHOT);
      }
    } catch {}
    code = 0;
  }
  ws.close();
} catch (e) {
  console.error('FAIL:', e.message);
} finally {
  chrome.kill('SIGKILL');
  server.close();
  try { fs.rmSync(profile, { recursive: true, force: true, maxRetries: 3 }); } catch {}
  process.exit(code);
}
