# knowledge.md — gesture project state

Last updated: 2026-07-14 (branch `claude/gesture-recognition-tools-dzwf59`)

## The one command that matters

Install AND update GestureDeck on the Mac — same command every time, nothing
else to remember:

```bash
curl -fsSL https://labern.github.io/Clean/gesture/deck.sh | bash
```

It finds or clones the repo, pulls the latest code, builds the app, quits any
old running copy, and launches the new one. If Xcode Command Line Tools are
missing it says so and asks for a one-time `xcode-select --install`.

## What exists (three tiers)

1. **GestureDeck/** — the flagship: native macOS menu bar app (Swift Package,
   SwiftUI + Apple Vision hand pose, zero external dependencies, video never
   leaves the Mac). Floating config window with live mirrored camera preview
   and a "what it's seeing" pill, per-gesture enable box + action picker
   (app / URL / shell) with Test buttons, trigger sounds (8 choices,
   toggleable, previewable), hold-time and cooldown sliders, launch at login,
   build-time-generated 🖐 icon. 14 gestures including two-hand combos.
2. **gesture_launcher.py** — Python/MediaPipe webcam launcher (the earlier
   iteration). Curl-able from the Pages site; config merges from
   `~/.config/gesture-launcher.json`.
3. **gesture.html** — browser demo (MediaPipe JS), live at
   https://labern.github.io/Clean/gesture/

## Gesture mappings (user-specified — keep these)

- ☝️ one finger → ChatGPT in Chrome, **focus the existing tab, never a new one**
- ✌️ two fingers → Claude app
- 🤟 three fingers → Spotify
- 🖖 four fingers → Obsidian
- 🖐 open palm → gesture web page (existing tab)
- ✊ fist → Spotify play/pause
- Others (👍 🤘 🤙 👌, two-hand combos) unmapped — "we'll decide others later"

## Hard rules learned this session

- **Never open duplicate tabs.** URL actions focus an already-open
  Safari/Chrome tab via AppleScript before falling back to `open`.
- **Never overwrite files via shell redirection** (`>`/`tee`) without reading
  first — a past session wiped `.gitignore` this way. Use Read-then-Write.
- **Check remote refs before pushing** — `gh-pages` carries other live sites
  (SpotifyDrive, claude-calendar, terra-cognita…); only add/modify the
  `/gesture/` subdirectory, via a git worktree.
- **Always include install/run instructions with every update** — now
  satisfied permanently by the single curl command above.
- **Minimal steps.** Multi-step instructions are unacceptable; everything
  must collapse to one command.

## Key technical decisions

- Apple Vision (`VNDetectHumanHandPoseRequest`, max 2 hands) — landmarks are
  normalized with **y pointing UP** (opposite of MediaPipe).
- Finger extended = tip farther from wrist than its PIP ×1.15 (orientation
  independent); hands below wrist level ("on the keyboard") are ignored.
- Debounce: hold pose `holdFrames`, fire once, re-arm only after hands drop
  for `releaseFrames`; plus per-gesture cooldown.
- 640×480 @ 15 fps capture to stay light; camera fully off when disabled.
- Must run as the `.app` bundle (permissions keyed to bundle id
  `com.labern.GestureDeck`); `build_app.sh` builds, generates the icon,
  writes Info.plist (LSUIElement + camera + AppleEvents usage strings),
  ad-hoc codesigns.
- Config at `~/Library/Application Support/GestureDeck/config.json`
  **migrates in place** (`defaultsVersion`, currently 2) — the user never
  deletes/resets anything to pick up new defaults or new gestures.
- `WindowGroup` (not `Window`) so the config window opens on launch;
  AppDelegate activates the app immediately and again after 0.4 s.
- Engine forwards `objectWillChange` into AppState so the UI live-updates.

## Fix history (why it "did nothing")

- `aa261f6`: missing `import Combine` in Engine.swift was a hard compile
  error — the build failed silently for the user, so the launched bundle was
  stale/empty. Also: Card view-builder init, AppKit import, window
  activation timing, camera mirroring re-applied in `updateNSView`.
- `748ed91`: one-command `deck.sh` installer/updater (also served from
  Pages at `/gesture/deck.sh`) + in-place config migration.

## Branches

- `claude/gesture-recognition-tools-dzwf59` — all app work (GestureDeck has
  never been merged to `main`; `deck.sh` checks out this branch).
- `gh-pages` — live sites; `/gesture/` holds index.html,
  gesture_launcher.py, deck.sh. Keep gesture_launcher.py synced when the
  Python launcher changes; update deck.sh's `BRANCH` if work merges to main.

## Still open

- Confirm GestureDeck builds and runs on the user's Mac (no real build
  output seen yet — fixes so far are from static audit; user pastes compiler
  errors if the curl command fails).
- Dedicated GitHub repo for GestureDeck (integration can't create repos —
  user creates it at github.com/new, then split it out).
- Web interface version of GestureDeck (grow the Pages `/gesture/` page
  into a full configurator) — after the Swift app works.
- Map the remaining gestures when the user decides.
