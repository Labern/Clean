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
    const hasBody = r.body !== undefined && r.body !== null;
    return {
      status, ok: status >= 200 && status < 300,
      // realistic: real json() throws on an empty body; text() returns ''
      async json() { if (!hasBody) throw new SyntaxError('Unexpected end of JSON input'); return r.body; },
      async text() { return hasBody ? JSON.stringify(r.body) : ''; },
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
    alert() {}, confirm: () => false, prompt: () => null, open() {},
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
  // one intentional emoji is allowed: the credit squirrel
  const htmlSansCredit = html.replace(/Made by Labern[^<]*/, '');
  check('no emoji (besides the credit squirrel)', !/[\u{1F000}-\u{1FAFF}\u{2600}-\u{27BF}\u{1F300}-\u{1F6FF}]/u.test(htmlSansCredit));

  // EVERY Spotify limit must be <= 10 — this app/account 400s "invalid limit" on higher
  const allLimits = [...html.matchAll(/[?&]limit=(\d+)/g)].map(m => Number(m[1]));
  check('every Spotify limit <= 10 (app rejects higher)',
    allLimits.length > 0 && allLimits.every(n => n <= 10), 'limits: ' + allLimits.join(','));
  // api() must guard JSON.parse so a bad 200 body can't surface as a raw parse error
  check('api() guards JSON.parse (no raw "Unexpected identifier")', /try \{ return JSON\.parse\(text\)/.test(html));
  // album title wraps (always visible), like the song title + artist
  check('album title wraps (no nowrap/ellipsis truncation)',
    !/#album-name\s*\{[^}]*white-space:\s*nowrap/.test(html) && /#album-name\s*\{[^}]*overflow-wrap:\s*anywhere/.test(html));

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

  // Inline-search + driving-UI features
  check('search is as-you-type (oninput)', /oninput="onSearchInput/.test(html));
  check('inline results, no full-screen overlay element', !/id="results-overlay"/.test(html));
  check('big search font (>=1.3rem)', /#search-input\b[\s\S]{0,240}font-size:\s*1\.(3|4|5)/.test(html));
  check('add-to-queue wired to /me/player/queue', /queueTrack\(/.test(html) && /\/me\/player\/queue/.test(html));
  check('title→album and artist→artist openers exist', /function openAlbum/.test(html) && /function openArtist/.test(html));
  check('Stats and Facts section + drive-time stat', /id="stat-drive"/.test(html) && /Stats and Facts/.test(html));
  check('plays-this-week stat (local play log)', /id="stat-plays"/.test(html) && /function playsThisWeek/.test(html));
  check('dashboard scopes requested (recently-played + playlists)',
    /user-read-recently-played/.test(html) && /playlist-read-private/.test(html));
  check('one-time scope upgrade for existing users',
    /SCOPE_VER/.test(html) && /function missingScopes/.test(html) && /scope_try/.test(html));
  check('demo mode present + gated OFF the production host',
    /const DEMO =/.test(html) && /function demoApi/.test(html) && !/DEMO =[^;]*labern\.github\.io/.test(html));
  check('voice dictation mic button + handler', /id="mic-btn"/.test(html) && /function startDictation/.test(html));
  check('dictation uses Web Speech (webkitSpeechRecognition)', /webkitSpeechRecognition/.test(html));
  check('footer credit present', /Made by Labern/.test(html));
  check('BMW Mode toggle present', /id="bmw-toggle"/.test(html) && /BMW Mode/.test(html));
  check('BMW palette + roundel defined', /#app\.bmw/.test(html) && /#0166B1/i.test(html) && /BMW_ROUNDEL/.test(html));
  check('in-app album view (fetches /albums/ + renders tracks)', /\/albums\//.test(html) && /function renderAlbum/.test(html));
  check('in-app artist view (artist albums)', /function renderArtistAlbums/.test(html) && /\/artists\//.test(html));
  check('album & artist views stay in-app (no open.spotify.com)', !/open\.spotify\.com/.test(html));
  check('top header hidden (no device pill / off button)', /#header\s*\{\s*display:\s*none/.test(html));
  check('queue view present (see what is queued)', /function showQueue/.test(html) && /\/me\/player\/queue/.test(html));
  check('search collapse never hides the album art', !/#main\.searching #album-art\s*\{[^}]*display\s*:\s*none/.test(html));
  check('brand wordmark in top bar (Spotify Drive / Labern)', /id="brand"/.test(html) && /Spotify <span class="brand-accent">Drive/.test(html) && /by Labern/.test(html));
  check('thin divider under the top bar', /#mode-bar\s*\{[\s\S]{0,220}border-bottom/.test(html));
  check('dashboard under search (recently played + playlists)', /function loadDashboard/.test(html) && /recently-played/.test(html) && /\/me\/playlists/.test(html));
  check('horizontal divider under search', /class="section-divider"/.test(html));

  // Progress time + now-playing deep-links + queue animation
  check('progress bar is chunky + rounded', /height:\s*9px/.test(html) && /#progress-fill[\s\S]{0,120}border-radius:\s*999px/.test(html));
  check('time readout under the bar', /id="time-elapsed"/.test(html) && /id="time-remaining"/.test(html));
  check('now-playing title→album & artist→artist', /id="track-name" onclick="openCurrentAlbum/.test(html) && /id="artist-name" onclick="openCurrentArtist/.test(html));
  check('album title element present', /id="album-name"/.test(html));
  check('queued animation (green QUEUED + tick)', /\.result-queue\.queued/.test(html) && /@keyframes queuePop/.test(html));
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

  // 5. runSearch builds the right query and renders tappable inline results
  {
    const app = load(); app.auth();
    app.queueResp({ status: 200, body: { tracks: { items: [
      { uri: 'spotify:track:1', name: 'One More Time', id: 't1',
        artists: [{ name: 'Daft Punk', id: 'ar1' }], album: { id: 'al1', images: [{}, {}, { url: 'u' }] } },
    ] } } });
    await app.ctx.runSearch('daft punk');
    await flush();
    const search = app.fetchCalls.find(c => c.url.includes('/search'));
    check('runSearch hits /search', !!search);
    check('runSearch uses limit=10', search && /[?&]limit=10\b/.test(search.url), search && search.url);
    check('runSearch url-encodes the query', search && search.url.includes('daft%20punk'), search && search.url);
    const list = app.getEl('results-list');
    check('inline result is tappable to play', list && list.innerHTML.includes("playSearchResult('spotify:track:1'"));
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

  // 10. Empty 200 body on play/pause must NOT raise a JSON error
  {
    const app = load(); app.auth();
    app.queueResp({ status: 200, body: { devices: [{ id: 'd1', is_active: true, type: 'Computer', name: 'Mac' }] } });
    app.queueResp({ status: 200 }); // play returns 200 with an EMPTY body
    await app.ctx.togglePlay();
    await flush();
    const toast = app.getEl('toast');
    check('empty-body play response is not a JSON error', !(toast && toast.className.includes('err')), toast && toast.textContent);
  }

  // 11. Inline result row exposes play / album / artist / queue targets
  {
    const app = load(); app.auth();
    app.queueResp({ status: 200, body: { tracks: { items: [
      { uri: 'spotify:track:Z', name: 'Song', id: 't1', artists: [{ name: 'Art', id: 'ar1' }], album: { id: 'al1', images: [{}, {}, { url: 'u' }] } },
    ] } } });
    await app.ctx.runSearch('song');
    await flush();
    const h = app.getEl('results-list').innerHTML;
    check('row plays the track', h.includes("playSearchResult('spotify:track:Z'"));
    check('title opens the album', h.includes("openAlbum('al1')"));
    check('artist opens the artist', h.includes("openArtist('ar1')"));
    check('row has + Queue button', h.includes("queueTrack(this, 'spotify:track:Z')"));
  }

  // 12. queueTrack POSTs to /me/player/queue with the uri (empty body must be fine)
  {
    const app = load(); app.auth();
    app.queueResp({ status: 200, body: { devices: [{ id: 'd1', is_active: true, type: 'Computer', name: 'Mac' }] } });
    app.queueResp({ status: 200 }); // queue add → empty body
    const btn = app.ctx.document.createElement('button');
    await app.ctx.queueTrack(btn, 'spotify:track:9');
    await flush();
    const q = app.fetchCalls.find(c => c.url.includes('/me/player/queue'));
    check('queueTrack hits /me/player/queue', !!q);
    check('queueTrack uses POST', q && q.method === 'POST', q && q.method);
    check('queueTrack passes the uri', q && q.url.includes(encodeURIComponent('spotify:track:9')), q && q.url);
    check('success animates button to QUEUED + tick', btn.className.includes('queued') && /queued/i.test(btn.innerHTML) && btn.innerHTML.includes('<svg'), btn.className + ' / ' + btn.innerHTML.slice(0, 40));
  }

  // 12b. Queue failure reverts the optimistic button and surfaces the error
  {
    const app = load(); app.auth();
    app.queueResp({ status: 200, body: { devices: [{ id: 'd1', is_active: true, type: 'Computer', name: 'Mac' }] } });
    app.queueResp({ status: 404, body: { error: { message: 'No active device found' } } });
    const btn = app.ctx.document.createElement('button');
    btn.innerHTML = '+ Queue';
    await app.ctx.queueTrack(btn, 'spotify:track:7');
    await flush(); await flush();
    check('queue failure reverts the button to + Queue', !btn.className.includes('queued') && btn.innerHTML === '+ Queue', btn.className + ' / ' + btn.innerHTML);
  }

  // 12c. Queue retries once on a stale-device 404, then succeeds (stays Queued — the reported bug)
  {
    const app = load(); app.auth();
    app.queueResp({ status: 200, body: { devices: [{ id: 'd1', is_active: true, type: 'Computer', name: 'Mac' }] } }); // ensureActiveDevice
    app.queueResp({ status: 404, body: { error: { message: 'Device not found' } } });                                  // first queue → 404
    app.queueResp({ status: 200, body: { devices: [{ id: 'd2', is_active: true, type: 'Computer', name: 'Mac' }] } }); // re-ensure
    app.queueResp({ status: 200 });                                                                                     // retry queue ok
    const btn = app.ctx.document.createElement('button'); btn.innerHTML = '+ Queue';
    await app.ctx.queueTrack(btn, 'spotify:track:R');
    await flush(); await flush();
    check('queue retries on stale-device 404 then stays Queued', btn.className.includes('queued') && /queued/i.test(btn.innerHTML), btn.className + ' / ' + btn.innerHTML);
  }

  // 13. Clearing the query returns to the dashboard (not an empty list)
  {
    const app = load(); app.auth();
    app.queueResp({ status: 200, body: { items: [{ track: { uri: 'spotify:track:r1', name: 'R1', artists: [{ name: 'A' }], album: { uri: 'spotify:album:a1', images: [{}, {}, { url: 'u' }] } } }] } });
    app.queueResp({ status: 200, body: { items: [] } });
    await app.ctx.loadDashboard();
    await flush();
    app.ctx.renderResults([{ uri: 'spotify:track:1', name: 'X', artists: [{ name: 'Y', id: 'a' }], album: { id: 'b', images: [{}, {}, { url: 'u' }] } }]);
    app.ctx.clearSearch();
    check('clearSearch returns to the dashboard (recently played)', /Recently played/.test(app.getEl('results-list').innerHTML));
  }

  // 14. Progress bar + ring update from fetchState and advance on tick
  {
    const app = load(); app.auth();
    app.queueResp({ status: 200, body: {
      is_playing: true, progress_ms: 30000, shuffle_state: false,
      device: { id: 'd1', name: 'Mac', type: 'Computer' },
      item: { id: 't1', name: 'Song', duration_ms: 60000, artists: [{ name: 'A' }], album: { images: [{ url: 'art' }] } },
    } });
    await app.ctx.fetchState();
    await flush();
    const fill = app.getEl('progress-fill');
    check('horizontal progress set to 50% after fetchState', fill && fill.style.width === '50%', fill && fill.style.width);
    const ring = app.getEl('#gauge-ring .fill');
    check('ring offset set (between empty and full)', ring && parseFloat(ring.style.strokeDashoffset) > 0 && parseFloat(ring.style.strokeDashoffset) < 289, ring && ring.style.strokeDashoffset);
    const before = parseFloat(app.getEl('progress-fill').style.width);
    app.ctx.tickProgress();
    const after = parseFloat(app.getEl('progress-fill').style.width);
    check('progress advances on tick', after > before, `${before} -> ${after}`);
  }

  // 15. Time readout + now-playing title/artist deep-links
  {
    const app = load(); app.auth();
    app.queueResp({ status: 200, body: {
      is_playing: true, progress_ms: 30000, shuffle_state: false,
      device: { id: 'd1', name: 'Mac', type: 'Computer' },
      item: { id: 't1', name: 'Song', duration_ms: 95000, artists: [{ name: 'A', id: 'ar1' }], album: { id: 'al1', name: 'Album X', images: [{ url: 'art' }] } },
    } });
    await app.ctx.fetchState();
    await flush();
    check('elapsed time shows 0:30', app.getEl('time-elapsed').textContent === '0:30', app.getEl('time-elapsed').textContent);
    check('remaining time shows -1:05', app.getEl('time-remaining').textContent === '-1:05', app.getEl('time-remaining').textContent);
    check('album title shows under song title', app.getEl('album-name').textContent === 'Album X', app.getEl('album-name').textContent);
    app.queueResp({ status: 200, body: { name: 'Al', images: [{ url: 'a' }], tracks: { items: [] } } });
    await app.ctx.openCurrentAlbum();
    await flush();
    check('now-playing title opens the album inline (fetches /albums/al1)', !!app.fetchCalls.find(c => c.url.includes('/albums/al1')));
    app.queueResp({ status: 200, body: { items: [{ id: 'alX', name: 'A', images: [{ url: 'a' }], artists: [{ id: 'ar1', name: 'Daft Punk' }] }] } });
    await app.ctx.openCurrentArtist();
    await flush();
    check('now-playing artist opens artist inline (fetches /artists/ar1/albums)', !!app.fetchCalls.find(c => c.url.includes('/artists/ar1/albums')));
  }

  // 16. Searching collapses now-playing (frees room → no awkward scroll while driving)
  {
    const app = load(); app.auth();
    app.queueResp({ status: 200, body: { tracks: { items: [
      { uri: 'spotify:track:1', name: 'S', id: 't', artists: [{ name: 'A', id: 'a' }], album: { id: 'b', name: 'Al', images: [{}, {}, { url: 'u' }] } },
    ] } } });
    await app.ctx.runSearch('x');
    await flush();
    check('search mode collapses now-playing (searching class on #main)', app.getEl('main').classList.contains('searching'));
    app.ctx.clearSearch();
    check('clearing search exits search mode', !app.getEl('main').classList.contains('searching'));
  }

  // 17. BMW Mode: blue theme + roundel play button, persisted across loads
  {
    const app = load(); app.auth();
    app.ctx.toggleBmw();
    check('BMW toggle adds bmw class to #app', app.getEl('app').classList.contains('bmw'));
    check('BMW mode persisted to localStorage', app.ls.getItem('bmw_mode') === '1');
    app.ctx.renderPlayBtn();
    const btn = app.getEl('play-btn');
    check('play button becomes BMW roundel', /bmw-roundel/.test(btn.innerHTML) && /0166B1/i.test(btn.innerHTML), btn.innerHTML.slice(0, 50));
    app.ctx.toggleBmw();
    check('BMW toggle off restores default', !app.getEl('app').classList.contains('bmw') && app.ls.getItem('bmw_mode') === '0');
  }

  // 18. Tapping an album loads its tracks inline (selectable), not the Spotify app
  {
    const app = load(); app.auth();
    app.queueResp({ status: 200, body: {
      name: 'Discovery', images: [{ url: 'a' }, { url: 'b' }],
      tracks: { items: [
        { uri: 'spotify:track:a', name: 'Aerodynamic', artists: [{ name: 'Daft Punk' }] },
        { uri: 'spotify:track:b', name: 'One More Time', artists: [{ name: 'Daft Punk' }] },
      ] },
    } });
    await app.ctx.openAlbum('al1');
    await flush();
    const h = app.getEl('results-list').innerHTML;
    check('album tap fetches /albums/{id}', !!app.fetchCalls.find(c => c.url.includes('/albums/al1')));
    check('album view shows the album name', h.includes('Discovery'));
    check('album tracks are play-tappable', h.includes("playTrackUri('spotify:track:a'") && h.includes("playTrackUri('spotify:track:b'"));
    check('album tracks have queue buttons', h.includes("queueTrack(this, 'spotify:track:a')"));
    check('album view has a back button', /results-back/.test(h));
  }

  // 19. Tapping an artist loads their albums inline (in-app, never the Spotify app)
  {
    const app = load(); app.auth();
    app.queueResp({ status: 200, body: { items: [
      { id: 'al1', name: 'Discovery', album_type: 'album', total_tracks: 14, images: [{ url: 'a' }], artists: [{ id: 'ar1', name: 'Daft Punk' }] },
      { id: 'al2', name: 'Homework', album_type: 'album', total_tracks: 16, images: [{ url: 'b' }], artists: [{ id: 'ar1', name: 'Daft Punk' }] },
    ] } });
    await app.ctx.openArtist('ar1');
    await flush();
    const h = app.getEl('results-list').innerHTML;
    check('artist tap fetches /artists/{id}/albums', !!app.fetchCalls.find(c => c.url.includes('/artists/ar1/albums')));
    check('artist view shows the artist name', h.includes('Daft Punk'));
    check('artist albums drill into the album', h.includes("openAlbum('al1')") && h.includes("openAlbum('al2')"));
    check('artist view never opens the Spotify app', !/open\.spotify\.com/.test(h));
  }

  // 20. Queue view: see what's queued up, including now-playing header
  {
    const app = load(); app.auth();
    app.queueResp({ status: 200, body: {
      currently_playing: { name: 'NowPlaying', uri: 'spotify:track:now', artists: [{ name: 'A' }], album: { images: [{}, {}, { url: 'u' }] } },
      queue: [
        { uri: 'spotify:track:q1', name: 'Q1', artists: [{ name: 'A' }], album: { images: [{}, {}, { url: 'u' }] } },
        { uri: 'spotify:track:q2', name: 'Q2', artists: [{ name: 'B' }], album: { images: [{}, {}, { url: 'u' }] } },
      ]
    } });
    await app.ctx.showQueue();
    await flush();
    const h = app.getEl('results-list').innerHTML;
    check('queue view fetches /me/player/queue', !!app.fetchCalls.find(c => c.url.endsWith('/me/player/queue')));
    check('queue view shows currently-playing header', h.includes('NowPlaying') && /Now playing/i.test(h));
    check('queue view lists upcoming tracks', h.includes('Q1') && h.includes('Q2'));
    check('queue items are tappable to jump', h.includes("playTrackUri('spotify:track:q1'"));
  }

  // 20b. Queue view empty state is descriptive (not just "Nothing queued")
  {
    const app = load(); app.auth();
    app.queueResp({ status: 200, body: { currently_playing: null, queue: [] } });
    await app.ctx.showQueue();
    await flush();
    check('empty queue state tells user how to add tracks', /tap \+ Queue/i.test(app.getEl('results-list').innerHTML));
  }

  // 20c. Queue API error surfaces as toast + inline message
  {
    const app = load(); app.auth();
    app.queueResp({ status: 503, body: { error: { message: 'Service unavailable' } } });
    await app.ctx.showQueue();
    await flush();
    const toast = app.getEl('toast');
    check('queue error toasts the user', toast && /queue/i.test(toast.textContent), toast && toast.textContent);
  }

  // 21. Playing a track uses its album context (so it doesn't loop / re-play one song)
  {
    const app = load(); app.auth();
    app.queueResp({ status: 200, body: { devices: [{ id: 'd1', is_active: true, type: 'Computer', name: 'Mac' }] } });
    app.queueResp({ status: 200 });
    await app.ctx.playTrackUri('spotify:track:T', 'spotify:album:AL');
    await flush();
    const play = app.fetchCalls.find(c => c.url.includes('/me/player/play'));
    check('play uses album context_uri + offset (not a context-less single track)',
      play && play.body && play.body.context_uri === 'spotify:album:AL' && play.body.offset && play.body.offset.uri === 'spotify:track:T',
      play && JSON.stringify(play.body));
  }

  // 22. New song snaps the progress bar to 0 (no backward "rewind" animation)
  {
    const app = load(); app.auth();
    app.queueResp({ status: 200, body: { is_playing: true, progress_ms: 30000, shuffle_state: false,
      device: { id: 'd1', name: 'M', type: 'Computer' },
      item: { id: 't1', name: 'A', duration_ms: 60000, artists: [{ name: 'A' }], album: { images: [{ url: 'x' }] } } } });
    await app.ctx.fetchState(); await flush();
    app.queueResp({ status: 200, body: { is_playing: true, progress_ms: 0, shuffle_state: false,
      device: { id: 'd1', name: 'M', type: 'Computer' },
      item: { id: 't2', name: 'B', duration_ms: 60000, artists: [{ name: 'B' }], album: { images: [{ url: 'x' }] } } } });
    await app.ctx.fetchState(); await flush();
    const fill = app.getEl('progress-fill');
    check('new song snaps progress to 0%', parseFloat(fill.style.width) === 0, fill.style.width);
    check('transitions restored after snap (ticks still animate)', fill.style.transition === 'width 1s linear', fill.style.transition);
  }

  // 23. Dashboard under search: recently played + your playlists (default browse view)
  {
    const app = load(); app.auth();
    app.queueResp({ status: 200, body: { items: [
      { track: { uri: 'spotify:track:r1', name: 'R1', artists: [{ name: 'A' }], album: { uri: 'spotify:album:a1', images: [{}, {}, { url: 'u' }] } } },
    ] } });
    app.queueResp({ status: 200, body: { items: [
      { id: 'p1', uri: 'spotify:playlist:p1', name: 'Chill', images: [{ url: 'u' }], tracks: { total: 42 } },
    ] } });
    await app.ctx.loadDashboard();
    await flush();
    const h = app.getEl('results-list').innerHTML;
    check('dashboard fetches recently-played', !!app.fetchCalls.find(c => c.url.includes('/me/player/recently-played')));
    check('dashboard fetches playlists', !!app.fetchCalls.find(c => c.url.includes('/me/playlists')));
    check('dashboard shows Recently played track', /Recently played/.test(h) && h.includes("playTrackUri('spotify:track:r1'"));
    check('dashboard shows a playlist tile (opens inline)', /Your playlists/.test(h) && h.includes("openPlaylist('p1'"));
  }

  // 24. playContext plays a whole playlist/album from the start
  {
    const app = load(); app.auth();
    app.queueResp({ status: 200, body: { devices: [{ id: 'd1', is_active: true, type: 'Computer', name: 'Mac' }] } });
    app.queueResp({ status: 200 });
    await app.ctx.playContext('spotify:playlist:p1');
    await flush();
    const play = app.fetchCalls.find(c => c.url.includes('/me/player/play'));
    check('playContext sends context_uri', play && play.body && play.body.context_uri === 'spotify:playlist:p1', play && JSON.stringify(play.body));
  }

  // 25. Drive-time stat: formats h/m/s and gets written into the tile
  {
    const app = load(); app.auth();
    check('drive-time formats h/m/s', app.ctx.fmtDuration(3661) === '1h 1m' && app.ctx.fmtDuration(61) === '1m 1s' && app.ctx.fmtDuration(5) === '5s',
      `${app.ctx.fmtDuration(3661)} / ${app.ctx.fmtDuration(61)} / ${app.ctx.fmtDuration(5)}`);
    app.ctx.tickUptime();
    check('tickUptime writes the drive-time tile', /\d/.test(app.getEl('stat-drive').textContent), app.getEl('stat-drive').textContent);
  }

  // 26. Play log → "played X times this week" (dedupe + recently-played seed + 7-day window)
  {
    const app = load(); app.auth();
    app.ctx.recordPlay('songA');
    app.ctx.recordPlay('songA');   // rapid repeat of the same track → ignored (poll jitter)
    check('rapid same-track replays dedupe to one play', app.ctx.playsThisWeek('songA') === 1, String(app.ctx.playsThisWeek('songA')));
    const now = Date.now();
    app.ctx.mergeRecentIntoLog([
      { track: { id: 'songA' }, played_at: new Date(now - 2 * 3600 * 1000).toISOString() },
      { track: { id: 'songA' }, played_at: new Date(now - 5 * 3600 * 1000).toISOString() },
      { track: { id: 'songB' }, played_at: new Date(now - 1 * 3600 * 1000).toISOString() },
      { track: { id: 'songA' }, played_at: new Date(now - 9 * 24 * 3600 * 1000).toISOString() }, // 9 days → outside week
    ]);
    check('recently-played history counts toward this week', app.ctx.playsThisWeek('songA') === 3, String(app.ctx.playsThisWeek('songA')));
    check('plays older than 7 days are excluded', app.ctx.playsThisWeek('songB') === 1, String(app.ctx.playsThisWeek('songB')));
  }

  // 27. fetchState logs the current play and updates the plays-this-week tile
  {
    const app = load(); app.auth();
    app.queueResp({ status: 200, body: { is_playing: true, progress_ms: 1000, shuffle_state: false,
      device: { id: 'd1', name: 'M', type: 'Computer' },
      item: { id: 'songX', name: 'X', duration_ms: 200000, artists: [{ name: 'A' }], album: { images: [{ url: 'art' }] } } } });
    await app.ctx.fetchState(); await flush();
    check('fetchState updates the plays-this-week stat to 1', app.getEl('stat-plays').textContent === '1', app.getEl('stat-plays').textContent);
  }

  // 28. Scope upgrade: an old token missing new scopes is detected; a full grant clears it
  {
    const app = load();
    app.ls.setItem('granted_scope', 'user-read-playback-state user-modify-playback-state');
    const miss = app.ctx.missingScopes();
    check('missingScopes flags newly-added dashboard scopes',
      miss.includes('user-read-recently-played') && miss.includes('playlist-read-private'), JSON.stringify(miss));
    app.ls.setItem('granted_scope',
      'user-read-playback-state user-modify-playback-state user-read-currently-playing user-read-recently-played playlist-read-private playlist-read-collaborative user-library-read user-library-modify');
    check('missingScopes clears once all scopes are granted', app.ctx.missingScopes().length === 0, JSON.stringify(app.ctx.missingScopes()));
  }

  // 29. storeTokens persists the granted scope (so the upgrade check works)
  {
    const app = load();
    app.ctx.storeTokens({ access_token: 'A', expires_in: 3600, scope: 'user-read-playback-state user-read-recently-played' });
    check('storeTokens persists granted_scope', app.ls.getItem('granted_scope') === 'user-read-playback-state user-read-recently-played', app.ls.getItem('granted_scope'));
  }

  // 30. Playlist row opens tracks inline (not play immediately); Play all button exists
  {
    const app = load(); app.auth();
    app.queueResp({ status: 200, body: { items: [
      { track: { uri: 'spotify:track:pt1', name: 'Track One', artists: [{ name: 'Band' }], album: { images: [{}, {}, { url: 'u' }] } } },
      { track: { uri: 'spotify:track:pt2', name: 'Track Two', artists: [{ name: 'Band' }], album: { images: [{}, {}, { url: 'u' }] } } },
    ] } });
    await app.ctx.openPlaylist('pl1', 'spotify:playlist:pl1');
    await flush();
    const h = app.getEl('results-list').innerHTML;
    check('openPlaylist fetches /playlists/{id}/tracks', !!app.fetchCalls.find(c => c.url.includes('/playlists/pl1/tracks')));
    check('playlist view shows tracks', h.includes('Track One') && h.includes('Track Two'));
    check('tracks are playable inline', h.includes("playTrackUri('spotify:track:pt1', 'spotify:playlist:pl1')"));
    check('playlist tracks have queue buttons', h.includes("queueTrack(this, 'spotify:track:pt1')"));
    check('playlist view has a Play all button', h.includes("playContext('spotify:playlist:pl1')"));
    check('playlist view has a back button', /results-back/.test(h));
  }

  // 31. Dictation: no Web Speech (installed-PWA case) → graceful keyboard fallback, no throw
  {
    const app = load(); app.auth();
    let threw = false;
    try { app.ctx.startDictation(); } catch(e) { threw = true; }
    await flush();
    check('startDictation never throws when Web Speech is absent', !threw);
    check('fallback enters search mode', app.getEl('main').classList.contains('searching'));
    const toast = app.getEl('toast');
    check('fallback tells user to use the keyboard mic', toast && /keyboard/i.test(toast.textContent), toast && toast.textContent);
  }

  // 32. Dictation with Web Speech present: wipes prior text, fills from speech, runs search
  {
    const app = load(); app.auth();
    app.ctx.document.getElementById('search-input').value = 'wrong previous text';
    let started = false, instance = null;
    // minimal SpeechRecognition mock
    app.ctx.window.webkitSpeechRecognition = function () {
      instance = this;
      this.start = () => { started = true; };
      this.stop = () => { if (this.onend) this.onend(); };
    };
    app.ctx.startDictation();
    check('mic wipes the previous (wrong) dictation on a fresh tap', app.getEl('search-input').value === '');
    check('recognition started', started);
    // simulate a spoken result
    app.queueResp({ status: 200, body: { tracks: { items: [
      { uri: 'spotify:track:V', name: 'Voiced', id: 'tv', artists: [{ name: 'A', id: 'a' }], album: { id: 'b', images: [{}, {}, { url: 'u' }] } },
    ] } } });
    instance.onresult({ results: [[{ transcript: 'redbone' }]] });
    await flush();
    check('spoken words fill the search box', app.getEl('search-input').value === 'redbone');
    instance.onend();
    await flush();
    check('mic listening state cleared on end', !app.getEl('mic-btn').classList.contains('listening'));
  }

  // 33. Playing a search result exits search mode (full-size player snaps back)
  {
    const app = load(); app.auth();
    app.getEl('main').classList.add('searching');                // pretend mid-search
    app.queueResp({ status: 200, body: { devices: [{ id: 'd1', is_active: true, type: 'Computer', name: 'Mac' }] } });
    app.queueResp({ status: 200 });                              // play ok
    app.queueResp({ status: 200, body: { items: [] } });        // dashboard recently-played
    app.queueResp({ status: 200, body: { items: [] } });        // dashboard playlists
    await app.ctx.playSearchResult('spotify:track:S', 'spotify:album:A');
    await flush(); await flush();
    check('search result still plays', !!app.fetchCalls.find(c => c.url.includes('/me/player/play')));
    check('picking a result exits search mode', !app.getEl('main').classList.contains('searching'));
  }

  // 34. A malformed 200 body does NOT crash api() (no raw JSON parse error toast)
  {
    const app = load(); app.auth();
    app.queueResp({ status: 200, body: { devices: [{ id: 'd1', is_active: true, type: 'Computer', name: 'Mac' }] } });
    // monkeypatch text() to return non-JSON for the play response
    const origFetch = app.ctx.fetch;
    app.ctx.fetch = async (url, opts) => {
      if (url.includes('/me/player/play')) return { status: 200, ok: true, async json(){ throw new Error('x'); }, async text(){ return 'Premium required'; } };
      return origFetch(url, opts);
    };
    let threw = false;
    try { await app.ctx.togglePlay(); } catch(e) { threw = true; }
    await flush();
    check('togglePlay survives a non-JSON 200 body (no crash/parse error)', !threw);
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
