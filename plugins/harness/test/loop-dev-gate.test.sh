#!/usr/bin/env bash
# Tests for loop-dev-gate.sh — the staged Stop gate.
set -uo pipefail
GATE="$(cd "$(dirname "$0")/.." && pwd)/hooks/scripts/loop-dev-gate.sh"
pass=0; fail=0
run() { # run <cwd> ; feeds stdin JSON, prints hook stdout
  # CLAUDE_PROJECT_DIR pinned to the temp dir: under a Stop hook the env leaks
  # the real project dir and the gate would resolve DIR to it instead.
  printf '{"cwd":"%s"}' "$1" | CLAUDE_PROJECT_DIR="$1" bash "$GATE"
}
check() { # check <name> <condition-desc> <actual> <expected-substring-or-EMPTY>
  local name="$1" actual="$3" want="$4"
  if [ "$want" = "EMPTY" ]; then
    if [ -z "$actual" ]; then echo "ok: $name"; pass=$((pass+1)); else echo "FAIL: $name (wanted empty, got: $actual)"; fail=$((fail+1)); fi
  else
    if printf '%s' "$actual" | grep -q "$want"; then echo "ok: $name"; pass=$((pass+1)); else echo "FAIL: $name (wanted '$want' in: $actual)"; fail=$((fail+1)); fi
  fi
}
check_not() { # check_not <name> <actual> <unwanted-fixed-string>
  local name="$1" actual="$2" unwanted="$3"
  if printf '%s' "$actual" | grep -qF "$unwanted"; then echo "FAIL: $name (unwanted '$unwanted' found in: $actual)"; fail=$((fail+1)); else echo "ok: $name"; pass=$((pass+1)); fi
}

# 1. Not armed -> allow (no output)
d=$(mktemp -d); out=$(run "$d"); check "not-armed allows" "" "$out" "EMPTY"; rm -rf "$d"

# 2. Armed + deterministic FAIL -> block+feedback, counter=1, marker cleared
d=$(mktemp -d); touch "$d/.cc-loop-dev-active" "$d/.cc-dev-reviews-passed"
out=$(CC_GATE_CMD="false" run "$d")
check "det-fail blocks" "" "$out" '"decision": *"block"'
check "det-fail feedback" "" "$out" "attempt 1/3"
check "det-fail clears marker" "" "$([ -f "$d/.cc-dev-reviews-passed" ] && echo present || echo gone)" "gone"
rm -rf "$d"

# 3. Armed + deterministic GREEN + no marker -> block asking for reviews, sentinel kept
d=$(mktemp -d); touch "$d/.cc-loop-dev-active"
out=$(CC_GATE_CMD="true" run "$d")
check "green-no-marker asks reviews" "" "$out" "review stages"
check "green-no-marker keeps sentinel" "" "$([ -f "$d/.cc-loop-dev-active" ] && echo present)" "present"
rm -rf "$d"

# 4. Armed + green + marker -> allow (no output), state cleaned
d=$(mktemp -d); touch "$d/.cc-loop-dev-active" "$d/.cc-dev-reviews-passed"
out=$(CC_GATE_CMD="true" run "$d")
check "green+marker allows" "" "$out" "EMPTY"
check "green+marker disarms" "" "$([ -f "$d/.cc-loop-dev-active" ] && echo present || echo gone)" "gone"
rm -rf "$d"

# 5. Circuit breaker: counter at max-1, fail -> trips, sentinel removed
d=$(mktemp -d); touch "$d/.cc-loop-dev-active"; echo 2 > "$d/.cc-loop-dev-state"
out=$(CC_GATE_CMD="false" run "$d")
check "circuit breaker trips" "" "$out" "Circuit breaker"
check "circuit breaker disarms" "" "$([ -f "$d/.cc-loop-dev-active" ] && echo present || echo gone)" "gone"
rm -rf "$d"

