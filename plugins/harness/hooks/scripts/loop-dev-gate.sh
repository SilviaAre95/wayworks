#!/usr/bin/env bash
# Stop hook: staged dev loop. Opt-in via .cc-loop-dev-active sentinel.
# Blocks stop until BOTH the deterministic gate (.cc-verify) is green AND the
# reviews marker (.cc-dev-reviews-passed) exists and is fresh. Circuit breakers:
# max_retries failed deterministic attempts, max_review_rounds grading rounds
# without a clean stamp. Coexists with loop-gate.sh; serialized against
# sibling gates and overlapping sessions via gate-lock.sh.
set -uo pipefail
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/gate-lock.sh"
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/gate-standdown.sh"
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/gate-owner.sh"
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

# Armed by another session in this checkout -> not ours to gate.
gate_foreign "$SENTINEL" "$INPUT" && exit 0

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
( cd "$DIR" && eval "$GATE" ) >"$LOG" 2>&1; rc=$?
gate_foreign "$SENTINEL" "$INPUT" && exit 0   # re-armed by another session during the run
if [ "$rc" -ne 0 ]; then
  rm -f "$MARKER"   # code changed / broke -> any prior reviews are stale
  ATTEMPTS=$(cat "$STATE" 2>/dev/null || echo 0); [[ "$ATTEMPTS" =~ ^[0-9]+$ ]] || ATTEMPTS=0
  ATTEMPTS=$((ATTEMPTS + 1)); echo "$ATTEMPTS" > "$STATE"
  TAIL="$(tail -40 "$LOG" 2>/dev/null)"
  if [ "$ATTEMPTS" -ge "$MAX" ]; then
    gate_standdown "$DIR" loop-dev deterministic-breaker "attempts=$MAX"
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
# cannot collapse the check), a fingerprint of the working tree vs that
# anchor, and the commit the graders reviewed. Invariant under commits of
# already-fingerprinted content, so the PR stage never falsifies it; any
# tracked change vs the anchor does. The reviewed commit must carry exactly
# the fingerprinted diff: a grader whose worktree sat on `main` echoes a SHA
# with an empty diff, and uncommitted tracked changes are something no
# worktree grader saw (XARI-158). That the graders really read that SHA is on
# the agent. Untracked files are outside every fingerprint, as before.
# Both fingerprints use the same flags, so the working-tree form and the
# commit form stay byte-identical: dirty submodule contents (the `-dirty`
# suffix only the working-tree form prints) and repo diff drivers
# (diff.external, textconv) would otherwise make every correct stamp fail.
BASE=$(grep -E '^base:' "$CFG" 2>/dev/null | head -1 | sed -E 's/^base:[[:space:]]*//')
case "$BASE" in
  '"'*) BASE=$(printf '%s' "$BASE" | sed -E 's/^"([^"]*)".*$/\1/') ;;
  "'"*) BASE=$(printf '%s' "$BASE" | sed -E "s/^'([^']*)'.*\$/\\1/") ;;
  *)    BASE=$(printf '%s' "$BASE" | sed -E 's/[[:space:]]*#.*$//; s/[[:space:]]*$//') ;;
esac
# Only a sane ref name may reach tree_fp and the agent-facing STAMP command
# (anything else fails merge-base at best, injects shell into the agent at worst).
[[ "$BASE" =~ ^[A-Za-z0-9][A-Za-z0-9._/-]*$ ]] || BASE="main"
STAMP="sha=<REVIEWED_SHA> && mb=\$(git merge-base $BASE HEAD) && { echo \"\$mb\"; git diff --no-ext-diff --no-textconv --ignore-submodules=dirty \"\$mb\" | git hash-object --stdin; echo \"\$sha\"; } > .cc-dev-reviews-passed"
marker_fresh() {  # 0 = fresh (or unverifiable outside git), 1 = stale
  # Inside git the marker MUST be the three-line stamped format: anchor
  # commit, fingerprint, reviewed commit. Anything else — an empty (touched)
  # marker included — fails CLOSED — never fall back
  # to recomputing merge-base, whose ref can move with HEAD (base: HEAD).
  local anchor want fp sha
  git -C "$DIR" rev-parse --is-inside-work-tree >/dev/null 2>&1 || return 0
  anchor=$(sed -n 1p "$MARKER" | tr -d '[:space:]')
  want=$(sed -n 2p "$MARKER" | tr -d '[:space:]')
  sha=$(sed -n 3p "$MARKER" | tr -d '[:space:]')
  printf '%s' "$anchor" | grep -Eq '^[0-9a-f]{40,64}$' || return 1  # malformed anchor
  [ -n "$want" ] || return 1                                        # missing fingerprint
  git -C "$DIR" cat-file -e "$anchor" 2>/dev/null || return 1       # unknown commit
  fp=$(git -C "$DIR" diff --no-ext-diff --no-textconv --ignore-submodules=dirty "$anchor" 2>/dev/null | git -C "$DIR" hash-object --stdin)
  [ "$want" = "$fp" ] || return 1
  printf '%s' "$sha" | grep -Eq '^[0-9a-f]{40,64}$' || return 1     # missing/malformed reviewed commit
  git -C "$DIR" cat-file -e "$sha^{commit}" 2>/dev/null || return 1 # unknown commit
  fp=$(git -C "$DIR" diff --no-ext-diff --no-textconv --ignore-submodules=dirty "$anchor" "$sha" 2>/dev/null | git -C "$DIR" hash-object --stdin)
  [ "$want" = "$fp" ]                                               # reviewed commit != certified tree
}

