# Raven

A dashboard for the car's own screen — 2019 Model S Raven (Intel MCU2, UK,
miles). Runs in the Tesla browser at `labern.github.io/Clean/Raven/`. Does
what the car can't: Google Maps with "send to nav", WhatsApp on screen (names
only), full Spotify control, a drive log with real stats, live-location
sharing, replies from the wheel.

## The car's browser (measured on the Raven, 2026-10-06, via `probe.html`)
- Chrome/148 Linux x86_64 UA. Pages work while driving; video doesn't.
- **Portrait.** Screen 869×1391 CSS px at DPR 1.38 (= 1200×1920 physical);
  browser viewport **856×1096** with the nav strip below; a smaller
  856×668 window also occurs. `style.css` has a `max-width: 1100px` block
  for this: 2-column widget grid, chips wrap under the search field, brand
  name hidden, sheets stack one column (`.grid-2.stack-portrait`).
- Everything is in `rem`; `--ui` (Settings → Size) scales the whole UI.
- **Geolocation works**: ±1 m, ~2 s to first fix, speed/heading/altitude.
  `lib/geo.js` → `car.pos`; `lib/trip.js` segments it into drives locally,
  so Trip and Facts run with no server and no Tesla API.
- Audio: `AudioContext` runs and `<audio>.play()` resolves (chime works).
- 61 fps, fullscreen API works (Settings → Screen), WebSocket round-trips,
  localStorage persists, wake lock present, `Notification` denied (we don't
  need it), `speech`/`mediaDevices` objects exist but the car's own
  dictation (hold the right wheel button in a text field) is the input.
- `touch: 16 points, pointer: fine` — style for touch regardless. Targets
  ≥ 4.8rem.

## Design: OEM Tesla
- Type: Universal Sans Display/Text when a licensed copy is present (one
  `@font-face` in `style.css`); **Inter** (vendored, `fonts/`) otherwise.
  Weights 400 and 500 only. No uppercase, italics, bold. Display: 500,
  −0.02em, 1.1. Body: 400, 0, 1.43. Labels: 500, +0.04em, 1.2rem.
- Colour: Tesla neutrals (`#000`, `#171a20`, `#393c41`, `#5c5e62`, `#8e8e8e`,
  `#d0d1d2`, `#f4f4f4`, `#fff`), one accent `#3e6ae1` for primary actions only,
  green `#16a34a` for charging. Night is default; day via `[data-theme=day]`;
  auto switches at local sunset (`lib/sun.js`).
- Flat: no shadows, gradients or card borders. 4px buttons, 12px cards, pill
  chips. Motion 250–330ms `cubic-bezier(.5,0,0,.75)`, colour only.
- Tesla T mark (SVG symbol in `index.html`). Personal use.

## Layout (portrait-first, one target: 856×1096 at DPR 1.38, `--ui` 1.3)
Header 5.6rem (T mark, clock, car pill, unread pill, link dots, settings) ·
map stage (search full width, Home/Work chips, recenter + Send to nav) ·
Now Playing strip 9.6rem (full width) · 2×2 tiles of 16rem (Messages, Trip,
Battery, Facts) · sheet fixed full-screen under the header · toasts
top-right (sender name only, 6s, chime). Everything fits with no scrolling;
`shot-portrait` asserts `railBottom === innerHeight`. A laptop shows the
same layout centred at `max-width: 90rem` — there is no second design.

## Spotify (`lib/spotify-api.js`, ported from SpotifyDrive/variants/pure)
PKCE in the car's browser, tokens in localStorage (`sp_*`), redirect URI
`https://labern.github.io/Clean/Raven/index.html`, client id in
`config.js`. `handleRedirect()` on boot, `start()` polls `/me/player` every
3 s while visible, `cmd(name, arg)` for toggle/next/prev/like/shuffle/seek/
play/queue/transfer with the SpotifyDrive 404-re-resolve. Emits
`spotify.state`, `spotify.auth`, `spotify.error`. Demo mode never
constructs it; `lib/demo.js` answers `spotify.cmd` instead. The deployed
`config.js` on gh-pages carries the client id (not secret) and the Maps key
(referrer-restricted); it is gitignored on master.

