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
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/gate-standdown.sh"
DIR="${2:-$PWD}"

case "${1:-}" in
  dev)    sentinel=.cc-loop-dev-active; state=.cc-loop-dev-state; stale=".cc-dev-reviews-passed .cc-loop-dev-rounds"; label="loop-dev" ;;
  build)  sentinel=.cc-loop-active;     state=.cc-loop-state;     stale="";                                           label="loop" ;;
  deploy) sentinel=.cc-deploy-active;   state=.cc-deploy-state;   stale="";                                           label="loop-deploy" ;;
  *) echo "usage: loop-arm.sh dev|build|deploy [dir]" >&2; exit 2 ;;
esac

cd "$DIR" 2>/dev/null || { echo "ARM FAILED: cannot enter $DIR" >&2; exit 1; }

# The owner of a loop that is already armed, read before anything is written.
prev=$(head -1 "$sentinel" 2>/dev/null | tr -d '[:space:]')
[[ -z "$prev" || "$prev" =~ ^[A-Za-z0-9-]+$ ]] || prev="unrecognised"   # echoed to the agent and the log

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

# Record the arming session so a Stop from any other session in this checkout
# leaves the gate alone (gate-owner.sh). No usable id -> an ownerless sentinel,
# which every session drives; say so rather than arm quietly.
sid="${CLAUDE_CODE_SESSION_ID:-}"
[[ "$sid" =~ ^[A-Za-z0-9-]+$ ]] || sid=""

# Taking over a loop another session armed ends that session's gating and
# resets its counter — legitimate after /clear, a hijack otherwise. Allow it
# (refusing would strand the /clear case) but never quietly: warn, and log it
# where stand-downs are audited.
if [ -n "$prev" ] && [ "$prev" != "$sid" ]; then
  echo "WARNING: $label was already armed by session $prev — this arm takes it over; that session's stops are no longer gated and its attempt counter is reset" >&2
  gate_standdown "$PWD" "$label" reclaimed "from=$prev" "by=${sid:-none}"
fi

if [ -n "$sid" ]; then
  printf '%s\n' "$sid" > "$sentinel"
  echo "$label armed (session $sid)"
else
  : > "$sentinel"
  echo "$label armed"
  echo "WARNING: armed without an owner (no CLAUDE_CODE_SESSION_ID) — any session in this checkout will drive this gate" >&2
fi
