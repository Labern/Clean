# cycle

One-page menstrual-cycle mood tracker — rainbow sticker style (shared DNA with
`political/`). Single file: `index.html`. No build, no deps, no server.

## What it is

The point of the app: show **when moods are likely to be worst**. Moods ramp
through the luteal phase (red, deepening), hit their worst **5 days before
menstruation** (⚠ danger zone — last 5 luteal days, hazard-striped), then
**break on day 1** of bleeding (🌈 THE BREAK) and are fine again. Everything
else — phases, calendar, notes — supports that one arc.

- Phases: menstrual (pink) / follicular (green) / ovulation (gold ⭐, unique) /
  **luteal (red — the star)**. Ovulation is anchored ~14 days before the next
  period (luteal is the fixed-length phase — real physiology).
- Multiple recorded period starts, marked by tapping calendar days. Past
  cycles render from their **real** lengths; future is predicted from the last
  start + the cycle-length slider (default 28, exact numbers shown).
- Notes per day (tap a day), mood-weather tooltips on hover, 1/2/3/6-month
  views, full-cycle rainbow ribbon that tracks hover.
- **Sharing:** whole state (starts, lengths, notes) is base64url-encoded into
  `#s=…` in the link — no server. Opening a shared link imports it as a
  persistent read-only "💞 theirs" view alongside "👤 mine".

## State

`localStorage['cycle.state.v1']` — `{starts, cycleLen, periodLen, monthsView,
notes, name, theirs, view}`. **Never lose progress:** additive-only schema,
hydrate-over-defaults; never wipe or rename keys, only add optional ones.

## Deploy

Lives in the Clean repo (public). Serve = GitHub Pages via Clean's `gh-pages`
branch: checkout `cycle/` from master onto `gh-pages`, commit
`Deploy cycle: <desc>`, push. Live at https://labern.github.io/Clean/cycle/

## Working here

- Use sub-agents freely: fan-out searches, independent parallel work, and any
  noisy/large investigation should be delegated so the main context stays lean.
- Keep it one file; keep every colour a CSS token in `:root` (themeable).
- UK spellings in copy (oestrogen, colour).
