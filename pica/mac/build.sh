#!/bin/bash
# Build PICA.app — a native ⌘-Tab application wrapping the PICA editor.
#   ./build.sh            → builds to pica/mac/build/PICA.app
#   ./build.sh --install  → also copies it to /Applications
set -euo pipefail
cd "$(dirname "$0")"

# THE CONTRACT, enforced at the door: nothing ships to /Applications without the
# gates green. The fidelity gate + every regression mini-gate run first; the
# headless smoketest runs against the built bundle after. PICA_SKIP_TESTS=1 only
# for emergencies, and you had better mean it.
if [ "${1:-}" = "--install" ] && [ -z "${PICA_SKIP_TESTS:-}" ]; then
  echo "› gates: fidelity + regression mini-gates"
  if ! node ../tests/run.mjs > /tmp/pica-gate.log 2>&1; then
    echo "GATES RED — install refused. tail of /tmp/pica-gate.log:"
    tail -12 /tmp/pica-gate.log
    exit 1
  fi
  tail -1 /tmp/pica-gate.log
fi

APP_NAME="PICA"
BUNDLE_ID="com.labern.pica"
VERSION="1.0"
IDENTITY="pica-local"                 # fallback stable local identity
# build outside the repo: Desktop is iCloud-synced, and its xattr re-tagging lands
# between the xattr-clean and codesign, failing the signature ("detritus")
BUILD="${PICA_BUILD_DIR:-/tmp/pica-build}"
APP="$BUILD/$APP_NAME.app"
RES="$APP/Contents/Resources"
WEB="$RES/web"
PDFJS="4.10.38"

rm -rf "$BUILD"; mkdir -p "$APP/Contents/MacOS" "$WEB/fonts" "$WEB/vendor"

# ---- 1. icon: black mark on a white tile, rendered at every size ----
echo "› rendering icon"
swiftc -O makeicon.swift -o "$BUILD/makeicon" 2>/dev/null
"$BUILD/makeicon" "$BUILD/$APP_NAME.iconset" >/dev/null
iconutil -c icns "$BUILD/$APP_NAME.iconset" -o "$RES/$APP_NAME.icns"

