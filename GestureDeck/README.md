# 🖐 GestureDeck

A native macOS menu bar app: make a hand gesture at your webcam and things
happen — apps open, URLs come to the front, shell commands run. Built on
Apple's Vision framework (on-device hand tracking, no dependencies, no
network, video never leaves your Mac).

## Install / update — one command

```bash
curl -fsSL https://labern.github.io/Clean/gesture/deck.sh | bash
```

That's it — same command for first install and for every update. It finds
(or clones) the repo, pulls the latest code, builds the app, and launches
it. Building by hand still works too: `./build_app.sh && open GestureDeck.app`.

Requires macOS 13+ and Xcode Command Line Tools (`xcode-select --install`).
Always launch the `.app` bundle, not the bare binary — the camera and
Automation permission prompts are keyed to the bundle. macOS asks for
camera access once on first launch.

## Gestures

| One hand | | Both hands | |
|---|---|---|---|
| ☝️ One finger | index up | 🖐🖐 Both palms | |
| ✌️ Two fingers | index + middle | ✊✊ Both fists | |
| 🤟 Three fingers | + ring | 👍👍 Both thumbs up | |
| 🖖 Four fingers | thumb tucked | 🖐✊ Palm + fist | |
| 🖐 Open palm | all five | | |
| ✊ Fist | hand upright | | |
| 👍 Thumbs up | thumb on top | | |
| 🤘 Rock sign | index + pinky | | |
| 🤙 Call me | thumb + pinky | | |
| 👌 OK sign | thumb–index circle | | |

Defaults: ☝️ → ChatGPT in Chrome (focuses your existing tab, never a new
one) · ✌️ → Claude · 🤟 → Spotify · 🖖 → Obsidian ·
🖐 → gesture web page (existing tab) · ✊ → Spotify play/pause.
Defaults apply automatically — saved configs migrate in place when the
defaults change, so there's never anything to delete or reset.
Everything is remappable in the Gestures window (menu bar icon → Gestures…):
each gesture can open an app (picked from your installed apps), open a URL,
or run a shell command — with a per-gesture on/off switch and a Test button.

## Features

- A proper floating config window opens on launch — everything in one
  place: camera on the left (live mirrored preview with a "what it's
  seeing" pill), plus last trigger and all behavior controls under it;
  the full gesture list with per-gesture enable boxes and action
  selectors on the right.
- Menu bar hand icon shows listening state; popover has master toggle,
  live "what the camera sees" readout, and the last trigger.
- Sound on trigger — toggleable, 8 system sounds to pick from, previewable.
- Hold-time and cooldown sliders (how long a pose must be held; minimum
  gap between triggers). A gesture fires once, then re-arms when you
  drop your hand.
- Live mirrored camera preview in the config window.
- Launch at login toggle.
- URL actions focus an already-open Safari/Chrome tab instead of opening
  duplicates (one-time Automation permission prompt).
- Light by design: 640×480 @ 15 fps capture, hands ignored while they're
  down at the keyboard, camera fully off when listening is toggled off.
- Config persists at `~/Library/Application Support/GestureDeck/config.json`.
