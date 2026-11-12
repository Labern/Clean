#!/bin/bash
# Builds Focus.app next to this script and launches it. Needs only the Xcode command line tools.
set -e
cd "$(dirname "$0")"
C=Focus.app/Contents
mkdir -p "$C/MacOS"
swiftc -O -swift-version 5 main.swift -o "$C/MacOS/Focus"
cat > "$C/Info.plist" <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleExecutable</key><string>Focus</string>
  <key>CFBundleIdentifier</key><string>com.labern.focus</string>
  <key>CFBundleName</key><string>Focus</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>LSMinimumSystemVersion</key><string>11.0</string>
  <key>LSUIElement</key><true/>
</dict></plist>
EOF
codesign --force -s - Focus.app
pkill -x Focus || true
open Focus.app
