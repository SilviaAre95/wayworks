#!/usr/bin/env bash
# Tests for loop-arm.sh. Arming is the one step every loop depends on — if it
# half-succeeds (sentinel written, state missing) the Stop hook is armed
# against a loop that never initialised, which livelocks the session.
set -uo pipefail
SCRIPT=$(cd "$(dirname "$0")/../hooks/scripts" && pwd)/loop-arm.sh
fail=0
ok()  { echo "ok   - $*"; }
bad() { echo "FAIL - $*"; fail=1; }

TMP=$(mktemp -d); trap 'chmod -R u+w "$TMP" 2>/dev/null; rm -rf "$TMP"' EXIT
fresh() { d="$TMP/$1"; rm -rf "$d"; mkdir -p "$d"; echo "$d"; }
run() { OUT=$(bash "$SCRIPT" "$@" 2>&1); RC=$?; }

# --- each loop writes its own sentinel + state ------------------------------
d=$(fresh dev); run dev "$d"
{ [ "$RC" = 0 ] && [ -f "$d/.cc-loop-dev-active" ] && [ -f "$d/.cc-loop-dev-state" ] \
  && [ "$(cat "$d/.cc-loop-dev-state")" = "0" ] && echo "$OUT" | grep -q "loop-dev armed"; } \
  && ok "dev arms with sentinel + zeroed state" || bad "dev arms (rc=$RC out=$OUT)"

d=$(fresh build); run build "$d"
{ [ "$RC" = 0 ] && [ -f "$d/.cc-loop-active" ] && [ -f "$d/.cc-loop-state" ]; } \
  && ok "build arms" || bad "build arms (rc=$RC out=$OUT)"

d=$(fresh deploy); run deploy "$d"
{ [ "$RC" = 0 ] && [ -f "$d/.cc-deploy-active" ] && [ -f "$d/.cc-deploy-state" ]; } \
  && ok "deploy arms" || bad "deploy arms (rc=$RC out=$OUT)"

# --- dev clears stale markers from a killed run -----------------------------
d=$(fresh stale)
touch "$d/.cc-dev-reviews-passed" "$d/.cc-loop-dev-rounds"
run dev "$d"
{ [ ! -f "$d/.cc-dev-reviews-passed" ] && [ ! -f "$d/.cc-loop-dev-rounds" ]; } \
  && ok "dev clears stale marker and round count" || bad "dev clears stale state"

# --- build/deploy must NOT touch dev's markers ------------------------------
d=$(fresh isolate)
touch "$d/.cc-dev-reviews-passed"
run build "$d"
[ -f "$d/.cc-dev-reviews-passed" ] \
  && ok "build leaves dev's marker alone" || bad "build wrongly removed dev's marker"

# --- unknown loop name ------------------------------------------------------
d=$(fresh bogus); run bogus "$d"
{ [ "$RC" = 2 ] && echo "$OUT" | grep -q usage; } \
  && ok "unknown loop name exits 2 with usage" || bad "unknown loop name (rc=$RC)"

# --- missing argument -------------------------------------------------------
d=$(fresh noarg); run "" "$d"
[ "$RC" = 2 ] && ok "missing loop name exits 2" || bad "missing loop name (rc=$RC)"

# --- unwritable directory: fail loudly, leave NOTHING behind ----------------
# A sentinel without its state file arms the Stop hook against a loop that
# never initialised — worse than not arming at all.
d=$(fresh readonly); chmod 500 "$d"
run dev "$d"
{ [ "$RC" = 1 ] && echo "$OUT" | grep -q "ARM FAILED" && echo "$OUT" | grep -q "add this directory"; } \
  && ok "unwritable dir fails with an actionable message" || bad "unwritable dir (rc=$RC out=$OUT)"
chmod 700 "$d"
{ [ ! -f "$d/.cc-loop-dev-active" ] && [ ! -f "$d/.cc-loop-dev-state" ]; } \
  && ok "failed arm leaves no partial state" || bad "failed arm left files behind"

# --- nonexistent directory --------------------------------------------------
run dev "$TMP/does-not-exist"
{ [ "$RC" = 1 ] && echo "$OUT" | grep -q "cannot enter"; } \
  && ok "missing dir fails cleanly" || bad "missing dir (rc=$RC)"

exit $fail
