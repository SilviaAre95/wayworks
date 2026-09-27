#!/usr/bin/env bash
# Tests for check-release-rule.sh, in throwaway git repos. The rule it replaced
# passed whenever any "version" line changed, so the case that matters most is
# one plugin's bump covering another plugin's unbumped change.
set -uo pipefail
# Fixture commits must not sign: a contributor's commit.gpgsign=true would
# prompt for a key or fail every one. Applies to every git call below.
export GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0=commit.gpgsign GIT_CONFIG_VALUE_0=false
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
    mktjq ".plugins += [{\"name\":\"$p\",\"source\":\"./plugins/$p\",\"version\":\"1.0.0\",\"description\":\"$p\"}]"
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

addc() {  # addc <version> — add plugin c
  mkdir -p "$R/plugins/c/.claude-plugin"
  echo "{\"name\":\"c\",\"version\":\"$1\",\"description\":\"c\"}" > "$R/plugins/c/.claude-plugin/plugin.json"
  mktjq ".plugins += [{\"name\":\"c\",\"source\":\"./plugins/c\",\"version\":\"$1\",\"description\":\"c\"}]"; log c
}
fresh newp; addc 1.0.0; mktjq '.metadata.version="1.1.0"'; commit_run
expect_pass "a new plugin at 1.0.0 with a marketplace bump passes"
fresh newnometa; addc 1.0.0; commit_run
expect_fail "a new plugin without a marketplace bump fails" "plugin set changed"
fresh newver; addc 2.0.0; mktjq '.metadata.version="1.1.0"'; commit_run
expect_fail "a new plugin not at 1.0.0 fails" "must enter at 1.0.0"
fresh removed; rm -rf "$R/plugins/b"; mktjq 'del(.plugins[] | select(.name=="b"))'; log b; commit_run
expect_fail "removing a plugin without a marketplace bump fails" "plugin set changed"

# A rename is a removal plus an addition: it cannot slip through as neither.
fresh rename; setver a 1.2.0; log a; g add -A; g commit -q -m m; g checkout -q main; g merge -q pr; g checkout -q -b pr2
g mv plugins/a plugins/z; echo x >> "$R/plugins/z/README.md"
jq '.name="z"' "$R/plugins/z/.claude-plugin/plugin.json" > "$R/t" && mv "$R/t" "$R/plugins/z/.claude-plugin/plugin.json"
mktjq '(.plugins[] | select(.name=="a")) |= (.name = "z" | .source = "./plugins/z")'; log z; commit_run
expect_fail "renaming a plugin without a marketplace bump fails" "plugin set changed"
expect_fail "a renamed plugin enters at 1.0.0" "z is new since base"

# The path list must see every changed path.
fresh quoted; echo x > "$R/plugins/a/café.md"; commit_run
expect_fail "a non-ASCII path (git quotes it) is still a plugin change" "CHANGELOG.md was not updated"
fresh moved; g mv plugins/a/README.md docs-README.md; commit_run
expect_fail "moving a file out of a plugin is a change to that plugin" "a changed but"

fresh pre; echo x >> "$R/plugins/a/README.md"; setver a 1.0.0-rc1; log a; commit_run
expect_fail "a prerelease suffix is not a bump" "is not X.Y.Z"
fresh pjnl; echo x >> "$R/plugins/a/README.md"; setver a 1.0.1; log a
jq '.version="1.0.1\n"' "$R/plugins/a/.claude-plugin/plugin.json" > "$R/t" && mv "$R/t" "$R/plugins/a/.claude-plugin/plugin.json"; commit_run
expect_fail "a plugin.json version with a trailing newline is not a bump" "1.0.0 -> invalid"
fresh nomkt; echo x >> "$R/plugins/a/README.md"; g rm -q .claude-plugin/marketplace.json; log a; commit_run
expect_fail "a deleted marketplace.json fails as missing" "missing at HEAD"
fresh wsmkt; echo x >> "$R/plugins/a/README.md"; setver a 1.0.1; printf '  \n\n' > "$R/.claude-plugin/marketplace.json"; log a; commit_run
expect_fail "a whitespace-only marketplace.json fails as not JSON" "not exactly one JSON object"
fresh pjmulti; echo x >> "$R/plugins/a/README.md"; setver a 1.0.1; printf ' 5' >> "$R/plugins/a/.claude-plugin/plugin.json"; log a; commit_run
expect_fail "a plugin.json with a second document is not a bump" "1.0.0 -> invalid"
fresh badmkt; echo x >> "$R/plugins/a/README.md"; echo '{}' > "$R/.claude-plugin/marketplace.json"; log a; commit_run
expect_fail "a marketplace.json with no plugins array fails closed" "no plugins array"

# A name holding a newline read as two existing names and hid a new entry.
fresh nlname; mktjq '.plugins += [{"name":"a\na","source":"./plugins/a","version":"9.9.9","description":"x"}]'; log x; commit_run
expect_fail "a plugin name with a newline fails the shape check" 'plugin name "a\\na"'
fresh dup; mktjq '.plugins += [.plugins[0]]'; log x; commit_run
expect_fail "a duplicated plugin name fails the shape check" "listed more than once"

fresh badname; mkdir -p "$R/plugins/Bad.Name"; echo x > "$R/plugins/Bad.Name/f"; log x; commit_run
expect_fail "a plugin dir outside [a-z0-9-] fails" "is not \[a-z0-9-\]"

exit $fail
