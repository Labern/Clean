#!/bin/bash
# GestureDeck — one-step install AND update. The only command you ever need:
#
#   curl -fsSL https://labern.github.io/Clean/gesture/deck.sh | bash
#
# Finds (or clones) the Clean repo, pulls the latest GestureDeck, builds it,
# and launches it. Safe to re-run any time — it's the update command too.
set -euo pipefail

REPO_URL="https://github.com/labern/Clean.git"
BRANCH="claude/gesture-recognition-tools-dzwf59"

if ! xcode-select -p >/dev/null 2>&1; then
  echo "✗ Xcode Command Line Tools missing. Run:  xcode-select --install"
  echo "  then re-run this command."
  exit 1
fi

# find an existing clone, else clone to ~/Clean
DIR=""
for d in "$HOME/Clean" "$HOME/Desktop/Clean" "$HOME/Documents/Clean" \
         "$HOME/Developer/Clean" "$HOME/Downloads/Clean" "$PWD/Clean" "$PWD"; do
  if [ -d "$d/GestureDeck" ] && [ -d "$d/.git" ]; then DIR="$d"; break; fi
done
if [ -z "$DIR" ]; then
  DIR="$HOME/Clean"
  echo "→ cloning to $DIR"
  git clone --branch "$BRANCH" "$REPO_URL" "$DIR"
fi

echo "→ updating $DIR"
git -C "$DIR" fetch origin "$BRANCH"
if ! git -C "$DIR" checkout "$BRANCH" 2>/dev/null; then
  echo "✗ couldn't switch branches (uncommitted changes in $DIR?)"
  echo "  commit/stash them, or delete the clone and re-run this command."
  exit 1
fi
git -C "$DIR" pull --ff-only origin "$BRANCH"

cd "$DIR/GestureDeck"
./build_app.sh

pkill -x GestureDeck 2>/dev/null || true   # replace a running old version
open GestureDeck.app
echo
echo "✓ GestureDeck is running — window on screen, 🖐 in the menu bar."
