# SpotifyDrive — Knowledge Base

Everything learned building this, condensed. If you're picking this up cold, read
this first, then `variants/pure/index.html` (the whole app) and `tests/run.mjs`.

---

## 1. What it is

A **single-file PWA "Spotify remote for driving"** — huge buttons, glanceable,
everything on one screen, no dangerous screen-switching. It controls your *active*
Spotify device (phone / CarPlay / speaker) through the Spotify Web API.

- **Live:** https://labern.github.io/Clean/SpotifyDrive/index.html
- **The app IS one file:** `variants/pure/index.html` (inline `<style>` + `<script>`,
  no build step, no dependencies, no backend).
- Design ethos: **size + tap-safety first**; inline everything; never swallow errors.

## 2. Features (what was built)

- **Now playing:** album art, wrapping title/album/artist, chunky progress bar with
  elapsed/-remaining, a gauge play button with a progress ring.
- **Transport:** play/pause, prev, next, shuffle, like (all oversized).
- **Search:** inline as-you-type + **one-tap voice dictation** (mic → Web Speech;
  strips filler like "play…"; re-tap wipes a wrong result and re-listens; 7s safety
  timeout; "didn't catch that" retry; falls back to the keyboard mic where Web Speech
  is unavailable).
- **Swipe a song row:** left = play, right = queue (per-direction tint + toast).
- **Touch-scrub** the progress bar: it grows thick, drag to seek.
- **Stats and Facts dashboard** (browse view under search): **Drive time** (session
  uptime), **Plays this week** (local play-log seeded from recently-played), **Quick
  Play** tiles (one tap plays a whole playlist), Recently played, Your playlists.
- **In-app views:** album / artist / playlist / queue render inline — never bounce to
  the Spotify app.
- **Queue:** add (optimistic), view "up next", **Clear queue**, last-queued track
  **continues into its own album**, no duplicate on re-tap, honest "can't un-queue".
- **Themes** (one toggle each in the top bar; they compose):
  - **BMW Mode** — blue/white/black, play button becomes the BMW roundel.
  - **Light / Dark** — sun/moon icon toggle.
  - **PARADOX** (★) — the whole app as a terminal: monospace, xterm-256 palette,
    flat dark purple, gold/teal accents, wordmark becomes `> PARADOX DRIVE`.
- **Visible tap feedback:** accent glow-ring + scale pulse on every button press.
- **Beat trinket:** a ♪ that pulses at the track's **real BPM** (from Deezer).
- **Deep-links:** `?bmw=1`, `?light=1`, `?paradox=1`, `?demo=1`.
- **Demo mode:** auto-on for localhost / LAN / `?demo=1` (never on the live host) —
  sample data, no Spotify login. Used for previews + screenshots.

## 3. How it works (architecture)

- **PKCE OAuth.** The code verifier lives in **`localStorage`, not `sessionStorage`**
  — an installed iOS PWA loses sessionStorage across the redirect to accounts.spotify.com.
- **Token refresh** on expiry; 401 → refresh-once-then-retry, else bounce to Connect.
- **Themeable tokens.** Every accent/surface is a CSS custom property at `:root`,
  referenced via `var(--token)` everywhere. A theme = **one class on `#app`
  overriding tokens** (`#app.bmw { --green:#0166B1 }`, `#app.light {…}`,
  `#app.paradox {…}`). They compose because each overrides different tokens.
- **Demo mode** intercepts `api()` and returns canned data; skips auth.
- **Polling:** `fetchState` every 5s + a 1s progress tick; `recentTurns`-style logic
  isn't here — this is simpler.

## 4. The hard-won constraints (READ THIS)

### Spotify Web API
- **Every `limit` query param MUST be ≤ 10** for this dev-mode app, or it returns
  `400 invalid limit`. This silently emptied the dashboard and broke artist/playlist
  views. **Paginate (offset) instead of raising the limit.** A test enforces ≤10.
- **`audio-features` / `audio-analysis` are deprecated** for apps created after
  **2024-11-27** → 403. So **we cannot read tempo/BPM/beats from Spotify.** (We use
  Deezer instead — see Beat trinket below.)
- **No remove-from-queue endpoint exists** — the queue is add (`POST /me/player/queue`)
  + read (`GET /me/player/queue`) only. "Clear queue" works by **re-issuing the current
  context** (which wipes the user-added queue). Re-tapping "Queued" can't undo it — we
  tell the truth instead of faking a removal.
- **Playback verbs:** play/pause/shuffle/seek/transfer/repeat = **PUT**;
  next/prev/queue = **POST**.
- **Play a track via `context_uri` + `offset`**, NOT `uris:[x]` — a context-less single
  track loops/re-plays. We also set `repeat=context` on play to kill single-track loops.