# 6. .cc-dev.yaml graders line with trailing comment -> comment stripped from feedback
d=$(mktemp -d); touch "$d/.cc-loop-dev-active"
printf 'graders: [a, b]   # some comment\n' > "$d/.cc-dev.yaml"
out=$(CC_GATE_CMD="true" run "$d")
check "graders comment stripped: shows list" "" "$out" 'review stages: \[a, b\]'
check_not "graders comment stripped: no comment text" "$out" "# some comment"
check_not "graders comment stripped: no bare #" "$out" "#"
rm -rf "$d"

# 7. Deterministic gate GREEN -> failure counter reset to 0
d=$(mktemp -d); touch "$d/.cc-loop-dev-active"; echo 2 > "$d/.cc-loop-dev-state"
out=$(CC_GATE_CMD="true" run "$d")
check "green resets counter" "" "$(cat "$d/.cc-loop-dev-state" 2>/dev/null)" "0"
rm -rf "$d"

# 8. Live lock held by another process -> block without running the gate:
#    counter untouched, marker kept, lock not stolen
d=$(mktemp -d); touch "$d/.cc-loop-dev-active" "$d/.cc-dev-reviews-passed"; echo 1 > "$d/.cc-loop-dev-state"
mkdir "$d/.cc-loop-gate.lock"; echo $$ > "$d/.cc-loop-gate.lock/pid"
out=$(CC_GATE_CMD="false" run "$d")
check "live lock blocks" "" "$out" "already in progress"
check "live lock keeps counter" "" "$(cat "$d/.cc-loop-dev-state")" "1"
check "live lock keeps marker" "" "$([ -f "$d/.cc-dev-reviews-passed" ] && echo present)" "present"
check "live lock not stolen" "" "$([ -d "$d/.cc-loop-gate.lock" ] && echo present)" "present"
rm -rf "$d"

# 9. Stale lock (dead holder pid) -> stolen, gate proceeds, lock released on exit
d=$(mktemp -d); touch "$d/.cc-loop-dev-active"
mkdir "$d/.cc-loop-gate.lock"; dead=$(bash -c 'echo $$'); echo "$dead" > "$d/.cc-loop-gate.lock/pid"
out=$(CC_GATE_CMD="true" run "$d")
check "stale lock stolen: gate proceeds" "" "$out" "review stages"
check "stale lock released after run" "" "$([ -d "$d/.cc-loop-gate.lock" ] && echo present || echo gone)" "gone"
rm -rf "$d"

# git helper for fingerprint tests
gsetup() { # gsetup <dir> — init repo on main with one tracked file
  git -C "$1" init -q -b main
  echo hi > "$1/f.txt"; git -C "$1" add f.txt
  git -C "$1" -c user.email=t@t -c user.name=t commit -qm init
}
FPFLAGS="--no-ext-diff --no-textconv --ignore-submodules=dirty"   # as in the STAMP command
gstamp() { # gstamp <dir> [reviewed-sha] — three-line marker as the STAMP command writes it
  local mb sha; sha=${2:-$(git -C "$1" rev-parse HEAD)}
  mb=$(git -C "$1" merge-base main HEAD) && { echo "$mb"; git -C "$1" diff $FPFLAGS "$mb" | git -C "$1" hash-object --stdin; echo "$sha"; } > "$1/.cc-dev-reviews-passed"
}
gcommit() { git -C "$1" -c user.email=t@t -c user.name=t commit -q "${@:2}"; }

# 10. Git repo + marker with matching fingerprint + reviewed HEAD -> allow, disarm
d=$(mktemp -d); gsetup "$d"; git -C "$d" checkout -qb feature; touch "$d/.cc-loop-dev-active"
echo reviewed >> "$d/f.txt"; gcommit "$d" -am reviewed; gstamp "$d"
out=$(CC_GATE_CMD="true" run "$d")
check "fresh marker allows" "" "$out" "EMPTY"
check "fresh marker disarms" "" "$([ -f "$d/.cc-loop-dev-active" ] && echo present || echo gone)" "gone"
rm -rf "$d"

