#!/bin/sh
# GT7 Endgame bridge, one-line install for your Mac:
#   curl -fsSL https://labern.github.io/Clean/gt7/bridge/install.sh | sh
# Downloads the bridge (5 small files, zero dependencies) to ~/GT7Bridge and
# starts it. Re-run any time to update. Needs Node 18+ (brew install node).
set -e
BASE=https://labern.github.io/Clean/gt7
DIR="$HOME/GT7Bridge"
if ! command -v node >/dev/null 2>&1; then
  echo "Node.js is needed. Install it with:  brew install node   (or from nodejs.org), then run this again."; exit 1
fi
MAJOR=$(node -p 'process.versions.node.split(".")[0]')
if [ "$MAJOR" -lt 18 ]; then echo "Node 18 or newer is needed (you have $(node -v)). brew upgrade node"; exit 1; fi
mkdir -p "$DIR/bridge" "$DIR/app" "$DIR/data"
curl -fsSL "$BASE/bridge/gt7-bridge.mjs" -o "$DIR/bridge/gt7-bridge.mjs"
curl -fsSL "$BASE/bridge/protocol.mjs" -o "$DIR/bridge/protocol.mjs"
curl -fsSL "$BASE/app/psn-core.js" -o "$DIR/app/psn-core.js"
curl -fsSL "$BASE/app/gt7proto.js" -o "$DIR/app/gt7proto.js"
curl -fsSL "$BASE/data/demo-lap.json" -o "$DIR/data/demo-lap.json"
echo '{ "type": "module" }' > "$DIR/package.json"   # app/*.js are ES modules
echo "Installed to $DIR"
echo "Starting. Leave this window open; Ctrl+C stops it."
echo "Next: open $BASE/#/connect on this Mac."
cd "$DIR" && exec node bridge/gt7-bridge.mjs --ps5 "${PS5:-auto}"