- **Empty 200 bodies** on playback commands → `res.text()` then guarded `JSON.parse`
  (try/catch → null), never `res.json()` (throws "Unexpected end of JSON input", and a
  bad body would surface as "play/pause failed: JSON Parse error").
- **Errors:** 404 = NO_ACTIVE_DEVICE (re-ensure device + retry once, else prompt device
  picker), 403 = PREMIUM_REQUIRED. **Always surface errors** (toast + inline message +
  a big full-width Back button). Never swallow.
- **Scopes:** adding a scope later needs **re-consent** — refresh tokens keep only the
  originally-granted scopes. `SCOPE_VER` + `missingScopes()` force a one-time re-auth on
  load. Current scopes: playback-state, modify-playback-state, currently-playing,
  recently-played, playlist-read-private, playlist-read-collaborative, library read/modify.

### iOS / PWA
- **Web Speech (dictation)** works in a Safari *tab* but is broken in an **installed
  home-screen PWA** → `startDictation()` falls back to the keyboard mic.
- **`visualViewport`** resizing keeps the search bar above the iOS keyboard.
- We can't analyse the audio ourselves — it plays on the **car/phone Spotify app**, not
  through our page, so there's no stream to read.

### Beat trinket (BPM)
- Spotify's tempo is dead (above). **Deezer's public API** (`api.deezer.com`) returns
  `bpm` and **supports JSONP** → real BPM client-side with **no key and no CORS issue**.
  Search by title+artist, read `bpm` (sometimes a 2nd `/track/{id}` call). Falls back to
  a decorative pulse when Deezer has no BPM. Pulse matches the *tempo* (rate), not the
  exact downbeat phase (Spotify's beat-timestamp endpoint is the one they killed).

## 5. CSS / theming gotchas (each one was a real bug)

- **`#app { color: var(--text) }`** is required so descendants inherit the *themed*
  text colour. `body` resolves `--text` from `:root` (white), and `#app.light` is a
  *descendant* of body — so without it, text inside `#app` inherited white and was
  invisible in light mode.
- **Don't blanket replace-all a colour into a token** — `s/#2f2e36/var(--active)/g`
  clobbered the token's own definition into `--active: var(--active)` (self-reference →
  invalid → dark active states resolved to nothing). A test now fails on any
  self-referential token.
- **Flex children that hold text/inputs need `min-width: 0`** or they refuse to shrink
  and push siblings off-screen (the search input pushed the clear button off the edge).
- **Circular buttons need equal width AND height** — `border-radius:50%` on a 72×46 box
  is an ellipse. Set explicit `height` and `align-items:center` on the row.
- **SVG `<text>` inherits `font-family` from the CSS cascade** — PARADOX's monospace
  shifted the BMW roundel letters. Set an explicit `font-family` on the SVG text.
- **Scope conflicting theme overrides with `:not()`** — PARADOX's gold play button was
  clobbering the BMW roundel; `#app.paradox:not(.bmw) #play-btn` fixes it.
- **`color-mix(in srgb, var(--x) N%, transparent)`** for themed alpha (glow rings, soft
  backgrounds). Safari 16.2+.
- **Centre with `margin: 0 auto` + `max-width`**, not flex on `body` — flex centering is
  fragile right at the max-width boundary.
- On a NEW track, **`snapProgress()`** kills the bar transition so it jumps to the new
  position instead of animating backwards ("rewind").

## 6. Deploy + CDN

- Source lives on **`master`** (via the `worktree-spotify-drive` branch, ff-merged).
- **`gh-pages`** branch serves the live site; `SpotifyDrive/index.html` there is a
  **copy** of `variants/pure/index.html`. `.nojekyll` is set.
- Flow: commit on the worktree branch → `git -C <clean> merge --ff-only` master → push
  master → `cp pure → ghp/SpotifyDrive/index.html` → commit + push gh-pages.
- **The GitHub Pages CDN lags ~30–90s behind the push.** Do NOT tell the user a change
  is live/clickable until the **live `labern.github.io` URL** (not `raw.githubusercontent`
  or the gh-pages branch) actually serves a unique marker from this deploy. **Poll it.**
- Experiment variants deploy to preview paths (`/neo/`, `/paradox/`) and **force demo
  mode on that path** so they preview without auth.

## 7. Test harness (`tests/run.mjs`)

- **Zero dependencies.** Runs the app's real inline `<script>` inside a Node `vm` with a
  mocked DOM / `fetch` / `localStorage` / `crypto`. No browser, no account, no deploy.
- **Two kinds:** static checks (regex over the HTML — handlers defined, ids exist, no
  emoji, limits ≤10, theme structure, button geometry…) and behavioural (queue fake
  fetch responses, call the real functions, assert calls/DOM).
