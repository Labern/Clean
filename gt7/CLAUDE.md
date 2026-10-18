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
GT originals (Trial Mountain, Deep Forest, …) have no geometry: `map: null`,
drawn as a lap strip with estimated corner positions. Never fake a map for them.

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