# 11. Git repo + tree edited AFTER stamping -> stale marker: block + marker cleared
d=$(mktemp -d); gsetup "$d"; touch "$d/.cc-loop-dev-active"; gstamp "$d"
echo late-edit >> "$d/f.txt"
out=$(CC_GATE_CMD="true" run "$d")
check "stale marker blocks" "" "$out" "stale"
check "stale marker cleared" "" "$([ -f "$d/.cc-dev-reviews-passed" ] && echo present || echo gone)" "gone"
check "stale marker keeps sentinel" "" "$([ -f "$d/.cc-loop-dev-active" ] && echo present)" "present"
rm -rf "$d"

# 12. Feature branch (the loop-dev flow): a post-stamp commit that carries no
#     new content (here an amend — new SHA, same tree) does NOT falsify the
#     marker; merge-base stays the fork point and the reviewed commit still
#     exists. (Working on the base branch itself is not invariant: a
#     post-stamp commit moves the merge-base and fails safe into a re-review.)
d=$(mktemp -d); gsetup "$d"; git -C "$d" checkout -qb feature
touch "$d/.cc-loop-dev-active"
echo reviewed-change >> "$d/f.txt"; gcommit "$d" -am work; gstamp "$d"
gcommit "$d" --amend -m "work, reworded"
out=$(CC_GATE_CMD="true" run "$d")
check "content-free commit after stamp still allows" "" "$out" "EMPTY"
rm -rf "$d"

# 12b. XARI-158: a grader whose worktree sat on main echoes main's SHA. The
#      stamp claims that SHA was reviewed; its diff is empty, not the
#      certified tree -> rejected, marker cleared.
d=$(mktemp -d); gsetup "$d"; main_sha=$(git -C "$d" rev-parse main)
git -C "$d" checkout -qb feature; touch "$d/.cc-loop-dev-active"
echo change >> "$d/f.txt"; gcommit "$d" -am change; gstamp "$d" "$main_sha"
out=$(CC_GATE_CMD="true" run "$d")
check "reviewed SHA on main blocks" "" "$out" "REVIEWED_SHA"
check "reviewed SHA on main clears marker" "" "$([ -f "$d/.cc-dev-reviews-passed" ] && echo present || echo gone)" "gone"
rm -rf "$d"

# 12c. Uncommitted work at stamp time: no worktree grader saw it -> rejected,
#      even though the working-tree fingerprint matches.
d=$(mktemp -d); gsetup "$d"; git -C "$d" checkout -qb feature; touch "$d/.cc-loop-dev-active"
echo committed >> "$d/f.txt"; gcommit "$d" -am committed
echo uncommitted >> "$d/f.txt"; gstamp "$d"
out=$(CC_GATE_CMD="true" run "$d")
check "uncommitted work at stamp blocks" "" "$out" "stale"
rm -rf "$d"

# 12c2. A dirty submodule prints `-dirty` only in the working-tree diff form.
#       Without --ignore-submodules=dirty every correct stamp mismatched and
#       the loop burned review rounds until its breaker tripped.
d=$(mktemp -d); mkdir "$d/sub" "$d/p"
git -C "$d/sub" init -q; echo s > "$d/sub/s"; git -C "$d/sub" add s; gcommit "$d/sub" -m s
gsetup "$d/p"; git -C "$d/p" checkout -qb feature; touch "$d/p/.cc-loop-dev-active"
git -C "$d/p" -c protocol.file.allow=always submodule add -q "$d/sub" sub 2>/dev/null; gcommit "$d/p" -m addsub
echo dirty >> "$d/p/sub/s"; gstamp "$d/p"
out=$(CC_GATE_CMD="true" run "$d/p")
check "dirty submodule does not falsify a correct stamp" "" "$out" "EMPTY"
rm -rf "$d"

# 12c3. A repo diff driver that prints differently per invocation must not
#       reach either fingerprint.
d=$(mktemp -d); gsetup "$d"; git -C "$d" checkout -qb feature; touch "$d/.cc-loop-dev-active"
printf '#!/bin/sh\necho "$$ $(date +%%N)"\n' > "$d/.x"; chmod +x "$d/.x"
git -C "$d" config diff.external "$d/.x"
echo change >> "$d/f.txt"; gcommit "$d" -am change; gstamp "$d"
out=$(CC_GATE_CMD="true" run "$d")
check "diff.external does not falsify a correct stamp" "" "$out" "EMPTY"
rm -rf "$d"

