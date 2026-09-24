#!/usr/bin/env bash
# loop-deploy gate must ignore the other loops' sentinels, and vice versa.
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DEP="$ROOT/hooks/scripts/loop-deploy-gate.sh"
DEV="$ROOT/hooks/scripts/loop-dev-gate.sh"
BUILD="$ROOT/hooks/scripts/loop-gate.sh"
pass=0; fail=0
empty() { if [ -z "$2" ]; then echo "ok: $1"; pass=$((pass+1)); else echo "FAIL: $1 got: $2"; fail=$((fail+1)); fi; }

# CLAUDE_PROJECT_DIR is pinned to the temp dir: when these tests run under a
# Stop hook (the gates gate their own repo), the hook env leaks the real
# project dir and the gates would otherwise resolve DIR to it — recursing into
# the armed loop and contending on the real .cc-loop-gate.lock.

# deploy gate ignores build + dev sentinels
d=$(mktemp -d); touch "$d/.cc-loop-active" "$d/.cc-loop-dev-active"
empty "deploy-gate ignores other sentinels" "$(printf '{"cwd":"%s"}' "$d" | CLAUDE_PROJECT_DIR="$d" bash "$DEP")"; rm -rf "$d"
# build + dev gates ignore deploy sentinel
d=$(mktemp -d); touch "$d/.cc-deploy-active"
empty "build-gate ignores deploy sentinel" "$(printf '{"cwd":"%s"}' "$d" | CLAUDE_PROJECT_DIR="$d" bash "$BUILD")"
empty "dev-gate ignores deploy sentinel" "$(printf '{"cwd":"%s"}' "$d" | CLAUDE_PROJECT_DIR="$d" bash "$DEV")"; rm -rf "$d"

echo "---"; echo "pass=$pass fail=$fail"; [ "$fail" -eq 0 ]
