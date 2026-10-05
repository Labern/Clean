# Raven

A dashboard for the car's own screen — 2019 Model S Raven (Intel MCU2, UK,
miles). Runs in the Tesla browser at `labern.github.io/Clean/Raven/`. Does
what the car can't: Google Maps with "send to nav", WhatsApp on screen (names
only), full Spotify control, a drive log with real stats, live-location
sharing, replies from the wheel.

## The car's browser (verified 2026-10-05)
- Chromium 148 since 2026.26. Pages work while driving; video doesn't.
- 2026.26 changed the default zoom. Everything is in `rem`; `--ui` (Settings →
  Size) scales the whole UI. Default 1.5 = 14px body reads as 21px.
- **No microphone or camera on Intel cars.** Voice input comes from the phone
  (or Siri over Bluetooth), never the car. `probe.html` tests the exact
  browser: geolocation, audio, WebSocket, fps, fullscreen. Run it first.
- 1920×1200 landscape, desktop UA, touch. Targets ≥ 4.8rem.

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

## Layout
Header (clock, car pill, unread, link dots, settings) · map stage with search,
saved-place chips, recenter, Send to nav · widget rail · sheet (expanded
widget over the map) · toasts top-right (sender name only, 6s, chime).

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

## Tests
`node Raven/tests/run.mjs` — zero-dep harness: bus, store, fmt, sun, drives,
link, demo, widget contract. Keep it green.

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