# 12d. Reviewed SHA missing (legacy two-line marker), malformed, or unknown
#      -> fails closed.
for bad in "" "not-a-sha" "0123456789012345678901234567890123456789"; do
  d=$(mktemp -d); gsetup "$d"; git -C "$d" checkout -qb feature; touch "$d/.cc-loop-dev-active"
  echo change >> "$d/f.txt"; gcommit "$d" -am change; gstamp "$d"
  { sed -n 1,2p "$d/.cc-dev-reviews-passed"; if [ -n "$bad" ]; then echo "$bad"; fi; } > "$d/m"
  mv "$d/m" "$d/.cc-dev-reviews-passed"
  out=$(CC_GATE_CMD="true" run "$d")
  check "reviewed SHA '${bad:-<absent>}' fails closed" "" "$out" "stale"
  rm -rf "$d"
done

# 13. Git repo + legacy empty marker (touch) -> allow (escape hatch)
d=$(mktemp -d); gsetup "$d"; touch "$d/.cc-loop-dev-active" "$d/.cc-dev-reviews-passed"
out=$(CC_GATE_CMD="true" run "$d")
check "empty marker allows (legacy)" "" "$out" "EMPTY"
rm -rf "$d"

# 14. Non-git dir + non-empty marker -> allow (fingerprint unavailable, skip check)
d=$(mktemp -d); touch "$d/.cc-loop-dev-active"; echo whatever > "$d/.cc-dev-reviews-passed"
out=$(CC_GATE_CMD="true" run "$d")
check "non-git non-empty marker allows" "" "$out" "EMPTY"
rm -rf "$d"

# 15. Stage-2 block message includes the fingerprint stamp command
d=$(mktemp -d); touch "$d/.cc-loop-dev-active"
out=$(CC_GATE_CMD="true" run "$d")
check "stage-2 message has stamp cmd" "" "$out" 'echo \\"$sha\\"; } > .cc-dev-reviews-passed'
check "stage-2 message asks graders to echo the SHA" "" "$out" "REVIEWED_SHA"
# The same stamp is written out in loop-dev.md; the two must not drift, or the
# agent follows prose that writes a marker this gate rejects.
doc_stamp=$(sed -nE 's/^[[:space:]]*`(sha=<REVIEWED_SHA> && mb=.*\.cc-dev-reviews-passed)`$/\1/p' "$(dirname "$0")/../commands/loop-dev.md" | sed 's/<base>/main/')
gate_stamp=$(printf '%s' "$out" | jq -r .reason | sed -nE 's/^[[:space:]]*(sha=<REVIEWED_SHA> && .*)$/\1/p')
if [ -n "$doc_stamp" ] && [ "$doc_stamp" = "$gate_stamp" ]; then echo "ok: loop-dev.md stamp matches the gate's"; pass=$((pass+1))
else echo "FAIL: loop-dev.md stamp drifted from the gate's (doc='$doc_stamp' gate='$gate_stamp')"; fail=$((fail+1)); fi
rm -rf "$d"

# 16. Quoted YAML base ("main") -> quotes stripped, fingerprint STILL enforced
#     (regression: unstripped quotes made merge-base fail and the check fail open)
d=$(mktemp -d); gsetup "$d"; touch "$d/.cc-loop-dev-active"
printf 'base: "main"\n' > "$d/.cc-dev.yaml"
gstamp "$d"; echo late-edit >> "$d/f.txt"
out=$(CC_GATE_CMD="true" run "$d")
check "quoted base: staleness still enforced" "" "$out" "stale"
rm -rf "$d"

