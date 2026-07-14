# knowledge.md — gesture project state

Last updated: 2026-07-14, Mac session (branch `claude/gesture-recognition-tools-dzwf59`)

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
- Debounce (v3, "instant" rules from the user — no lag, no cooldown):
  hold pose `holdFrames` (~0.12 s default, slider floor 0.05 s), fire once;
  **switching to a different pose re-arms instantly** (no need to drop the
  hand), dropping the hands re-arms the same pose after `releaseFrames` (4).
  Cooldown defaults to **0 = off** (slider allows re-enabling).
  ~~re-arm only after hands drop; plus per-gesture cooldown~~ (superseded).
- 640×480 @ **30 fps** capture (~~15 fps~~ — raised for instant response);
  camera fully off when disabled. `onPose` only fires when the label
  *changes*, so SwiftUI isn't re-rendered 30×/s.
- Must run as the `.app` bundle (permissions keyed to bundle id
  `com.labern.GestureDeck`); `build_app.sh` builds, generates the icon,
  writes Info.plist (LSUIElement + camera + AppleEvents usage strings),
  ad-hoc codesigns.
- Config at `~/Library/Application Support/GestureDeck/config.json`
  **migrates in place** (`defaultsVersion`, currently 3) — the user never
  deletes/resets anything. Migrations must **never slow the user down**:
  v3 clamps holdSeconds with `min(existing, 0.12)` because he had already
  set 0.05 by hand. Migrated configs save back to disk immediately.
- Config window is an **AppKit `NSWindow` owned by `WindowManager`**
  (~~`WindowGroup`~~ superseded): opens in `applicationDidFinishLaunching`,
  `makeKeyAndOrderFront` + `activate(ignoringOtherApps:)` — this is what
  finally made every button/picker take clicks immediately. `deck` action
  kind ("GestureDeck window") re-fronts it — usable for any gesture.
- Launch at login **auto-registers** via `SMAppService` on every launch —
  no toggle hunting (the toggle still exists to turn it off).
- Config `didSet` no longer restarts the engine per keystroke: engine
  start/stop only on `enabled` flips; disk saves debounced 0.5 s.
- Icon: IconGen renders into an explicit `NSBitmapImageRep` at exact pixel
  sizes — `NSImage.lockFocus()` renders at 2× on Retina and iconutil then
  rejects the set (this is why the app had NO icon before). build_app.sh
  now fails loudly if the .icns is missing, and auto-detects a Developer ID
  cert (falls back to ad-hoc; on this Mac stable identities fail with
  errSecInternalComponent — see Blueprints).

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

- ~~Confirm GestureDeck builds and runs on the user's Mac~~ **DONE
  2026-07-14**: built, launched, and screenshot-verified on the Mac —
  window opens at launch, camera live ("watching"), pickers/buttons respond,
  login item registered, icon present. The user was already interacting
  with it (changed sound to Ping, hold to 0.05 s) mid-session.
- Dedicated GitHub repo for GestureDeck (integration can't create repos —
  user creates it at github.com/new, then split it out).
- Web interface version of GestureDeck (grow the Pages `/gesture/` page
  into a full configurator) — after the Swift app works.
- Map the remaining gestures when the user decides.
