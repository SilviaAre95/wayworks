#!/usr/bin/env bash
# Dependency-free assertions for the block-stray-docs PreToolUse hook.
set -uo pipefail
HOOK="$(dirname "$0")/../hooks/scripts/block-stray-docs.sh"
T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT
fail=0
check() { # name | file_path | tool | expect-decision-or-EMPTY
  local name="$1" path="$2" tool="$3" expect="$4"
  local out; out=$(printf '{"tool_name":"%s","tool_input":{"file_path":"%s"}}' "$tool" "$path" | bash "$HOOK")
  local got; got=$(printf '%s' "$out" | jq -r '.hookSpecificOutput.permissionDecision // "EMPTY"' 2>/dev/null || echo PARSE_ERR)
  if [ "$got" = "$expect" ]; then echo "ok   - $name"; else echo "FAIL - $name (got '$got' want '$expect')"; fail=1; fi
}
mkdir -p "$T/proj/docs" "$T/proj/src" "$T/proj/skills/foo"
check "stray root md asks"        "$T/proj/NOTES.md"            Write "ask"
check "stray txt asks"            "$T/proj/summary.txt"         Write "ask"
check "README allowed"            "$T/proj/README.md"           Write "EMPTY"
check "CLAUDE.md allowed"         "$T/proj/CLAUDE.md"           Write "EMPTY"
check "CHANGELOG allowed"         "$T/proj/CHANGELOG.md"        Write "EMPTY"
check "docs/ allowed"             "$T/proj/docs/arch.md"        Write "EMPTY"
check "skills/ allowed"           "$T/proj/skills/foo/guide.md" Write "EMPTY"
check "non-doc file defers"       "$T/proj/src/foo.ts"          Write "EMPTY"
check "non-Write tool defers"     "$T/proj/NOTES.md"            Edit  "EMPTY"
echo "existing" > "$T/proj/EXISTING.md"
check "existing doc defers"       "$T/proj/EXISTING.md"         Write "EMPTY"
exit $fail
