#!/bin/bash
# Puts global/standing-rules.md into ~/.claude/CLAUDE.md, the file every Claude
# session on this Mac reads whatever repo it is in. Safe to run any number of
# times: it replaces its own block and touches nothing else in the file.
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
target="${CLAUDE_GLOBAL:-$HOME/.claude/CLAUDE.md}"
start="<!-- standing-rules:start (managed by Clean/global/install.sh) -->"
end="<!-- standing-rules:end -->"
mkdir -p "$(dirname "$target")"
touch "$target"
tmp="$(mktemp)"
awk -v s="$start" -v e="$end" '$0==s{skip=1} !skip{print} $0==e{skip=0}' "$target" > "$tmp"
# Drop trailing blank lines left behind by a previous block.
printf '%s\n' "$(cat "$tmp")" > "$tmp"
{
  if grep -q '[^[:space:]]' "$tmp"; then cat "$tmp"; echo; fi
  echo "$start"; cat "$here/standing-rules.md"; echo "$end"
} > "$target"
rm -f "$tmp"
echo "standing rules installed in $target"
