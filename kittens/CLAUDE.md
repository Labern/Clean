# kittens

Tracker for Misato (white) and Pen Pen (black) — the lemon and the girl's
kittens. Lemon Counter styling (`lemons.html` on gh-pages): vertical rainbow
gradient, Comic Sans, white cards with thick black borders. `sol-lemon.png` is
copied from gh-pages root. Live at https://labern.github.io/Clean/kittens/

## Files
- `index.html` — everything (inline CSS/JS). Cartoons are inline SVG
  (`kittenSVG`, `girlSVG`, drawn from their real photos: Pen Pen is a
  tuxedo, Misato white with black patches); kittens are drawn to scale with
  each other (width ∝ ∛weight, from `estNow`).
- `vendor/mqtt.min.js` — copied from `cycle/vendor/`.
- `manifest.webmanifest`, `sw.js`, `icon-192/512.png` — installable PWA +
  offline shell (network-first, cache fallback). Icons are a Playwright
  render of the two cartoons (`scratchpad/icon.mjs` in the session).

## Layout rule
The page is two halves. **Everything above the `✨ Extras` divider is the
original and stays as it was** (the user asked for it preserved); new
features go below the divider, in `renderExtras()`, with their own
collections. The only touches above the divider since: the `🔍 Zoom in`
button on the weight card, `lastFed` written by the meal counters, and
`seedExtras()` called from `seed()`.

## Extras (below the divider)
- 💬 Chat (`msgs`): bubbles 🍋/🌙, status chips (fed/tray/water/play also
  bump the Today counters; `fed` sets `meta.lastFed`), pins, ❤️ reactions,
  photo replies, unread badge on the nav (`kittens.lastread` per phone).
  Optional ntfy pings: topic in `meta.ntfy`, on/off per phone
  (`kittens.ntfyOn`); the ping body never contains the message.
- 🎂 Birthday: writes `dob`/`dobEst` to both kittens — every age, chart,
  to-do due date (`dueAge`), guide band and stage box derive from it.
- 🩺 Health (`health`, id `<date>_<kitten>`): 4 metrics × good/meh/bad;
  any `bad` shows the call-the-vet alert.
- 💷 Costs (`costs`): balance sign convention = + means girl owes lemon;
  `cat:'settle'` records are settle-ups and are excluded from totals.
- 📆 Reminders: builds an `.ics` from open dated to-dos (UID = todo id, so
  re-adding updates rather than duplicates), alarms -PT15H and PT9H.
- 🗓 Rota (`meta.rota`, key `<Day><duty>`), 🎓 Training (`skills`, seeded
  with fixed ids), 🎞 Flipbook (photos with `flip:true`).
- 🧳 Sitter page: `#sitter=<base64url JSON>` renders a read-only sheet.
  `SITTER` short-circuits `save()`, `initSync()` and the whole normal boot.
- 🐾 Motion: per-device watcher (`kittens.watch`) diffing 64×36 greyscale
  frames of Snapshot/MJPEG cams; needs CORS on the bridge; one catch per
  10 min per cam → photo + event.
- 🔍 Weight zoom (`#wzoom`): range toggles, series toggles, projection,
  milestone lines, g/day bars, editable table, CSV.

## Data
`localStorage['kittens.state.v1']` = doc of collections (`COLS`), each a map
id → record with `u` (updated-at ms). Merge = per record, newest `u` wins;
deletes are tombstones `{del:true,u}`. Seed records have fixed ids + `u:1`
so two phones seeding independently never duplicate. **Additive only** —
never rename/drop collections or keys.
Photos: `kittens.img.<id>` (JPEG data URL, shrunk to 900px); meta in `photos`.
Per-phone only: `kittens.me` (lemon/girl), `kittens.secret` (sync key).

## Sync
Retained MQTT messages on the same 3 public brokers as `cycle/`, but
AES-GCM encrypted with a key derived from `secret`, topic = hash of secret.
Pairing link carries the secret in `#pair=` (never sent to a server). Photos
on `<topic>/img/<id>`. Each phone republishes the merged doc on connect, so
the brokers are a meeting point, not the store. `window.KT_BROKERS` overrides
the broker list (used for local testing with aedes).
Seed: born ~2026-08-19 (estimated: ~6 wks when weighed Wed 30 Sep 2026 —
Misato ~700g, Pen Pen ~600g).

## Deploy
gh-pages worktree: copy `kittens/` (minus this file) onto `gh-pages` —
including `manifest.webmanifest`, `sw.js` and the icons —
commit `Deploy kittens: <desc>`, push.

## ⛔ THE RULE — append only, never lose anything (user's standing instruction)
Anything any version adds must be **appended**, and must be **silently kept**
when the user opens an older version — always present, forever.
- Add collections and fields; never rename, repurpose or remove them.
- `mergeRec()` (identical in v1 and `shared/core.js`) keeps every field that
  only the older side has, so an old version's edit can't drop a newer
  version's field. Deletes are whole tombstones.
- To clear a field, set it to `null`/`''` explicitly — a merely *missing*
  field is always refilled from the other copy (the weight app's Undo does this).
- `node kittens/tests/compat.mjs` (31 checks) must pass on every change; it
  also fails if v1's and core's merge code ever differ.

## Versions (all share ONE dataset — this is the priority)
- `kittens/` = v1 (the full original), `kittens/v2/` = streamlined v2,
  `kittens/weight/` = the weight app. Same origin → same localStorage keys
  (`kittens.state.v1`, `kittens.img.*`, `kittens.secret`, `kittens.me`) →
  same data with no import step, and the same encrypted sync topic.
- v2 + weight app load `shared/core.js` (v1's data/sync code extracted
  verbatim) and `shared/theme.css` (v1's stylesheet). v1 keeps its inline copy.
- **Forward-compat rules (don't break):** `merge()` keeps collections it
  doesn't know (v1 was patched to do this too), and `save()` merges with
  what's on disk first (stale tabs of any version can't clobber). New
  versions may ADD collections/fields, never rename or remove. Extra fields
  on weight records (`time`, `note`, `fed`, `photo`, `guess`) are preserved
  by every version because records are merged whole.
- v2 adds the `bond` collection ({k, by, date, at, score 1–5, tags, text}).
- Weight-app view prefs are per phone under `kittens.wapp.*` (not synced).
- Growth model for long-range dates: `refCurve`/`projCurve`/`whenReaches`
  in core (typical curve scaled to the kitten's latest weight).
- Tested: cross-version (v1 → v2 → weight app → v1, stale v1 tab) and
  3-phone sync over a local aedes broker (`window.KT_BROKERS`).

## The weight app (kittens/weight/)
Rebuilt as scenes: ⚖️ drum scale (drag to spin, 1 turn = 500 g; the dialled
value is a live "ghost" weigh-in on the chart via `withGhost()`), 📈 chart
(SVG re-measured to real pixel width each draw; drag = time playhead, brush =
zoom window, sliders = future pace / look-ahead / smoothness; monotone-cubic
`smoothPath`), 🏁 race, 🎢 damped-spring seesaw, 🌀 Archimedean growth spiral
(constant day spacing — a 7-days-per-lap angle makes spokes, not a spiral),
🔢 numbers, 📋 editable log + undo, 🎞 photo film strip.
`weight/classic.html` = the previous tabbed version, kept.
- Gotcha: `shared/theme.css` is v1's stylesheet and contains `#chart text
  {fill;font-size}` which overrides SVG attributes — that's why the weight
  app's chart is `#gchart`. Don't reuse v1 ids (#chart, #tip, #week…) in new SVGs.
