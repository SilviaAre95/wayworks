#!/usr/bin/env bash
# Tests for session ownership across all three Stop gates (XARI-159).
# A loop armed by one session must be a no-op for a Stop from any other
# session in the same checkout — above all loop-deploy's rollback, which a
# bystander session used to be able to trigger against prod.
set -uo pipefail
S=$(cd "$(dirname "$0")/../hooks/scripts" && pwd)
pass=0; fail=0
ok()  { echo "ok: $*"; pass=$((pass+1)); }
bad() { echo "FAIL: $*"; fail=$((fail+1)); }
OWNER=aaaaaaaa-1111-2222-3333-444444444444
OTHER=bbbbbbbb-1111-2222-3333-444444444444

# stop <gate> <dir> [session_id] — feed a Stop hook input, print hook stdout.
# Every failing command also touches RAN, so "the gate did nothing" is
# observable beyond an empty stdout.
stop() {
  local gate="$1" d="$2" sid="${3:-}" input
  if [ -n "$sid" ]; then input=$(jq -nc --arg c "$d" --arg s "$sid" '{cwd:$c, session_id:$s}')
  else input=$(jq -nc --arg c "$d" '{cwd:$c}'); fi
  printf '%s' "$input" | CLAUDE_PROJECT_DIR="$d" \
    CC_GATE_CMD="touch $d/RAN; false" \
    CC_DEPLOY_VERIFY_CMD="touch $d/RAN; false" \
    CC_DEPLOY_ROLLBACK_CMD="touch $d/ROLLED_BACK" \
    bash "$S/$gate"
}

# arm <dir> <sentinel> <state> <owner-or-empty> [state-value]
arm() { printf '%s' "${4:+$4
}" > "$1/$2"; echo "${5:-0}" > "$1/$3"; }

for spec in "loop-gate.sh .cc-loop-active .cc-loop-state" \
            "loop-dev-gate.sh .cc-loop-dev-active .cc-loop-dev-state" \
            "loop-deploy-gate.sh .cc-deploy-active .cc-deploy-state"; do
  set -- $spec; gate=$1 sent=$2 state=$3

  # Foreign session: silent, nothing ran, nothing changed.
  d=$(mktemp -d); arm "$d" "$sent" "$state" "$OWNER"
  out=$(stop "$gate" "$d" "$OTHER")
  { [ -z "$out" ] && [ ! -e "$d/RAN" ] && [ -f "$d/$sent" ] \
    && [ "$(cat "$d/$state")" = 0 ] && [ ! -e "$d/.cc-loop-gate.lock" ]; } \
    && ok "$gate: foreign session is a no-op" || bad "$gate: foreign session (out=$out)"
  rm -rf "$d"

  # Owner session: gated exactly as before.
  d=$(mktemp -d); arm "$d" "$sent" "$state" "$OWNER"
  out=$(stop "$gate" "$d" "$OWNER")
  { printf '%s' "$out" | grep -q '"decision": *"block"' && [ -e "$d/RAN" ]; } \
    && ok "$gate: owner session is gated" || bad "$gate: owner session (out=$out)"
  rm -rf "$d"

  # Ownerless (legacy) sentinel: any session still drives it.
  d=$(mktemp -d); arm "$d" "$sent" "$state" ""
  out=$(stop "$gate" "$d" "$OTHER")
  printf '%s' "$out" | grep -q '"decision": *"block"' \
    && ok "$gate: ownerless sentinel still gates" || bad "$gate: ownerless sentinel (out=$out)"
  rm -rf "$d"

  # No session_id in the hook input: fall back to gating, never to silence.
  d=$(mktemp -d); arm "$d" "$sent" "$state" "$OWNER"
  out=$(stop "$gate" "$d")
  printf '%s' "$out" | grep -q '"decision": *"block"' \
    && ok "$gate: input without session_id still gates" || bad "$gate: no session_id (out=$out)"
  rm -rf "$d"
done

# The dangerous path: deploy at its redeploy cap. The owner rolls back; a
# bystander must not.
d=$(mktemp -d); arm "$d" .cc-deploy-active .cc-deploy-state "$OWNER" 2
stop loop-deploy-gate.sh "$d" "$OTHER" >/dev/null
{ [ ! -e "$d/ROLLED_BACK" ] && [ "$(cat "$d/.cc-deploy-state")" = 2 ]; } \
  && ok "deploy at cap: foreign session does not roll back" || bad "foreign session rolled back prod"
stop loop-deploy-gate.sh "$d" "$OWNER" >/dev/null
[ -e "$d/ROLLED_BACK" ] \
  && ok "deploy at cap: owner session rolls back" || bad "owner session did not roll back"
rm -rf "$d"

echo "$pass passed, $fail failed"
[ "$fail" = 0 ]
