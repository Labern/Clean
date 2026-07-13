#!/usr/bin/env python3
"""
gesture_launcher.py — webcam gesture → app launcher for macOS.

Hold up N fingers (index/middle/ring/pinky; thumb is ignored) and the
matching app opens. Out of the box: one finger = Obsidian. Edit the
GESTURES table below to map more.

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
import subprocess
import sys
import time
import urllib.request
from collections import deque
from pathlib import Path

# ── gesture map ──────────────────────────────────────────────────────────
# finger count (index/middle/ring/pinky held up, thumb ignored) → app name
# as it appears in /Applications. Add your own:
GESTURES = {
    1: "Obsidian",
    # 2: "Notes",
    # 3: "Spotify",
    # 4: "Slack",
}

# ── tuning ───────────────────────────────────────────────────────────────
HOLD_FRAMES = 8        # gesture must be stable this many frames to fire
RELEASE_FRAMES = 10    # frames with no gesture before it can re-arm
COOLDOWN_SEC = 4.0     # per-app minimum time between launches
CAMERA_INDEX = 0

MODEL_URL = ("https://storage.googleapis.com/mediapipe-models/hand_landmarker/"
             "hand_landmarker/float16/1/hand_landmarker.task")
MODEL_PATH = Path.home() / "Library/Caches/gesture-launcher/hand_landmarker.task"

# landmark indices (MediaPipe hand model)
WRIST = 0
MIDDLE_MCP = 9
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


def launch(app: str) -> bool:
    result = subprocess.run(["open", "-a", app], capture_output=True, text=True)
    if result.returncode != 0:
        print(f"✖ couldn't open “{app}”: {result.stderr.strip()}"
              f" — is it installed in /Applications?")
        return False
    return True


def main() -> int:
    parser = argparse.ArgumentParser(description="webcam gesture → app launcher")
    parser.add_argument("--preview", action="store_true",
                        help="show a live camera window with the detected count")
    parser.add_argument("--list", action="store_true", help="print gesture map and exit")
    args = parser.parse_args()

    if args.list:
        for fingers, app in sorted(GESTURES.items()):
            print(f"  {'☝✌🤟🖖'[fingers - 1]}  {fingers} finger{'s' if fingers > 1 else ''} → {app}")
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
    for fingers, app in sorted(GESTURES.items()):
        print(f"  {fingers} finger{'s' if fingers > 1 else ''} up → {app}")

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
                count = count_raised_fingers(result.hand_landmarks[0])
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
                fingers = recent[0]
                app = GESTURES.get(fingers)
                if app:
                    now = time.monotonic()
                    if now - last_fired.get(app, -COOLDOWN_SEC) >= COOLDOWN_SEC:
                        print(f"☝ {fingers} finger{'s' if fingers > 1 else ''} up "
                              f"→ opening {app}")
                        if launch(app):
                            last_fired[app] = now
                        armed = False   # re-arms after the hand drops

            if args.preview:
                h, w = frame.shape[:2]
                if result.hand_landmarks:
                    for p in result.hand_landmarks[0]:
                        cv2.circle(frame, (int(p.x * w), int(p.y * h)), 4,
                                   (212, 234, 94), -1)
                label = f"fingers: {count}" if count else "no gesture"
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
