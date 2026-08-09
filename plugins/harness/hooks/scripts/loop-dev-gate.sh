#!/usr/bin/env bash
# Stop hook: staged dev loop. Opt-in via .cc-loop-dev-active sentinel.
# Blocks stop until BOTH the deterministic gate (.cc-verify) is green AND the
# reviews marker (.cc-dev-reviews-passed) exists and is fresh. Circuit breakers:
# max_retries failed deterministic attempts, max_review_rounds grading rounds
# without a clean stamp. Coexists with loop-gate.sh; serialized against
# sibling gates and overlapping sessions via gate-lock.sh.
set -uo pipefail
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/gate-lock.sh"
INPUT=$(cat)
DIR="${CLAUDE_PROJECT_DIR:-$(printf '%s' "$INPUT" | jq -r '.cwd // "."')}"
SENTINEL="$DIR/.cc-loop-dev-active"
STATE="$DIR/.cc-loop-dev-state"
MARKER="$DIR/.cc-dev-reviews-passed"
GATE_FILE="$DIR/.cc-verify"
CFG="$DIR/.cc-dev.yaml"
LOG="$DIR/.cc-loop-dev.log"
ROUNDS_FILE="$DIR/.cc-loop-dev-rounds"

# 1. Not armed for loop-dev -> allow stop.
[ -f "$SENTINEL" ] || exit 0

# 2. One gate run at a time. Stop hooks run in parallel and sessions can
#    overlap; a concurrent run must not race the verify command or the state.
if ! gate_lock "$DIR"; then
  jq -n '{decision:"block", reason:"Another harness gate run is already in progress in this project (.cc-loop-gate.lock). Wait for it to finish, then try to stop again — do NOT delete the lock; stale locks are reclaimed automatically."}'
  exit 0
fi

# 3. max_retries from .cc-dev.yaml (default 3).
MAX=3
if [ -f "$CFG" ]; then
  v=$(grep -E '^max_retries:' "$CFG" | head -1 | sed -E 's/^max_retries:[[:space:]]*//; s/[^0-9].*$//')
  [[ "$v" =~ ^[0-9]+$ ]] && MAX="$v"
fi

# 4. Resolve the deterministic gate: env override (tests) > .cc-verify > default.
if [ -n "${CC_GATE_CMD:-}" ]; then GATE="$CC_GATE_CMD"
elif [ -f "$GATE_FILE" ]; then GATE="$(cat "$GATE_FILE")"
else GATE="npm run lint && npm run build && npm test"; fi

# 5. Stage 1 — deterministic gate.
if ! ( cd "$DIR" && eval "$GATE" ) >"$LOG" 2>&1; then
  rm -f "$MARKER"   # code changed / broke -> any prior reviews are stale
  ATTEMPTS=$(cat "$STATE" 2>/dev/null || echo 0); [[ "$ATTEMPTS" =~ ^[0-9]+$ ]] || ATTEMPTS=0
  ATTEMPTS=$((ATTEMPTS + 1)); echo "$ATTEMPTS" > "$STATE"
  TAIL="$(tail -40 "$LOG" 2>/dev/null)"
  if [ "$ATTEMPTS" -ge "$MAX" ]; then
    rm -f "$SENTINEL" "$STATE" "$ROUNDS_FILE"
    jq -n --arg log "$TAIL" --arg max "$MAX" \
      '{decision:"block", reason:("Circuit breaker: deterministic gate still failing after " + $max + " attempts. Stop fixing and summarize what is still broken:\n" + $log)}'
    exit 0
  fi
  jq -n --arg n "$ATTEMPTS" --arg max "$MAX" --arg gate "$GATE" --arg log "$TAIL" \
    '{decision:"block", reason:("Deterministic gate failed (attempt " + $n + "/" + $max + "): " + $gate + "\nFix the failures and continue; do not stop until green.\n" + $log)}'
  exit 0
fi

echo 0 > "$STATE"

# The reviews marker carries the anchor commit (merge-base with `base`,
# frozen at stamp time — never recomputed, so a moving base ref like HEAD
# cannot collapse the check) and a fingerprint of the working tree vs that
# anchor. Invariant under commits of already-fingerprinted content, so the
# PR stage never falsifies it; any tracked change vs the anchor does.
BASE=$(grep -E '^base:' "$CFG" 2>/dev/null | head -1 | sed -E 's/^base:[[:space:]]*//')
case "$BASE" in
  '"'*) BASE=$(printf '%s' "$BASE" | sed -E 's/^"([^"]*)".*$/\1/') ;;
  "'"*) BASE=$(printf '%s' "$BASE" | sed -E "s/^'([^']*)'.*\$/\\1/") ;;
  *)    BASE=$(printf '%s' "$BASE" | sed -E 's/[[:space:]]*#.*$//; s/[[:space:]]*$//') ;;
