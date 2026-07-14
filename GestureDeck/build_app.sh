#!/bin/bash
# Builds GestureDeck.app. Must run as a bundle (not the bare binary) so the
# camera/Automation permission prompts attribute to "GestureDeck".
set -euo pipefail
cd "$(dirname "$0")"

swift build -c release

APP=GestureDeck.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp .build/release/GestureDeck "$APP/Contents/MacOS/GestureDeck"

# icon (drawn at build time; needs Xcode CLT's swift + iconutil)
if command -v iconutil >/dev/null 2>&1; then
  rm -rf AppIcon.iconset
  swift IconGen.swift AppIcon.iconset
  iconutil -c icns AppIcon.iconset -o "$APP/Contents/Resources/AppIcon.icns"
  rm -rf AppIcon.iconset
fi

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>GestureDeck</string>
    <key>CFBundleDisplayName</key><string>GestureDeck</string>
    <key>CFBundleIdentifier</key><string>com.labern.GestureDeck</string>
    <key>CFBundleExecutable</key><string>GestureDeck</string>
    <key>CFBundleIconFile</key><string>AppIcon</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>1.0</string>
    <key>CFBundleVersion</key><string>1</string>
    <key>LSMinimumSystemVersion</key><string>13.0</string>
    <key>LSUIElement</key><true/>
    <key>NSCameraUsageDescription</key>
    <string>GestureDeck watches your webcam to recognize hand gestures. Video never leaves your Mac.</string>
    <key>NSAppleEventsUsageDescription</key>
    <string>GestureDeck switches your browser back to an already-open tab instead of opening duplicates.</string>
</dict>
</plist>
PLIST

codesign --force -s - "$APP"
echo "✓ built $APP — launch with:  open $APP"
