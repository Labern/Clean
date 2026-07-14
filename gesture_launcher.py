#!/usr/bin/env python3
"""
gesture_launcher.py — webcam gesture → app launcher for macOS.

Make a hand pose and the matching action fires. Recognized poses:
    ☝ "1"          one finger up
    ✌ "2"          two fingers up
    🤟 "3"          three fingers up
    🖖 "4"          four fingers up, thumb tucked
    🖐 "palm"       open palm (four fingers + thumb)
    ✊ "fist"       closed fist, hand upright
    👍 "thumbs-up"  fist with thumb sticking up
    🤘 "rock"       index + pinky up, middle/ring folded
Out of the box: 1 → Obsidian, 2 → Claude, 3 → Spotify,
palm → back to the gesture web page (returns to the tab you already
have open in Safari/Chrome rather than opening a duplicate — first use
asks a one-time macOS Automation permission), fist → Spotify play/pause.
Actions can be app names, URLs, or "cmd: <shell command>". Edit the
GESTURES table below, or create ~/.config/gesture-launcher.json to
override without touching this file.

Setup (once):
    pip3 install mediapipe

Run:
    python3 gesture_launcher.py             # headless, prints events
    python3 gesture_launcher.py --preview   # with a live camera window
    python3 gesture_launcher.py --list      # show current gesture map

macOS will ask for camera access for your terminal the first time.
The hand-tracking model (~8 MB) is downloaded once to ~/Library/Caches.

To keep it running in the background:
    nohup python3 gesture_launcher.py >/tmp/gesture_launcher.log 2>&1 &
(or wrap it in a LaunchAgent if you want it to start at login).
"""

import argparse
import json
import subprocess
import sys
import time
import urllib.request
from collections import deque
from pathlib import Path

# ── gesture map ──────────────────────────────────────────────────────────
# gesture id → action. Ids: "1".."4" (raised fingers, thumb tucked),
# "palm", "fist", "thumbs-up", "rock". An action can be:
#   • an app name as it appears in /Applications   → opened with `open -a`
#   • a URL starting with http:// or https://      → opened in your browser
#     (returns to an existing tab if one is already showing it)
#   • "cmd: <shell command>"                       → run as a shell command
# Override without editing this file by creating
# ~/.config/gesture-launcher.json, e.g. {"rock": "Notes", "fist": ""}
# (set a key to "" there to disable one of these defaults).
GESTURES = {
    "1": "Obsidian",
    "2": "Claude",        # the Claude desktop app
    "3": "Spotify",
    "palm": "https://labern.github.io/Clean/gesture/",   # back to the web page
    "fist": "cmd: osascript -e 'tell application \"Spotify\" to playpause'",
    # "4": "cmd: open ~/Downloads",
    # "thumbs-up": "obsidian://new",
    # "rock": "https://claude.ai",
}

GESTURE_ORDER = ["1", "2", "3", "4", "palm", "fist", "thumbs-up", "rock"]

# ── tuning ───────────────────────────────────────────────────────────────
HOLD_FRAMES = 8        # gesture must be stable this many frames to fire
RELEASE_FRAMES = 10    # frames with no gesture before it can re-arm
COOLDOWN_SEC = 4.0     # per-app minimum time between launches
CAMERA_INDEX = 0

MODEL_URL = ("https://storage.googleapis.com/mediapipe-models/hand_landmarker/"
             "hand_landmarker/float16/1/hand_landmarker.task")
MODEL_PATH = Path.home() / "Library/Caches/gesture-launcher/hand_landmarker.task"
CONFIG_PATH = Path.home() / ".config/gesture-launcher.json"

# landmark indices (MediaPipe hand model)
WRIST = 0
THUMB_TIP = 4
INDEX_MCP = 5
MIDDLE_MCP = 9
PINKY_MCP = 17
FINGERS = [(8, 6), (12, 10), (16, 14), (20, 18)]  # (tip, pip): index..pinky


def ensure_model() -> Path:
    if not MODEL_PATH.exists():
        print(f"⇣ downloading hand model to {MODEL_PATH} …")
        MODEL_PATH.parent.mkdir(parents=True, exist_ok=True)
        tmp = MODEL_PATH.with_suffix(".tmp")
        urllib.request.urlretrieve(MODEL_URL, tmp)
        tmp.rename(MODEL_PATH)
    return MODEL_PATH


def _dist(a, b):
    return ((a.x - b.x) ** 2 + (a.y - b.y) ** 2) ** 0.5


