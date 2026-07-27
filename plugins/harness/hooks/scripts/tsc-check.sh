#!/usr/bin/env bash
# PostToolUse hook: type-check TypeScript edits at write time instead of at
# the loop's verify gate. Cheap exits keep it silent everywhere it doesn't
# apply: not a TS file, no tsconfig.json at the project root, no locally
# installed tsc (never npx-installs). Reports only errors in the edited file
# — project-wide errors are pre-existing noise — capped at 10 lines.
set -uo pipefail
INPUT=$(cat)
FILE=$(printf '%s' "$INPUT" | jq -r '.tool_input.file_path // ""')
case "$FILE" in
  *.ts|*.tsx|*.mts|*.cts) ;;
  *) echo '{}'; exit 0 ;;
esac
DIR="${CLAUDE_PROJECT_DIR:-$(printf '%s' "$INPUT" | jq -r '.cwd // "."')}"
if [ ! -f "$DIR/tsconfig.json" ]; then echo '{}'; exit 0; fi
TSC="$DIR/node_modules/.bin/tsc"
if [ ! -x "$TSC" ]; then echo '{}'; exit 0; fi
REL="${FILE#"$DIR"/}"
ERRORS=$( (cd "$DIR" && "$TSC" --noEmit --pretty false 2>&1 || true) | grep -F "$REL(" | head -10 )
if [ -n "$ERRORS" ]; then
  jq -n --arg f "$REL" --arg e "$ERRORS" \
    '{decision:"block", reason:("tsc reports type errors in " + $f + " after this edit — fix them now:\n" + $e)}'
else
  echo '{}'
fi
