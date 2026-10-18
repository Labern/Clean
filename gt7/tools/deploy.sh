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
git add -A gt7
git commit -q -m "Deploy gt7: ${1:-update}" || echo "nothing to deploy"
git push -q origin gh-pages
cd "$ROOT" && git worktree remove --force "$WT"
echo "deployed → https://labern.github.io/Clean/gt7/"
