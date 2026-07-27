#!/usr/bin/env bash
# Dependency-free assertions for the tsc-check PostToolUse hook.
# The "tsc" used in error-path tests is a stub script, so no real
# TypeScript install is needed.
set -uo pipefail
HOOK="$(dirname "$0")/../hooks/scripts/tsc-check.sh"
T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT
fail=0
check() { # name | project-dir | file_path | expect-decision-or-EMPTY
  local name="$1" dir="$2" path="$3" expect="$4"
  local out; out=$(printf '{"tool_input":{"file_path":"%s"},"cwd":"%s"}' "$path" "$dir" \
    | CLAUDE_PROJECT_DIR="$dir" bash "$HOOK")
  local got; got=$(printf '%s' "$out" | jq -r '.decision // "EMPTY"' 2>/dev/null || echo PARSE_ERR)
  if [ "$got" = "$expect" ]; then echo "ok   - $name"; else echo "FAIL - $name (got '$got' want '$expect')"; fail=1; fi
}

# Project with a tsc stub that reports an error in src/bad.ts only.
P="$T/proj"; mkdir -p "$P/src" "$P/node_modules/.bin"
echo '{}' > "$P/tsconfig.json"
cat > "$P/node_modules/.bin/tsc" <<'EOF'
#!/usr/bin/env bash
echo "src/bad.ts(1,1): error TS2322: Type 'string' is not assignable to type 'number'."
exit 2
EOF
chmod +x "$P/node_modules/.bin/tsc"

# Project with no tsconfig at all.
N="$T/notsc"; mkdir -p "$N"

check "non-TS file skips"              "$P" "$P/src/app.css"  "EMPTY"
check "no tsconfig skips"              "$N" "$N/foo.ts"       "EMPTY"
check "error in edited file blocks"    "$P" "$P/src/bad.ts"   "block"
check "error in other file stays quiet" "$P" "$P/src/ok.ts"   "EMPTY"

rm "$P/node_modules/.bin/tsc"
check "missing local tsc skips"        "$P" "$P/src/bad.ts"   "EMPTY"
exit $fail
