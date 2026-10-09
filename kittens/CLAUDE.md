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
