#!/bin/bash
# Builds Focus.app, installs it to /Applications and launches it. Needs only the Xcode command line tools.
#   ./build.sh            build + install + launch
#   ./build.sh --ci       build only (used by GitHub Actions)
set -e
cd "$(dirname "$0")"
C=Focus.app/Contents
rm -rf Focus.app && mkdir -p "$C/MacOS"
swiftc -O -swift-version 5 main.swift -o "$C/MacOS/Focus"
cat > "$C/Info.plist" <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleExecutable</key><string>Focus</string>
  <key>CFBundleIdentifier</key><string>com.labern.focus</string>
  <key>CFBundleName</key><string>Focus</string>
  <key>CFBundleShortVersionString</key><string>1.0</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>LSMinimumSystemVersion</key><string>13.0</string>
  <key>LSUIElement</key><true/>
</dict></plist>
EOF
codesign --force -s - Focus.app
[ "$1" = "--ci" ] && exit 0
pkill -x Focus || true
rm -rf /Applications/Focus.app && cp -R Focus.app /Applications/   # fixed location, so "Open at login" sticks
open /Applications/Focus.app
