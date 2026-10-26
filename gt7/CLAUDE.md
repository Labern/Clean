# GT7 Endgame

Gran Turismo 7 companion for the post-Café endgame: credits, buying the great
cars, track mastery, racecraft, Sport Mode, wheel setup, GT heritage. Live at
`labern.github.io/Clean/gt7/`. Must work on a MacBook and a phone (rail nav
≥760px, bottom tab bar below). A native iOS/Android port comes later; keep
data and UI separate so the port only rewrites the UI.

## Layout
- `index.html`, `style.css`: shell and the GT house style (white, GT navy
  `#0b1f4b`, blue/red stripe, Barlow Condensed italic display type).
- `app/main.js`: hash router + every view. A view returns `html` (escaped
  tagged template from `util.js`) and an optional `wire(root)`.
- `app/state.js`: the single persisted object (localStorage key
  `gt7-endgame-v1`). Swap this module for sync/native storage.
- `app/engine.js`: next-step engine (roadmap priority + focus boost +
  wishlist affordability) and credit maths (credits/hour, hours to target).
- `app/map.js`: track drawings. `app/widgets.js`: Academy diagrams.
- `data/*.js`: all content. `data/tracks/*.js` hold the track guides.
- `img/cars/<id>.jpg`: one Wikimedia Commons photo per car (credits in
  `data/credits.json`). `escudo` has no usable free photo; the UI draws a placeholder.
- `img/brand/`: Gran Turismo logos (Commons renders) and the app icon.

## Track geometry (the part that's easy to break)
Real circuits come from OpenStreetMap, not hand-drawing:
1. `tools/osm_tracks.py` fetches each bbox from the OSM API (Overpass is
   blocked from the cloud sandbox), keeps `highway=raceway` (or a
   `type=circuit` relation for public-road tracks: Le Mans, Bathurst), drops
   pit lanes and one-off layouts (`EXCLUDE`), enumerates cycles and keeps the
   one closest to the official length. It orients the lap from the one-way pit
   lane, then applies `FLIP` and `SF` (start/finish relative to a named
   corner) overrides. Output: `tools/geo.json` (1000 points per lap, equal
   arc length, plus OSM corner names).
2. `tools/build_maps.py` → `data/maps.js` (integer XY, north up).
3. `tools/corners.py` prints detected corners (lap fraction, L/R, angle, OSM
   name). Corner `at` values in the guides come from this output. If you
   re-extract a track, re-check its corner `at`s.
Hard-won fixes, don't undo: Daytona's target is 5.78 km so the loop takes the
Bus Stop. Watkins Glen targets 5.552 so it takes the Inner Loop. MotoGP and
long-lap segments are excluded. Autopolis is flipped. "Paddock Hill",
"Pit Straight" and "Virage du Karting" are racing line, so the pit filter
matches whole phrases only.
GT originals (Trial Mountain, Deep Forest, …) have no real-world geometry. They
are traced from their in-game course maps (Gran Turismo Wiki images) by
`tools/trace_gt.py <imgdir>` → `data/maps-gt.js` (numpy + PIL only: threshold,
bridge corner-tick gaps, hand-cut pit lanes via `erase`, fill the lap interior,
grow to the line centre, trace, resample, orient from a known start + direction,
scale to the official km). `data/allmaps.js` merges both; import MAPS from there.
Corner `at`s for originals were snapped to curvature detected on the trace; the
guide's own descriptions (Deep Forest, Trial Mountain final chicane) confirmed
the direction of travel. Never hand-draw a map.

## Cloud save (`app/sync.js`)
Sign in once per device with PSN ID + passphrase → PBKDF2 → AES-GCM key +
topic id. The save is published *retained* on three public MQTT brokers
(same pattern as `kittens/`, `cycle/`; mqtt.js vendored in `vendor/`). Newest
`updatedAt` wins. A pristine device (updatedAt 0) never publishes, so it can't
clobber the cloud copy. Laps go on `<topic>/laps/<hash>`, thinned to ~10 Hz.
Local test broker: aedes over ws, pages
pick it up via `window.GT7_BROKERS`.

## Data Logger (`bridge/`, `app/telemetry.js`, `app/laps.js`)
`bridge/gt7-bridge.mjs` (zero deps) decodes GT7's Salsa20 UDP telemetry
(`bridge/protocol.mjs`, verified against the eSTREAM vector), records laps at
20 Hz into `~/GT7Laps`, serves the app + `/api/*` on :8787 (same origin, so
no mixed-content problem), and streams live frames over SSE. `--demo` encrypts
`data/demo-lap.json` (made by `tools/make_demo_lap.mjs` from real Spa
geometry, in a rotated + mirrored frame) and sends it to itself.
`laps.js align()` identifies the circuit by Procrustes-fitting the lap to
every OSM map (rotation, reflection, scale 0.85–1.15, start offset); the
replay draws in the map's north-up frame via `Tinv`. Laps live in IndexedDB.

