#!/bin/bash
# Runs on the Mac before every `ios-device` build (Labern/iOS calls it with the
# phone's devicectl id). Two jobs, and neither may ever stop an install:
#
# 1. Copy his data off the phone, from the build that is installed now:
#    Library/Application Support/{Backups,Icons,Profile} → ~/PARADOX backups/<stamp>/.
#    A folder the phone doesn't have yet is skipped; an empty stamp is removed;
#    the newest 60 stamps are kept.
# 2. Put every icon he made on the phone into design/icons/custom/ (gitignored),
#    so bake_custom.sh (preGenCommand) bakes it into this very build.
#
#   pre-device.sh <device-id>            both jobs
#   pre-device.sh <device-id> --backup   job 1 only (to look again after a launch)
set -u
DEV="${1:-}"; [ -n "$DEV" ] || exit 0
MODE="${2:-}"
BID="com.labern.paradox.hq"
HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$HOME/PARADOX backups"
OUT="$ROOT/$(date '+%Y-%m-%d %H%M%S')"

mkdir -p "$OUT" || exit 0
for X in Backups Icons Profile; do
  if MSG="$(xcrun devicectl device copy from --device "$DEV" --domain-type appDataContainer \
        --domain-identifier "$BID" --source "Library/Application Support/$X" \
        --destination "$OUT/$X" 2>&1)" && ! grep -q '^ERROR' <<< "$MSG" && [ -d "$OUT/$X" ]; then
    echo "› saved $X off the phone ($(find "$OUT/$X" -type f | wc -l | tr -d ' ') files)"
  else
    rm -rf "${OUT:?}/$X"
    echo "› $X: not on the phone yet"
  fi
done
if [ -z "$(find "$OUT" -type f 2>/dev/null | head -1)" ]; then
  rm -rf "$OUT"; echo "› nothing to save from the phone"
else
  echo "› saved to $OUT"
fi
# Keep the newest 60 stamped folders.
ls -1d "$ROOT"/2???-??-??\ ?????? 2>/dev/null | sort -r | tail -n +61 | while IFS= read -r old; do rm -rf "$old"; done

[ "$MODE" = "--backup" ] && exit 0

if [ -d "$OUT/Icons" ]; then
  mkdir -p "$HERE/design/icons/custom"
  n=0
  for png in "$OUT"/Icons/*.png; do
    [ -f "$png" ] || continue
    cp "$png" "$HERE/design/icons/custom/" && n=$((n + 1))
  done
  echo "› $n icon(s) from the phone to bake into this build"
fi
exit 0
