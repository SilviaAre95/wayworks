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
FILES="plugins/harness/commands/loop-dev.md plugins/harness/hooks/scripts/loop-dev-preflight.sh plugins/harness/commands/shape.md plugins/harness/templates/design.md"

reset() {
  rm -rf "$TMP/plugins"
  for f in $FILES; do mkdir -p "$TMP/$(dirname "$f")"; cp "$REPO/$f" "$TMP/$f"; done
}
# edit <file> <sed expression> — applied to the copy only
edit() { sed -E "$2" "$TMP/$1" > "$TMP/$1.new" && mv "$TMP/$1.new" "$TMP/$1"; }
run() { OUT=$(CONTRACT_ROOT="$TMP" bash "$CHECK" 2>&1); RC=$?; }
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

reset; edit plugins/harness/templates/design.md 's/^stage: discover$/stage: discovery/'; run
expect_fail "a template seeding an unknown stage fails" "discovery"

exit $fail