- **257 tests.** Run: `node SpotifyDrive/tests/run.mjs` (or pass a variant path).
- **Harness facts:**
  - `const`/`let` top-level bindings (`S`, `appOpenedAt`) are **lexical — NOT on
    `app.ctx`**. You can't poke them directly; drive state through `fetchState` or call
    function *declarations* (which are on `ctx`).
  - `el.style` is a plain object → guard `el.style.setProperty` (custom props).
  - `document.head` / `window.addEventListener` may be absent → guard before use.
  - The mocked `fetch` shifts queued responses in call order; an unconsumed/extra call
    (e.g. `checkLiked`, `setRepeatContext`) shifts everything — order your `queueResp`s.
- **Limit:** it checks logic + structural/CSS *values*. It can't see real **pixel
  rendering** ("this looks off"). For that, add a headless-Chrome **screenshot-diff**
  harness (we already use headless Chrome for screenshots).

## 8. Variants / branches

- **`pure`** (master) — the live app; BMW / Light / PARADOX are built-in toggles.
- **`ui-experiment`** branch — `neo` variant (Space Grotesk + squircle buttons). Was too
  timid a redesign.
- **`paradox-edition`** branch — standalone terminal variant (its look now also ships as
  the in-app ★ PARADOX toggle).
- The PARADOX style spec lives at `~/Desktop/★★★★★/STYLE.md` (xterm-256 palette,
  terminal-window-on-gradient). The in-app toggle drops the window chrome for a clean
  flat dark-purple per the user's preference.

## 9. Process lessons

- **Self-review before shipping:** walk flex/overflow, long text, empty + error paths,
  and API constraints yourself — don't make the user find them.
- **Verify the live CDN serves the build before saying it's ready.**
- **Don't over-use multi-agent workflows** on a single-file app — parallel agents
  collide and need conflict-merging; sequential is faster here.
- Keep responses short; surface cost/footguns proactively.

---

## 10. Scope contract & working protocol (added 2026-06-25)

- **Default scope = PARADOX** unless the user names another mode. He locked **normal mode
  as approved — do NOT restyle it** without an explicit ask.
- **Styling** (typography / colour / layout of a *themed surface*) = **mode-scoped**.
  **Features / bug-fixes** (new buttons, data, API, fixes) = **app-wide** unless told.
- **No screenshots** (headless Chrome / reading PNGs) unless explicitly asked — verify via
  code/diff/`node --check`/CDN-poll instead.
- **Fast-build:** don't reflexively run/write the full test suite; **batch edits → one
  deploy**; keep replies terse. (Conflicts with "ultracode" mode — that should be OFF here.)
- Before editing when a request doesn't name a mode, **state the target in one line**
  ("doing this on PARADOX") so a wrong assumption is caught before deploy.
- A message arriving **mid-task may be a correction** — reconcile before firing more work.
- Full cue protocol in the auto-memory `feedback-scope-transitions`.

## 11. Session log — 2026-06-25 (typography, search cluster, lag, scopes)

### Now-playing typography
- Tried **Bricolage Grotesque** on the *normal* title — user wanted it on **PARADOX only**,
  so reverted normal byte-for-byte and moved on. PARADOX title/album/artist now use
  **Space Mono** via a `--font-para` token; title `clamp(1.55rem,6vw,2.1rem)`; shimmer
  **softened** to teal→violet (dropped hot pink), **slowed 7s→18s**, `background-size:200%`.

### Search-row action cluster — Artist · Album · Queue · Radio
- Each search result row has a vertical `.row-actions` stack:
  **Artist** (`openArtist`), **Album** (`openAlbum`), **+ Queue** (`queueTrack`),
  **Radio** (`startRadio`). Classes `.result-artist-btn` / `.result-album` / `.result-radio`
  (neutral pills; radio gets a subtle green border). The in-app album/artist views already
  existed (`openAlbum`/`openArtist`); "Go to album" was praised as working great.

### Radio — HARD LIMIT (important)
- Spotify's public Web API has **no create-radio-station endpoint** (native "Song Radio" is
  a *private* endpoint). **`/recommendations` is DEPRECATED** for apps created after
  **2024-11-27** (same cutoff that 403s audio-features / related-artists). So **true radio
  is impossible** for this app. `startRadio()` plays the seed, tries `/recommendations`
  (403s), and falls back to the **artist's top-tracks** ("artist mix"). Closest-to-native
  alternative = **Spotify Autoplay** (play the seed ALONE, no queue) — only works if the
  user's Autoplay setting is on, which we can't toggle via API. Button may be cut.

