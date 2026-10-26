#!/bin/sh
# Publish gt7/ to GitHub Pages (gh-pages branch → labern.github.io/Clean/gt7/).
# Ships only what the browser needs: no tools/, tests/.
set -e
ROOT=$(git rev-parse --show-toplevel)
WT=$(mktemp -d)
git -C "$ROOT" fetch -q origin gh-pages
git -C "$ROOT" worktree add -q "$WT" origin/gh-pages
cd "$WT"
git checkout -q -B gh-pages origin/gh-pages
rm -rf gt7 && mkdir gt7
cp -r "$ROOT"/gt7/index.html "$ROOT"/gt7/style.css "$ROOT"/gt7/sw.js "$ROOT"/gt7/manifest.webmanifest "$ROOT"/gt7/app "$ROOT"/gt7/data "$ROOT"/gt7/img "$ROOT"/gt7/vendor gt7/
[ -f "$ROOT"/gt7/native/dist/GT7Endgame.apk ] && mkdir -p gt7/download && cp "$ROOT"/gt7/native/dist/GT7Endgame.apk gt7/download/
# the iPhone app is built in the cloud (.github/workflows/gt7-ios.yml → ci/gt7 branch); keep the latest
mkdir -p gt7/download && cp "$ROOT"/gt7/docs/GT7-Endgame-Install.pdf gt7/download/
git -C "$ROOT" fetch -q origin ci/gt7 2>/dev/null && git -C "$ROOT" show origin/ci/gt7:GT7Endgame.ipa > gt7/download/GT7Endgame.ipa 2>/dev/null || rm -f gt7/download/GT7Endgame.ipa
mkdir -p gt7/bridge && cp "$ROOT"/gt7/bridge/gt7-bridge.mjs "$ROOT"/gt7/bridge/protocol.mjs "$ROOT"/gt7/bridge/install.sh "$ROOT"/gt7/bridge/README.md gt7/bridge/
git add -A gt7
git commit -q -m "Deploy gt7: ${1:-update}" || echo "nothing to deploy"
git push -q origin gh-pages
cd "$ROOT" && git worktree remove --force "$WT"
echo "deployed → https://labern.github.io/Clean/gt7/"
