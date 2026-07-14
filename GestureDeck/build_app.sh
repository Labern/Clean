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
rm -rf AppIcon.iconset
swift IconGen.swift AppIcon.iconset
iconutil -c icns AppIcon.iconset -o "$APP/Contents/Resources/AppIcon.icns"
rm -rf AppIcon.iconset
[ -s "$APP/Contents/Resources/AppIcon.icns" ] || { echo "✗ icon generation failed" >&2; exit 1; }

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
    <!-- Regular app: shows in the Dock and the ⌘-Tab app switcher, not a
         menu-bar-only accessory. The menu-bar item is still present too. -->
    <key>LSUIElement</key><false/>
    <key>NSCameraUsageDescription</key>
    <string>GestureDeck watches your webcam to recognize hand gestures. Video never leaves your Mac.</string>
    <key>NSAppleEventsUsageDescription</key>
    <string>GestureDeck switches your browser back to an already-open tab instead of opening duplicates.</string>
</dict>
</plist>
PLIST

# Sign with a STABLE identity so TCC grants (camera, Automation) survive
# rebuilds — ad-hoc changes identity every build and re-prompts everything.
BUNDLE_ID="com.labern.GestureDeck"
IDENTITIES="$(security find-identity -v -p codesigning 2>/dev/null)"
DEV_ID="$(echo "$IDENTITIES" | sed -n 's/.*"\(Developer ID Application:[^"]*\)".*/\1/p' | head -1)"
APPLE_DEV="$(echo "$IDENTITIES" | sed -n 's/.*"\(Apple Development:[^"]*\)".*/\1/p' | head -1)"

if [ -n "$DEV_ID" ] && codesign --force --options runtime --timestamp --sign "$DEV_ID" --identifier "$BUNDLE_ID" "$APP" 2>/dev/null; then
  echo "› signed with Apple Developer ID ($DEV_ID) — trusted, notarizable"
elif [ -n "$APPLE_DEV" ] && codesign --force --timestamp --sign "$APPLE_DEV" --identifier "$BUNDLE_ID" "$APP" 2>/dev/null; then
  echo "› signed with Apple Development cert ($APPLE_DEV) — stable identity, TCC grants persist"
else
  echo "› ad-hoc signing (permission prompts will re-appear after every rebuild)"
  codesign --force --sign - --identifier "$BUNDLE_ID" "$APP"
fi
echo "✓ built $APP — launch with:  open $APP"
