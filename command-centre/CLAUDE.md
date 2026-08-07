# ★★★★★ × PARADOX Command Centre

A native macOS app (`mac/CommandCentre.swift`, SwiftUI + AppKit, one file, no
dependencies, built by `swiftc`) that is **the room the company acts from**. Not a
dashboard about the work — the place you enter to do it.

`mac/` is the product. `web/index.html` is an earlier single-file web sketch of the
same design, kept only as reference — it is not deployed and not the deliverable.

## The shape

- **The threshold** — an entrance condition. You cross it (click / Return) before the
  room exists. Crossings are counted and timestamped; `⌘⌫` or *Room ▸ Leave the room*
  puts you back outside and stops the desk clock.
- **01 COMMAND** — the wall: CURRENT CAMPAIGN · NOW · NEXT · CANON · POWER.
  Live information only, never slogans. Meters are click-to-set (0 = we don't have it).
- **02 THE MAKING DESK** — one focus line, a clock-in/clock-out session timer with a
  log, the machines this project requires, and the rule of the surface.
- **03 THE TABLE** — a drag-anywhere surface with its own grain. Cards carry a kind
  (NOTE · SCRIPT · IMAGE · OBJECT · PLAN) that colours their left accent. The point is
  seeing twenty things at once, which a screen otherwise refuses to do.
- **04 THE ARSENAL** — two shelves. CURRENT STUDY is the visible one; ◇/◆ moves an
  item between them. REFERENCE ≠ CURRENT STUDY is the whole design.
- **05 THE REVIEW WALL** — pinned work gets a verdict in the company's voice
  (HOLD · REWORK · NOT YET · → CANON). **→ CANON moves the item onto the command
  wall** — that connective tissue is the point: the room accumulates its own history.

Keys: `⌘1`–`⌘5` walk the territories · `⌘⌫` leaves the room. They are Command-modified
so they never collide with typing into the walls.

## Rules that hold

- **The window draws no chrome.** It is an ordinary titled, resizable NSWindow with a
  transparent title bar; the traffic lights are the system's own. It opens at
  `NSScreen.visibleFrame` — filling the screen, not taking it over as a Space.
- **Never lose progress.** State is `~/Library/Application Support/PARADOX Command
  Centre/state.json`, written atomically. Every `Codable` type has a hand-written
  `init(from:)` that falls back to a default per field, so a file from any earlier
  build opens in a newer one and no future field can wipe an existing one. Verify an
  upgrade against a populated file before shipping — a hand-written `state.json` is a
  perfectly good test fixture.
- **Themeable via one value.** Every colour comes from a `Palette` injected through
  `@Environment(\.p)`. `Palette.ember` is a complete second token set; swapping the
  value on the root re-themes the whole room. Never name a colour inside a view.
- **The house style is PARADOX terminal** — spec at `~/Desktop/★★★★★/STYLE.md`.
  Menlo everywhere, box-drawing card grammar (`Box`), `▰▱` meters, gold = titles,
  teal = primary, violet = identity, pink = alert.
- **Nothing leaves the Mac.** No network, no analytics, no external assets.

## Gotchas already paid for

- **Never use a TextField's own placeholder here.** AppKit draws it in the *system*
  font at the system size no matter what `.font` the field has, so at Menlo 11 it
  overflows its line box and every empty line comes back sliced in half. `Field` draws
  the placeholder itself as a `Text` behind the field.
- **A width-only `Rectangle` as an HStack sibling is greedy.** Used as the box's left
  rule it took all the height the scroll view offered and stretched every box to the
  viewport. It is an `.overlay` on the content instead, so it matches content height.
- **`swiftc -parse-as-library` forbids top-level code** — the entry point is
  `@main enum CommandCentre { static func main() }`, and the delegate is retained
  explicitly because `NSApplication.delegate` is unowned.
- **Build outside the repo.** `build.sh` builds in `$TMPDIR`: the Desktop is
  iCloud-synced and the FileProvider's xattrs make `codesign` refuse the bundle.

## Working on it

```bash
mac/build.sh              # → $TMPDIR/command-centre-build/Command Centre.app
mac/build.sh --install    # → /Applications/Command Centre.app
```

Signing auto-detects an Apple Developer ID, falls back to the Apple Development cert,
then a local identity, then ad-hoc — no identity is ever hardcoded.

**Verifying without stealing the screen:** `CC_ENTER=<1-5> open -g -a "Command Centre"`
opens already inside that territory, behind everything, without activating; capture it
with `screencapture -x -o -l <window id>` (find the id via `CGWindowListCopyWindowInfo`).
A test run deliberately does not count as a crossing. Never repeatedly `open` the app
to check something — each launch steals focus.

Delegate fan-out work to **sub-agents** — searching prior art across Clean, sweeping the
★★★★★ vaults, any noisy investigation. Keep this context for the room itself.
