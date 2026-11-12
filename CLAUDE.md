# CLAUDE.md

## ALWAYS — end every reply with the live link(s)
Every reply must END with clickable links to the thing currently being worked
on ONLY (its live GitHub Pages URL, plus its code location) — NOT every
project. The user corrected this: "the link of the thing we're working on,
not all the links." Reference list, pick the relevant one(s):
Flap Guard (cat flap chip lock):
- https://labern.github.io/Clean/catflap/
- Code: https://github.com/Labern/Clean/tree/master/catflap
For the kittens project:
- The weight app: https://labern.github.io/Clean/kittens/weight/
- v2: https://labern.github.io/Clean/kittens/v2/
- Original (v1): https://labern.github.io/Clean/kittens/
- Classic weight app: https://labern.github.io/Clean/kittens/weight/classic.html
- Data check: https://labern.github.io/Clean/kittens/check/
- Code branch: https://github.com/Labern/Clean/tree/kittens-v2
For GT7 Endgame:
- The app: https://labern.github.io/Clean/gt7/
- Sector Trainer: https://labern.github.io/Clean/gt7/#/ce
- Code branch: https://github.com/Labern/Clean/tree/master/gt7
For Focus (macOS menu bar app, no web page):
- Code: https://github.com/Labern/Clean/tree/claude/quirky-dirac-h70tbn/focus
Add any new page to this list the moment it ships.

## Project
A sandbox directory, not a formal app. Currently contains a single static
demo page (`index.html`) built during a Claude Code session — a hero
section plus a "how Claude Code works" explainer section, pure HTML/CSS/JS,
no build step, no dependencies.

## Structure
- `index.html` — the whole site (inline `<style>` and `<script>`, no separate
  assets). Open directly in a browser, no server needed.
- `file` — an empty test file from early in the session. Safe to ignore or delete.
- `ClaudeUsageMonitor/` — a macOS menu bar app (Swift Package, SwiftUI) showing
  a live "% of Claude plan used" gauge. See its own section below.
- `fullres/` — FullRes: send photos/videos via WhatsApp at original quality
  (share-as-document trick, zero compression). Single-file web app, live at
  `labern.github.io/Clean/fullres/`. See `fullres/CLAUDE.md`.
- `restore/` — Revive: drop in scanned photographs (one or a hundred), get them
  back cleaned, sharpened, colourised. Live at `labern.github.io/Clean/restore/`.
  **No longer single-file**: `index.html` (UI) + `engine.js` (compute core,
  shared) + `worker.js` (runs every heavy stage off the main thread) + `ort/`
  (vendored onnxruntime-web) + `colorize.onnx` and `models/` (quantised model
  weights). Nothing is uploaded — the models come to the photograph.
  - Classical DSP does the cleanup: dust, scratches, fade, cast, grain, upscale.
  - Two learned models do what classical cannot, **both on by default**:
    GFPGAN for faces (the only thing that can fix focus) and DDColor for colour.
  - See `restore/CLAUDE.md` before changing anything. Its suite
    (`node restore/tests/run.mjs`, 71 assertions) must stay green, and the
    calibrated constants documented there each encode a real bug — don't
    "tidy" them. Read in particular the sections on orientation, on the two
    bugs that presented as "it does nothing", and on the do-no-harm gate.
- `kittens/` — Misato & Pen Pen tracker (age, weight chart, moments, food,
  to-dos, shopping, Ring cam framework, photos), encrypted two-phone sync.
  Live at `labern.github.io/Clean/kittens/`. See `kittens/CLAUDE.md`.
- `Raven/` — a dashboard for the Tesla's own browser (2019 Model S Raven):
  Google Maps → send to nav, WhatsApp names on screen, Spotify control, drive
  stats, live-location sharing. OEM Tesla look (Universal Sans/Inter, Tesla
  neutrals, one blue). ES modules, no build; `node Raven/tests/run.mjs`.
  Live at `labern.github.io/Clean/Raven/`. See `Raven/CLAUDE.md`.
- `pica/` — PICA: screenplay editor that imports Final Draft PDFs and reproduces
  them identically, with the full Tab/Enter typing grammar. Single-file web app,
  live at `labern.github.io/Clean/pica/`. See `pica/CLAUDE.md` — its fidelity
  test (`node pica/tests/run.mjs`) must stay at 100% on every engine change.