def classify_gesture(lm):
    """Return a gesture id from GESTURE_ORDER, or None.

    Normalized image coords: y grows downward, so "above" means smaller y.
    A finger counts as extended when its tip is clearly farther from the
    wrist than its middle (PIP) joint — orientation-independent, so fists
    and thumbs-up work even when the hand isn't perfectly upright.
    """
    palm_width = _dist(lm[INDEX_MCP], lm[PINKY_MCP])
    if palm_width < 0.02:
        return None
    ext = [_dist(lm[t], lm[WRIST]) > _dist(lm[p], lm[WRIST]) * 1.15
           for t, p in FINGERS]
    thumb_out = _dist(lm[THUMB_TIP], lm[PINKY_MCP]) > palm_width * 1.4
    upright = lm[MIDDLE_MCP].y < lm[WRIST].y

    if not any(ext):
        knuckle_top = min(lm[INDEX_MCP].y, lm[MIDDLE_MCP].y, lm[PINKY_MCP].y)
        if lm[THUMB_TIP].y < knuckle_top - palm_width * 0.4:
            return "thumbs-up"          # fist with the thumb clearly on top
        return "fist" if upright else None

    if not upright:                      # ignore hands down at the keyboard
        return None
    if ext == [True, False, False, True]:
        return "rock"                    # index + pinky, middle/ring folded
    raised = sum(1 for e, (t, _) in zip(ext, FINGERS)
                 if e and lm[t].y < lm[WRIST].y)
    if raised == 4:
        return "palm" if thumb_out else "4"
    if raised:
        return str(raised)
    return None


# AppleScripts to focus an existing browser tab whose URL starts with the
# target, instead of opening a duplicate. Each prints "focused" on success.
# The Chrome one simply fails to compile if Chrome isn't installed — that's
# fine, we fall through. First use triggers a one-time macOS Automation
# permission prompt ("Terminal wants to control Safari/Chrome").
_SAFARI_FOCUS = '''on run argv
    set target to item 1 of argv
    if application "Safari" is running then
        tell application "Safari"
            repeat with w in every window
                try
                    repeat with t in every tab of w
                        if URL of t starts with target then
                            tell w to set current tab to t
                            set index of w to 1
                            activate
                            return "focused"
                        end if
                    end repeat
                end try
            end repeat
        end tell
    end if
    return "notfound"
end run'''

_CHROME_FOCUS = '''on run argv
    set target to item 1 of argv
    if application id "com.google.Chrome" is running then
        tell application id "com.google.Chrome"
            repeat with w in every window
                try
                    set tIndex to 0
                    repeat with t in every tab of w
                        set tIndex to tIndex + 1
                        if URL of t starts with target then
                            set active tab index of w to tIndex
                            set index of w to 1
                            activate
                            return "focused"
                        end if
                    end repeat
                end try
            end repeat
        end tell
    end if
    return "notfound"
end run'''


def open_url(url: str) -> bool:
    """Return to an already-open tab showing the URL; open it only if none."""
    target = url.rstrip("/")
    for script in (_SAFARI_FOCUS, _CHROME_FOCUS):
        try:
            out = subprocess.run(["osascript", "-e", script, target],
                                 capture_output=True, text=True, timeout=10)
            if out.returncode == 0 and out.stdout.strip() == "focused":
                return True
        except (OSError, subprocess.TimeoutExpired):
            pass
    result = subprocess.run(["open", url], capture_output=True, text=True)
    if result.returncode != 0:
        print(f"✖ couldn't open “{url}”: {result.stderr.strip()}")
        return False
    return True


def load_gestures() -> dict:
    """Built-in GESTURES, overridden by ~/.config/gesture-launcher.json."""
    gestures = dict(GESTURES)
    if CONFIG_PATH.exists():
        try:
            user = json.loads(CONFIG_PATH.read_text())
            gestures.update({str(k): v for k, v in user.items()})
        except (ValueError, OSError) as err:
            print(f"⚠ ignoring {CONFIG_PATH}: {err}")
    return {k: v for k, v in gestures.items() if v and k in GESTURE_ORDER}


def launch(action: str) -> bool:
    if action.startswith(("http://", "https://")):
        return open_url(action)
    if action.startswith("cmd:"):
        cmd, what = ["/bin/sh", "-c", action[4:].strip()], f"run “{action[4:].strip()}”"
    else:
        cmd, what = ["open", "-a", action], f"open “{action}” — is it installed in /Applications?"
    result = subprocess.run(cmd, capture_output=True, text=True)
    if result.returncode != 0:
        print(f"✖ couldn't {what}: {result.stderr.strip()}")
        return False
    return True