# Review-round budget: every stop attempt that still needs grading costs one
# round. Past max_review_rounds (.cc-dev.yaml, default 3) the loop must stop
# paying for grader passes — grading that never converges is a task problem,
# not something more rounds will fix.
#
# Except a stop that only waits for a panel (XARI-157). Graders run in the
# background, so an interactive loop ends its turn to wait for them, and each
# of those stops used to cost a round: a healthy run spent 3 of 3 before any
# grader reported. Claude Code's Stop input lists running background tasks.
# A round is bound to the panel it pays for — the committed tree the graders
# review (the loop commits before every panel, and the marker rejects
# uncommitted work, so HEAD^{tree} is the code under review):
#   - nothing running: charge a round, unbound (as before)
#   - a subagent running, round unbound: bind it to HEAD^{tree} — free
#   - a subagent running, bound to this tree: free wait, up to MAX_WAITS
#   - a subagent running on a new tree: a new panel — charge and bind
# A shell-only task, no background_tasks field (older Claude Code), or no
# commit/git all charge as before, so a loop that stops without doing anything
# still trips the breaker. Uncommitted edits mid-panel ride on the bound tree:
# at most MAX_WAITS free stops, never a stamp.
# .cc-loop-dev-rounds: count, bound tree (empty = unbound), free waits used.
MAXR=3
if [ -f "$CFG" ]; then
  vr=$(grep -E '^max_review_rounds:' "$CFG" | head -1 | sed -E 's/^max_review_rounds:[[:space:]]*//; s/[^0-9].*$//')
  [[ "$vr" =~ ^[0-9]+$ ]] && MAXR="$vr"
