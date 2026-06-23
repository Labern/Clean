#!/bin/bash
# Build Strata as a real .app bundle (required: WKWebView's persistent login
# cookies are keyed to the bundle identifier). Mirrors ClaudeUsageMonitor.
set -e
cd "$(dirname "$0")"

APP_NAME="Strata"
swift build -c release

APP="$APP_NAME.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp ".build/release/$APP_NAME" "$APP/Contents/MacOS/$APP_NAME"

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key><string>Strata</string>
    <key>CFBundleIdentifier</key><string>com.local.strata</string>
    <key>CFBundleName</key><string>Strata</string>
    <key>CFBundleDisplayName</key><string>Strata</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>0.1.0</string>
    <key>CFBundleVersion</key><string>1</string>
    <key>LSMinimumSystemVersion</key><string>13.0</string>
    <key>NSHighResolutionCapable</key><true/>
</dict>
</plist>
PLIST

codesign --force --deep -s - "$APP" 2>/dev/null || true
echo "Built $APP"

INSTALL_DIR="/Applications"
[ -w "$INSTALL_DIR" ] || INSTALL_DIR="$HOME/Applications"
mkdir -p "$INSTALL_DIR/$APP"
rsync -a --delete "$APP/" "$INSTALL_DIR/$APP/"
echo "Installed to $INSTALL_DIR/$APP"

open "$INSTALL_DIR/$APP"
