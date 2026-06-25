#!/usr/bin/env node
// Zero-dependency test harness for SpotifyDrive.
// Runs the app's real inline <script> inside a mocked DOM + Spotify API so we can
// verify behaviour instantly — no browser, no Spotify account, no deploy.
//
//   node SpotifyDrive/tests/run.mjs [path-to-index.html]
//
// Default target: the Pure variant (our chosen base).

import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, resolve } from 'node:path';
import vm from 'node:vm';

const HERE = dirname(fileURLToPath(import.meta.url));
const TARGET = process.argv[2]
  ? resolve(process.argv[2])
  : resolve(HERE, '../variants/pure/index.html');

const html = readFileSync(TARGET, 'utf8');

// ── tiny assert framework ────────────────────────────────────────────
let pass = 0; const fails = [];
function check(name, cond, detail) {
  if (cond) { pass++; }
  else { fails.push(name + (detail ? ` — ${detail}` : '')); }
}

// ── DOM mock ─────────────────────────────────────────────────────────
function makeEl(id) {
  const el = {
    id, tagName: 'DIV', textContent: '', innerHTML: '', value: '', src: '',
    style: {}, dataset: {}, _cls: new Set(), _t: null, children: [],
    appendChild(c) { this.children.push(c); return c; },
    setAttribute() {}, removeAttribute() {}, addEventListener() {},
    removeEventListener() {}, blur() {}, focus() {}, click() {},
    querySelector() { return makeEl('_q'); },
    querySelectorAll() { return []; },
  };
  el.classList = {
    add: c => el._cls.add(c),
    remove: c => el._cls.delete(c),
    contains: c => el._cls.has(c),
    toggle: (c, on) => {
      const want = on === undefined ? !el._cls.has(c) : !!on;
      want ? el._cls.add(c) : el._cls.delete(c);
      return want;
    },
  };
  Object.defineProperty(el, 'className', {
    get() { return [...el._cls].join(' '); },
    set(v) { el._cls = new Set(String(v).split(/\s+/).filter(Boolean)); },
  });
  return el;
}

function makeStorage() {
  const m = new Map();
  return {
    getItem: k => (m.has(k) ? m.get(k) : null),
    setItem: (k, v) => m.set(k, String(v)),
    removeItem: k => m.delete(k),
    clear: () => m.clear(),
  };
}

// ── Build a fresh sandbox and run the app script in it ───────────────
function load() {
  const els = new Map();
  const fetchCalls = [];
  const queue = [];

  const document = {
    getElementById(id) { if (!els.has(id)) els.set(id, makeEl(id)); return els.get(id); },
    querySelector(sel) { if (!els.has(sel)) els.set(sel, makeEl(sel)); return els.get(sel); },
    querySelectorAll() { return []; },
    createElement(tag) { return makeEl('new-' + tag); },
    body: makeEl('body'),
    addEventListener() {},
  };

  async function fetchMock(url, opts = {}) {
    const call = {
      url, method: (opts.method || 'GET').toUpperCase(),
      body: opts.body ? safeJson(opts.body) : null,
      headers: opts.headers || {},
    };
    fetchCalls.push(call);
    const r = queue.shift() || { status: 200, body: {} };
    const status = r.status ?? 200;
    return {
      status, ok: status >= 200 && status < 300,
      json: async () => (r.body ?? {}),
    };
  }

  const localStorage = makeStorage();
  const sessionStorage = makeStorage();

  const sandbox = {
    document, fetch: fetchMock, localStorage, sessionStorage,
    location: { href: '', search: '', pathname: '/SpotifyDrive/index.html',
                origin: 'http://127.0.0.1:8787', replace() {}, assign() {} },
    history: { replaceState() {} },
    navigator: { userAgent: 'node-test' },
    crypto: {
      getRandomValues: a => { for (let i = 0; i < a.length; i++) a[i] = (i * 7) % 256; return a; },
      subtle: { digest: async () => new Uint8Array(32).buffer },
    },
    btoa: s => Buffer.from(s, 'binary').toString('base64'),
    atob: s => Buffer.from(s, 'base64').toString('binary'),
    TextEncoder, URLSearchParams, encodeURIComponent, decodeURIComponent,
    console: { log() {}, warn() {}, error() {}, info() {} },
    alert() {}, confirm: () => false, prompt: () => null,
    setTimeout: () => 0, clearTimeout: () => {},
    setInterval: () => 0, clearInterval: () => {},
    Math, JSON, Date, Object, Array, String, Number, Boolean, Promise, Error, RegExp, Symbol, Map, Set,
  };
  sandbox.window = sandbox;
  sandbox.globalThis = sandbox;
  sandbox.self = sandbox;

  const ctx = vm.createContext(sandbox);
  const scriptSrc = extractScript(html);
  vm.runInContext(scriptSrc, ctx, { filename: 'spotifydrive-app.js' });

  return {
    ctx, fetchCalls, els, ls: localStorage,
    getEl: id => (els.has(id) ? els.get(id) : null),
    queueResp: r => queue.push(r),
    auth() {
      localStorage.setItem('access_token', 'TESTTOKEN');
      localStorage.setItem('token_expiry', String(Date.now() + 3600_000));
    },
  };
}

