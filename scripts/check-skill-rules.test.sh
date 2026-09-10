#!/usr/bin/env bash
# Tests for check-skill-rules.sh. The whole point of that script is to fail
# when a trim drops a rule, so the thing that must be proven is that it CAN
# fail — a checker whose pattern never matches, or whose manifest is empty,
# would report every skill intact forever. That is the exact failure mode it
# was written to prevent, so each class is asserted to actually exit non-zero.
set -uo pipefail
CHECK=$(cd "$(dirname "$0")" && pwd)/check-skill-rules.sh
fail=0
ok()  { echo "ok   - $*"; }
bad() { echo "FAIL - $*"; fail=1; }

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

SKILL_DIR="$TMP/plugins/demo/skills/thing"
reset() {
  rm -rf "$TMP/plugins" "$TMP/scripts"
  mkdir -p "$SKILL_DIR" "$TMP/scripts/skill-rules"
  printf '%s\n' \
    'Submit with `save_issue`.' \
    'The cap is 180 words.' \
    'Relations go in fields.' > "$SKILL_DIR/SKILL.md"
  printf '%s\n' \
    'submit call survives :: save_issue' \
    'word cap survives :: 180 words' > "$TMP/scripts/skill-rules/demo__thing.rules"
}

run() { OUT=$(RULES_ROOT="$TMP" bash "$CHECK" 2>&1); RC=$?; }

# --- baseline: an intact skill passes -----------------------------------
reset; run
[ "$RC" -eq 0 ] && ok "intact skill passes" || bad "intact skill should pass (rc=$RC): $OUT"
grep -q "2 rule(s)" <<<"$OUT" && ok "counts the rules it checked" || bad "should report 2 rules: $OUT"

# --- a dropped rule must fail -------------------------------------------
reset
grep -v 'save_issue' "$SKILL_DIR/SKILL.md" > "$SKILL_DIR/tmp" && mv "$SKILL_DIR/tmp" "$SKILL_DIR/SKILL.md"
run
[ "$RC" -ne 0 ] && ok "dropped rule fails" || bad "dropping save_issue should fail (rc=$RC)"
grep -q "lost rule — submit call survives" <<<"$OUT" \
  && ok "names the rule that was lost" || bad "should name the lost rule: $OUT"

# --- a reworded rule still passes ---------------------------------------
# The manifest asserts the operative token, not the sentence around it, so
# rewriting prose must not trip it. Otherwise every edit becomes a failure and
# the check gets disabled.
reset
printf '%s\n' 'Hand it over, or `save_issue` it.' 'Body stays under 180 words.' 'Relations: fields.' \
  > "$SKILL_DIR/SKILL.md"
run
[ "$RC" -eq 0 ] && ok "reworded rule still passes" || bad "rewording should pass (rc=$RC): $OUT"

# --- an empty manifest must fail ----------------------------------------
reset
: > "$TMP/scripts/skill-rules/demo__thing.rules"
run
[ "$RC" -ne 0 ] && ok "empty manifest fails" || bad "an empty manifest asserts nothing and must fail"

# --- a comments-only manifest must fail ---------------------------------
reset
printf '%s\n' '# only a comment' '' > "$TMP/scripts/skill-rules/demo__thing.rules"
run
[ "$RC" -ne 0 ] && ok "comments-only manifest fails" || bad "comments-only manifest must fail"

# --- a manifest naming a missing skill must fail ------------------------
reset
mv "$TMP/scripts/skill-rules/demo__thing.rules" "$TMP/scripts/skill-rules/demo__gone.rules"
run
[ "$RC" -ne 0 ] && ok "manifest for a missing skill fails" || bad "missing target must fail"

# --- a malformed rule line must fail ------------------------------------
reset
printf '%s\n' 'no separator here' > "$TMP/scripts/skill-rules/demo__thing.rules"
run
[ "$RC" -ne 0 ] && ok "missing :: separator fails" || bad "malformed rule must fail"

# --- a badly named manifest must fail -----------------------------------
reset
mv "$TMP/scripts/skill-rules/demo__thing.rules" "$TMP/scripts/skill-rules/nodoubleunderscore.rules"
run
[ "$RC" -ne 0 ] && ok "manifest without <plugin>__<skill> name fails" || bad "bad filename must fail"

exit $fail
