#!/bin/sh
# Publish once/ to GitHub Pages (gh-pages branch → labern.github.io/Clean/once/).
set -e
ROOT=$(git rev-parse --show-toplevel)
node "$ROOT"/once/tools/build.mjs
WT=$(mktemp -d)
git -C "$ROOT" fetch -q origin gh-pages
git -C "$ROOT" worktree add -q "$WT" origin/gh-pages
cd "$WT"
git checkout -q -B gh-pages origin/gh-pages
rm -rf once && mkdir once
cp "$ROOT"/once/index.html "$ROOT"/once/bookmarklet.min.js "$ROOT"/once/once-extension.zip "$ROOT"/once/icon-192.png "$ROOT"/once/icon-512.png once/
git add -A once
git commit -q -m "Deploy once: ${1:-update}" || echo "nothing to deploy"
git push -q origin gh-pages
cd "$ROOT" && git worktree remove --force "$WT"
echo "deployed → https://labern.github.io/Clean/once/"
