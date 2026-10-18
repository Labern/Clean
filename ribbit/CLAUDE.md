# ribbit

Ribbit: a Tamagotchi-style frog pet, born from a lily. Kawaii look (Sanrio-
inspired proportions, but an original character — never copy Keroppi).
Live at https://labern.github.io/Clean/ribbit/ — installable PWA.
Designed first on the claude.ai Design canvas "Frog Pet"
(https://claude.ai/artifact/QFW1GK2jMw6raEdDXzKk8N); the app is the
playable build of those artboards.

## Files
- `index.html` — everything (inline CSS/JS, no build). Art is inline SVG:
  `frogSVG({mood, wear, color, stage})` and `ART[kind]` (48×48 treats,
  items, friends). Blink/breathe/hop are CSS animations on `.blink`,
  `.breathe`, `.frog.hop`.
- `manifest.webmanifest`, `sw.js` (network-first, cache fallback),
  `icon-192/512.png` (Playwright render of `frogSVG`).

## Game rules (all in `index.html`)
- State lives in `localStorage['ribbit.v1']`, per device. Default name is
  Ribbit; the player names the frog on the lily screen and can rename in
  Growth → Settings.
- `tick()` applies real elapsed time: tummy −5/h (−2.5 at night), joy −3.5/h
  (−2 in rain, +0.125/h per placed decoration), energy −3/h by day, +9/h at
  night (19:00–07:00). Nothing ever dies; the worst mood is Lonely.
- Stars: +2 per cuddle (20 s cooldown), daily +10 bonus, baking, gifts.
  Strawberries are free and unlimited so the frog can always eat.
- Growth = consecutive care days (`careDays`): 3 → Sprout, 10 → Full Bloom.
- Friends: Shelly (rain, or 1 day in 3), Dot (joy > 80), Bumble (baked
  today); each visits once a day with a gift.
- Bakery: 15-min oven cooldown; daily craving = hash(date + name).
- Live weather is opt-in (geolocation → open-meteo, cached 30 min).

## Deploy
Same as the other Clean apps: commit to `master`, then copy `ribbit/` onto
the hand-curated `gh-pages` branch (worktree), commit `Deploy Ribbit: …`, push.
