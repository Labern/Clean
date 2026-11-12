#!/bin/bash
# Builds Later.app next to this script and launches it. Needs only the Xcode command line tools.
set -e
cd "$(dirname "$0")"
C=Later.app/Contents
mkdir -p "$C/MacOS"
swiftc -O -swift-version 5 main.swift -o "$C/MacOS/Later"
cat > "$C/Info.plist" <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleExecutable</key><string>Later</string>
  <key>CFBundleIdentifier</key><string>com.labern.later</string>
  <key>CFBundleName</key><string>Later</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>LSMinimumSystemVersion</key><string>11.0</string>
  <key>LSUIElement</key><true/>
</dict></plist>
EOF
codesign --force -s - Later.app
pkill -x Later || true
open Later.app
