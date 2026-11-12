#!/bin/bash
# Builds Focus.app, installs it to /Applications and launches it. Needs only the Xcode command line tools.
#   ./build.sh            build + install + launch
#   ./build.sh --ci       build only (used by GitHub Actions)
set -e
trap 'echo "✗ build.sh failed at line $LINENO (if replacing /Applications/Focus.app: allow your terminal in Privacy & Security ▸ App Management)" >&2' ERR
cd "$(dirname "$0")"
# Built and signed outside the iCloud-synced Desktop: iCloud re-adds file attributes mid-build, and codesign
# rejects them ("resource fork, Finder information, or similar detritus not allowed") — intermittently.
OUT="${TMPDIR:-/tmp}/focus-build"; rm -rf "$OUT"; mkdir -p "$OUT"
C="$OUT/Focus.app/Contents"
mkdir -p "$C/MacOS"
swiftc -O -swift-version 5 main.swift -o "$C/MacOS/Focus"
mkdir -p "$C/Resources"                                  # app icon, drawn by the app's own glyph()
"$C/MacOS/Focus" --make-icon "$OUT/Focus.iconset" && iconutil -c icns "$OUT/Focus.iconset" -o "$C/Resources/Focus.icns"
cat > "$C/Info.plist" <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleExecutable</key><string>Focus</string>
  <key>CFBundleIdentifier</key><string>com.labern.focus</string>
  <key>CFBundleName</key><string>Focus</string>
  <key>CFBundleIconFile</key><string>Focus</string>
  <key>CFBundleShortVersionString</key><string>1.0</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>LSMinimumSystemVersion</key><string>13.0</string>
  <key>LSUIElement</key><true/>
</dict></plist>
EOF
APP="$OUT/Focus.app"; BUNDLE_ID=com.labern.focus; IDENTITY="${IDENTITY:-Focus Local Signing}"
DEV_ID="$(security find-identity -v -p codesigning 2>/dev/null | sed -n 's/.*"\(Developer ID Application:[^"]*\)".*/\1/p' | head -1)"
# Apple Development: not for distribution, but a stable identity — macOS keeps Focus's permissions across rebuilds.
APPLE_DEV="$(security find-identity -v -p codesigning 2>/dev/null | sed -n 's/.*"\(Apple Development:[^"]*\)".*/\1/p' | head -1)"

if [ -n "$DEV_ID" ]; then
  codesign --force --options runtime --timestamp --sign "$DEV_ID" --identifier "$BUNDLE_ID" "$APP"
  echo "› signed with Apple Developer ID ($DEV_ID) — trusted, notarizable"
elif [ -n "$APPLE_DEV" ] && codesign --force --sign "$APPLE_DEV" --identifier "$BUNDLE_ID" "$APP" 2>/dev/null; then
  echo "› signed with Apple Development (stable on this Mac; Developer ID needed to share it)"
elif codesign --force --sign "$IDENTITY" --identifier "$BUNDLE_ID" "$APP" 2>/dev/null; then
  echo "› signed with stable local identity ($IDENTITY)"
else
  echo "› ad-hoc signing (run setup-signing.sh for a stable identity)"
  codesign --force --sign - "$APP"
fi
rm -rf Focus.app && ditto "$APP" Focus.app             # a copy beside the source, for CI's zip and --selftest
if [ "$1" = "--ci" ]; then exit 0; fi
pkill -x Focus || true; sleep 1; pkill -9 -x Focus || true   # an old build can hang on quit
rm -rf /Applications/Focus.app && ditto "$APP" /Applications/Focus.app   # fixed location, so "Open at login" sticks
cmp -s "$APP/Contents/MacOS/Focus" /Applications/Focus.app/Contents/MacOS/Focus || { echo "✗ install failed — /Applications/Focus.app is not this build"; exit 1; }
open /Applications/Focus.app
