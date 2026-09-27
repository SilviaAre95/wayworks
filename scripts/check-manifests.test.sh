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

TMP=$(mktemp -d) || exit 1
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
reset; jqedit "$MP" '.plugins += [{"name":"../../x","version":"1.0.0","description":"d"}]'; run
expect_fail "a plugin name outside [a-z0-9-] fails" "is not a \[a-z0-9-\] string"
reset; jqedit "$MP" '.plugins += [{"name":"harness\nshared","source":"./plugins/harness","version":"9.9.9","description":"x"}]'; run
expect_fail "a name holding a newline cannot pose as existing plugins" 'plugin name "harness\\nshared"'
reset; jqedit "$MP" '.plugins += [{"name":"harness\n","source":"./plugins/harness\n","version":"9.9.9","description":"x"}]'; run
expect_fail "a name with a trailing newline fails the shape check" 'plugin name "harness\\n"'
reset; jqedit "$MP" '(.plugins[] | select(.name=="harness") | .version) += "\n"'; run
expect_fail "a version with a trailing newline fails" 'version ".*\\n" is not X.Y.Z'
reset; jqedit "$MP" '.plugins += [(.plugins[] | select(.name=="harness"))]'; run
expect_fail "a duplicated plugin name fails" "listed more than once"
reset; jqedit "$MP" '(.plugins[] | select(.name=="harness") | .source) = {"source":"github","repo":"x/y"}'; run
expect_fail "a source other than ./plugins/<name> fails" "is not \"./plugins/harness\""
reset; jqedit "$MP" '(.plugins[] | select(.name=="harness") | .version) = "2.3.8-rc1"'; run
expect_fail "a marketplace version outside X.Y.Z fails" "is not X.Y.Z"
reset; jqedit plugins/harness/.claude-plugin/plugin.json 'del(.version)'; jqedit "$MP" '(.plugins[] | select(.name=="harness")) |= del(.version)'; run
expect_fail "a version missing from both manifests fails" "is not X.Y.Z"
OUT=$(cd "$REPO/scripts" && bash check-manifests.sh 2>&1); RC=$?
[ "$RC" -eq 0 ] && ok "runs from another directory by a relative path" || bad "relative-path run (rc=$RC: $OUT)"
OUT=$(MANIFEST_ROOT="$TMP/nope" bash "$CHECK" 2>&1); RC=$?
expect_fail "a missing root fails instead of checking the wrong dir" "cannot cd"

exit $fail