function safeJson(s) { try { return JSON.parse(s); } catch { return s; } }

function extractScript(src) {
  // greedy: first <script> to last </script> (these files have a single script block)
  const m = src.match(/<script[^>]*>([\s\S]*)<\/script>/i);
  if (!m) throw new Error('no <script> block found');
  return m[1];
}

const flush = () => new Promise(r => setImmediate(r));

// ════════════════════════════════════════════════════════════════════
// STATIC checks (parse the HTML/JS text directly)
// ════════════════════════════════════════════════════════════════════
function staticChecks() {
  // every onclick handler has a defined function
  const handlers = [...html.matchAll(/onclick="(\w+)\(/g)].map(m => m[1]);
  const uniqueHandlers = [...new Set(handlers)];
  for (const h of uniqueHandlers) {
    const defined = new RegExp(`function\\s+${h}\\b`).test(html);
    check(`handler defined: ${h}`, defined);
  }

  // every $('id') / getElementById('id') target exists as an id="..."
  const ids = new Set([...html.matchAll(/id="([\w-]+)"/g)].map(m => m[1]));
  const refs = new Set([
    ...[...html.matchAll(/\$\('([\w-]+)'\)/g)].map(m => m[1]),
    ...[...html.matchAll(/getElementById\('([\w-]+)'\)/g)].map(m => m[1]),
  ]);
  // #toast is created dynamically, allow it
  ids.add('toast');
  for (const r of refs) check(`element id exists: ${r}`, ids.has(r));

  // no emoji anywhere
  check('no emoji', !/[\u{1F000}-\u{1FAFF}\u{2600}-\u{27BF}\u{1F300}-\u{1F6FF}]/u.test(html));

  // search limit must be <= 10 (Spotify cap)
  const lim = html.match(/[?&]limit=(\d+)/);
  check('search limit <= 10', lim && Number(lim[1]) <= 10, lim ? `limit=${lim[1]}` : 'no limit found');

  // required playback scopes present
  for (const sc of ['user-read-playback-state', 'user-modify-playback-state']) {
    check(`scope present: ${sc}`, html.includes(sc));
  }

  // regression: playback errors must NOT be silently swallowed to console only
  check('no silent console.warn in playTrackUri',
    !/playTrackUri[\s\S]*?console\.warn\('playTrack'/.test(html));
  check('toast() exists for user feedback', /function\s+toast\b/.test(html));
  check('ensureActiveDevice() exists', /function\s+ensureActiveDevice\b/.test(html));

  // OAuth/iOS hardening (from research)
  check('pkce_v stored in localStorage (survives iOS PWA OAuth redirect)',
    /localStorage\.setItem\('pkce_v'/.test(html) && !/sessionStorage\.\w+Item\('pkce_v'/.test(html));
  check('viewport-fit=cover present (safe-area insets)', /viewport-fit=cover/.test(html));
  check('handles 403 PREMIUM_REQUIRED', /status === 403/.test(html) && /premium/i.test(html));

  // Auth recovery + remaining playback hardening (from the audit)
  check('refresh checks res.ok (no Bearer-undefined cascade)', /refreshAccessToken[\s\S]{0,600}?!res\.ok/.test(html));
  check('api() retries once on 401 then re-auths', /status === 401/.test(html) && /_retried/.test(html));
  check('pickDevice starts playback (play:true)', /device_ids:\s*\[id\],\s*play:\s*true/.test(html));
  check('no remaining catch(console.warn) silent swallows', !/catch\(console\.warn\)/.test(html));
}

// ════════════════════════════════════════════════════════════════════
// BEHAVIOURAL checks (run the real functions)
// ════════════════════════════════════════════════════════════════════
async function behaviourChecks() {
  // 1. Tap a search result with an active device → plays on that device
  {
    const app = load(); app.auth();
    app.queueResp({ status: 200, body: { devices: [{ id: 'dev1', is_active: true, type: 'Smartphone', name: 'Phone' }] } });
    app.queueResp({ status: 200, body: {} }); // play ok
    await app.ctx.playTrackUri('spotify:track:ABC');
    await flush();
    const play = app.fetchCalls.find(c => c.url.includes('/me/player/play'));
    check('playTrackUri issues a play call', !!play);
    check('play targets resolved device_id', play && play.url.includes('device_id=dev1'), play && play.url);
    check('play sends the track uri', play && play.body && Array.isArray(play.body.uris) && play.body.uris[0] === 'spotify:track:ABC');
    check('play uses PUT', play && play.method === 'PUT', play && play.method);
  }

  // 2. No active device → user gets a visible toast (NOT a silent failure)
  {
    const app = load(); app.auth();
    app.queueResp({ status: 200, body: { devices: [] } });        // ensureActiveDevice: none
    app.queueResp({ status: 404, body: { error: { message: 'No active device found', reason: 'NO_ACTIVE_DEVICE' } } }); // play 404
    app.queueResp({ status: 200, body: { devices: [] } });        // retry ensure: none
    await app.ctx.playTrackUri('spotify:track:XYZ');
    await flush(); await flush();
    const toast = app.getEl('toast');
    check('no-device shows a toast', toast && /no active spotify device/i.test(toast.textContent), toast && toast.textContent);
    check('toast marked as error', toast && toast.className.includes('err'));
  }

  // 3. togglePlay (initial state paused) → starts playback via PUT
  {
    const app = load(); app.auth();
    app.queueResp({ status: 200, body: { devices: [{ id: 'd9', is_active: true, type: 'Computer', name: 'Mac' }] } });
    app.queueResp({ status: 200, body: {} });
    await app.ctx.togglePlay();
    await flush();
    const play = app.fetchCalls.find(c => c.url.includes('/me/player/play'));
    check('togglePlay starts playback', !!play, app.fetchCalls.map(c => c.method + ' ' + c.url).join(' | '));
    check('togglePlay uses PUT', play && play.method === 'PUT');
  }

  // 4. next() uses POST
  {
    const app = load(); app.auth();
    app.queueResp({ status: 200, body: { devices: [{ id: 'd9', is_active: true, type: 'Computer', name: 'Mac' }] } });
    app.queueResp({ status: 200, body: {} });
    await app.ctx.next();
    await flush();
    const nx = app.fetchCalls.find(c => c.url.includes('/me/player/next'));
    check('next() calls /me/player/next', !!nx);
    check('next() uses POST', nx && nx.method === 'POST', nx && nx.method);
  }

  // 5. doSearch builds the right query and renders tappable results
  {
    const app = load(); app.auth();
    app.getEl('search-input') || app.ctx.document; // ensure
    app.ctx.document.getElementById('search-input').value = 'daft punk';
    app.queueResp({ status: 200, body: { tracks: { items: [
      { uri: 'spotify:track:1', name: 'One More Time', artists: [{ name: 'Daft Punk' }], album: { images: [{}, {}, { url: 'u' }] } },
    ] } } });
    await app.ctx.doSearch();
    await flush();
    const search = app.fetchCalls.find(c => c.url.includes('/search'));
    check('doSearch hits /search', !!search);
    check('doSearch uses limit=10', search && /[?&]limit=10\b/.test(search.url), search && search.url);
    check('doSearch url-encodes the query', search && search.url.includes('daft%20punk'), search && search.url);
    const list = app.getEl('results-list');
    check('search renders a tappable result', list && list.innerHTML.includes('playTrackUri('), list && list.innerHTML.slice(0, 60));
  }

  // 6. Free account (403 Premium) → clear, specific message
  {
    const app = load(); app.auth();
    app.queueResp({ status: 200, body: { devices: [{ id: 'd1', is_active: true, type: 'Smartphone', name: 'Phone' }] } });
    app.queueResp({ status: 403, body: { error: { message: 'Player command failed: Premium required', reason: 'PREMIUM_REQUIRED' } } });
    await app.ctx.playTrackUri('spotify:track:P');
    await flush(); await flush();
    const toast = app.getEl('toast');
    check('403 surfaces a Premium message', toast && /premium/i.test(toast.textContent), toast && toast.textContent);
  }

  // 7. Expired/revoked refresh token → poisoned creds cleared, bounced to Connect
  {
    const app = load();
    app.ls.setItem('refresh_token', 'BADRT');
    app.ls.setItem('access_token', 'OLD');
    app.ls.setItem('token_expiry', String(Date.now() - 1000)); // expired → forces a refresh
    app.queueResp({ status: 400, body: { error: 'invalid_grant' } }); // refresh rejected
    try { await app.ctx.fetchState(); } catch {}
    await flush(); await flush();
    check('failed refresh clears the poisoned access_token', app.ls.getItem('access_token') === null);
    check('failed refresh clears the refresh_token', app.ls.getItem('refresh_token') === null);
  }

  // 8. pickDevice transfers with play:true (a paused remote actually starts)
  {
    const app = load(); app.auth();
    app.queueResp({ status: 200, body: {} });
    app.ctx.pickDevice('dev2', 'Speaker', 'Speaker');
    await flush();
    const tr = app.fetchCalls.find(c => c.method === 'PUT' && c.body && c.body.device_ids);
    check('pickDevice issues a transfer', !!tr);
    check('pickDevice transfer sets play:true', tr && tr.body.play === true, tr && JSON.stringify(tr.body));
  }

  // 9. toggleShuffle failure reverts + surfaces (no silent desync)
  {
    const app = load(); app.auth();
    app.queueResp({ status: 200, body: { devices: [{ id: 'd1', is_active: true, type: 'Computer', name: 'Mac' }] } });
    app.queueResp({ status: 404, body: { error: { message: 'No active device found' } } });
    await app.ctx.toggleShuffle();
    await flush(); await flush();
    const toast = app.getEl('toast');
    check('toggleShuffle surfaces failure via toast', toast && toast.className.includes('err') && toast.textContent.length > 0);
  }
}

// ── run ──────────────────────────────────────────────────────────────
(async () => {
  console.log(`\n  SpotifyDrive test suite\n  target: ${TARGET}\n`);
  try {
    staticChecks();
    await behaviourChecks();
  } catch (e) {
    fails.push('HARNESS ERROR: ' + (e && e.stack || e));
  }
  for (const f of fails) console.log('  ✗ ' + f);
  const total = pass + fails.length;
  console.log(`\n  ${pass}/${total} passed` + (fails.length ? `, ${fails.length} FAILED\n` : ' — all green\n'));
  process.exit(fails.length ? 1 : 0);
})();
