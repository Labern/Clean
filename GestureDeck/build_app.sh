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

# icon (drawn at build time) — never fail the whole build over the icon,
# but say loudly when it didn't work
ICON_OK=0
if command -v iconutil >/dev/null 2>&1; then
  rm -rf AppIcon.iconset
  if swiftc -O IconGen.swift -o .build/icongen 2>/tmp/icongen-err.log \
     && .build/icongen AppIcon.iconset \
     && iconutil -c icns AppIcon.iconset -o "$APP/Contents/Resources/AppIcon.icns"; then
    ICON_OK=1
  fi
  rm -rf AppIcon.iconset
fi
if [ "$ICON_OK" = 1 ]; then
  echo "✓ icon generated"
else
  echo "⚠ icon generation FAILED (see /tmp/icongen-err.log) — app will show a generic icon"
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
    <key>CFBundleIconName</key><string>AppIcon</string>
    <key>NSHighResolutionCapable</key><true/>
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
touch "$APP"   # nudge Finder's icon cache
echo "✓ built $APP — launch with:  open $APP"
echo "  (the config window opens on launch; the 🖐 lives in the menu bar)"
echo "  to reset saved gesture mappings:  rm -rf ~/Library/Application\\ Support/GestureDeck"
