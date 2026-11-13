#!/bin/bash
# Focus test suite.
#
#   ./test.sh          QUICK — run after every major change. ~30 s. Opens and quits no apps.
#                      Builds with zero warnings, then checks the menu, settings, history and shortcuts.
#   ./test.sh full     FULL — run when it's needed (before a release, after touching sessions or quitting). ~7 min.
#                      Every scenario: sessions, modes, crash recovery, save prompts, self-relaunching apps, the launch
#                      race. Uses only TextEdit, Calculator and throwaway stand-in apps, with Focus's separate test
#                      settings. Restarts the installed Focus once (for the launch-race test).
#
# Both print a plain-English pass/fail table and save it to docs/TEST-REPORT.md.
set -u
cd "$(dirname "$0")"
MODE="${1:-quick}"
WORK="${TMPDIR:-/tmp}/focus-tests"; mkdir -p "$WORK"
BIN="Focus.app/Contents/MacOS/Focus"
REPORT="docs/TEST-REPORT.md"
RESULTS=()                                   # "PASS|FAIL<TAB>name<TAB>detail"
started=$(date +%s)

record() { RESULTS+=("$1	$2	$3"); printf '  %s  %s\n' "$1" "$2"; }
quiet_mic() { [ -x "$HOME/.claude/scripts/micbusy" ] && "$HOME/.claude/scripts/micbusy" --wait 4; return 0; }

# Lines from the in-app harness: "stress: PASS  N. name — detail"
collect() {
    while IFS= read -r line; do
        case "$line" in
            "stress: PASS  "*|"stress: FAIL  "*)
                v="${line:8:4}"; rest="${line:14}"
                record "$v" "${rest%% — *}" "${rest#* — }" ;;
        esac
    done
}

echo "Focus tests — $MODE"
echo "1. Build"
build_log=$(./build.sh --ci 2>&1)
warnings=$(grep -c "warning:" <<< "$build_log"); errors=$(grep -c "error:" <<< "$build_log")
if [ "$errors" = 0 ] && [ "$warnings" = 0 ] && [ -x "$BIN" ]; then record PASS "Builds with zero errors and zero warnings" ""
else record FAIL "Builds with zero errors and zero warnings" "$errors errors, $warnings warnings"; fi

echo "2. Menu, settings, history, shortcuts"
collect < <("$BIN" --selftest-stress --only=4,9,16,18,23,24,26,27,28,29,32,33,34,35,36,38,39 2>&1)   # not a pipe: results must reach this shell

if [ "$MODE" = "full" ]; then
    quiet_mic
    echo "3. Stand-in apps"
    for N in SavePromptStandIn SlowQuit Relauncher; do
        L=$(echo "$N" | tr 'A-Z' 'a-z'); A="$WORK/$N.app"
        mkdir -p "$A/Contents/MacOS"
        swiftc -O tests/standins.swift -o "$A/Contents/MacOS/$N" 2>/dev/null
        printf '<?xml version="1.0" encoding="UTF-8"?><plist version="1.0"><dict><key>CFBundleExecutable</key><string>%s</string><key>CFBundleIdentifier</key><string>com.labern.focus.%s</string><key>CFBundleName</key><string>%s</string><key>CFBundlePackageType</key><string>APPL</string></dict></plist>' "$N" "$L" "$N" > "$A/Contents/Info.plist"
        codesign -fs - "$A" >/dev/null 2>&1
    done

    echo "4. Every session scenario"
    open -g -j "$WORK/SlowQuit.app"; open -g -j "$WORK/Relauncher.app"
    ( for _ in $(seq 1 420); do pgrep -x Relauncher >/dev/null || open -g -j "$WORK/Relauncher.app"; sleep 1; done ) & WATCH=$!
    sleep 2
    collect < <("$BIN" --selftest-stress 2>&1 | grep -v -E "stress: (PASS|FAIL)  (4|9|16|18|23|24|26|27|28|29|32|33|34|35|36|38|39)\.")
    kill "$WATCH" 2>/dev/null; pkill -x Relauncher; pkill -x SlowQuit

    echo "5. Snapshot and a full session on TextEdit"
    open -g -j -a TextEdit; sleep 2
    out=$("$BIN" --selftest 2>&1 | grep "selftest:" | grep -v protected)
    if echo "$out" | grep -q "✗\|ABORT"; then record FAIL "Session on TextEdit, snapshot kept, newest + one spare" "$(echo "$out" | grep "✗\|ABORT" | head -1)"
    else record PASS "Session on TextEdit, snapshot kept, newest + one spare" ""; fi

    echo "6. An app stuck on a save prompt"
    open -g -j "$WORK/SavePromptStandIn.app"; open -g -j -a Calculator; sleep 2
    out=$("$BIN" --selftest-unsaved 2>&1 | grep "selftest:")
    pkill -9 -x SavePromptStandIn
    if echo "$out" | grep -q "✗\|ABORT"; then record FAIL "Save prompt doesn't stall the queue; app brought forward" "$(echo "$out" | grep "✗\|ABORT" | head -1)"
    else record PASS "Save prompt doesn't stall the queue; app brought forward" ""; fi

    echo "7. Crash mid-session (SIGKILL), then a fresh Focus"
    "$BIN" --selftest-crash-a >/dev/null 2>&1
    out=$("$BIN" --selftest-crash-b 2>&1 | grep "stress:")
    if echo "$out" | grep -q "✗"; then record FAIL "Crash mid-session: a fresh Focus restores it" "$(echo "$out" | grep "✗" | head -1)"
    else record PASS "Crash mid-session: a fresh Focus restores it" ""; fi

    echo "8. Launch race (restarts the installed Focus)"
    fails=0
    for _ in 1 2 3 4 5; do
        pkill -x Focus; sleep 1.2
        open -n -g /Applications/Focus.app & open -n -g /Applications/Focus.app & open -n -g /Applications/Focus.app & wait
        sleep 3; [ "$(pgrep -x Focus | wc -l | tr -d ' ')" = 1 ] || fails=$((fails + 1))
    done
    pgrep -x Focus >/dev/null || open -g /Applications/Focus.app
    if [ "$fails" = 0 ]; then record PASS "Three Focus launches at once leave exactly one (5 rounds)" ""
    else record FAIL "Three Focus launches at once leave exactly one (5 rounds)" "$fails rounds wrong"; fi

    osascript -e 'tell application "TextEdit" to quit' -e 'tell application "Calculator" to quit' >/dev/null 2>&1
fi

# —— report ——
pass=0; fail=0
for r in "${RESULTS[@]}"; do [ "${r%%	*}" = PASS ] && pass=$((pass + 1)) || fail=$((fail + 1)); done
secs=$(( $(date +%s) - started ))
{
    echo "# Focus — test report"
    echo
    echo "**$MODE** run · version $(tr -d '[:space:]' < VERSION) · $(date '+%Y-%m-%d %H:%M') · ${secs}s · **$pass passed, $fail failed**"
    echo
    echo "| Result | Check | Detail |"
    echo "|---|---|---|"
    for r in "${RESULTS[@]}"; do IFS=$'\t' read -r v n d <<< "$r"; echo "| $v | $n | $d |"; done
    echo
    echo "Quick: \`./test.sh\` (every major change). Full: \`./test.sh full\` (when needed)."
} > "$REPORT"
echo
echo "$pass passed, $fail failed — ${secs}s. Report: focus/$REPORT"
[ "$fail" = 0 ]
