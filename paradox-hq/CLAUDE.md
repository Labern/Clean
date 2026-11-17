# PARADOX HQ

The iOS app (SwiftUI) that runs ★★★★★ × PARADOX from the phone: what came in,
what needs a decision, and what every project needs next.

**Lives here for now.** Clean is public; this folder moves to the company's
private repo as soon as that exists. Until then: no keys, no tokens, no account
details in any file. The Stripe key and the feed token are typed into the app
and kept in the Keychain on the phone.

## Layout (Labern/iOS pipeline)
- App: `ios/` — `project.yml` is the source of truth; the `.xcodeproj` is generated
  (`xcodegen generate`) and gitignored. Swift 6, iOS 26, bundle `com.labern.paradox.hq`.
- On the Mac: `~/Desktop/Clean/iOS/bin/ios-run ~/Desktop/Clean/paradox-hq/ios`.
- Cloud: `.github/workflows/paradox-hq-ios.yml` builds, tests and screenshots every
  screen on any push that touches `paradox-hq/ios/`, then force-pushes the results to
  `ci/paradox-hq` (`git fetch origin ci/paradox-hq`). `result.txt` holds the compiler
  errors. Launch arguments: `-unlocked YES -screen lock|today|money|projects|project|company`.

## The four tabs
- **Today** — the mark, today's takings over a 30-day trend, this month and the
  Stripe balance, *Needs you* (disputes, failed payments, deadlines inside 30 days,
  the site being down; hidden when empty), and the next open line of each project.
- **Money** — revenue by week, month, quarter or year against the same stretch of
  the period before; subscribers and monthly recurring; payouts; every payment.
- **Projects** — each project has a Focus list. Lines tick, edit, take a note and
  sub-items. Ticking the last sub-item ticks its parent; reopening one reopens it.
- **Company** — filing deadlines, the three connections (Stripe, Claude, website),
  the Face ID lock.

## Sources
- `Stripe.swift` — Keychain, Stripe's JSON, the client. **Read-only**: there is no
  call in the app that can move money. Charges are required; balance, payouts,
  disputes and subscriptions are each left empty if the key can't read them.
- `MoneyStore.swift` — `Period`, `Ledger` (all the sums, pure and tested), the
  example figures, the store. Example figures are deterministic and always labelled.
- `Feed.swift` — the Claude feed (below), the first-launch seed, the site check.
- `Models.swift` — SwiftData: `Project`, `FocusItem`, `Deadline`. Additive-only
  schema, every property defaulted. Never lose a line.
- `Lock.swift` — Face ID / passcode at launch and after 30 seconds away. The mark
  covers the app in the app switcher.
- `Theme.swift`, `Components.swift` — the look.

## The Claude feed
`ios/Resources/feed.json` is the list of projects and their Focus lines. It seeds
the first launch, and it is the file a Claude session edits to put work on the
phone: add a project, add a line, set `"done": true`. The app pulls the hosted copy
(address set in Company ▸ Claude; a token there reads it from a private repo through
GitHub's contents API) on every open and on pull-to-refresh.

Merging only adds and ticks. It never unticks a line, never deletes one, and never
touches a project made on the phone. Ids are permanent: change a line's wording by
keeping its id; a new id is a new line.

## The look
The Focus site's tokens (black, `#1A1A1A` surfaces, white and greys, one hazard red
`#ED4E3B`), with the Focus icon's violet `#A78BFA` and green `#5FD7AF`. Headings are
large and white with a white line under. Solid white is the one primary button on a
screen. SF Pro throughout. Dark only: the brand is the black box.

**The mark is never redrawn.** `Mark.imageset/mark.svg` is ★★★★★ × over PARADOX with
™ top right, built from the outlines in `logo-experiments/logos.js`. The proper
masters are on the Mac at `~/Documents/Codex/2026-09-17/t/outputs/PARADOX_Logo_Library/`;
swap the master in when on the Mac. Do not adjust spacing, order or glyphs.

## Rules
- Apple's Human Interface Guidelines govern the design: `paradokkusu/docs/APPLE-HIG.md`.
- No instructional hint text in the UI.
- Xcode project, automatic signing under Labern's team. Never hardcode a Team ID.
- Tests are Swift Testing (`ios/Tests`), run by the cloud build.

## Not built yet
Lock Screen and Home Screen widgets, and payment notifications (these need an App
Group and a small server for Stripe webhooks). Sending the phone's ticks back to
the feed.
