#!/usr/bin/env bash
# Stop hook: build-test-fix loop. Opt-in via .cc-loop-active sentinel.
# Blocks Claude from stopping until the project's verify gate is green, with a
# circuit breaker after MAX failed attempts. Bounded by attempt counter, not
# stop_hook_active (which Claude Code sets on every re-entry after a block).
# Serialized against sibling gates and overlapping sessions via gate-lock.sh.
set -uo pipefail
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/gate-lock.sh"
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/gate-standdown.sh"
MAX=5
INPUT=$(cat)
DIR="${CLAUDE_PROJECT_DIR:-$(printf '%s' "$INPUT" | jq -r '.cwd // "."')}"
SENTINEL="$DIR/.cc-loop-active"
STATE="$DIR/.cc-loop-state"
GATE_FILE="$DIR/.cc-verify"
LOG="$DIR/.cc-loop.log"

# 1. Loop not armed -> allow stop.
[ -f "$SENTINEL" ] || exit 0

# 1b. One gate run at a time (Stop hooks run in parallel; sessions can overlap).
if ! gate_lock "$DIR"; then
  jq -n '{decision:"block", reason:"Another harness gate run is already in progress in this project (.cc-loop-gate.lock). Wait for it to finish, then try to stop again — do NOT delete the lock; stale locks are reclaimed automatically."}'
  exit 0
fi

# 2. Resolve the gate command: env override (tests) > .cc-verify > default.
if [ -n "${CC_GATE_CMD:-}" ]; then
  GATE="$CC_GATE_CMD"
elif [ -f "$GATE_FILE" ]; then
  GATE="$(cat "$GATE_FILE")"
else
  GATE="npm run lint && npm run build && npm test"
fi

# 3. Run the gate.
if ( cd "$DIR" && eval "$GATE" ) >"$LOG" 2>&1; then
  rm -f "$SENTINEL" "$STATE" "$LOG"
  exit 0   # green -> allow stop
fi

# 4. Failed: increment attempt counter.
ATTEMPTS=$(cat "$STATE" 2>/dev/null || echo 0)
[[ "$ATTEMPTS" =~ ^[0-9]+$ ]] || ATTEMPTS=0
ATTEMPTS=$((ATTEMPTS + 1))
echo "$ATTEMPTS" > "$STATE"

TAIL="$(tail -40 "$LOG" 2>/dev/null)"

if [ "$ATTEMPTS" -ge "$MAX" ]; then
  # Circuit breaker: disarm, then block ONCE telling Claude to summarize.
  # Sentinel is now gone, so the next stop attempt is allowed.
  gate_standdown "$DIR" loop verify-breaker "attempts=$MAX"
  rm -f "$SENTINEL" "$STATE"
  jq -n --arg log "$TAIL" --arg max "$MAX" \
    '{decision:"block", reason:("Circuit breaker tripped: verify gate still failing after " + $max + " attempts. STOP trying to fix. Summarize for the user what is still failing, what you tried, and the last error below:\n" + $log)}'
  exit 0
fi

# 5. Under the cap: block and feed failures back so Claude fixes and continues.
jq -n --arg n "$ATTEMPTS" --arg max "$MAX" --arg gate "$GATE" --arg log "$TAIL" \
  '{decision:"block", reason:("Verify gate failed (attempt " + $n + "/" + $max + "): " + $gate + "\nFix the failures and continue; do not stop until green.\n" + $log)}'
exit 0
