#!/usr/bin/env bash
# Tests for loop-dev-preflight.sh. Each blocking condition must actually block,
# and each legitimate setup must actually pass — a preflight that always exits 0
# is worse than none, because it reads as confirmation.
set -uo pipefail
SCRIPT=$(cd "$(dirname "$0")/../hooks/scripts" && pwd)/loop-dev-preflight.sh
fail=0
ok()  { echo "ok   - $*"; }
bad() { echo "FAIL - $*"; fail=1; }

TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT

# Fresh git repo with a main branch, so base resolution succeeds by default.
newrepo() {
  d="$TMP/$1"; rm -rf "$d"; mkdir -p "$d"
  git -C "$d" init -q -b main
  git -C "$d" -c user.email=t@t -c user.name=t commit -q --allow-empty -m init
  echo "$d"
}
run() { OUT=$(bash "$SCRIPT" "$1" 2>&1); RC=$?; }

# --- happy path -------------------------------------------------------------
d=$(newrepo happy)
echo "make check" > "$d/.cc-verify"
printf 'graders: [code-review, security, bugs]\nbase: main\n' > "$d/.cc-dev.yaml"
run "$d"
[ "$RC" = "0" ] && ok "valid config passes" || bad "valid config passes (rc=$RC: $OUT)"

# grader list is handed back for the agent-side availability check, naming the
# plugin each one needs — "bugs did not resolve" is not actionable on its own.
run "$d"
{ echo "$OUT" | grep -q "bugs -> qa:bug-review" \
  && echo "$OUT" | grep -q "needs qa@wayworks" \
  && echo "$OUT" | grep -q "security -> security:code-audit" \
  && echo "$OUT" | grep -q "code-review -> /code-review"; } \
  && ok "emits grader -> skill -> plugin mapping" || bad "emits mapping (got: $OUT)"

# an unrecognised grader still reports, without inventing a plugin name
d=$(newrepo custom)
echo "make check" > "$d/.cc-verify"
printf 'graders: [custom-thing]\nbase: main\n' > "$d/.cc-dev.yaml"
run "$d"
echo "$OUT" | grep -q "custom-thing -> skill named 'custom-thing'" \
  && ok "unknown grader maps to a same-named skill" || bad "unknown grader mapping (got: $OUT)"

# --- the npm-default trap ---------------------------------------------------
d=$(newrepo nonode)
printf 'graders: [code-review]\nbase: main\n' > "$d/.cc-dev.yaml"
run "$d"   # no .cc-verify, no package.json
{ [ "$RC" = "1" ] && echo "$OUT" | grep -q "npm commands this repo cannot run"; } \
  && ok "no .cc-verify in a non-Node repo blocks" || bad "no .cc-verify in a non-Node repo blocks (rc=$RC)"

# a Node repo may legitimately rely on the default
d=$(newrepo node)
echo '{}' > "$d/package.json"
printf 'base: main\ngraders: [code-review]\n' > "$d/.cc-dev.yaml"
run "$d"
{ [ "$RC" = "0" ] && echo "$OUT" | grep -q "falling back to"; } \
  && ok "Node repo without .cc-verify warns but passes" || bad "Node repo without .cc-verify warns but passes (rc=$RC)"

# --- empty gate -------------------------------------------------------------
d=$(newrepo emptygate)
: > "$d/.cc-verify"
run "$d"
[ "$RC" = "1" ] && ok "empty .cc-verify blocks" || bad "empty .cc-verify blocks"

# --- unresolvable base ------------------------------------------------------
d=$(newrepo badbase)
echo "make check" > "$d/.cc-verify"
printf 'graders: [code-review]\nbase: nope-not-a-branch\n' > "$d/.cc-dev.yaml"
run "$d"
{ [ "$RC" = "1" ] && echo "$OUT" | grep -q "does not resolve"; } \
  && ok "unresolvable base blocks" || bad "unresolvable base blocks (rc=$RC)"

# --- graders key present but empty ------------------------------------------
d=$(newrepo nograders)
echo "make check" > "$d/.cc-verify"
printf 'graders:\nbase: main\n' > "$d/.cc-dev.yaml"
run "$d"
{ [ "$RC" = "1" ] && echo "$OUT" | grep -q "no value"; } \
  && ok "empty graders list blocks" || bad "empty graders list blocks (rc=$RC)"

