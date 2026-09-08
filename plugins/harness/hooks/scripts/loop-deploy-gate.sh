#!/usr/bin/env bash
# Stop hook: production verify loop. Opt-in via .cc-deploy-active sentinel.
# Runs the deterministic prod-verify command; green => loop closed. Failing =>
# block "fix and redeploy". After max_redeploys => run the rollback command,
# disarm, and block telling the agent to escalate. Never leaves prod broken by
# an exhausted loop. Coexists with loop-gate.sh / loop-dev-gate.sh;
# serialized against sibling gates and overlapping sessions via gate-lock.sh.
set -uo pipefail
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/gate-lock.sh"
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/gate-standdown.sh"
INPUT=$(cat)
DIR="${CLAUDE_PROJECT_DIR:-$(printf '%s' "$INPUT" | jq -r '.cwd // "."')}"
SENTINEL="$DIR/.cc-deploy-active"
STATE="$DIR/.cc-deploy-state"
CFG="$DIR/.cc-deploy.yaml"
LOG="$DIR/.cc-deploy.log"

_cfg_get_str() {  # _cfg_get_str <key> — read a string value from $CFG, honoring quotes + inline comments
  local key="$1" raw
  raw="$(grep -E "^${key}:" "$CFG" 2>/dev/null | head -1 | sed -E "s/^${key}:[[:space:]]*//")"
  case "$raw" in
    '"'*) printf '%s' "$raw" | sed -E 's/^"([^"]*)".*$/\1/' ;;
    "'"*) printf '%s' "$raw" | sed -E "s/^'([^']*)'.*\$/\\1/" ;;
    *)    printf '%s' "$raw" | sed -E 's/[[:space:]]*#.*$//; s/[[:space:]]*$//' ;;
  esac
}

# 1. Not armed for loop-deploy -> allow stop.
[ -f "$SENTINEL" ] || exit 0

# 1b. One gate run at a time (Stop hooks run in parallel; sessions can overlap).
if ! gate_lock "$DIR"; then
  jq -n '{decision:"block", reason:"Another harness gate run is already in progress in this project (.cc-loop-gate.lock). Wait for it to finish, then try to stop again — do NOT delete the lock; stale locks are reclaimed automatically."}'
  exit 0
fi

# 2. max_redeploys from .cc-deploy.yaml (default 3).
MAX=3
if [ -f "$CFG" ]; then
  v=$(grep -E '^max_redeploys:' "$CFG" | head -1 | sed -E 's/^max_redeploys:[[:space:]]*//; s/[^0-9].*$//')
  [[ "$v" =~ ^[0-9]+$ ]] && MAX="$v"
fi

# 3. Resolve verify + rollback: env overrides (tests) > .cc-deploy.yaml.
if [ -n "${CC_DEPLOY_VERIFY_CMD:-}" ]; then VERIFY="$CC_DEPLOY_VERIFY_CMD"
elif [ -f "$CFG" ]; then VERIFY="$(_cfg_get_str verify)"
else VERIFY=""; fi
if [ -n "${CC_DEPLOY_ROLLBACK_CMD:-}" ]; then ROLLBACK="$CC_DEPLOY_ROLLBACK_CMD"
elif [ -f "$CFG" ]; then ROLLBACK="$(_cfg_get_str rollback)"
else ROLLBACK=""; fi

# 4. No verify command configured -> cannot gate; tell the agent and allow stop.
if [ -z "$VERIFY" ]; then
  jq -n '{decision:"block", reason:"loop-deploy is armed but .cc-deploy.yaml has no `verify:` command. Add one (health check + smoke + error-rate) or disarm with: rm .cc-deploy-active"}'
  gate_standdown "$DIR" loop-deploy no-verify-command
  rm -f "$SENTINEL" "$STATE"
  exit 0
fi

# 5. Run the prod-verify.
if ( cd "$DIR" && eval "$VERIFY" ) >"$LOG" 2>&1; then
  rm -f "$SENTINEL" "$STATE" "$LOG"
  exit 0   # prod healthy -> loop closed
fi

# 6. Unhealthy: increment redeploy counter.
ATTEMPTS=$(cat "$STATE" 2>/dev/null || echo 0); [[ "$ATTEMPTS" =~ ^[0-9]+$ ]] || ATTEMPTS=0
ATTEMPTS=$((ATTEMPTS + 1)); echo "$ATTEMPTS" > "$STATE"
TAIL="$(tail -40 "$LOG" 2>/dev/null)"

if [ "$ATTEMPTS" -ge "$MAX" ]; then
  # Exhausted: roll back to last-good, disarm, escalate.
  ROLLMSG="(no rollback command configured)"; ROLLSTATE=none
  if [ -n "$ROLLBACK" ]; then
    if ( cd "$DIR" && eval "$ROLLBACK" ) >>"$LOG" 2>&1; then ROLLMSG="rolled back via: $ROLLBACK"; ROLLSTATE=ok; else ROLLMSG="ROLLBACK FAILED: $ROLLBACK — prod may be broken, act now"; ROLLSTATE=FAILED; fi
  fi
  TAIL="$(tail -40 "$LOG" 2>/dev/null)"
  gate_standdown "$DIR" loop-deploy redeploy-breaker "attempts=$MAX" "rollback=$ROLLSTATE"
  rm -f "$SENTINEL" "$STATE"
  jq -n --arg max "$MAX" --arg roll "$ROLLMSG" --arg log "$TAIL" \
    '{decision:"block", reason:("Prod still failing after " + $max + " redeploys. " + $roll + ". STOP redeploying — escalate to the user with what broke and what you tried:\n" + $log)}'
  exit 0
fi

# 7. Under the cap: block and tell the agent to fix + redeploy.
jq -n --arg n "$ATTEMPTS" --arg max "$MAX" --arg log "$TAIL" \
  '{decision:"block", reason:("Prod verification failed (attempt " + $n + "/" + $max + "). Fix the issue (you may run /loop-dev) and redeploy; do not stop until prod verifies healthy.\n" + $log)}'
exit 0