### Lag fix — wall-clock anchoring (the right pattern)
- **Root cause:** `tickProgress` added `+1000ms` per `setInterval` tick (drifts late under
  load) and only corrected every 5s → the bar/clock fell **1–5s behind** the song.
- **Fix:** anchor `S.progressAt = Date.now()` at each sync; `livePos()` returns
  `progressMs + (playing ? now − progressAt : 0)`, clamped. `renderProgress`/`tickProgress`
  read `livePos()` (no mutation, no drift). Poll **5s→3s**. Near the end
  (`durationMs − livePos() < 1200`) fire an immediate `fetchState` (debounced 4s) so the
  **next track appears instantly**. Seek/scrub/`clearQueue` re-anchor `progressAt` / use `livePos()`.

### Like fix — 403 self-heal + coloured success
- `PUT/DELETE /me/tracks` needs `user-library-modify`. **`granted_scope` can CLAIM a scope
  the live token actually lacks** → 403. Fix: on 403, clear the scope guard + **re-authorize
  ONCE** (persisted `like_reauth` flag prevents a loop; cleared on success). Bumped
  `SCOPE_VER` `v3-playlist`→`v4-library` (the one-time-reconnect guard `scope_try===SCOPE_VER`
  was blocking re-consent for already-"tried" tokens). Coloured liked state
  (`.sec.liked` tint + `.just-liked` `likePop` pop); error toast now shows the real status.
- **Test lesson the user (rightly) pushed:** a mocked fetch always "succeeds", so a logic
  test can NEVER catch a missing OAuth scope. Added a **static scope-coverage map**
  (endpoint regex → required scope): if the code calls the endpoint, the scope must be in
  `SCOPES`. That's the assertion that would have caught this without a live account.

### Dashboard
- **Quick Play moved to the BOTTOM.** "Your playlists" now render as **square tiles**
  (`.preset-tile` reused, `openPlaylist`, no play overlay) instead of rows.

### Playlist open 403 → play
- Curated/algorithmic playlists (Discover Weekly, Daily Mix, Release Radar) **can't have
  their tracks read** via the API for new apps (403, same deprecation family). `openPlaylist`
  now **falls back to `playContext(uri)`** on 403 instead of showing a dead error.

### Layout
- **Search row swapped above** the shuffle/like/queue (`#secondary`) row — search is used more.

## 12. Deploy / cache gotcha (reinforced)
- GitHub Pages serves the HTML with **`Cache-Control: max-age=600`** → the user's browser
  replays a **stale copy for up to 10 min** even after the CDN itself updates; an installed
  PWA caches longer. "Looks exactly the same" usually = they're on the cached file, not a
  failed deploy. To let them see a change *now*, hand a **cache-busted link**
  (`?v=N`, or `?paradox=1&v=N`). Always poll the live `labern.github.io` URL for a unique
  marker before saying it's ready.

## 13. Test-harness facts (tests/run.mjs)
- `setTimeout` is **stubbed to a no-op** and `location` is a **mock object** — so functions
  that schedule a redirect (e.g. `authorize` via `setTimeout`) are safe to exercise in tests.
- `app.ls` IS the localStorage the app code reads; `flush = () => new Promise(setImmediate)`.

## 14. Song-row action layouts (known models)
The per-row action cluster (Artist / Album / Queue) is rendered by ONE shared helper,
`rowActionsHTML(t)`, used by BOTH search results (`renderResults`) and recently-played
(`trackRowHTML`). **The cluster is the default for every song row shown** (user: "that's
the default for all songs being shown"). Edit the helper once → all rows change together.

Two layouts have been built; the helper currently renders Model B:
- **Model A — horizontal full-width row** (rejected, kept as a known option): Artist · Album ·
  Queue as three equal flex:1 buttons wrapped onto their own full-width line *below* the
  track (`.result-row{flex-wrap:wrap}`, `.row-actions{flex-basis:100%}`). Shorter rows, but
  not the wanted shape.
- **Model B — stacked + tall queue (CURRENT)**: Artist and Album stacked vertically in
  `.aa-stack` (a flex column), sitting to the LEFT of a single tall Queue button; the whole
  cluster sits on the RIGHT of the row (`.row-actions{flex-direction:row;align-items:stretch}`,
  no row wrap). Queue stretches to the stack's full height via `align-items:stretch`.

To switch back to Model A: re-add `flex-wrap:wrap` to `.result-row`, set `.row-actions` to
`flex-basis:100%;width:100%`, make the three buttons `flex:1`, and drop the `.aa-stack`
wrapper in `rowActionsHTML`.

Note: album/artist/playlist/queue *context* views still use their own single Queue button
(not the shared cluster) — extend them to `rowActionsHTML` if "all songs" should include those too.
