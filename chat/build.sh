#!/bin/bash
# Build the native WhatsApp client.
#   ./build.sh              → builds to chat/build/<APP_NAME>.app
#   ./build.sh --install    → also installs it to /Applications
#
# ─── RENAMING THE APP ────────────────────────────────────────────────────────
# Change APP_NAME and BUNDLE_ID below and rebuild. Nothing else needs touching:
# Shell.swift reads its own name out of the bundle, and the injected CSS/JS are
# namespaced `shell`, not after the app. Optionally `git mv chat <newname>`.
# NOTE: BUNDLE_ID is the key to the WebKit data store, so changing it after
# you've linked WhatsApp means scanning the QR code once more. APP_NAME alone is
# free to change; keep BUNDLE_ID stable once you're using the app.
# ─────────────────────────────────────────────────────────────────────────────
set -euo pipefail
cd "$(dirname "$0")"

APP_NAME="CHAT"
BUNDLE_ID="com.labern.chat"

VERSION="1.0"
IDENTITY="chat-local"                  # fallback stable local identity
MIN_OS="13.0"                          # WKDownload + inspectable webviews
BUILD="build"
APP="$BUILD/$APP_NAME.app"
RES="$APP/Contents/Resources"

rm -rf "$BUILD"; mkdir -p "$APP/Contents/MacOS" "$RES"

# ---- 1. icon ----
echo "› rendering icon"
swiftc -O makeicon.swift -o "$BUILD/makeicon"
"$BUILD/makeicon" "$BUILD/$APP_NAME.iconset" >/dev/null
iconutil -c icns "$BUILD/$APP_NAME.iconset" -o "$RES/$APP_NAME.icns"

# ---- 2. injected resources ----
# Read at runtime rather than baked into the binary, so a theme tweak is a file
# edit plus ⌘R — no recompile.
echo "› staging theme.css + shell.js"
cp Resources/theme.css Resources/shell.js "$RES/"

# ---- 3. Info.plist ----
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
  <key>CFBundleIconFile</key><string>$APP_NAME</string>
  <key>LSMinimumSystemVersion</key><string>$MIN_OS</string>
  <key>NSHighResolutionCapable</key><true/>
  <key>LSApplicationCategoryType</key><string>public.app-category.social-networking</string>
  <key>NSHumanReadableCopyright</key><string>A native macOS client for WhatsApp</string>
  <key>NSMicrophoneUsageDescription</key><string>So you can record voice messages and take calls.</string>
  <key>NSCameraUsageDescription</key><string>So you can take photos and make video calls.</string>
</dict></plist>
PLIST

# ---- 4. compile ----
# -swift-version 5 keeps the Carbon hot-key C callback out of strict-concurrency
# territory (see the hotkey-agent blueprint, gotcha 6).
echo "› compiling"
swiftc -O -swift-version 5 -parse-as-library Shell.swift \
  -o "$APP/Contents/MacOS/$APP_NAME" \
  -framework Cocoa -framework WebKit -framework Carbon -framework UserNotifications

strip -S -x "$APP/Contents/MacOS/$APP_NAME"

# ---- 5. sign (auto-detects an Apple Developer ID; degrades gracefully) ----
# Copied resources carry xattrs from the source tree; codesign refuses to sign over them.
xattr -cr "$APP" 2>/dev/null || true

DEV_ID="$(security find-identity -v -p codesigning 2>/dev/null | sed -n 's/.*"\(Developer ID Application:[^"]*\)".*/\1/p' | head -1)"
# Second tier: the Apple Development certificate. Not for distribution, but it is
# a real, STABLE identity — which is what makes the microphone grant (voice notes)
# survive a rebuild instead of being asked for again every time. Auto-detected the
# same way, so nothing here hardcodes a Team ID.
APPLE_DEV="$(security find-identity -v -p codesigning 2>/dev/null | sed -n 's/.*"\(Apple Development:[^"]*\)".*/\1/p' | head -1)"

if [ -n "$DEV_ID" ]; then
  codesign --force --options runtime --timestamp --sign "$DEV_ID" --identifier "$BUNDLE_ID" "$APP"
  echo "› signed with Apple Developer ID ($DEV_ID) — trusted, notarizable"
elif [ -n "$APPLE_DEV" ]; then
  codesign --force --sign "$APPLE_DEV" --identifier "$BUNDLE_ID" "$APP"
  echo "› signed with Apple Development cert ($APPLE_DEV) — stable, so TCC grants persist"
elif codesign --force --sign "$IDENTITY" --identifier "$BUNDLE_ID" "$APP" 2>/dev/null; then
  echo "› signed with stable local identity ($IDENTITY)"
else
  echo "› ad-hoc signing — no stable identity, so mic/camera grants reset on each rebuild"
  codesign --force --sign - "$APP"
fi

echo "› built $APP"

if [ "${1:-}" = "--install" ]; then
  pkill -x "$APP_NAME" 2>/dev/null || true
  rm -rf "/Applications/$APP_NAME.app"
  cp -R "$APP" "/Applications/$APP_NAME.app"
  echo "› installed to /Applications/$APP_NAME.app"
fi
