# ★★★★★ × PARADOX — Command Centre

A single-file web app (`index.html`, no build, no deps) that is **the room the
company acts from**. Not a dashboard about the work — the place you enter to do it.

## The shape

- **The threshold** — an entrance condition. You cross it (click / Enter) before the
  room exists. Crossings are counted and timestamped; `⌫ leave the room` / `Esc`
  puts you back outside and stops the desk clock.
- **01 COMMAND** — the wall: CURRENT CAMPAIGN · NOW · NEXT · CANON · POWER.
  Live information only, never slogans. Meters are click-to-set (0 = we don't have it).
- **02 THE MAKING DESK** — one focus line, a clock-in/clock-out session timer with a
  log, the machines this project requires, and the rule of the surface.
- **03 THE TABLE** — a drag-anywhere surface. Cards carry a kind (NOTE · SCRIPT ·
  IMAGE · OBJECT · PLAN) that colours their left accent. The point is seeing twenty
  things at once, which a screen otherwise refuses to do.
- **04 THE ARSENAL** — two shelves. CURRENT STUDY is the visible one; ◇/◆ moves an
  item between them. REFERENCE ≠ CURRENT STUDY is the whole design.
- **05 THE REVIEW WALL** — pinned work gets a verdict in the company's voice
  (HOLD · REWORK · NOT YET · → CANON). **→ CANON moves the item onto the command
  wall** — that connective tissue is the point: the room accumulates its own history.

Keys: `1`–`5` switch territories · `Esc` leaves the room · `Enter` commits an edit.

## Rules that hold

- **Never lose progress.** State lives in `localStorage` under
  `paradox.commandcentre.v1`, hydrated over `DEFAULTS` by `merge()` — additive only.
  New fields get a default; existing saved data is never wiped or migrated
  destructively. Test an upgrade against a populated store before shipping.
- **Themeable via tokens.** Every colour is a CSS custom property on `:root`.
  Re-theme the entire room by overriding tokens on one ancestor class — see
  `.theme-ember`. Never hard-code a hex in a component rule.
- **The house style is PARADOX terminal** — spec at `~/Desktop/★★★★★/STYLE.md`.
  Monospace, box-drawing card grammar, `▰▱` meters, gold = titles, teal = primary,
  violet = identity, pink = alert.
- **Nothing leaves the device.** No network calls, no analytics, no external assets.
  Whatever POWER or CANON eventually holds stays in this browser.

## Working on it

Delegate fan-out work to **sub-agents** — searching prior art across Clean, sweeping
the ★★★★★ vaults, any noisy investigation. Keep this context for the room itself.

Serve it with `python3 -m http.server --directory .` and verify in a **new** Chrome
window (never take over a tab in use). Deployed at
`labern.github.io/Clean/command-centre/` from the `gh-pages` branch.
