#!/usr/bin/env bash
# Stop hook: non-blocking sweep for console.log left in modified tracked
# JS/TS files. Warns the user via systemMessage and always allows the stop —
# a console.log can be intentional, and blocking is the loop gates' job.
set -uo pipefail
INPUT=$(cat)
DIR="${CLAUDE_PROJECT_DIR:-$(printf '%s' "$INPUT" | jq -r '.cwd // "."')}"
git -C "$DIR" rev-parse --is-inside-work-tree >/dev/null 2>&1 || exit 0
HITS=""
while IFS= read -r f; do
  [ -f "$DIR/$f" ] || continue
  n=$(grep -c 'console\.log' -- "$DIR/$f" 2>/dev/null || true)
  if [ "${n:-0}" -gt 0 ] 2>/dev/null; then HITS="$HITS$f ($n) · "; fi
done < <(git -C "$DIR" diff --name-only HEAD -- '*.ts' '*.tsx' '*.js' '*.jsx' 2>/dev/null)
[ -n "$HITS" ] || exit 0
jq -n --arg h "${HITS% · }" '{systemMessage:("harness: console.log left in modified files — " + $h)}'
exit 0
