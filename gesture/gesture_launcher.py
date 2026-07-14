#!/usr/bin/env python3
"""
gesture_launcher.py — webcam gesture → app launcher for macOS.

Hold up N fingers (index/middle/ring/pinky; thumb is ignored) and the
matching action fires. Out of the box:
    ☝ 1 finger  → Obsidian
    ✌ 2 fingers → Claude (desktop app)
    🤟 3 fingers → Spotify
    🖐 open palm → the gesture web page (labern.github.io/Clean/gesture)
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
# gesture id → action. Ids 1–4 are raised fingers (index/middle/ring/pinky,
# thumb tucked); id 5 is an open palm (all four fingers + thumb extended).
# An action can be:
#   • an app name as it appears in /Applications   → opened with `open -a`
#   • a URL starting with http:// or https://      → opened in your browser
#   • "cmd: <shell command>"                       → run as a shell command
# Override without editing this file by creating
# ~/.config/gesture-launcher.json, e.g. {"2": "Notes", "4": "https://claude.ai"}
# (set a key to "" there to disable one of these defaults).
GESTURES = {
    1: "Obsidian",
    2: "Claude",        # the Claude desktop app
    3: "Spotify",
    5: "https://labern.github.io/Clean/gesture/",   # open palm → the web page
    # 4: "cmd: open ~/Downloads",   # four fingers with thumb tucked is free
}

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


def count_raised_fingers(lm) -> int:
    """Fingers extended upward on an upright hand; 0 if hand isn't upright.

    Normalized image coords: y grows downward, so "above" means smaller y.
    """
    if lm[MIDDLE_MCP].y > lm[WRIST].y:      # knuckles below wrist → hand not up
        return 0
    count = 0
    for tip, pip in FINGERS:
        if lm[tip].y < lm[pip].y - 0.03 and lm[tip].y < lm[WRIST].y:
            count += 1
    return count


def thumb_extended(lm) -> bool:
    """Thumb sticking out sideways, vs tucked across the palm.

    Compares the thumb tip's distance from the pinky knuckle against the
    palm width (index knuckle ↔ pinky knuckle): an extended thumb reaches
    well past the far edge of the palm, a tucked one stays within it.
    """
    dist = lambda a, b: ((a.x - b.x) ** 2 + (a.y - b.y) ** 2) ** 0.5
    palm_width = dist(lm[INDEX_MCP], lm[PINKY_MCP])
    return dist(lm[THUMB_TIP], lm[PINKY_MCP]) > palm_width * 1.4


def classify_gesture(lm) -> int:
    """0 = nothing, 1–4 = raised fingers (thumb tucked), 5 = open palm."""
    count = count_raised_fingers(lm)
    if count == 4 and thumb_extended(lm):
        return 5
    return count


def load_gestures() -> dict:
    """Built-in GESTURES, overridden by ~/.config/gesture-launcher.json."""
    gestures = dict(GESTURES)
    if CONFIG_PATH.exists():
        try:
            user = json.loads(CONFIG_PATH.read_text())
            gestures.update({int(k): v for k, v in user.items()})
        except (ValueError, OSError) as err:
            print(f"⚠ ignoring {CONFIG_PATH}: {err}")
    return {k: v for k, v in gestures.items() if v and 1 <= k <= 5}


def launch(action: str) -> bool:
    if action.startswith(("http://", "https://")):
        cmd, what = ["open", action], f"open “{action}”"
    elif action.startswith("cmd:"):
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
                        help="show a live camera window with the detected count")
    parser.add_argument("--list", action="store_true", help="print gesture map and exit")
    args = parser.parse_args()

    gestures = load_gestures()
    icons = {1: "☝", 2: "✌", 3: "🤟", 4: "🖖", 5: "🖐"}
    names = {1: "1 finger", 2: "2 fingers", 3: "3 fingers",
             4: "4 fingers (thumb tucked)", 5: "open palm"}

    if args.list:
        for gid, action in sorted(gestures.items()):
            print(f"  {icons[gid]}  {names[gid]} → {action}")
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
    for gid, action in sorted(gestures.items()):
        print(f"  {icons[gid]}  {names[gid]} → {action}")

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

            count = 0
            if result.hand_landmarks:
                count = classify_gesture(result.hand_landmarks[0])
            recent.append(count)

            if count == 0:
                idle_frames += 1
                if idle_frames >= RELEASE_FRAMES:
                    armed = True
            else:
                idle_frames = 0

            stable = (len(recent) == HOLD_FRAMES and len(set(recent)) == 1
                      and recent[0] > 0)
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
                label = ("open palm" if count == 5 else f"fingers: {count}") if count else "no gesture"
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
