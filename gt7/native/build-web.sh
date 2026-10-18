#!/bin/sh
# Copy the web app into www/ for Capacitor. Same files as the GitHub Pages deploy.
set -e
cd "$(dirname "$0")"
rm -rf www && mkdir www
cp -r ../index.html ../style.css ../manifest.webmanifest ../app ../data ../img ../vendor www/
# no service worker inside the native shell: the bundle is already local
printf '' > www/sw.js
echo "www/ ready ($(du -sh www | cut -f1))"
