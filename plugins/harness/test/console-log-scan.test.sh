#!/usr/bin/env bash
# Dependency-free assertions for the console-log-scan Stop hook.
set -uo pipefail
HOOK="$(dirname "$0")/../hooks/scripts/console-log-scan.sh"
T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT
fail=0
check() { # name | dir | expect-substring-or-EMPTY
  local name="$1" dir="$2" expect="$3"
  local out; out=$(printf '{"cwd":"%s"}' "$dir" | CLAUDE_PROJECT_DIR="$dir" bash "$HOOK")
  local got
  if [ -z "$out" ]; then got="EMPTY"; else got=$(printf '%s' "$out" | jq -r '.systemMessage // "EMPTY"' 2>/dev/null || echo EMPTY); fi
  case "$got" in
    *"$expect"*) echo "ok   - $name" ;;
    *) echo "FAIL - $name (got '$got' want match '$expect')"; fail=1 ;;
  esac
}

# Not a git repo -> silent.
N="$T/plain"; mkdir -p "$N"
check "non-git dir is silent" "$N" "EMPTY"

# Git repo: commit a clean file, then dirty it with console.log.
R="$T/repo"; mkdir -p "$R"
git -C "$R" init -q
git -C "$R" -c user.email=t@t -c user.name=t commit -q --allow-empty -m init
printf 'export const x = 1\n' > "$R/app.ts"
git -C "$R" add app.ts
git -C "$R" -c user.email=t@t -c user.name=t commit -q -m add
check "clean modified set is silent" "$R" "EMPTY"

printf 'export const x = 1\nconsole.log(x)\n' > "$R/app.ts"
check "console.log in modified file warns" "$R" "app.ts (1)"

# Non-JS files never warn, even with console.log-looking content.
printf 'console.log in prose\n' > "$R/README.md"
git -C "$R" add README.md
git -C "$R" -c user.email=t@t -c user.name=t commit -q -m readme
printf 'more console.log prose\n' > "$R/README.md"
git -C "$R" checkout -q app.ts
check "md changes are ignored" "$R" "EMPTY"
exit $fail
