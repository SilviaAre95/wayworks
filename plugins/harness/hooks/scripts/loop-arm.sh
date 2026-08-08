#!/usr/bin/env bash
# Arm a harness loop by creating its sentinel and state files.
#
# This exists because Claude Code blocks shell output redirection inside a
# command's `!` pre-execution block. The loops used to arm with
#
#   !`touch .cc-loop-dev-active && echo 0 > .cc-loop-dev-state && ...`
#
# and as of ~2.1.223 that fails the permission check outright:
#
#   Output redirection to '.../.cc-loop-dev-state' was blocked.
#
# declaring Bash(echo:*) does not help — running `echo` and *redirecting* it
# to a file are checked separately. Inside a script the redirection is never
# parsed by the permission checker; the grant is on invoking this path, so
# `allowed-tools` names the script instead of the shell builtins.
#
# Usage: loop-arm.sh dev|build|deploy [dir]
set -uo pipefail
DIR="${2:-$PWD}"

case "${1:-}" in
  dev)    sentinel=.cc-loop-dev-active; state=.cc-loop-dev-state; stale=".cc-dev-reviews-passed .cc-loop-dev-rounds"; label="loop-dev" ;;
  build)  sentinel=.cc-loop-active;     state=.cc-loop-state;     stale="";                                           label="loop" ;;
  deploy) sentinel=.cc-deploy-active;   state=.cc-deploy-state;   stale="";                                           label="loop-deploy" ;;
  *) echo "usage: loop-arm.sh dev|build|deploy [dir]" >&2; exit 2 ;;
esac

cd "$DIR" 2>/dev/null || { echo "ARM FAILED: cannot enter $DIR" >&2; exit 1; }

# Fail with the real reason rather than a partial arm. A sentinel without its
# state file leaves the Stop hook armed against a loop that never initialised.
if ! touch "$sentinel" 2>/dev/null; then
  echo "ARM FAILED: cannot write $sentinel in $PWD" >&2
  echo "  The session may not be permitted to write here. Start Claude Code" >&2
  echo "  from the repository root, or add this directory with /add-dir." >&2
  exit 1
fi
if ! echo 0 > "$state" 2>/dev/null; then
  echo "ARM FAILED: cannot write $state in $PWD" >&2
  rm -f "$sentinel"
  exit 1
fi

# Markers from an earlier run are anchored to a different tree; the gate would
# reject them anyway, but clearing here keeps the arm deterministic.
[ -n "$stale" ] && rm -f $stale

echo "$label armed"
