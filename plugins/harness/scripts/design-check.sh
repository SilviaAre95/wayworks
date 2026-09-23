#!/usr/bin/env bash
# Deterministic gate over a design: <dir>/design.md + <dir>/plan.md.
#
# Why this exists: /harness:shape moves human supervision to before code, so a
# coding loop can run unattended. That only holds if the design it builds from
# has no open question, every decision says who made it, every byproduct was
# acknowledged, and every what-if became a task with a test. Those are grep-able
# facts, so they are checked here rather than trusted to a model.
#
# Usage: design-check.sh <design-dir> [--require-locked]
#   --require-locked  also require frontmatter status: locked (loop-dev passes it;
#                     shape's lock stage does not, since it locks after this passes)
# Exit 0 = pass, 1 = blocked, 2 = usage error. BLOCK lines go to stdout.
set -uo pipefail
usage() { echo "usage: design-check.sh <design-dir> [--require-locked]" >&2; exit 2; }
[ $# -ge 1 ] || usage
DIR="$1"; shift
REQUIRE_LOCKED=0
for a in "$@"; do
  case "$a" in --require-locked) REQUIRE_LOCKED=1 ;; *) usage ;; esac
done
DESIGN="$DIR/design.md"; PLAN="$DIR/plan.md"

fail=0
block() { echo "BLOCK: $*"; fail=1; }
finish() {
  [ "$fail" -eq 0 ] && echo "DESIGN OK — $n decision(s) checked" || echo "DESIGN BLOCKED"
  exit $fail
}
n=0
[ -f "$DESIGN" ] || { block "design.md: $DESIGN does not exist"; finish; }

# --- frontmatter -----------------------------------------------------------
fm=$(awk 'NR==1 && $0!="---"{exit} NR>1 && $0=="---"{exit} NR>1{print}' "$DESIGN")
if [ -z "$fm" ]; then
  block "design.md: no frontmatter (expected slug, status, stage between --- lines)"
fi
status=$(printf '%s\n' "$fm" | sed -nE 's/^status:[[:space:]]*([A-Za-z]+).*/\1/p' | head -1)
case "$status" in
  draft|locked|shipped) ;;
  *) block "design.md: status '${status:-<missing>}' is not draft|locked|shipped" ;;
esac
if [ "$REQUIRE_LOCKED" -eq 1 ] && [ "$status" != "locked" ]; then
  block "design.md: status is '${status:-<missing>}', not locked — finish it with /harness:shape"
fi

# --- decision lines --------------------------------------------------------
re_line='^- \[([ x~])\] ([AQWB][0-9]+) · (.+)$'
re_by='decided-by: (you|accepted-default)( |$)'
re_ack='(^|· )ack( ·|$)'
decided_w=""
infence=0
while IFS= read -r line || [ -n "$line" ]; do
  case "$line" in '```'*) infence=$((1 - infence)); continue ;; esac
  [ "$infence" -eq 1 ] && continue
  case "$line" in '- ['*) ;; *) continue ;; esac
  n=$((n + 1))
  if ! [[ "$line" =~ $re_line ]]; then
    block "malformed decision line (want '- [x|~| ] <A|Q|W|B><n> · …'): $line"; continue
  fi
  mark="${BASH_REMATCH[1]}"; id="${BASH_REMATCH[2]}"; rest="${BASH_REMATCH[3]}"
  case "$mark" in
    ' ') block "$id: still open — triage it" ;;
    '~') [[ "$rest" == *"deferred:"* ]] || block "$id: deferred without 'deferred: <reason>'" ;;
    x)
      [[ "$rest" =~ $re_by ]] || block "$id: decided but no 'decided-by: you|accepted-default'"
      case "$id" in
        B*) [[ "$rest" =~ $re_ack ]] || block "$id: byproduct not acknowledged ('ack')" ;;
        W*) decided_w="$decided_w $id" ;;
      esac
      ;;
  esac
done < "$DESIGN"
[ "$n" -eq 0 ] && block "design.md: no decision lines — stages 3, 4, 6 and 7 never recorded anything, so this design asserts nothing"

# --- plan cross-check ------------------------------------------------------
if [ ! -f "$PLAN" ]; then
  block "plan.md: $PLAN does not exist — stage 5 must write it"
else
  for id in $decided_w; do
    grep -qw -- "$id" "$PLAN" || block "$id: decided what-if never appears in plan.md — it needs a task with a test"
  done
fi
finish