## Start Here (`app/start.js`, `data/beginners.js`)
The beginners' course, first in the nav and as a band above the home hero.
Physics chapters embed the Academy widgets (`widgetFor`). The content was drafted
by a Haiku sub-agent and fact-corrected (tyre families, ABS, wheel rotation).
Keep it consistent with the Academy: inputs *blend*, they aren't sequential.

## The priority: tell the player what to do next
Every screen serves `engine.nextSteps()`. Home leads with one big NEXT card
(Do it / Done / Not now, where snooze = 24 h in `s.snooze`), "Then" shows two more,
and `#nextbar` shows the top move on every other page. New data sources
should feed the engine, not just a screen.

## Beyond the Apex (`app/apex.js`, `data/apex.js`)
Polyphony's official GT7 manual (TOC API `gran-turismo.com/us/gt7/api/apex/`,
articles at `/us/gt7/apex<src>`). Each concept is paraphrased, never copied, links
its source article, and is pinned to `demos` = track id + corner indices drawn by
`map.js focusMap`. Tests check every track/corner/lesson reference. Progress lives in
`s.apex`; the roadmap step `apex` sends the engine to the next undriven concept, and
track guides list the concepts demonstrated there.

## Accounts (`app/connect.js`, `app/psn-core.js`, `app/platform.js`)
- PSN: NPSSO → OAuth (PlayStation App client, as psn-api does) → profile,
  GT7 trophies + rarity, play time. Browsers can't call Sony (no CORS), so the
  web app goes through the bridge (`/api/psn/*`; token in `~/GT7Laps/.psn-token.json`,
  0600, never synced). Native shells call Sony directly via CapacitorHttp with
  the same `psn-core.js`. Results (no tokens) go into the synced save as `s.psn`.
- GT7 stats: GT-Gridstats (`gtgridstats.com/api/racers/<psn>`, Bearer token).
  Fetched directly, falling back to the bridge relay. `applyGT` makes GT7
  credits replace typed credits and ticks licence/Sport steps; `applyPSN`
  ticks steps from trophy names. PSN lists the game as "Gran Turismo™ 7".
- `platform.js` is the only place that knows web vs native.

## Direct connection, no bridge (`app/direct.js`, `app/gt7proto.js`, `native/plugin/`)
The iOS/Android app talks to Gran Turismo itself. `native/plugin/{ios,android}`
is the app's own Capacitor plugin `Gt7Direct`: UDP heartbeat to the PS5 (33739,
"~"), packets from 33740 handed to JS as base64 (`packet` events); "auto" sweeps
the Wi-Fi /24 with unicast heartbeats (no iOS multicast entitlement needed).
`gt7proto.js` is the bridge protocol without Node Buffer (tests check it matches
byte for byte) plus the lap recorder; laps are identified by shape and the best
per track lands in `s.logged`. GT7 account: `gt7SignIn` shows gran-turismo.com in a
web view (Sony's PSN login), reads `/us/gt7/info/api/token/`, then JS calls
`web-api.gt7.game.gran-turismo.com/stats/get` with native HTTP; credits/DR found
by key search and applied (`creditsSource: 'gt7'`). Other endpoint names are
tentative; the Connect page shows which ones answered. `native/install-plugin.sh`
wires the plugin into generated projects (npm run ios|android call it). Android
builds here with the SDK (debug APK published at `/gt7/download/` by deploy.sh);
iOS needs Xcode on the Mac. Browsers keep the bridge as a fallback.

## Track studio + reference laps (`app/trackstudio.js`, `tools/reflap.mjs`)
`reflap.mjs` drives a Gr.3-class point mass round each circuit's real geometry on
a minimum-curvature line (14 m track, solved coarse to fine; a Laplacian pull gives
the *shortest* path, not the racing line, so don't swap the update back). Laps sit
within ~1% of Gr.3 benchmarks on average; traced originals run quick. Per-corner
stats are measured at the corner's own tightest point (a wide window catches the
next braking zone). Video chapters come from YouTube's Data API with the player's
own key (`app/ytchapters.js`); scraping watch pages is blocked and off-limits.

## Native (`native/`)
Capacitor shells around this same code (`npm run ios|android` on the Mac).
UI is touch-first: `--tap` 52 px minimum, hover only under `@media (hover: hover)`,
safe-area insets on header/nav.

## Content honesty
Lap benchmarks are estimates (labelled so in the UI). Credit payouts and
Legend prices drift with patches: every number is user-overridable and
the user's value wins. Sources are listed in More → Sources.

## Commands
- Tests: `node gt7/tests/run.mjs` (cross-references, photos, lap ordering,
  map lengths). Must stay green.
- Local: `npx http-server -p 8077` from the repo root → `/gt7/`.
- Deploy: `gt7/tools/deploy.sh "message"` (Pages serves the `gh-pages` branch).
- Photos: `node gt7/tools/fetch_images.mjs [id]`; wrong-variant fixes via
  `tools/commons_pick.mjs list|fetch`.