# --- tracked loop state (livelocks the gate) --------------------------------
d=$(newrepo tracked)
echo "make check" > "$d/.cc-verify"
printf 'graders: [code-review]\nbase: main\n' > "$d/.cc-dev.yaml"
touch "$d/.cc-loop-dev-active"
git -C "$d" add -f .cc-loop-dev-active
git -C "$d" -c user.email=t@t -c user.name=t commit -q -m "oops"
run "$d"
{ [ "$RC" = "1" ] && echo "$OUT" | grep -q "TRACKED by git"; } \
  && ok "tracked loop-state file blocks" || bad "tracked loop-state file blocks (rc=$RC)"

# --- missing config falls back to documented defaults -----------------------
d=$(newrepo nocfg)
echo "make check" > "$d/.cc-verify"
run "$d"
{ [ "$RC" = "0" ] \
  && echo "$OUT" | grep -q "code-review -> /code-review" \
  && echo "$OUT" | grep -q "security -> security:code-audit" \
  && echo "$OUT" | grep -q "bugs -> qa:bug-review"; } \
  && ok "absent .cc-dev.yaml uses documented defaults" || bad "absent .cc-dev.yaml uses defaults (rc=$RC)"

# --- stale marker warns, does not block -------------------------------------
d=$(newrepo stale)
echo "make check" > "$d/.cc-verify"
printf 'graders: [code-review]\nbase: main\n' > "$d/.cc-dev.yaml"
touch "$d/.cc-dev-reviews-passed"
run "$d"
{ [ "$RC" = "0" ] && echo "$OUT" | grep -q "stale .cc-dev-reviews-passed"; } \
  && ok "stale marker warns without blocking" || bad "stale marker warns without blocking (rc=$RC)"

# --- bundled graders resolve without a plugin -------------------------------
# The graders list accepts Claude Code's bundled skills. Before 1.10.1 the case
# block had no arm for them, so `security-review` fell through to "needs
# whichever plugin provides it" and loop-dev step 1 sent the agent hunting for a
# plugin that cannot exist — or halting the loop before it built anything.
d=$(newrepo bundled)
echo "make check" > "$d/.cc-verify"
printf 'graders: [code-review, security, security-review, bugs]\nbase: main\n' > "$d/.cc-dev.yaml"
run "$d"
{ [ "$RC" = "0" ] && echo "$OUT" | grep -q "security-review -> /security-review"; } \
  && ok "bundled security-review resolves without a plugin" \
  || bad "bundled security-review resolves without a plugin (rc=$RC: $OUT)"
echo "$OUT" | grep -q "security-review.*needs whichever plugin" \
  && bad "security-review must not fall through to the unknown-grader arm" \
  || ok "security-review does not fall through to the unknown-grader arm"

# --- a mutating grader is refused ------------------------------------------
# /simplify's contract is "review ... then apply the fixes". Graders run
# concurrently and their edits are not findings the parent fixed, so a mutating
# grader edits the tree mid-review and lands inside the marker fingerprint with
# no grader having read it.
d=$(newrepo mutating)
echo "make check" > "$d/.cc-verify"
printf 'graders: [code-review, simplify]\nbase: main\n' > "$d/.cc-dev.yaml"
run "$d"
# Assert the EXIT CODE, not just the message. The first version of this test
# grepped only for the string, which is exactly why the guard shipped calling
# `echo` instead of `err`: it printed BLOCK, then printed PREFLIGHT OK, and
# exited 0. This file's own header says a preflight that always exits 0 is
# worse than none, because it reads as confirmation.
{ [ "$RC" = "1" ] && echo "$OUT" | grep -q "applies its own fixes"; } \
  && ok "mutating grader (simplify) blocks with exit 1" \
  || bad "mutating grader (simplify) blocks with exit 1 (rc=$RC: $OUT)"
echo "$OUT" | grep -q "PREFLIGHT OK" \
  && bad "a blocked preflight must not also print PREFLIGHT OK" \
  || ok "a blocked preflight does not also print PREFLIGHT OK"

exit $fail