esac
# Only a sane ref name may reach tree_fp and the agent-facing STAMP command
# (anything else fails merge-base at best, injects shell into the agent at worst).
[[ "$BASE" =~ ^[A-Za-z0-9][A-Za-z0-9._/-]*$ ]] || BASE="main"
STAMP="mb=\$(git merge-base $BASE HEAD) && { echo \"\$mb\"; git diff \"\$mb\" | git hash-object --stdin; } > .cc-dev-reviews-passed"
marker_fresh() {  # 0 = fresh (or unverifiable outside git), 1 = stale
  # A non-empty marker MUST be the two-line stamped format: anchor commit,
  # then fingerprint. Anything else fails CLOSED — never fall back to
  # recomputing merge-base, whose ref can move with HEAD (base: HEAD).
  local anchor want fp
  git -C "$DIR" rev-parse --is-inside-work-tree >/dev/null 2>&1 || return 0
  anchor=$(sed -n 1p "$MARKER" | tr -d '[:space:]')
  want=$(sed -n 2p "$MARKER" | tr -d '[:space:]')
  printf '%s' "$anchor" | grep -Eq '^[0-9a-f]{40,64}$' || return 1  # malformed anchor
  [ -n "$want" ] || return 1                                        # missing fingerprint
  git -C "$DIR" cat-file -e "$anchor" 2>/dev/null || return 1       # unknown commit
  fp=$(git -C "$DIR" diff "$anchor" 2>/dev/null | git -C "$DIR" hash-object --stdin)
  [ "$want" = "$fp" ]
}

# Review-round budget: every stop attempt that still needs grading costs one
# round. Past max_review_rounds (.cc-dev.yaml, default 3) the loop must stop
# paying for grader passes — grading that never converges is a task problem,
# not something more rounds will fix.
MAXR=3
if [ -f "$CFG" ]; then
  vr=$(grep -E '^max_review_rounds:' "$CFG" | head -1 | sed -E 's/^max_review_rounds:[[:space:]]*//; s/[^0-9].*$//')
  [[ "$vr" =~ ^[0-9]+$ ]] && MAXR="$vr"
fi
review_round() {  # increment the round counter; fails when the budget is spent
  local r
  r=$(cat "$ROUNDS_FILE" 2>/dev/null || echo 0); [[ "$r" =~ ^[0-9]+$ ]] || r=0
  r=$((r + 1)); echo "$r" > "$ROUNDS_FILE"
  [ "$r" -le "$MAXR" ]
}
review_breaker() {  # disarm and tell the agent to summarize, not re-grade
  rm -f "$SENTINEL" "$STATE" "$ROUNDS_FILE" "$MARKER"
  jq -n --arg max "$MAXR" \
    '{decision:"block", reason:("Review circuit breaker: " + $max + " review rounds without a clean stamped marker. Stop dispatching graders and do NOT stamp the marker — summarize the outstanding findings and what you changed, then stop. The loop is disarmed.")}'
}

# 6. Stage 2 — reviews marker must exist.
if [ ! -f "$MARKER" ]; then
  # ...but only if there is something to review. A green deterministic gate on
  # an empty diff does not mean "work is done and verified", it means "no work
  # exists" — and demanding a stamp there livelocks the loop: the only way out
  # is a marker certifying that every grader passed on a change nobody made,
  # which is indistinguishable from a real green run afterwards. The marker's
  # fingerprint guards against edits landing AFTER a stamp; this is the same
  # failure reached from the other side.
  #
  # Conservative on purpose: untracked files count as work, so a run that only
  # added new files still gets graded.
  if git -C "$DIR" rev-parse --git-dir >/dev/null 2>&1; then
    mb=$(git -C "$DIR" merge-base "$BASE" HEAD 2>/dev/null)
    if [ -n "$mb" ] \
       && [ -z "$(git -C "$DIR" diff "$mb" 2>/dev/null)" ] \
       && [ -z "$(git -C "$DIR" ls-files --others --exclude-standard 2>/dev/null | grep -v '^\.cc-' | head -1)" ]; then
      jq -n --arg b "$BASE" \
        '{systemMessage:("Loop-dev: nothing to review — the working tree is identical to " + $b + " (no diff, no new files). Stopping without a marker; no reviews were run and none were needed.")}'
      exit 0
    fi
  fi

  if ! review_round; then review_breaker; exit 0; fi
  GRADERS=$(grep -E '^graders:' "$CFG" 2>/dev/null | head -1 | sed -E 's/^graders:[[:space:]]*//; s/[[:space:]]*#.*$//')
  [ -z "$GRADERS" ] && GRADERS="[code-review, security, bugs]"
  jq -n --arg g "$GRADERS" --arg stamp "$STAMP" \
    '{decision:"block", reason:("Deterministic gate is green. Now run the review stages: " + $g + ". Dispatch one subagent per grader against the diff, fix every blocking finding, and re-verify. When ALL graders are clean AND you have made no further code edits, stamp the marker to finish:\n\n  " + $stamp + "\n\n(outside a git repo: touch .cc-dev-reviews-passed)\n\nDo NOT create the marker before the reviews are actually clean.")}'
  exit 0
fi

# 7. Stage 3 — a stamped marker must still match the tree vs its stored
#    anchor. Late changes (the agent, or background jobs finishing after the
#    graders passed) invalidate the reviews, whether committed or not; an
#    empty marker (touch) is the legacy/non-git escape hatch.
if [ -s "$MARKER" ] && ! marker_fresh; then
  rm -f "$MARKER"
  if ! review_round; then review_breaker; exit 0; fi
  jq -n --arg stamp "$STAMP" \
    '{decision:"block", reason:("Reviews marker is stale: the working tree changed after the graders passed (fingerprint mismatch — late edits or background jobs?). Re-run the affected graders on the current diff, fix any findings, then re-stamp:\n\n  " + $stamp)}'
  exit 0
fi

# 8. All green: disarm and allow stop.
rm -f "$SENTINEL" "$STATE" "$MARKER" "$LOG" "$ROUNDS_FILE"
exit 0
