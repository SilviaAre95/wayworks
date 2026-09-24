#!/usr/bin/env bash
# Each gate must ignore the other's sentinel.
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DEV="$ROOT/hooks/scripts/loop-dev-gate.sh"; BUILD="$ROOT/hooks/scripts/loop-gate.sh"
pass=0; fail=0
expect_empty() { if [ -z "$2" ]; then echo "ok: $1"; pass=$((pass+1)); else echo "FAIL: $1 got: $2"; fail=$((fail+1)); fi; }

# CLAUDE_PROJECT_DIR is pinned to the temp dir: under a Stop hook the env
# leaks the real project dir and the gates would resolve DIR to it instead.

# loop-build sentinel only -> loop-dev gate must allow (empty)
d=$(mktemp -d); touch "$d/.cc-loop-active"
out=$(printf '{"cwd":"%s"}' "$d" | CLAUDE_PROJECT_DIR="$d" bash "$DEV"); expect_empty "dev-gate ignores build sentinel" "$out"; rm -rf "$d"

# loop-dev sentinel only -> loop-build gate must allow (empty)
d=$(mktemp -d); touch "$d/.cc-loop-dev-active"
out=$(printf '{"cwd":"%s"}' "$d" | CLAUDE_PROJECT_DIR="$d" bash "$BUILD"); expect_empty "build-gate ignores dev sentinel" "$out"; rm -rf "$d"

echo "---"; echo "pass=$pass fail=$fail"; [ "$fail" -eq 0 ]
