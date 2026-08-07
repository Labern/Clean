#!/bin/bash
# Build the ★★★★★ × PARADOX Command Centre.
#   ./build.sh              → builds to $TMPDIR/command-centre-build/<APP_NAME>.app
#   ./build.sh --install    → also installs it to /Applications
#
# ─── RENAMING THE APP ────────────────────────────────────────────────────────
# The name is deliberately kept in one place. Change APP_NAME (and BUNDLE_ID if
# you want a fresh state file) and rebuild — nothing in the Swift depends on it.
# The saved state lives under ~/Library/Application Support/PARADOX Command Centre/,
# keyed by that folder name rather than the bundle id, so renaming the app never
# loses a word of what is on the walls.
# ─────────────────────────────────────────────────────────────────────────────
set -euo pipefail
cd "$(dirname "$0")"

APP_NAME="Command Centre"
BUNDLE_ID="com.labern.commandcentre"

VERSION="1.0"
IDENTITY="commandcentre-local"         # fallback stable local identity
MIN_OS="13.0"                          # TextField(axis:) needs Ventura

# Build OUTSIDE the project: this repo lives on an iCloud-synced Desktop, and the
# FileProvider stamps xattrs onto new directories that make codesign refuse the
# bundle ("resource fork, Finder information, or similar detritus not allowed").
# Building in TMPDIR sidesteps the race completely.
BUILD="${CC_BUILD_DIR:-${TMPDIR:-/tmp}}/command-centre-build"
APP="$BUILD/$APP_NAME.app"
RES="$APP/Contents/Resources"

rm -rf "$BUILD"; mkdir -p "$APP/Contents/MacOS" "$RES"

# ---- 1. icon ----
echo "› rendering icon"
swiftc -O makeicon.swift -o "$BUILD/makeicon"
"$BUILD/makeicon" "$BUILD/AppIcon.iconset" >/dev/null
iconutil -c icns "$BUILD/AppIcon.iconset" -o "$RES/AppIcon.icns"

# ---- 2. Info.plist ----
cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleName</key><string>$APP_NAME</string>
  <key>CFBundleDisplayName</key><string>$APP_NAME</string>
  <key>CFBundleExecutable</key><string>$APP_NAME</string>
  <key>CFBundleIdentifier</key><string>$BUNDLE_ID</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>$VERSION</string>
  <key>CFBundleVersion</key><string>$VERSION</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>LSMinimumSystemVersion</key><string>$MIN_OS</string>
  <key>NSHighResolutionCapable</key><true/>
  <key>LSApplicationCategoryType</key><string>public.app-category.productivity</string>
  <key>NSHumanReadableCopyright</key><string>★★★★★ × PARADOX</string>
</dict></plist>
PLIST

# ---- 3. compile ----
echo "› compiling"
swiftc -O -swift-version 5 -parse-as-library CommandCentre.swift \
  -o "$APP/Contents/MacOS/$APP_NAME" \
  -framework Cocoa -framework SwiftUI -framework Combine

strip -S -x "$APP/Contents/MacOS/$APP_NAME"

# ---- 4. sign (auto-detects an Apple Developer ID; degrades gracefully) ----
xattr -cr "$APP" 2>/dev/null || true

DEV_ID="$(security find-identity -v -p codesigning 2>/dev/null | sed -n 's/.*"\(Developer ID Application:[^"]*\)".*/\1/p' | head -1)"
APPLE_DEV="$(security find-identity -v -p codesigning 2>/dev/null | sed -n 's/.*"\(Apple Development:[^"]*\)".*/\1/p' | head -1)"

if [ -n "$DEV_ID" ]; then
  codesign --force --options runtime --timestamp --sign "$DEV_ID" --identifier "$BUNDLE_ID" "$APP"
  echo "› signed with Apple Developer ID ($DEV_ID) — trusted, notarizable"
elif [ -n "$APPLE_DEV" ]; then
  codesign --force --sign "$APPLE_DEV" --identifier "$BUNDLE_ID" "$APP"
  echo "› signed with Apple Development cert ($APPLE_DEV) — stable identity"
elif codesign --force --sign "$IDENTITY" --identifier "$BUNDLE_ID" "$APP" 2>/dev/null; then
  echo "› signed with stable local identity ($IDENTITY)"
else
  echo "› ad-hoc signing (run a setup-signing step for a stable identity)"
  codesign --force --sign - "$APP"
fi

echo "› built $APP"

if [ "${1:-}" = "--install" ]; then
  pkill -x "$APP_NAME" 2>/dev/null || true
  rm -rf "/Applications/$APP_NAME.app"
  cp -R "$APP" "/Applications/$APP_NAME.app"
  echo "› installed to /Applications/$APP_NAME.app"
fi