## Code
- No build step. ES modules served as-is. `config.js` (gitignored, from
  `config.example.js`) holds the Google Maps key.
- `app.js` — shell. Owns rail, sheet, toasts, theme, scale, settings, link.
- `lib/bus.js` — event bus; `latest(type)` lets late widgets render at once.
- `lib/store.js` — localStorage, hydrate-over-defaults (`merge`), debounced.
- `lib/link.js` — the one WebSocket to the server; republishes server events.
- `lib/demo.js` — synthetic events. On for localhost/LAN or `?demo=1`.
- `lib/drives.js` — drive segmentation (start ≥ 5 km/h, end after 5 min
  stopped) and stats. `lib/fmt.js` — miles/mph/Wh/mi/£. `lib/sun.js`.
- `widgets/*.js` — plug-ins:
  `{ id, title, order, events: [...], summary(el, data, ctx), detail(el, data, ctx), actions: { name(ctx) } }`.
  `summary` renders the tile, `detail` the sheet; both re-run on each listed
  event. Buttons use `data-act="name"`. A new widget = one file + one import.
- Bus event names (server → car): `spotify.state`, `wa.chats`, `wa.message
  {name, chat, ts}`, `tesla.state`, `drive.update`, `drives.history`, `notify`,
  `link.status`. Car → server: `spotify.cmd`, `tesla.nav`, `wa.send`.
- Auth: `?key=…&server=…` once → localStorage → URL scrubbed. Spotify PKCE
  in-browser (Phase 2). WhatsApp QR and Tesla OAuth on the phone setup page.

## Server (`server/`)
Node ≥ 22.13 on your Mac behind Tailscale Funnel; see `server/README.md`.
`index.mjs` (HTTP + WS + routes) · `hub.mjs` (broadcast, replays last state
per type on connect) · `wa.mjs` (Baileys linked device; names and counts
only; `WA_DEMO=1` for synthetic traffic) · `live.mjs` (share tokens, public
`/api/live/:token`) · `db.mjs` (`node:sqlite`) · `setup.html` (phone page:
key, QR, open-in-car link, quick replies, active shares).
Car → server over the WS: `car.pos` (from `lib/geo.js`, browser GPS),
`wa.send`, `wa.read`, `wa.share {chat, minutes, refreshMin}`, `wa.share.stop`.
Server → car: `wa.status`, `wa.chats`, `wa.message`, `wa.canned`,
`share.state`, `car.pos`, `wa.sent`, `wa.shared`, `error`.
Replies: the composer in the Messages sheet is a plain text field — the
car's own dictation (hold the right wheel button) types into it.
Live location: pin + `live/index.html#s=<server>&t=<token>` (Leaflet + CARTO
tiles, no key), pin refreshed every `refreshMin` while active.

## Tests
`node Raven/tests/run.mjs` (client: bus, store, fmt, sun, drives, link,
demo, geo, widget contract/behaviour) and `node Raven/server/tests/run.mjs`
(db, hub, live, real HTTP + WS against a demo instance). Keep both green.

## Deploy
GitHub Pages like the rest of `Clean`: copy `Raven/` onto the gh-pages
worktree, commit `Deploy Raven: …`, push. `config.js` must be copied by hand
(it's gitignored) — the Maps key is referrer-restricted so it's safe there.

## Roadmap
1. Google Maps live: Places search, traffic, car marker, saved places.
2. Spotify: port SpotifyDrive `variants/pure` PKCE + player core.
3. Server (`server/`, Node ≥ 22, on the Mac behind Tailscale Funnel, free):
   WS hub, Baileys bridge → names/unread + toasts; **replies from the wheel**
   (canned one-tap; voice via phone mic page or Siri over Bluetooth; in-car
   mic only if the probe proves it); **share where I am** (location pin +
   `live/` link showing the car moving with ETA; optional pin refresh).
4. Trip + stats from browser geolocation (if the probe says yes) or Tesla data.
5. Tesla Fleet API when a domain exists: nav, battery, climate, telemetry.
6. Backlog: charging £ and curves, battery health trend, phantom drain,
   0–60 pulls, destination weather, calendar → nav.
