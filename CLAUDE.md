# CLAUDE.md

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

## Commands
Top-level dir: none — `index.html` is static, just `open` it.
For `ClaudeUsageMonitor/`, see that subsection.

## Conventions
- Keep `index.html` a single self-contained file unless the project grows
  enough to justify splitting out CSS/JS — don't add a build tool prematurely.
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
- NEVER create or write a file via shell redirection (`>`, `tee`, etc.) or any
  other method that silently overwrites, without first checking whether the
  file already exists and reading it if it does. A session once ran
  `printf ... > .gitignore` and wiped the repo's existing .gitignore. Use the
  Read-then-Write/Edit tools for file changes — their overwrite guard exists
  for exactly this reason. The same applies to remote refs: check what exists
  before pushing (a gh-pages branch with live sites already existed here).
