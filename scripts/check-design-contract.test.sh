#!/usr/bin/env bash
# Tests for check-design-contract.sh. A contract check that cannot fail reads
# as agreement forever, so each half of the contract is broken in a copy of the
# real files and asserted to exit non-zero.
set -uo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
CHECK=$HERE/check-design-contract.sh
REPO=$(cd "$HERE/.." && pwd)
fail=0
ok()  { echo "ok   - $*"; }
bad() { echo "FAIL - $*"; fail=1; }

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
FILES="plugins/harness/commands/loop-dev.md plugins/harness/commands/loop-deploy.md plugins/harness/commands/loop-build.md plugins/harness/hooks/scripts/loop-dev-preflight.sh plugins/harness/hooks/scripts/loop-arm.sh plugins/harness/hooks/scripts/loop-dev-gate.sh plugins/harness/hooks/scripts/loop-deploy-gate.sh plugins/harness/commands/shape.md plugins/harness/templates/design.md"

reset() {
  rm -rf "$TMP/plugins"
  for f in $FILES; do mkdir -p "$TMP/$(dirname "$f")"; cp "$REPO/$f" "$TMP/$f"; done
}
# edit <file> <sed expression> — applied to the copy only
edit() { sed -E "$2" "$TMP/$1" > "$TMP/$1.new" && mv "$TMP/$1.new" "$TMP/$1"; }
# pedit <file> <perl expression> — for edits sed -E cannot spell portably (\n)
pedit() { perl -pi -e "$2" "$TMP/$1"; }
run() { OUT=$(CONTRACT_ROOT="$TMP" bash "${RUN_CHECK:-$CHECK}" 2>&1); RC=$?; }
expect_fail() { # $1=label $2=grep pattern
  { [ "$RC" -ne 0 ] && grep -q -- "$2" <<<"$OUT"; } && ok "$1" || bad "$1 (rc=$RC: $OUT)"
}

reset; run
[ "$RC" -eq 0 ] && ok "the real files agree" || bad "real files should pass (rc=$RC: $OUT)"

reset; edit plugins/harness/hooks/scripts/loop-dev-preflight.sh 's/echo "DESIGN_ALREADY_FOLDED: /echo "DESIGN_FOLDED: /'; run
expect_fail "preflight renaming DESIGN_ALREADY_FOLDED fails" "DESIGN_ALREADY_FOLDED"
reset; edit plugins/harness/hooks/scripts/loop-dev-preflight.sh 's/echo "REQUIRE_DESIGN: /echo "DESIGN_MODE: /'; run
expect_fail "preflight renaming REQUIRE_DESIGN fails" "REQUIRE_DESIGN"
reset; edit plugins/harness/commands/loop-dev.md 's/DESIGN_ALREADY_FOLDED/DESIGN_FOLDED/g'; run
expect_fail "loop-dev.md no longer reading DESIGN_ALREADY_FOLDED fails" "DESIGN_ALREADY_FOLDED"
reset; edit plugins/harness/commands/loop-dev.md 's/REQUIRE_DESIGN/DESIGN_MODE/g'; run
expect_fail "loop-dev.md no longer reading REQUIRE_DESIGN fails" "REQUIRE_DESIGN"

reset; edit plugins/harness/commands/shape.md 's/`what-ifs`/`whatifs`/'; run
expect_fail "a stage name the table does not carry fails" "whatifs"
reset; edit plugins/harness/commands/shape.md '/^\| 2 \| \*\*Scope\*\*/d'; run
expect_fail "a table row dropped (Scope, a suffix of Attack scope) fails" "table rows"
reset; edit plugins/harness/commands/shape.md 's/`plan`, `what-ifs`/`what-ifs`, `plan`/'; run
expect_fail "stages out of order fail" "stage 5"
reset; edit plugins/harness/commands/shape.md 's/^`stage:` names, in order:/Stage names:/'; run
expect_fail "an unparseable stage list fails loudly" "could not parse"

# --- loop commands' pinned allowed-tools --------------------------------------
# Each loop command's allowed-tools must equal its pinned list, and its disarm
# the body's one rm command. Each case below breaks one rule; it must fail with
# the real checker AND pass with that one rule switched off — proving the rule,
# not some other check, is what catches it (a mutation check).
grant_case() { # $1=label $2=rule $3=pattern; $4..=edit function + expr
  local label=$1 rule=$2 pat=$3; shift 3
  reset; "$@"; run
  expect_fail "$label" "$pat"
  sed "/# rule:$rule\$/ s/err \"/: \"/" "$CHECK" > "$TMP/check-mut.sh"
  grep -q "^[^#]*: \".*# rule:$rule\$" "$TMP/check-mut.sh" || { bad "$label: rule:$rule not found in the checker"; return; }
  reset; "$@"; RUN_CHECK=$TMP/check-mut.sh; run; unset RUN_CHECK
  [ "$RC" -eq 0 ] && ok "  ...and only rule:$rule catches it" || bad "$label: still fails with rule:$rule off (rc=$RC: $OUT)"
}
add() { pedit "$1" 's#^(allowed-tools:.*)$#$1, '"$2"'#'; }
# set_disarm <file> <old> <new> — rewrite the disarm in the grant AND the body
set_disarm() { pedit "$1" "s/\\Q$2\\E/$3/g"; }