- `gt7/` — GT7 Endgame: Gran Turismo 7 companion (next-move engine, 25 track
  guides on real OSM geometry, garage + credit engine, academy, wheel lab,
  heritage). ES modules, no build; `node gt7/tests/run.mjs`. Deployed via the
  `gh-pages` branch to `labern.github.io/Clean/gt7/`. See `gt7/CLAUDE.md`.

- `catflap/` — Flap Guard: spec/mock-up page for a ~£22 ESP32 + WL-134 FDX-B
  reader + servo add-on that keeps the kittens (Misato, Pen Pen) from exiting
  via the existing 4-clip cat flap. Rule: exit locked by default, any non-kitten
  chip unlocks 4 s, a kitten read locks + vetoes 15 s. Single file, deployed to
  gh-pages `/catflap/`.

- `ribbit/` — Ribbit: kawaii frog pet born from a lily (treats, cuddles,
  shop, decorating, friends, bakery, growth, day/night/rain). Single-file PWA,
  live at `labern.github.io/Clean/ribbit/`. See `ribbit/CLAUDE.md`.

- `focus/` — Focus: macOS menu bar app. Saves every open app as a session and
  quits or hides it; apps the user excludes stay open. While focused, ⌘⇥ only
  cycles what's still open (native switcher disabled via private
  `CGSSetSymbolicHotKeyEnabled`, same as AltTab — re-enabled on every launch/quit/
  signal). Past sessions reopen from the menu. One Swift file, Carbon hotkeys, no
  permissions; `./focus/build.sh` builds and launches `Focus.app` (Mac only).
  ⌘⇧F start session / bring back; ⌘⇧E opens the menu (user's picks, 2026-11-12). Sessions quit apps
  ONE AT A TIME, biggest first, normal quit (state saved, prompts honoured), wait until gone, never
  forced; restore relaunches one at a time (Chrome with --restore-last-session). Menu rows show memory;
  big button caption shows quits/frees/keeps live. "Critical System Processes" (was "Never close" — user found that name cringe) is a window (SwiftUI) + a menu section BELOW the app list
  System apps (/System/Library/CoreServices), menu-bar-only apps and Focus are always safe.
  NEVER touch the system ⌘⇥ again: an earlier build disabled it via CGSSetSymbolicHotKeyEnabled and the
  user lost ⌘⇥; launch now only re-enables it. Hiding OTHER apps from Dock/⌘⇥ is not possible cleanly:
  _LSSetApplicationInformationItem returns 0 but is ignored for foreign pids (tested 2026-11-12); editing
  Info.plist + re-sign would wipe the app's TCC grants. (No seeded apps.)
  (Superseded 2026-11-12: Claude-terminal detection REMOVED — see "No user-specific hard-coding" below.) (claudeHosts: ancestors of the `claude`
  process, matched by proc_name/path — p_comm is the version string). Process lists come from sysctl
  KERN_PROC_ALL: proc_listallpids silently skipped processes.
  Snapshot: screencapture of the main display at session start → ~/Library/Application Support/Focus;
  rule (user's): keep the newest + one spare, delete older. Thumbnail tops the menu while in session.
  Main list shows every Dock app except critical ones; every row toggles on click and the menu stays open.
  Single instance: a second launch exits. `Focus.app/Contents/MacOS/Focus --selftest` runs the real
  session path on TextEdit only (own defaults suite + folder; aborts if anything else would quit).
  ⌘⇧F must be INSTANT: the session pill (SessionPill — zop, hit stop, icons sucked into the menu bar icon,
  zip; reverse on End Session) plays at once; the snapshot runs async and only if
  CGPreflightScreenCaptureAccess() — NEVER let it prompt (user hit a prompt on every press). The one ask is
  Settings ▸ "Allow snapshots…". `--pill-demo X Y` plays both shows without a session.
  App icon: generated at build by `Focus --make-icon` from the same glyph() (rest state, white on near-black).
  NO custom ⌘⇥ switcher — user rejected it outright ("use the native Command-Tab"); built + removed 2026-11-12.
  Tools submenu: Quit All Apps, Quit All & Restart Mac (restarts only once every app has quit), Force Quit All
  (red confirm), Open Activity Monitor, Open System Settings. All spare Critical + Claude's terminal; "keep open"
  ticks don't apply; each is saved to Past sessions (kind: quit all / force quit). Disabled during a session.
  Save prompts never stall a queue: after `patience` (8 s) the app goes on `waiting`, the queue moves on, and at
  the end the waiting app is brought forward with its prompt. `--selftest-unsaved` proves it with a stand-in app
  that refuses to quit (build it in a temp dir — see git log).
  Chrome is relaunched with --restore-last-session (user's Chrome is set to New Tab page) AND
  --autoplay-policy=user-gesture-required — restored YouTube must not autoplay.
  Signing order: Developer ID → Apple Development (stable TCC on this Mac) → local → ad-hoc. Self-test copies
  hide their status item under autosaveName "focus-selftest" — hiding under the default name hid the REAL icon.
  Icon colour: default for everyone is WHITE (template image); the user's own purple ring + green dot
  (A78BFA / 5FD7AF) is HIS saved setting, not the default. New users get one hint row ("Make the icon yours…")
  until any colour is picked (colourTipSeen).
  NO USER-SPECIFIC HARD-CODING (user's rule): Focus is being built to sell/release. Nothing about the user's own
  apps (Claude, Terminal, Wispr Flow, Mu…) lives in code, seeds or wording — protection comes only from saved
  lists (Critical System Processes / keep-open) plus built-in safety for macOS system apps, menu-bar-only apps and
  Focus. UI copy names apps from those lists (staysOpen()). His own setup lives in his defaults only.
  Release polish: strip any stock-AI wording from every UI string before shipping.
  Customised Logo (Settings ▸ Icon Colour): the app's own icon in the user's colours (logoBg/logoMark), drawn by
  appIconRep() — same code as the standard icon — and set with NSWorkspace.setIcon on the installed bundle;
  re-applied at launch because a reinstall replaces the bundle. Signature still verifies with it attached.
  VERSIONING: semver in focus/VERSION (build.sh stamps it into Info.plist; menu shows it). CHANGELOG.md per release;
  tags focus-vX.Y.Z. Features on focus/feat-<name> branches cut from focus/main; fixes bump PATCH, features MINOR.
  build.sh builds/signs in $TMPDIR — iCloud re-adds xattrs on ~/Desktop and codesign fails intermittently.

- `iOS/` — the iOS app pipeline (nested **private** repo, `github.com/Labern/iOS`,
  gitignored here). XcodeGen template + `bin/ios-*` scripts: scaffold, run in the
  Simulator, test, install on a phone, upload to TestFlight. New iPhone apps live at
  `<Project>/ios/`. See `iOS/README.md`.

## Commands
Top-level dir: none — `index.html` is static, just `open` it.
For `ClaudeUsageMonitor/`, see that subsection.

## Conventions
- Keep `index.html` a single self-contained file unless the project grows
  enough to justify splitting out CSS/JS — don't add a build tool prematurely.
  (`restore/` has outgrown this and is now several files; that was forced by
  needing a Web Worker, which cannot share code with the page any other way.)
- The terminal/monospace house style below applies to the older pages.
  `restore/` deliberately departs from it — plain system font, near-monochrome
  — because it was rebuilt to put the photograph first and the chrome nowhere.
- Visual style: dark gradient background, monospace/terminal-flavored type,
  teal/violet/pink accent palette (`#5eead4` / `#a78bfa` / `#f472b6`), glassy
  bordered cards. Match this look across both the webpage and the menu bar app.

## ClaudeUsageMonitor (macOS menu bar app)
A SwiftUI `MenuBarExtra` app that estimates "% of your Claude plan used" as a
gradient gauge, instead of showing raw tokens/dollars (explicitly what the
user did *not* want as the headline metric).

- **Data sources:**
  - Local token usage: tails every `~/.claude/projects/**/*.jsonl` transcript
    on this Mac every second, dedupes by message id, and converts tokens to
    an internal "weighted cost" using real per-model pricing + cache
    read/write multipliers (`App.swift`). This $-equivalent is never shown
    to the user directly — it's only the unit used to interpolate drift.
  - Real plan %: there's no public API for an individual's Claude.ai plan
    quota. Instead, the app embeds a logged-in `WKWebView` (`WebScraping.swift`)
    — user logs into claude.ai once, picks the % element on their usage page
    by clicking it, and the app stores that CSS selector + URL. A headless
    `WKWebView` then re-reads that selector immediately after every turn
    (throttled to once every 12s via `scrapeCooldown` so a burst of tool
    calls in one turn doesn't fire repeated page loads), plus a 60s safety-net
    timer in case turns are infrequent. No fixed long-interval polling.
  - Calibration: each time a fresh % is scraped, the app computes
    `% delta / weighted-cost delta` since the last scrape to learn a
    "percent per dollar-equivalent" factor, then uses that factor to
    interpolate the live % between scrapes based on local token activity
    (this part already updates every second, independent of scrape timing).
- **Insights window** (`Insights.swift`, opened via the sparkle icon in the
  popover): scans every local `.jsonl` transcript across all projects,
  groups by session/conversation, and surfaces rule-based recommendations —
  busiest conversation, cost concentration, cache-reuse efficiency, % of
  plan burned across recent sessions, and rising cost-per-turn trend. No
  LLM call involved, purely local statistics over real token data.
- **Packaging:** must run as a proper `.app` bundle, not the bare binary —
  WKWebView's persistent cookie/session storage is keyed to the bundle
  identifier. Build with `./build_app.sh` (wraps `swift build -c release`,
  writes `Info.plist` with `LSUIElement` so there's no Dock icon, ad-hoc
  codesigns). Launch via `open ClaudeUsageMonitor.app`, not the raw binary.
- **Persisted state:** `~/Library/Application Support/ClaudeUsageMonitor/state.json`
  (sync anchor, calibration factor, saved selector/URL).
- **RECENT TURNS list & time labels** (in `App.swift`):
  - `recentTurns` is kept sorted by `timestamp` descending (NOT by file /
    processing order). On launch the tailer reads every transcript's full
    history from offset 0, so without the sort a background session processed
    last would push the live turn off the top — this is what caused "it shows
    sonnet when I'm on opus": a background Sonnet turn was displacing the live
    Opus one. `lastTurn` / `lastTurnPercentImpact` only update when the incoming
    turn is the chronologically newest.
  - Transcript timestamps carry fractional seconds (e.g.
    `2026-06-18T00:37:42.925Z`). Parse them with `parseUsageDate`
    (`UsageCore/DateParsing.swift`), NOT a bare `ISO8601DateFormatter` — the
    bare formatter silently fails on fractional seconds and falls back to
    `Date()`, making every turn read as "now"/stale. `parseTurnUsage` uses
    `parseUsageDate`; there's a regression test in `UsageTests.swift`.
  - `relativeTime(_:relativeTo:)` has seconds-level granularity ("just now"
    <5s, "Xs ago", "X min ago", "X hr ago", "X days ago") and is ALWAYS
    computed from the real timestamp — never hardcode "just now" for a row
    (the user is sensitive to fake/stale labels; see auto-memory).
  - Refresh re-ages the labels: `UsageMonitor.now` is a `@Published Date`
    bumped in `refreshNow()` and threaded into `RecentTurnRow` as an input.
    SwiftUI memoizes a row's body and won't re-run `relativeTime` unless one of
    the row's inputs changes, so the reference date must be passed in explicitly.
  - `<synthetic>` appears as a `model` value in some transcript lines (zero-token
    system messages); it has no pricing entry so `weightedCost` is 0 — harmless.
- **Known fragility:** the scraper depends on Anthropic's usage-page DOM
  structure not changing. If auto-sync starts failing, the UI surfaces
  "Reconnect" so the user re-picks the element — there's no way to make this
  more robust without an official API.

## Gotchas
- This is now a git repository (`main` is the primary branch; work has happened
  on `master`). History is shallow — there's still little to fall back on, so be
  careful with large rewrites.
- `main.swift` is intentionally named `App.swift` in this package — Swift
  treats a file literally named `main.swift` as implicit top-level code,
  which conflicts with the `@main` attribute used here.

## Do NOT
- Don't introduce a framework/bundler for what is currently a one-page demo.
- Don't delete `file` or `index.html` without checking with the user first —
  this directory's contents were built interactively and may still be in use.
