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
  // Scope coverage: every privileged endpoint the app calls must have its OAuth scope in
  // SCOPES. This is the assertion that would have caught the Like 403 without a live account
  // — a mocked fetch always "succeeds", so only a static endpoint→scope map can catch a
  // forgotten/insufficient scope. If we call the endpoint, we MUST request its scope.
  const scopeNeeds = [
    [/\/me\/tracks\?ids=/,                                       'user-library-modify',       'like / unlike'],
    [/\/me\/tracks\/contains/,                                   'user-library-read',         'checkLiked'],
    [/\/me\/player\/recently-played/,                            'user-read-recently-played', 'recently played'],
    [/api\([`'"]\/me\/playlists/,                                'playlist-read-private',     'your playlists'],
    [/\/me\/player\/(play|pause|next|previous|shuffle|seek|queue|repeat)/, 'user-modify-playback-state', 'playback control'],
    [/\/me\/player['"`?]/,                                       'user-read-playback-state',  'read playback state'],
    [/\/me\/top\/(artists|tracks)/,                              'user-top-read',             'discover: your top artists/tracks'],
    [/\/me\/albums\?ids=/,                                       'user-library-modify',       'save / remove album'],
    [/\/me\/albums\/contains/,                                   'user-library-read',         'album saved-state'],
  ];
  for (const [pat, sc, label] of scopeNeeds) {
    if (pat.test(html)) check(`scope coverage: "${label}" requires ${sc}`, html.includes(sc));
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
  check('search font set (0.9–1.3rem)', /#search-input\b[\s\S]{0,240}font-size:\s*(0\.9|1\.[0-3])/.test(html));
  check('search input height matches the 60px round buttons', /#search-input\s*\{[^}]*height:\s*60px/.test(html));
  check('visible tap feedback (glow + scale pulse on buttons)', /@keyframes tapFlash/.test(html) && /function flashTap/.test(html));
  check('beat trinket: ♪ pulses at the BPM (real tempo via Deezer)',
    /id="beat"/.test(html) && /@keyframes beatPulse/.test(html) && /function lookupBpm/.test(html) && /api\.deezer\.com/.test(html));
  check('dashboard preset tiles (Quick play, one-tap playlist)',
    /function presetTileHTML/.test(html) && /class="preset-tile"/.test(html) && /Quick play/.test(html));
  check('plays default to album/context repeat (no single-track loop)',
    /function setRepeatContext/.test(html) && /repeat\?state=context/.test(html));
  // flex inputs must be allowed to shrink or they push siblings off-screen (horizontal spill)
  check('#search-input has min-width:0 (no flex overflow)', /#search-input\s*\{[^}]*min-width:\s*0/.test(html));
  check('#app clips horizontal overflow', /#app\s*\{[^}]*overflow-x:\s*hidden/.test(html));
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
  // Browsing stays in-app; the ONLY external Spotify link is the deliberate album Download
  // deep-link (Web API has no offline/download endpoint, so Download opens the app).
  check('only external Spotify link is the deliberate album download deep-link',
    (html.match(/open\.spotify\.com/g) || []).length === 1 && /window\.open\('https:\/\/open\.spotify\.com\/album\//.test(html));
  check('top header hidden (no device pill / off button)', /#header\s*\{\s*display:\s*none/.test(html));
  check('queue view present (see what is queued)', /function showQueue/.test(html) && /\/me\/player\/queue/.test(html));
  // Browse/search views intentionally HIDE the now-playing album art (it collided with the
  // play button); they must still keep the play controls visible.
  check('browse views hide the album art but keep the play controls',
    /#main\.searching #album-art\s*\{[^}]*display\s*:\s*none/.test(html) && !/#main\.searching #controls\s*\{[^}]*display\s*:\s*none/.test(html));
  check('brand wordmark in top bar (Spotify Drive / Labern)', /id="brand"/.test(html) && /Spotify <span class="brand-accent">Drive/.test(html) && /by Labern/.test(html));
  check('thin divider under the top bar', /#mode-bar\s*\{[\s\S]{0,220}border-bottom/.test(html));
  check('dashboard under search (recently played + playlists)', /function loadDashboard/.test(html) && /recently-played/.test(html) && /\/me\/playlists/.test(html));
  check('horizontal divider under search', /class="section-divider"/.test(html));

  // Progress time + now-playing deep-links + queue animation
  check('progress bar is chunky + rounded', /#progress-wrap\s*\{[^}]*height:\s*1[0-4]px/.test(html) && /#progress-fill[\s\S]{0,120}border-radius:\s*999px/.test(html));
  check('touch-to-scrub the progress bar (grows + seeks)', /#progress-wrap\.scrubbing/.test(html) && /function setupScrub/.test(html) && /player\/seek\?position_ms=/.test(html));
  check('swipe rows: left=play, right=queue', /function setupSwipe/.test(html) && /data-uri=/.test(html));
  check('queue-view rows marked no-requeue (Spotify has no un-queue)', /data-noqueue="1"/.test(html) && /dataset\.noqueue/.test(html));
  check('Clear-queue button on the queue page', /function clearQueue/.test(html) && /onclick="clearQueue\(\)"/.test(html));
  check('last queued track continues into its album', /function maybeContinueAlbum/.test(html) && /myQueued/.test(html));
  check('light mode has themed (dark) text — #app sets color', /#app\s*\{[^}]*color:\s*var\(--text\)/.test(html));
  // a custom property must never reference itself (a perl replace-all bit us once)
  check('no self-referential CSS tokens', !/--(\w[\w-]*):\s*var\(--\1\)\s*;/.test(html));
  check('light/dark toggle, icon-only, composes with BMW', /id="theme-toggle"/.test(html) && /#app\.light/.test(html) && /function toggleTheme/.test(html) && /ICONS\.sun/.test(html));
  check('error back button full-width', /\.err-back\s*\{[^}]*width:\s*100%/.test(html));
  check('queue button border follows the theme (BMW recolours it)', /\.result-queue\s*\{[^}]*border:\s*1px solid var\(--green\)/.test(html));
  check('time readout under the bar', /id="time-elapsed"/.test(html) && /id="time-remaining"/.test(html));
  check('now-playing title→album & artist→artist', /id="track-name" onclick="openCurrentAlbum/.test(html) && /id="artist-name" onclick="openCurrentArtist/.test(html));
  check('album title element present', /id="album-name"/.test(html));
  check('queued animation (green QUEUED + tick)', /\.result-queue\.queued/.test(html) && /@keyframes queuePop/.test(html));

  // ── Visual / structural regression guards ──
  check('round buttons are square (equal w/h → real circles, not ovals)',
    /#mic-btn\s*\{[^}]*width:\s*60px;\s*height:\s*60px/.test(html) &&
    /#search-clear\s*\{[^}]*width:\s*60px;\s*height:\s*60px/.test(html));
  check('three theme toggles present (paradox / light-dark / BMW)',
    /id="paradox-toggle"/.test(html) && /id="theme-toggle"/.test(html) && /id="bmw-toggle"/.test(html));
  check('each theme defines its token overrides (bmw / light / paradox)',
    /#app\.bmw\s*\{/.test(html) && /#app\.light\s*\{/.test(html) && /#app\.paradox\s*\{/.test(html));
  check('paradox wordmark becomes PARADOX (renderBrand)', /function renderBrand/.test(html) && /'PARADOX'/.test(html));
  check('icon controls carry aria-labels (a11y)', (html.match(/aria-label=/g) || []).length >= 6);
  check('search box has a placeholder', /id="search-input"[\s\S]{0,260}placeholder="[^"]+"/.test(html));
  check('progress bar is touch-scrubbable (touch-action:none)', /#progress-wrap\s*\{[^}]*touch-action:\s*none/.test(html));
  check('every onclick handler in the markup is a real function (already per-handler above) — sanity: app has a play handler',
    /onclick="togglePlay\(\)"/.test(html));
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
    // ~50% — livePos() may already have interpolated a few ms past the anchor, so allow a small margin.
    check('horizontal progress set to ~50% after fetchState', fill && Math.abs(parseFloat(fill.style.width) - 50) < 1, fill && fill.style.width);
    const ring = app.getEl('#gauge-ring .fill');
    check('ring offset set (between empty and full)', ring && parseFloat(ring.style.strokeDashoffset) > 0 && parseFloat(ring.style.strokeDashoffset) < 289, ring && ring.style.strokeDashoffset);
    const before = parseFloat(app.getEl('progress-fill').style.width);
    // livePos() interpolates from a wall-clock anchor (S.progressAt set in fetchState), so
    // nothing moves within the same instant — let real time elapse, then tick.
    await new Promise(r => globalThis.setTimeout(r, 80));
    app.ctx.tickProgress();
    const after = parseFloat(app.getEl('progress-fill').style.width);
    check('progress advances on tick (wall-clock interpolation)', after > before, `${before} -> ${after}`);
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
    check('album tracks are play-tappable (playFromAlbum → seeds the album queue)', h.includes("playFromAlbum('spotify:track:a'") && h.includes("playFromAlbum('spotify:track:b'"));
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
      'user-read-playback-state user-modify-playback-state user-read-currently-playing user-read-recently-played playlist-read-private playlist-read-collaborative user-library-read user-library-modify user-top-read');
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

  // 35. Re-tapping a Queued button doesn't add a duplicate (Spotify has no un-queue API)
  {
    const app = load(); app.auth();
    const btn = app.ctx.document.createElement('button');
    btn.classList.add('queued');
    btn.innerHTML = 'Queued';
    await app.ctx.queueTrack(btn, 'spotify:track:dup');
    await flush();
    check('re-tapping Queued issues no second queue POST', !app.fetchCalls.find(c => c.url.includes('/me/player/queue')));
    const toast = app.getEl('toast');
    check('re-tap explains Spotify cannot un-queue', toast && /un-?queue/i.test(toast.textContent), toast && toast.textContent);
  }

  // 36. Dictation normalizes the phrase (strips lead command word + trailing punctuation)
  {
    const app = load();
    check('cleanDictation strips "play"/"search for" + trailing punctuation',
      app.ctx.cleanDictation('play Redbone') === 'Redbone' &&
      app.ctx.cleanDictation('search for Daft Punk.') === 'Daft Punk' &&
      app.ctx.cleanDictation('  Tame Impala  ') === 'Tame Impala',
      [app.ctx.cleanDictation('play Redbone'), app.ctx.cleanDictation('search for Daft Punk.')].join(' | '));
  }

  // 37. Dictation that captures nothing prompts a retry (no silent dead-end)
  {
    const app = load(); app.auth();
    let inst = null;
    app.ctx.window.webkitSpeechRecognition = function () { inst = this; this.start = () => {}; this.stop = () => {}; };
    app.ctx.startDictation();
    inst.onend();                         // ended with no speech captured
    const toast = app.getEl('toast');
    check('empty dictation prompts the user to retry', toast && /didn.t catch/i.test(toast.textContent), toast && toast.textContent);
  }

  // 38. Dashboard "Quick play" preset tiles play the playlist on tap
  {
    const app = load(); app.auth();
    app.queueResp({ status: 200, body: { items: [] } });        // recently-played
    app.queueResp({ status: 200, body: { items: [
      { id: 'p1', uri: 'spotify:playlist:p1', name: 'Morning Drive', images: [{ url: 'u' }], tracks: { total: 20 } },
    ] } });                                                       // playlists
    await app.ctx.loadDashboard();
    await flush();
    const h = app.getEl('results-list').innerHTML;
    check('dashboard shows Quick play preset tiles', /Quick play/.test(h) && /preset-tile/.test(h));
    check('preset tile plays the playlist on tap', h.includes("playContext('spotify:playlist:p1')"));
  }

  // 39. Playing a track also sets repeat=context (so it follows the album, no loop)
  {
    const app = load(); app.auth();
    app.queueResp({ status: 200, body: { devices: [{ id: 'd1', is_active: true, type: 'Computer', name: 'Mac' }] } });
    app.queueResp({ status: 200 });                              // play
    app.queueResp({ status: 200 });                              // repeat
    await app.ctx.playTrackUri('spotify:track:T', 'spotify:album:AL');
    await flush(); await flush();
    check('play sets repeat=context', !!app.fetchCalls.find(c => c.url.includes('/me/player/repeat?state=context')));
  }

  // 40. Light/dark theme toggle: adds .light, persists, composes with BMW, toggles back
  {
    const app = load();
    app.ctx.toggleBmw();                              // BMW on first
    app.ctx.toggleTheme();
    check('theme toggle adds .light', app.getEl('app').classList.contains('light'));
    check('theme persisted to localStorage', app.ls.getItem('theme') === 'light');
    check('light composes with BMW (both classes present)', app.getEl('app').classList.contains('bmw') && app.getEl('app').classList.contains('light'));
    app.ctx.toggleTheme();
    check('theme toggles back to dark', !app.getEl('app').classList.contains('light') && app.ls.getItem('theme') === 'dark');
  }

  // 40b. PARADOX theme toggle (★): adds .paradox, persists, toggles back
  {
    const app = load();
    app.ctx.toggleParadox();
    check('PARADOX toggle adds .paradox', app.getEl('app').classList.contains('paradox'));
    check('PARADOX persisted to localStorage', app.ls.getItem('paradox') === '1');
    app.ctx.toggleParadox();
    check('PARADOX toggles back off', !app.getEl('app').classList.contains('paradox') && app.ls.getItem('paradox') === '0');
  }

  // 41. Scrub → seek: seekTo issues /me/player/seek with position_ms
  {
    const app = load(); app.auth();
    app.queueResp({ status: 200, body: { devices: [{ id: 'd1', is_active: true, type: 'Computer', name: 'Mac' }] } });
    app.queueResp({ status: 200 });                  // seek ok
    await app.ctx.seekTo(42000);
    await flush();
    const seek = app.fetchCalls.find(c => c.url.includes('/me/player/seek?position_ms='));
    check('seekTo issues a seek with position_ms', !!seek, app.fetchCalls.map(c => c.url).join(' | '));
    check('seek uses PUT', seek && seek.method === 'PUT');
    check('seek position is the requested ms', seek && /position_ms=42000\b/.test(seek.url), seek && seek.url);
  }

  // 42. Gesture wiring (swipe + scrub) attaches without throwing
  {
    const app = load();
    let threw = false;
    try { app.ctx.setupSwipe(); app.ctx.setupScrub(); } catch(e) { threw = true; }
    check('setupSwipe + setupScrub wire up without throwing', !threw);
  }

  // 43. Last queued track continues into its album when nothing else is queued
  {
    const app = load(); app.auth();
    app.queueResp({ status: 200, body: { devices: [{ id: 'd1', is_active: true, type: 'Computer', name: 'Mac' }] } });
    app.queueResp({ status: 200 });                              // queue add (records Q1)
    await app.ctx.queueTrack(app.ctx.document.createElement('button'), 'spotify:track:Q1');
    await flush();
    app.queueResp({ status: 200, body: { queue: [] } });        // GET queue → empty (Q1 is the last)
    app.queueResp({ status: 200, body: { tracks: { items: [
      { id: 'Q1', uri: 'spotify:track:Q1' }, { id: 'Q2', uri: 'spotify:track:Q2' }, { id: 'Q3', uri: 'spotify:track:Q3' },
    ] } } });                                                    // GET album
    app.queueResp({ status: 200 }); app.queueResp({ status: 200 });   // queue Q2, Q3
    await app.ctx.maybeContinueAlbum({ id: 'Q1', album: { id: 'albX' } });
    await flush(); await flush();
    const posts = app.fetchCalls.filter(c => c.method === 'POST' && c.url.includes('/me/player/queue'));
    check('last queued song queues the rest of its album', posts.some(c => decodeURIComponent(c.url).includes('spotify:track:Q2')), posts.map(c => c.url).join(' | '));
  }

  // 44. Clear queue re-issues the current context (the only way Spotify can wipe the queue)
  {
    const app = load(); app.auth();
    app.queueResp({ status: 200, body: { is_playing: true, progress_ms: 5000, shuffle_state: false,
      context: { uri: 'spotify:album:CTX' }, device: { id: 'd1', name: 'M', type: 'Computer' },
      item: { id: 'cur', name: 'Cur', duration_ms: 200000, artists: [{ name: 'A' }], album: { id: 'albCur', images: [{ url: 'a' }] } } } });
    await app.ctx.fetchState(); await flush();                  // populates S (track, context, device)
    app.queueResp({ status: 200 });                             // play (clear) — device already known, no /devices call
    app.queueResp({ status: 200 });                             // repeat
    app.queueResp({ status: 200 });                             // seek (pos > 1500)
    await app.ctx.clearQueue(); await flush();
    const play = app.fetchCalls.find(c => c.url.includes('/me/player/play') && c.method === 'PUT' && c.body && c.body.context_uri === 'spotify:album:CTX');
    check('clearQueue re-issues the current context to wipe the queue', !!play, app.fetchCalls.filter(c => c.method === 'PUT').map(c => c.url).join(' | '));
  }

  // 45. Tap feedback: flashTap marks the element so the glow/scale animation plays
  {
    const app = load();
    const btn = app.ctx.document.createElement('button');
    app.ctx.flashTap(btn);
    check('flashTap adds the .tapped class', btn.classList.contains('tapped'));
  }

  // 46. Beat trinket shows the ♪ on a new track (BPM lookup is best-effort, non-blocking)
  {
    const app = load();
    let threw = false;
    try { app.ctx.updateBeat({ name: 'Midnight City', artists: [{ name: 'M83' }] }); } catch(e) { threw = true; }
    check('updateBeat runs without throwing', !threw);
    check('beat note is revealed on a new track', app.getEl('beat') && !app.getEl('beat').classList.contains('hidden'));
  }

  // ── helper: load a track into state via fetchState (player + checkLiked responses) ──
  async function withTrack(app, id, liked, extra) {
    app.queueResp({ status: 200, body: Object.assign({ is_playing: true, progress_ms: 1000, shuffle_state: false,
      device: { id: 'd1', name: 'Mac', type: 'Computer' },
      item: { id, name: 'Song ' + id, duration_ms: 200000, artists: [{ name: 'A' }], album: { name: 'Alb', images: [{ url: 'art' }] } } }, extra || {}) });
    app.queueResp({ status: 200, body: [!!liked] });           // checkLiked /contains
    await app.ctx.fetchState(); await flush();
  }

  // 47. togglePlay pauses when already playing
  {
    const app = load(); app.auth();
    await withTrack(app, 'tp', false);                          // S.playing = true, deviceId = d1
    app.queueResp({ status: 200 });                            // pause PUT
    await app.ctx.togglePlay(); await flush();
    check('togglePlay pauses when playing', !!app.fetchCalls.find(c => c.url.includes('/me/player/pause') && c.method === 'PUT'));
  }

  // 48/49. toggleLike: like → PUT, unlike → DELETE
  {
    const app = load(); app.auth();
    await withTrack(app, 'tL', false);
    app.queueResp({ status: 200 });
    await app.ctx.toggleLike(); await flush();
    check('toggleLike adds to Liked Songs (PUT /me/tracks)', !!app.fetchCalls.find(c => c.url.includes('/me/tracks?ids=tL') && c.method === 'PUT'));
    check('toggleLike colours the like button on success', app.getEl('like-btn').classList.contains('liked'));
  }
  // 48b. A 403 on the like (missing/stale library-modify consent) reverts the button and
  // triggers a ONE-TIME re-consent (clears the scope guard, sets the persisted like_reauth).
  {
    const app = load(); app.auth();
    await withTrack(app, 'tF', false);
    app.queueResp({ status: 403, body: { error: { status: 403, message: 'Insufficient client scope' } } });
    await app.ctx.toggleLike(); await flush();
    check('like 403 reverts the button (not left in liked state)', !app.getEl('like-btn').classList.contains('liked'));
    check('like 403 arms one-time re-consent (like_reauth + scope_try cleared)',
      app.ls.getItem('like_reauth') === '1' && app.ls.getItem('scope_try') === '');
  }
  // 48c. A second 403 after re-consent does NOT loop — it shows an honest message instead.
  {
    const app = load(); app.auth();
    app.ls.setItem('like_reauth', '1');                         // already reconnected once
    await withTrack(app, 'tF2', false);
    app.queueResp({ status: 403, body: { error: { status: 403, message: 'Insufficient client scope' } } });
    await app.ctx.toggleLike(); await flush();
    check('like 403 after reconnect does not re-arm (no loop)', app.ls.getItem('scope_try') !== '' || app.ls.getItem('scope_try') === null);
  }
  {
    const app = load(); app.auth();
    await withTrack(app, 'tU', true);                           // already liked
    app.queueResp({ status: 200 });
    await app.ctx.toggleLike(); await flush();
    check('toggleLike removes from Liked Songs (DELETE) when liked', !!app.fetchCalls.find(c => c.url.includes('/me/tracks?ids=tU') && c.method === 'DELETE'));
  }

  // 50. toggleShuffle success turns shuffle on
  {
    const app = load(); app.auth();
    app.queueResp({ status: 200, body: { devices: [{ id: 'd1', is_active: true, type: 'Computer', name: 'M' }] } });
    app.queueResp({ status: 200 });
    await app.ctx.toggleShuffle(); await flush();
    check('toggleShuffle turns shuffle on (PUT state=true)', !!app.fetchCalls.find(c => c.url.includes('/me/player/shuffle?state=true') && c.method === 'PUT'), app.fetchCalls.map(c => c.url).join(' | '));
  }

  // 51. prev() uses POST
  {
    const app = load(); app.auth();
    app.queueResp({ status: 200, body: { devices: [{ id: 'd9', is_active: true, type: 'Computer', name: 'M' }] } });
    app.queueResp({ status: 200 });
    await app.ctx.prev(); await flush();
    const p = app.fetchCalls.find(c => c.url.includes('/me/player/previous'));
    check('prev() POSTs to /me/player/previous', p && p.method === 'POST', p && p.method);
  }

  // 52. checkLiked marks the like button
  {
    const app = load(); app.auth();
    await withTrack(app, 'tH', true);
    check('checkLiked marks the like button liked', app.getEl('like-btn') && app.getEl('like-btn').classList.contains('liked'));
  }

  // 53/54. ensureActiveDevice: prefers the active device, else the first
  {
    const app = load(); app.auth();
    app.queueResp({ status: 200, body: { devices: [{ id: 'dA', is_active: false, type: 'Computer', name: 'A' }, { id: 'dB', is_active: true, type: 'Speaker', name: 'B' }] } });
    check('ensureActiveDevice returns the active device', (await app.ctx.ensureActiveDevice()) === 'dB');
  }
  {
    const app = load(); app.auth();
    app.queueResp({ status: 200, body: { devices: [{ id: 'dX', is_active: false, type: 'Computer', name: 'X' }] } });
    check('ensureActiveDevice falls back to the first device', (await app.ctx.ensureActiveDevice()) === 'dX');
  }

  // 55. esc() escapes HTML special chars (XSS hardening)
  {
    const app = load();
    check('esc() escapes < > & " \'', app.ctx.esc('<b>&"\'') === '&lt;b&gt;&amp;&quot;&#39;', app.ctx.esc('<b>&"\''));
  }

  // 56. Search results escape HTML in track names (no injection)
  {
    const app = load(); app.auth();
    app.ctx.renderResults([{ uri: 'spotify:track:x', name: '<img src=x onerror=alert(1)>', artists: [{ name: 'A', id: 'a' }], album: { id: 'b', images: [{}, {}, { url: 'u' }] } }]);
    const h = app.getEl('results-list').innerHTML;
    check('search results escape HTML in names (no XSS)', h.includes('&lt;img') && !h.includes('<img src=x onerror'));
  }

  // 57. fmtTime formats mm:ss
  {
    const app = load();
    check('fmtTime formats mm:ss', app.ctx.fmtTime(0) === '0:00' && app.ctx.fmtTime(95000) === '1:35' && app.ctx.fmtTime(605000) === '10:05',
      [app.ctx.fmtTime(0), app.ctx.fmtTime(95000), app.ctx.fmtTime(605000)].join(' '));
  }

  // 58. handlePlaybackError → specific messages
  {
    const app = load(); app.auth();
    app.ctx.handlePlaybackError({ status: 403, message: 'x' }, 'Play');
    check('403 surfaces a Premium message', /premium/i.test(app.getEl('toast').textContent));
    app.ctx.handlePlaybackError({ status: 500, message: 'boom' }, 'Skip');
    check('generic error shows "<what> failed: <msg>"', /Skip failed: boom/.test(app.getEl('toast').textContent), app.getEl('toast').textContent);
  }

  // 59. fetchState renders the now-playing text + art
  {
    const app = load(); app.auth();
    app.queueResp({ status: 200, body: { is_playing: true, progress_ms: 1000, shuffle_state: false,
      device: { id: 'd1', name: 'Mac', type: 'Computer' },
      item: { id: 'tR', name: 'My Song', duration_ms: 200000, artists: [{ name: 'Art1' }, { name: 'Art2' }], album: { name: 'My Album', images: [{ url: 'art' }] } } } });
    app.queueResp({ status: 200, body: [false] });
    await app.ctx.fetchState(); await flush();
    check('fetchState renders the track name', app.getEl('track-name').textContent === 'My Song', app.getEl('track-name').textContent);
    check('fetchState joins multiple artists', app.getEl('artist-name').textContent === 'Art1, Art2', app.getEl('artist-name').textContent);
    check('fetchState shows album art', app.getEl('album-art').src === 'art' && !app.getEl('album-art').classList.contains('hidden'));
  }

  // N. playFromAlbum: play a track, then seed the queue with the rest of the album, wrapping
  {
    const app = load(); app.auth();
    app.queueResp({ status: 200, body: { devices: [{ id: 'd1', is_active: true, type: 'Computer', name: 'Mac' }] } }); // ensureActiveDevice
    app.queueResp({ status: 200, body: {} });                                                                          // play ok
    app.queueResp({ status: 200, body: {} });                                                                          // setRepeatContext (fire-and-forget)
    app.queueResp({ status: 200, body: { tracks: { items: [
      { uri: 'spotify:track:t1' }, { uri: 'spotify:track:t2' }, { uri: 'spotify:track:t3' },
      { uri: 'spotify:track:t4' }, { uri: 'spotify:track:t5' },
    ] } } });                                                                                                          // GET /albums/ALB
    await app.ctx.playFromAlbum('spotify:track:t3', 'ALB');
    await flush();
    const queued = app.fetchCalls
      .filter(c => c.url.includes('/me/player/queue?uri='))
      .map(c => decodeURIComponent(c.url.split('uri=')[1].split('&')[0]));
    check('playFromAlbum queues the album remainder in rotation (X+1..N, then 1..X-1)',
      JSON.stringify(queued) === JSON.stringify(['spotify:track:t4', 'spotify:track:t5', 'spotify:track:t1', 'spotify:track:t2']),
      queued.join(',') || '(none)');
    const play = app.fetchCalls.find(c => c.url.includes('/me/player/play'));
    check('playFromAlbum plays the chosen track as a single uri (clean queue)',
      play && play.body && Array.isArray(play.body.uris) && play.body.uris[0] === 'spotify:track:t3', play && JSON.stringify(play.body));
  }

  // O. saveAlbum: adds the album to the user's Library (PUT /me/albums), flips the button state
  {
    const app = load(); app.auth();
    const btn = app.ctx.document.createElement('button');
    app.queueResp({ status: 200, body: {} });
    await app.ctx.saveAlbum('ALB123', btn);
    await flush();
    const put = app.fetchCalls.find(c => c.url.includes('/me/albums?ids=ALB123') && c.method === 'PUT');
    check('saveAlbum PUTs the album to /me/albums', !!put, app.fetchCalls.map(c => c.method + ' ' + c.url).join(' | '));
    check('saveAlbum marks the button saved', btn.classList.contains('saved'));
  }

  // P. Discover: loadDiscover pulls top artists / top tracks / new releases and renders sections
  {
    const app = load(); app.auth();
    // No track playing → S.artistId unset → "from this artist" makes no call. Order: top artists, top tracks, new releases.
    app.queueResp({ status: 200, body: { items: [{ id: 'a1', name: 'Top Artist', images: [{}, { url: 'u' }] }] } });
    app.queueResp({ status: 200, body: { items: [{ id: 't1', name: 'Top Track', uri: 'spotify:track:t1', artists: [{ name: 'A' }], album: { uri: 'spotify:album:x', images: [{}, {}, { url: 'u' }] } }] } });
    app.queueResp({ status: 200, body: { albums: { items: [{ id: 'al1', name: 'Fresh Album', images: [{}, { url: 'u' }] }] } } });
    await app.ctx.loadDiscover();
    await flush();
    const urls = app.fetchCalls.map(c => c.url).join(' | ');
    check('discover fetches your top artists (limit<=10)', urls.includes('/me/top/artists?limit=10'));
    check('discover fetches new releases', urls.includes('/browse/new-releases?limit=10'));
    const dc = app.getEl('discover-content').innerHTML;
    check('discover renders top-artists + new-releases sections',
      /Your top artists/.test(dc) && /New releases/.test(dc) && dc.includes('Top Artist'), dc.slice(0, 90));
  }

  // Q. Discover degrades gracefully when a section 403s (deprecated/insufficient) — section omitted
  {
    const app = load(); app.auth();
    app.queueResp({ status: 403, body: { error: { message: 'insufficient' } } });   // top artists fails
    app.queueResp({ status: 403, body: { error: { message: 'insufficient' } } });   // top tracks fails
    app.queueResp({ status: 200, body: { albums: { items: [{ id: 'al1', name: 'Fresh', images: [{ url: 'u' }] }] } } }); // new releases ok
    await app.ctx.loadDiscover();
    await flush();
    const dc = app.getEl('discover-content').innerHTML;
    check('discover shows the surviving section and omits failed ones',
      /New releases/.test(dc) && !/Your top artists/.test(dc), dc.slice(0, 90));
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
