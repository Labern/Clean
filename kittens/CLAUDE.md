# kittens

Tracker for Misato (white) and Pen Pen (black) — the lemon and the girl's
kittens. Lemon Counter styling (`lemons.html` on gh-pages): vertical rainbow
gradient, Comic Sans, white cards with thick black borders. `sol-lemon.png` is
copied from gh-pages root. Live at https://labern.github.io/Clean/kittens/

## Files
- `index.html` — everything (inline CSS/JS). Cartoons are inline SVG
  (`kittenSVG`, `girlSVG`); kittens are drawn to scale with each other
  (width ∝ ∛weight, from `estNow`).
- `vendor/mqtt.min.js` — copied from `cycle/vendor/`.

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
gh-pages worktree: copy `kittens/` (minus this file) onto `gh-pages`,
commit `Deploy kittens: <desc>`, push.