# 16b. Empty diff -> nothing to review, allow stop WITHOUT demanding a stamp.
#      Previously the gate read "deterministic gate green" as "work is verified"
#      when it actually meant "no work exists", and demanded a marker that would
#      certify graders passed on a change nobody made. The loop could not exit.
d=$(mktemp -d); gsetup "$d"; touch "$d/.cc-loop-dev-active"
out=$(CC_GATE_CMD="true" run "$d")
check "empty diff: does not demand reviews" "" "$out" "nothing to review"
check "empty diff: no stamp command offered" "" "$([ -n "${out##*merge-base*}" ] && echo absent || echo present)" "absent"
check "empty diff: no block decision" "" "$([ -n "${out##*\"block\"*}" ] && echo none || echo blocked)" "none"
rm -rf "$d"

# 16c. A tracked change IS work -> the gate must still demand reviews.
d=$(mktemp -d); gsetup "$d"; touch "$d/.cc-loop-dev-active"
echo change >> "$d/f.txt"
out=$(CC_GATE_CMD="true" run "$d")
check "tracked diff still demands reviews" "" "$out" "review stages"
rm -rf "$d"

# 16d. An UNTRACKED new file is work too — the diff is empty but the run
#      produced something, and it must not slip past ungraded.
d=$(mktemp -d); gsetup "$d"; touch "$d/.cc-loop-dev-active"
echo new > "$d/added.py"
out=$(CC_GATE_CMD="true" run "$d")
check "untracked file still demands reviews" "" "$out" "review stages"
rm -rf "$d"

# 16e. Loop state files are not work — they exist in every armed run.
d=$(mktemp -d); gsetup "$d"; touch "$d/.cc-loop-dev-active" "$d/.cc-loop-dev-rounds"
out=$(CC_GATE_CMD="true" run "$d")
check "loop state alone is not work" "" "$out" "nothing to review"
rm -rf "$d"

# 17. Hostile base value -> sanitized to main; no shell injection in the STAMP
#     command the agent is told to run
d=$(mktemp -d); gsetup "$d"; touch "$d/.cc-loop-dev-active"
printf 'base: main"; touch PWNED #\n' > "$d/.cc-dev.yaml"
echo work >> "$d/f.txt"   # a diff must exist, else the gate correctly reports nothing to review
out=$(CC_GATE_CMD="true" run "$d")
check "hostile base: falls back to main" "" "$out" "git merge-base main HEAD"
check_not "hostile base: no injection in message" "$out" "PWNED"
rm -rf "$d"

# 18. Post-stamp COMMIT (clean tree at stamp AND at stop) -> caught: the
#     anchor is frozen in the marker at stamp time, so a recomputed/moving
#     merge-base (e.g. base: HEAD, or base == checked-out branch) cannot
#     collapse the check
d=$(mktemp -d); gsetup "$d"; touch "$d/.cc-loop-dev-active"
echo reviewed >> "$d/f.txt"; git -C "$d" -c user.email=t@t -c user.name=t commit -qam reviewed
gstamp "$d"
echo unreviewed >> "$d/f.txt"; git -C "$d" -c user.email=t@t -c user.name=t commit -qam unreviewed
out=$(CC_GATE_CMD="true" run "$d")
check "post-stamp commit blocks" "" "$out" "stale"
rm -rf "$d"

# 19. Non-empty marker that is not the two-line stamped format -> fails
#     CLOSED (stale), never falls back to recomputing a movable merge-base
d=$(mktemp -d); gsetup "$d"; touch "$d/.cc-loop-dev-active"
git -C "$d" diff "$(git -C "$d" merge-base main HEAD)" | git -C "$d" hash-object --stdin > "$d/.cc-dev-reviews-passed"
out=$(CC_GATE_CMD="true" run "$d")
check "single-line marker fails closed" "" "$out" "stale"
check "single-line marker cleared" "" "$([ -f "$d/.cc-dev-reviews-passed" ] && echo present || echo gone)" "gone"
rm -rf "$d"

# 20. Review rounds: each green-no-marker block increments the counter
d=$(mktemp -d); touch "$d/.cc-loop-dev-active"
out=$(CC_GATE_CMD="true" run "$d")
check "round 1 counted" "" "$(cat "$d/.cc-loop-dev-rounds" 2>/dev/null)" "1"
out=$(CC_GATE_CMD="true" run "$d")
check "round 2 counted" "" "$(cat "$d/.cc-loop-dev-rounds" 2>/dev/null)" "2"
check "round 2 still asks reviews" "" "$out" "review stages"
rm -rf "$d"

# 21. Review circuit breaker: past max_review_rounds (default 3) -> disarm,
#     tell the agent to summarize, no more grader dispatch requests
d=$(mktemp -d); touch "$d/.cc-loop-dev-active"; echo 3 > "$d/.cc-loop-dev-rounds"
out=$(CC_GATE_CMD="true" run "$d")
check "review breaker trips" "" "$out" "Review circuit breaker"
check_not "review breaker: no grader ask" "$out" "review stages:"
check "review breaker disarms" "" "$([ -f "$d/.cc-loop-dev-active" ] && echo present || echo gone)" "gone"
check "review breaker clears rounds" "" "$([ -f "$d/.cc-loop-dev-rounds" ] && echo present || echo gone)" "gone"
rm -rf "$d"

# 22. max_review_rounds override from .cc-dev.yaml
d=$(mktemp -d); touch "$d/.cc-loop-dev-active"
printf 'max_review_rounds: 1\n' > "$d/.cc-dev.yaml"
out=$(CC_GATE_CMD="true" run "$d")
check "override: round 1 allowed" "" "$out" "review stages"
out=$(CC_GATE_CMD="true" run "$d")
check "override: round 2 trips breaker" "" "$out" "Review circuit breaker"
rm -rf "$d"

# 23. Success path clears the rounds counter
d=$(mktemp -d); touch "$d/.cc-loop-dev-active" "$d/.cc-dev-reviews-passed"; echo 2 > "$d/.cc-loop-dev-rounds"
out=$(CC_GATE_CMD="true" run "$d")
check "success allows despite rounds" "" "$out" "EMPTY"
check "success clears rounds" "" "$([ -f "$d/.cc-loop-dev-rounds" ] && echo present || echo gone)" "gone"
rm -rf "$d"

# 19. Stand-down audit trail. Both breakers disarm the loop and let the stop
#     through; nothing durable said WHY the loop ended, so a reviewer could not
#     tell "shipped via exhaustion" from "shipped clean". Each trip appends one
#     line to .cc-loop-standdowns.log; a clean run writes nothing.
d=$(mktemp -d); touch "$d/.cc-loop-dev-active"; echo 2 > "$d/.cc-loop-dev-state"
CC_GATE_CMD="false" run "$d" >/dev/null
check "det breaker logs stand-down" "" "$(tail -1 "$d/.cc-loop-standdowns.log" 2>/dev/null)" "loop-dev deterministic-breaker attempts=3"
# re-arm in the same dir: the review breaker (rounds already at max, green gate,
# no marker, non-git so "nothing to review" cannot short-circuit) appends a 2nd line
touch "$d/.cc-loop-dev-active"; echo 3 > "$d/.cc-loop-dev-rounds"
CC_GATE_CMD="true" run "$d" >/dev/null
check "review breaker logs stand-down" "" "$(tail -1 "$d/.cc-loop-standdowns.log" 2>/dev/null)" "loop-dev review-breaker rounds=3"
check "stand-down log appends" "" "$(wc -l < "$d/.cc-loop-standdowns.log" 2>/dev/null | tr -d ' ')" "^2$"
rm -rf "$d"
d=$(mktemp -d); touch "$d/.cc-loop-dev-active" "$d/.cc-dev-reviews-passed"
CC_GATE_CMD="true" run "$d" >/dev/null
check "clean run writes no stand-down" "" "$([ -f "$d/.cc-loop-standdowns.log" ] && echo present || echo gone)" "gone"
rm -rf "$d"

echo "---"; echo "pass=$pass fail=$fail"; [ "$fail" -eq 0 ]
