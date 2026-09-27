#!/usr/bin/env bash
# Tests for check-manifests.sh. A sync check that cannot fail reads as
# agreement forever, so each compared field is broken in a copy of the real
# manifests and asserted to exit non-zero naming the field.
set -uo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
CHECK=$HERE/check-manifests.sh
REPO=$(cd "$HERE/.." && pwd)
fail=0
ok()  { echo "ok   - $*"; }
bad() { echo "FAIL - $*"; fail=1; }

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

reset() {
  rm -rf "$TMP/plugins" "$TMP/.claude-plugin"
  mkdir -p "$TMP/.claude-plugin"
  cp "$REPO/.claude-plugin/marketplace.json" "$TMP/.claude-plugin/"
  for m in "$REPO"/plugins/*/.claude-plugin/plugin.json; do
    rel=${m#"$REPO"/}; mkdir -p "$TMP/$(dirname "$rel")"; cp "$m" "$TMP/$rel"
  done
}
# jqedit <file> <jq filter> — applied to the copy only
jqedit() { jq "$2" "$TMP/$1" > "$TMP/$1.new" && mv "$TMP/$1.new" "$TMP/$1"; }
run() { OUT=$(MANIFEST_ROOT="$TMP" bash "$CHECK" 2>&1); RC=$?; }
expect_fail() { # $1=label $2=grep pattern
  { [ "$RC" -ne 0 ] && grep -q -- "$2" <<<"$OUT"; } && ok "$1" || bad "$1 (rc=$RC: $OUT)"
}

reset; run
[ "$RC" -eq 0 ] && ok "the real manifests agree" || bad "real manifests should pass (rc=$RC: $OUT)"

MP=.claude-plugin/marketplace.json
reset; jqedit plugins/harness/.claude-plugin/plugin.json '.version="0.0.1"'; run
expect_fail "version drift fails" "version 0.0.1 != marketplace"
reset; jqedit plugins/harness/.claude-plugin/plugin.json '.name="harnesz"'; run
expect_fail "name drift fails" "name 'harnesz'"
reset; jqedit "$MP" '(.plugins[] | select(.name=="harness") | .description) = "stale"'; run
expect_fail "marketplace description drift fails" "description differs"
reset; jqedit plugins/harness/.claude-plugin/plugin.json '.description="new"'; run
expect_fail "plugin.json description drift fails" "description differs"
reset; jqedit plugins/harness/.claude-plugin/plugin.json 'del(.description)'; run
expect_fail "missing plugin.json description fails" "no description"
reset; jqedit "$MP" '(.plugins[] | select(.name=="harness")) |= del(.description)'; run
expect_fail "missing marketplace description fails" "description differs"
reset; rm "$TMP/plugins/harness/.claude-plugin/plugin.json"; run
expect_fail "listed plugin without a manifest fails" "does not exist"
reset; mkdir -p "$TMP/plugins/orphan"; run
expect_fail "unlisted plugin dir fails" "plugins/orphan exists"

exit $fail