# ---- 2. the app itself: index.html verbatim, plus offline assets ----
echo "› staging web app"
cp ../index.html "$WEB/index.html"
cp ../fonts/*.ttf "$WEB/fonts/" 2>/dev/null || echo "  ! fonts missing — will fall back to Courier New offline"

# pdf.js is fetched at build time rather than committed; without it the app still
# imports PDFs, but only when online (it falls back to the CDN).
# the studio card — one file, shared by every product; see ~/Desktop/★★★★★/brand
CARD="$HOME/Desktop/★★★★★/brand/studio-card.html"
# the app's own logo, drawn for paper: made beside the iconset by makeicon
if [ -f "$BUILD/card-icon.png" ]; then
  cp "$BUILD/card-icon.png" "$WEB/app-icon.png"
  cp "$BUILD/card-icon.png" "../app-icon.png"
fi

if [ -f "$CARD" ]; then
  # into the bundle, and beside index.html so the web build ships the same file —
  # every build re-syncs from the master copy, so the two can never drift apart
  cp "$CARD" "$WEB/studio-card.html"
  cp "$CARD" "../studio-card.html"      # build.sh runs from mac/; the web copy lives beside index.html
  echo "  › studio card bundled"
else
  echo "  › no studio card found at $CARD — the app will simply open without one"
fi

if [ ! -f "vendor-cache/pdf.min.mjs" ]; then
  echo "› fetching pdf.js $PDFJS"
  mkdir -p vendor-cache
  curl -sfL "https://cdn.jsdelivr.net/npm/pdfjs-dist@$PDFJS/legacy/build/pdf.min.mjs" -o vendor-cache/pdf.min.mjs || true
  curl -sfL "https://cdn.jsdelivr.net/npm/pdfjs-dist@$PDFJS/legacy/build/pdf.worker.min.mjs" -o vendor-cache/pdf.worker.min.mjs || true
fi
if [ -s "vendor-cache/pdf.min.mjs" ] && [ -s "vendor-cache/pdf.worker.min.mjs" ]; then
  cp vendor-cache/pdf.min.mjs vendor-cache/pdf.worker.min.mjs "$WEB/vendor/"
  echo "  › pdf.js bundled — PDF import works offline"
else
  rmdir "$WEB/vendor" 2>/dev/null || true
  echo "  ! pdf.js not bundled — PDF import will need the network"
fi

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
  <key>LSMinimumSystemVersion</key><string>12.0</string>
  <key>NSHighResolutionCapable</key><true/>
  <key>NSSupportsAutomaticTermination</key><false/>
  <key>NSSupportsSuddenTermination</key><false/>
  <key>LSApplicationCategoryType</key><string>public.app-category.productivity</string>
  <key>NSHumanReadableCopyright</key><string>PICA — a screenwriting instrument</string>
  <key>CFBundleDocumentTypes</key><array>
    <dict>
      <key>CFBundleTypeName</key><string>Screenplay PDF</string>
      <key>CFBundleTypeRole</key><string>Editor</string>
      <key>LSHandlerRank</key><string>Alternate</string>
      <key>LSItemContentTypes</key><array><string>com.adobe.pdf</string></array>
    </dict>
    <dict>
      <key>CFBundleTypeName</key><string>PICA Script</string>
      <key>CFBundleTypeRole</key><string>Editor</string>
      <key>LSHandlerRank</key><string>Alternate</string>
      <key>LSItemContentTypes</key><array><string>public.json</string></array>
    </dict>
  </array>
</dict></plist>
PLIST

# ---- 4. compile ----
echo "› compiling"
swiftc -O -parse-as-library PICA.swift WebProxy.swift OCR.swift Splash.swift -o "$APP/Contents/MacOS/$APP_NAME" \
  -framework Cocoa -framework WebKit

# ---- 5. sign (auto-detects an Apple Developer ID; degrades gracefully) ----
# copied resources carry xattrs from the source tree; codesign refuses to sign over them
xattr -cr "$APP" 2>/dev/null || true

DEV_ID="$(security find-identity -v -p codesigning 2>/dev/null | sed -n 's/.*"\(Developer ID Application:[^"]*\)".*/\1/p' | head -1)"

if [ -n "$DEV_ID" ]; then
  codesign --force --options runtime --timestamp --sign "$DEV_ID" --identifier "$BUNDLE_ID" "$APP"
  echo "› signed with Apple Developer ID ($DEV_ID) — trusted, notarizable"
elif codesign --force --sign "$IDENTITY" --identifier "$BUNDLE_ID" "$APP" 2>/dev/null; then
  echo "› signed with stable local identity ($IDENTITY)"
else
  echo "› ad-hoc signing (run setup-signing.sh for a stable identity)"
  codesign --force --sign - "$APP"
fi

echo "› built $APP"

if [ "${1:-}" = "--install" ]; then
  if [ -z "${PICA_SKIP_TESTS:-}" ]; then
    echo "› smoketest: driving the built bundle headlessly"
    # NEVER hide this: a compile error here used to leave a STALE smoketest binary in
    # place, which then passed happily without running the step that had just been added.
    # two files means top-level code needs the entry point to be called main.swift
    cp smoketest.swift "$BUILD/main.swift"
    if ! swiftc -O "$BUILD/main.swift" WebProxy.swift OCR.swift -o "$BUILD/smoketest"; then
      echo "SMOKETEST DID NOT COMPILE — install refused"
      exit 1
    fi
    if ! PICA_BUILD_DIR="$BUILD" "$BUILD/smoketest" > /tmp/pica-smoke.log 2>&1; then
      echo "SMOKETEST RED — install refused. tail of /tmp/pica-smoke.log:"
      tail -12 /tmp/pica-smoke.log
      exit 1
    fi
    tail -1 /tmp/pica-smoke.log
  fi
  rm -rf "/Applications/$APP_NAME.app"
  cp -R "$APP" "/Applications/$APP_NAME.app"
  echo "› installed to /Applications/$APP_NAME.app"
fi
