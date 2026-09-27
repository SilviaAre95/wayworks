#!/usr/bin/env bash
# Tests for check-release-rule.sh, in throwaway git repos. The rule it replaced
# passed whenever any "version" line changed, so the case that matters most is
# one plugin's bump covering another plugin's unbumped change.
set -uo pipefail
CHECK=$(cd "$(dirname "$0")" && pwd)/check-release-rule.sh
fail=0
ok()  { echo "ok   - $*"; }
bad() { echo "FAIL - $*"; fail=1; }

TMP=$(mktemp -d) || exit 1
trap 'rm -rf "$TMP"' EXIT

g() { git -C "$R" -c user.email=t@t -c user.name=t "$@"; }
# setver <plugin> <version> — in both manifests
setver() {
  jq --arg v "$2" '.version=$v' "$R/plugins/$1/.claude-plugin/plugin.json" > "$R/t" && mv "$R/t" "$R/plugins/$1/.claude-plugin/plugin.json"
  jq --arg n "$1" --arg v "$2" '(.plugins[] | select(.name==$n) | .version) = $v' "$R/.claude-plugin/marketplace.json" > "$R/t" && mv "$R/t" "$R/.claude-plugin/marketplace.json"
}
mktjq() { jq "$1" "$R/.claude-plugin/marketplace.json" > "$R/t" && mv "$R/t" "$R/.claude-plugin/marketplace.json"; }
fresh() {  # repo on main with plugins a and b at 1.0.0, then a branch
  R="$TMP/$1"; rm -rf "$R"; mkdir -p "$R/.claude-plugin"
  g init -q -b main
  echo '{"metadata":{"version":"1.0.0"},"plugins":[]}' > "$R/.claude-plugin/marketplace.json"
  for p in a b; do
    mkdir -p "$R/plugins/$p/.claude-plugin"
    echo "{\"name\":\"$p\",\"version\":\"1.0.0\",\"description\":\"$p\"}" > "$R/plugins/$p/.claude-plugin/plugin.json"
    echo "$p" > "$R/plugins/$p/README.md"
    mktjq ".plugins += [{\"name\":\"$p\",\"version\":\"1.0.0\",\"description\":\"$p\"}]"
  done
  echo "# log" > "$R/CHANGELOG.md"
  g add -A; g commit -q -m base; g checkout -q -b pr
}
log() { echo "- $1" >> "$R/CHANGELOG.md"; }
commit_run() { g add -A; g commit -q -m change; OUT=$(cd "$R" && bash "$CHECK" main 2>&1); RC=$?; }
expect_pass() { [ "$RC" -eq 0 ] && ok "$1" || bad "$1 (rc=$RC: $OUT)"; }
expect_fail() { { [ "$RC" -ne 0 ] && grep -q -- "$2" <<<"$OUT"; } && ok "$1" || bad "$1 (rc=$RC: $OUT)"; }

fresh none; echo x > "$R/docs.md"; commit_run
expect_pass "a change outside plugins/ needs nothing"

fresh good; echo x >> "$R/plugins/a/README.md"; setver a 1.0.1; log a; commit_run
expect_pass "a changed and bumped, with CHANGELOG, passes"

fresh nolog; echo x >> "$R/plugins/a/README.md"; setver a 1.0.1; commit_run
expect_fail "no CHANGELOG fails" "CHANGELOG.md was not updated"

fresh cover; echo x >> "$R/plugins/a/README.md"; setver b 1.0.1; log ab; commit_run
expect_fail "b's bump does not cover a's change" "a changed but plugins/a/.claude-plugin/plugin.json version was not bumped"

fresh desc; mktjq '(.plugins[] | select(.name=="a") | .description) = "new"'; log a; commit_run
expect_fail "a marketplace-only description change needs a bump" "a changed but"

fresh halfpj; echo x >> "$R/plugins/a/README.md"; log a
jq '.version="1.0.1"' "$R/plugins/a/.claude-plugin/plugin.json" > "$R/t" && mv "$R/t" "$R/plugins/a/.claude-plugin/plugin.json"; commit_run
expect_fail "plugin.json bumped but marketplace entry not fails" "marketplace.json version was not bumped"

fresh down; echo x >> "$R/plugins/a/README.md"; setver a 0.9.0; log a; commit_run
expect_fail "a downgrade fails" "1.0.0 -> 0.9.0"

fresh semver; setver a 1.9.0; log a; g add -A; g commit -q -m m; g checkout -q main; g merge -q pr; g checkout -q -b pr2
echo x >> "$R/plugins/a/README.md"; setver a 1.10.0; log a
g add -A; g commit -q -m change; OUT=$(cd "$R" && bash "$CHECK" main 2>&1); RC=$?
expect_pass "1.9.0 -> 1.10.0 compares as semver, not text"

fresh newp; mkdir -p "$R/plugins/c/.claude-plugin"
echo '{"name":"c","version":"1.0.0","description":"c"}' > "$R/plugins/c/.claude-plugin/plugin.json"
mktjq '.plugins += [{"name":"c","version":"1.0.0","description":"c"}]'; log c; commit_run
expect_pass "a plugin new since base needs no bump"

fresh badname; mkdir -p "$R/plugins/Bad.Name"; echo x > "$R/plugins/Bad.Name/f"; log x; commit_run
expect_fail "a plugin dir outside [a-z0-9-] fails" "is not \[a-z0-9-\]"

exit $fail
