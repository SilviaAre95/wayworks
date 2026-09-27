#!/usr/bin/env bash
# Enforces the release rule (AGENTS.md / CONTRIBUTING.md) on HEAD against a base
# ref. CI runs it on every pull request as the required "Version bump +
# CHANGELOG on plugin changes" check.
#
#   - Any change under plugins/ or .claude-plugin/ must change CHANGELOG.md.
#   - Every plugin that changed — a file under plugins/<name>/, or its
#     marketplace entry in any field but version — must carry a strictly higher
#     version than base in BOTH its plugin.json and its marketplace entry.
#
# Per plugin, not per PR: grepping the diff for any "version" line let one
# plugin's bump cover another plugin's unbumped change. A plugin new since base
# needs no bump; check-manifests.sh already holds the two manifests in sync.
#
# Usage: check-release-rule.sh <base-ref>   (compares merge-base..HEAD)
set -uo pipefail
base=${1:?usage: check-release-rule.sh <base-ref>}
mb=$(git merge-base "$base" HEAD) || { echo "ERROR: no merge-base with $base" >&2; exit 2; }

fail=0
err() { echo "::error::$*"; fail=1; }

changed=$(git diff --name-only "$mb" HEAD)
printf '%s\n' "$changed"
if ! grep -qE '^(plugins/|\.claude-plugin/)' <<<"$changed"; then
  echo "No plugin changes — release rule not applicable."
  exit 0
fi
grep -qx 'CHANGELOG.md' <<<"$changed" \
  || err "plugins/ or .claude-plugin/ changed but CHANGELOG.md was not updated"

MKT=.claude-plugin/marketplace.json
at() { git show "$1:$2" 2>/dev/null; }  # <commit> <path> -> contents, empty if absent
entry() { jq -c --arg n "$2" '.plugins[]? | select(.name==$n)' <<<"$1"; }
higher() { [ "$1" != "$2" ] && [ "$(printf '%s\n%s\n' "$1" "$2" | sort -V | tail -1)" = "$2" ]; }  # $2 > $1

mkt_base=$(at "$mb" "$MKT"); mkt_head=$(at HEAD "$MKT")
# Plugins that changed: files under plugins/<name>/, plus any marketplace entry
# that differs outside its version.
while IFS= read -r name; do
  # The name is interpolated into a path and a grep pattern below.
  [[ "$name" =~ ^[a-z0-9][a-z0-9-]*$ ]] || { err "plugin name '$name' is not [a-z0-9-]"; continue; }
  eb=$(entry "$mkt_base" "$name"); eh=$(entry "$mkt_head" "$name")
  files_changed=$(grep -c "^plugins/$name/" <<<"$changed")
  if [ "$files_changed" -eq 0 ] \
     && [ "$(jq -S 'del(.version)' <<<"$eb" 2>/dev/null)" = "$(jq -S 'del(.version)' <<<"$eh" 2>/dev/null)" ]; then
    continue                                  # untouched plugin
  fi
  [ -n "$eh" ] || continue                    # removed from the marketplace
  [ -n "$eb" ] || continue                    # new since base: enters as-is
  pj="plugins/$name/.claude-plugin/plugin.json"
  pb=$(at "$mb" "$pj" | jq -r '.version // empty' 2>/dev/null)
  ph=$(at HEAD "$pj" | jq -r '.version // empty' 2>/dev/null)
  mb_v=$(jq -r '.version // empty' <<<"$eb"); mh_v=$(jq -r '.version // empty' <<<"$eh")
  higher "$pb" "$ph" || err "$name changed but $pj version was not bumped ($pb -> ${ph:-missing})"
  higher "$mb_v" "$mh_v" || err "$name changed but its marketplace.json version was not bumped ($mb_v -> ${mh_v:-missing})"
done < <({
  sed -nE 's#^plugins/([^/]+)/.*#\1#p' <<<"$changed"
  jq -r '.plugins[]?.name' <<<"$mkt_head"
} | sort -u)

[ "$fail" -eq 0 ] && echo "Release rule satisfied."
exit $fail