fi
MAX_WAITS=8   # a full panel wakes the loop at most once per grader; 8 leaves margin
TREE=$(git -C "$DIR" rev-parse -q --verify 'HEAD^{tree}' 2>/dev/null)
graders_running() {  # a subagent is still in flight (Stop input, CC >= 2.1.282)
  printf '%s' "$INPUT" | jq -e '[.background_tasks[]? | select(.type == "subagent" and .status == "running")] | length > 0' >/dev/null 2>&1
}
review_round() {  # charge a round, bound to TREE if a panel is running; fails when the budget is spent
  local r bound=""
  r=$(head -1 "$ROUNDS_FILE" 2>/dev/null); [[ "$r" =~ ^[0-9]+$ ]] || r=0
  [ -n "$TREE" ] && graders_running && bound="$TREE"
  r=$((r + 1)); printf '%s\n%s\n0\n' "$r" "$bound" > "$ROUNDS_FILE"
  [ "$r" -le "$MAXR" ]
}
panel_wait() {  # 0 = free: binds the charged round to this panel, or waits on it
  local r bound w
  [ -n "$TREE" ] && graders_running || return 1
  r=$(sed -n 1p "$ROUNDS_FILE" 2>/dev/null); [[ "$r" =~ ^[0-9]+$ ]] && [ "$r" -ge 1 ] || return 1
  bound=$(sed -n 2p "$ROUNDS_FILE" 2>/dev/null)
  w=$(sed -n 3p "$ROUNDS_FILE" 2>/dev/null); [[ "$w" =~ ^[0-9]+$ ]] || w=0
  if [ -z "$bound" ]; then printf '%s\n%s\n%s\n' "$r" "$TREE" "$w" > "$ROUNDS_FILE"; return 0; fi
  [ "$bound" = "$TREE" ] && [ "$w" -lt "$MAX_WAITS" ] || return 1
  printf '%s\n%s\n%s\n' "$r" "$bound" "$((w + 1))" > "$ROUNDS_FILE"
}
wait_notice() {  # allow the stop: the loop pauses for its panel and stays armed
  jq -n --arg r "$(head -1 "$ROUNDS_FILE")" --arg max "$MAXR" \
    '{systemMessage:("Loop-dev: NOT done — no reviews have passed yet. Pausing for a background subagent (the grader panel, if one was launched); the loop is still armed and the next stop is gated again (review round " + $r + "/" + $max + "; waiting costs no round). When the graders report, act on their findings; do not re-dispatch them.")}'
}
review_breaker() {  # disarm and tell the agent to summarize, not re-grade
  gate_standdown "$DIR" loop-dev review-breaker "rounds=$MAXR"
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

  if panel_wait; then wait_notice; exit 0; fi
  if ! review_round; then review_breaker; exit 0; fi
  # A charged stop always blocks with the grading instructions — a running
  # subagent may be anything, not this round's panel. If it IS the panel, the
  # next stop on this code is a free wait.
  PRE=""
  graders_running && PRE="A background subagent is still running. If it is this round's grader panel, do not re-dispatch it: end your turn to wait — waiting on unchanged code costs no round. Otherwise: "
  GRADERS=$(grep -E '^graders:' "$CFG" 2>/dev/null | head -1 | sed -E 's/^graders:[[:space:]]*//; s/[[:space:]]*#.*$//')
  [ -z "$GRADERS" ] && GRADERS="[code-review, security, bugs]"
  # /code-review runs as a background fork (CC >= 2.1.218): a subagent that
  # invokes it reports before the findings exist, so the agent launches it
  # itself, pinned by ref range, and it echoes no SHA (XARI-150).
  CR=false
  [[ "$GRADERS" =~ (^|[^A-Za-z0-9_:-])code-review([^A-Za-z0-9_-]|$) ]] && CR=true
  jq -n --arg g "$GRADERS" --arg stamp "$STAMP" --arg b "$BASE" --argjson cr "$CR" --arg pre "$PRE" \
    '{decision:"block", reason:($pre + "Deterministic gate is green. Now run the review stages: " + $g + ". Commit everything, record REVIEWED_SHA=$(git rev-parse HEAD), and launch every grader at once, one each. "
      + (if $cr then "Invoke /code-review " + $b + "...<REVIEWED_SHA> yourself, not in a subagent, and wait for its findings notification (the launch line is not a result). Dispatch one subagent per grader other than code-review" else "Dispatch one subagent per grader" end)
      + " with that SHA — each must confirm its HEAD matches it and echo it in its report. Fix every blocking finding and re-verify. When ALL graders are clean, every grader subagent echoed the same REVIEWED_SHA"
      + (if $cr then ", /code-review ran on that SHA'"'"'s range" else "" end)
      + ", it still equals HEAD, and the tree is clean, stamp the marker with that SHA:\n\n  " + $stamp + "\n\n(outside a git repo: touch .cc-dev-reviews-passed)\n\nDo NOT create the marker before the reviews are actually clean.")}'
  exit 0
fi

# 7. Stage 3 — a stamped marker must still match the tree vs its stored
#    anchor. Late changes (the agent, or background jobs finishing after the
#    graders passed) invalidate the reviews, whether committed or not. An
#    empty marker (touch) is accepted only outside git, where nothing can be
#    fingerprinted; inside a repo it used to skip every check above.
if ! marker_fresh; then
  rm -f "$MARKER"
  if ! review_round; then review_breaker; exit 0; fi
  jq -n --arg stamp "$STAMP" \
    '{decision:"block", reason:("Reviews marker is stale or does not match what was reviewed: the working tree changed after the graders passed (late edits or background jobs?), the tree holds uncommitted tracked changes no worktree grader saw, or the stamped REVIEWED_SHA is not the certified tree (a grader on the wrong branch, e.g. main) or is missing. An empty (touched) marker is only accepted outside a git repo. Commit, re-run the affected graders against the current HEAD SHA, fix any findings, then re-stamp:\n\n  " + $stamp)}'
  exit 0
fi

# 8. All green: disarm and allow stop.
rm -f "$SENTINEL" "$STATE" "$MARKER" "$LOG" "$ROUNDS_FILE"
exit 0