DEV=plugins/harness/commands/loop-dev.md
DEP=plugins/harness/commands/loop-deploy.md
BLD=plugins/harness/commands/loop-build.md
for cmd in "$DEV" "$DEP"; do
  n=$(basename "$cmd" .md)
  for g in 'Bash(rm)' 'Bash(rm*)' 'Bash(rm:*)' 'Bash(*)' 'Bash' 'Bash(cat:*)' 'Bash(rm -f .cc-*)' 'Read' \
           'Bash(\$\{CLAUDE_PLUGIN_ROOT\}/hooks/scripts/loop-gate.sh:*)'; do
    grant_case "$n: an added $g grant fails" pinned "not in its pinned list" add "$cmd" "$g"
  done
  grant_case "$n: a missing disarm grant fails" pinned \
    "missing from allowed-tools" pedit "$cmd" 's/, Bash\(rm -f [^)]*\)//'
  grant_case "$n: a second rm command in the body fails" disarm-body \
    "exactly one rm command" pedit "$cmd" 's/^(Target: \$ARGUMENTS|Arm the dev loop for this project:)$/Then run `rm -f .cc-other`.\n$1/'
  grant_case "$n: an indented continuation line in the frontmatter fails" frontmatter-keys \
    "frontmatter line" pedit "$cmd" 's/^(allowed-tools:.*)$/$1\n  , Bash(*)/'
  grant_case "$n: a differently spelled allowed-tools key fails" frontmatter-keys \
    "frontmatter line" pedit "$cmd" 's/^(allowed-tools:.*)$/$1\nallowedTools: Bash(*)/'
  grant_case "$n: a CR-smuggled second allowed-tools key fails" control-bytes \
    "control byte" pedit "$cmd" 's/^(description:.*)$/$1\rallowed-tools: Bash(*)/'
  grant_case "$n: a '---' inside a frontmatter line fails" fm-dashes \
    "inside a line" pedit "$cmd" 's/^(description: .*)$/$1 --- more/'
  grant_case "$n: a Unicode line separator in the frontmatter fails" fm-ascii \
    "non-ASCII byte" pedit "$cmd" 's/^(description: .*)$/$1\xe2\x80\xa8x/'
  grant_case "$n: a second allowed-tools line fails" one-allowed-tools \
    "allowed-tools lines" pedit "$cmd" 's/^(allowed-tools:.*)$/$1\nallowed-tools: Bash(*)/'
done
grant_case "loop-dev: a disarm that drifts from its grant fails" disarm-verbatim "verbatim" \
  pedit "$DEV" 's/^(\s*rm -f \.cc-loop-dev-active .*)$/$1 .cc-extra/'
grant_case "loop-deploy: a disarm that drifts from its grant fails" disarm-verbatim "verbatim" \
  pedit "$DEP" 's/`rm -f \.cc-deploy-active \.cc-deploy-state`/`rm -rf .cc-deploy-active .cc-deploy-state`/'
grant_case "loop-deploy: a disarm of another loop's files fails, grant and body alike" pinned "not in its pinned list" \
  set_disarm "$DEP" 'rm -f .cc-deploy-active .cc-deploy-state' 'rm -f .cc-deploy-active .cc-verify'
grant_case "loop-dev: a disarm of the reviews marker fails, grant and body alike" pinned "not in its pinned list" \
  set_disarm "$DEV" 'rm -f .cc-loop-dev-active .cc-loop-dev-state .cc-loop-dev-rounds' 'rm -f .cc-loop-dev-active .cc-dev-reviews-passed'
grant_case "loop-deploy-gate: a disarm hint that drifts from the grant fails" hook-disarm "tells the loop to disarm" \
  pedit plugins/harness/hooks/scripts/loop-deploy-gate.sh 's/^(set -uo pipefail)$/$1\n# disarm with: rm .cc-deploy-active/'
grant_case "loop-dev-gate: a disarm hint that drifts from the grant fails" hook-disarm "tells the loop to disarm" \
  pedit plugins/harness/hooks/scripts/loop-dev-gate.sh 's/^(set -uo pipefail)$/$1\n# disarm with: rm -f .cc-loop-dev-active/'
grant_case "a loop gate that goes missing fails instead of going unchecked" gate-exists "is missing" \
  rm "$TMP/plugins/harness/hooks/scripts/loop-deploy-gate.sh"
grant_case "a pinned script that no longer ships fails" script-exists "does not exist" \
  rm "$TMP/plugins/harness/hooks/scripts/loop-arm.sh"
grant_case "loop-build: an added Bash(*) grant fails" pinned "not in its pinned list" add "$BLD" 'Bash(*)'
grant_case "loop-build: any disarm grant fails (it has none)" pinned "not in its pinned list" \
  add "$BLD" 'Bash(rm -f .cc-loop-active)'

reset; edit plugins/harness/templates/design.md 's/^stage: discover$/stage: discovery/'; run
expect_fail "a template seeding an unknown stage fails" "discovery"

exit $fail
