#!/bin/sh
# Bakes icons made in the app's designer into this build.
#
# iOS only lets an app wear icons it was built with. The designer saves each
# icon as <id>.png (1024px, no transparency) and the app copies them into
# "Icons to bake" inside the folder chosen in the app (•••). This runs before the Xcode project
# is generated (project.yml, preGenCommand): it turns every such picture into
# an AppIcon-Custom-<id> set and lists them in Custom.xcconfig, which the
# project reads as $(CUSTOM_APPICONS).
#
# Pictures are looked for in:
#   design/custom/                            (drop one here by hand)
#   any "Icons to bake" folder in iCloud Drive (where the phone copies them)
#
# It never fails the build: with nothing to bake it writes an empty list.

cd "$(dirname "$0")/.." || exit 0
ASSETS="Resources/Assets.xcassets"
LIST="${TMPDIR:-/tmp}/icons-app-folders.$$"
names=""
count=0

rm -rf "$ASSETS"/AppIcon-Custom-*.appiconset

bake() {
    id="$(basename "$1" .png | tr -cd 'A-Za-z0-9')"
    [ -n "$id" ] || return 0
    [ "$count" -lt 12 ] || return 0
    set="$ASSETS/AppIcon-Custom-$id.appiconset"
    [ -d "$set" ] && return 0
    mkdir -p "$set" && cp "$1" "$set/icon-1024.png" || { rm -rf "$set"; return 0; }
    cat > "$set/Contents.json" <<JSON
{
 "images": [
  {
   "filename": "icon-1024.png",
   "idiom": "universal",
   "platform": "ios",
   "size": "1024x1024"
  }
 ],
 "info": {
  "author": "xcode",
  "version": 1
 }
}
JSON
    names="$names AppIcon-Custom-$id"
    count=$((count + 1))
}

echo "design/custom" > "$LIST"
CLOUD="$HOME/Library/Mobile Documents/com~apple~CloudDocs"
[ -d "$CLOUD" ] && find "$CLOUD" -maxdepth 4 -type d -name "Icons to bake" >> "$LIST" 2>/dev/null

while IFS= read -r folder; do
    for picture in "$folder"/*.png; do
        [ -f "$picture" ] && bake "$picture"
    done
done < "$LIST"
rm -f "$LIST"

echo "CUSTOM_APPICONS =$names" > Custom.xcconfig
[ "$count" -gt 0 ] && echo "baked $count custom icon(s):$names"
exit 0