def main() -> int:
    parser = argparse.ArgumentParser(description="webcam gesture → app launcher")
    parser.add_argument("--preview", action="store_true",
                        help="show a live camera window with the detected gesture")
    parser.add_argument("--list", action="store_true", help="print gesture map and exit")
    args = parser.parse_args()

    gestures = load_gestures()
    icons = {"1": "☝", "2": "✌", "3": "🤟", "4": "🖖",
             "palm": "🖐", "fist": "✊", "thumbs-up": "👍", "rock": "🤘"}
    names = {"1": "1 finger", "2": "2 fingers", "3": "3 fingers",
             "4": "4 fingers (thumb tucked)", "palm": "open palm",
             "fist": "fist", "thumbs-up": "thumbs up", "rock": "rock sign"}

    if args.list:
        for gid in GESTURE_ORDER:
            if gid in gestures:
                print(f"  {icons[gid]}  {names[gid]} → {gestures[gid]}")
        if CONFIG_PATH.exists():
            print(f"  (includes overrides from {CONFIG_PATH})")
        return 0

    try:
        import cv2
        import mediapipe as mp
        from mediapipe.tasks import python as mp_python
        from mediapipe.tasks.python import vision
    except ImportError:
        print("✖ missing dependencies — run:  pip3 install mediapipe")
        return 1

    model = ensure_model()
    landmarker = vision.HandLandmarker.create_from_options(
        vision.HandLandmarkerOptions(
            base_options=mp_python.BaseOptions(model_asset_path=str(model)),
            running_mode=vision.RunningMode.VIDEO,
            num_hands=1,
        ))

    cap = cv2.VideoCapture(CAMERA_INDEX)
    if not cap.isOpened():
        print("✖ couldn't open the camera — check macOS camera permissions "
              "for your terminal (System Settings → Privacy & Security → Camera).")
        return 1

    print("● watching for gestures — ctrl-C to quit")
    for gid in GESTURE_ORDER:
        if gid in gestures:
            print(f"  {icons[gid]}  {names[gid]} → {gestures[gid]}")

    recent = deque(maxlen=HOLD_FRAMES)
    armed = True
    idle_frames = 0
    last_fired = {}   # app → monotonic time
    start = time.monotonic()

    try:
        while True:
            ok, frame = cap.read()
            if not ok:
                time.sleep(0.05)
                continue

            rgb = cv2.cvtColor(frame, cv2.COLOR_BGR2RGB)
            image = mp.Image(image_format=mp.ImageFormat.SRGB, data=rgb)
            ts_ms = int((time.monotonic() - start) * 1000)
            result = landmarker.detect_for_video(image, ts_ms)

            gid = None
            if result.hand_landmarks:
                gid = classify_gesture(result.hand_landmarks[0])
            recent.append(gid)

            if gid is None:
                idle_frames += 1
                if idle_frames >= RELEASE_FRAMES:
                    armed = True
            else:
                idle_frames = 0

            stable = (len(recent) == HOLD_FRAMES and len(set(recent)) == 1
                      and recent[0] is not None)
            if stable and armed:
                gid = recent[0]
                action = gestures.get(gid)
                if action:
                    now = time.monotonic()
                    if now - last_fired.get(action, -COOLDOWN_SEC) >= COOLDOWN_SEC:
                        print(f"{icons[gid]} {names[gid]} → {action}")
                        if launch(action):
                            last_fired[action] = now
                        armed = False   # re-arms after the hand drops

            if args.preview:
                h, w = frame.shape[:2]
                if result.hand_landmarks:
                    for p in result.hand_landmarks[0]:
                        cv2.circle(frame, (int(p.x * w), int(p.y * h)), 4,
                                   (212, 234, 94), -1)
                label = names[gid] if gid else "no gesture"
                cv2.putText(frame, label, (16, 40), cv2.FONT_HERSHEY_SIMPLEX,
                            1.0, (250, 139, 167), 2)
                cv2.imshow("gesture launcher", cv2.flip(frame, 1))
                if cv2.waitKey(1) & 0xFF == ord("q"):
                    break
    except KeyboardInterrupt:
        print("\n○ stopped")
    finally:
        cap.release()
        if args.preview:
            cv2.destroyAllWindows()
    return 0


if __name__ == "__main__":
    sys.exit(main())
