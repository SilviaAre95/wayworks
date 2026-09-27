#!/usr/bin/env bash
# Enforces the release rule (AGENTS.md / CONTRIBUTING.md) on HEAD against a base
# ref. CI runs it on every pull request as the required "Version bump +
# CHANGELOG on plugin changes" check.
#
#   - Any change under plugins/ or .claude-plugin/ must change CHANGELOG.md.
#   - Every plugin that changed — a file under plugins/<name>/, or its
#     marketplace entry in any field but version — must carry a strictly higher
#     X.Y.Z version than base in BOTH its plugin.json and its marketplace entry.
#   - A plugin added or removed (a rename is both) changes the plugin set, so
#     metadata.version must rise too; a new plugin enters at 1.0.0.
#
# Guaranteed only for a marketplace.json that passes manifest-shape.jq (unique
# [a-z0-9-] names, source ./plugins/<name>, X.Y.Z versions), and only against
# the base CI ran on — the ruleset requires branches to be up to date so that
# base is main's tip at merge. Not covered: a PR that edits this script or
# ci.yml (the job runs the PR's copy), and top-level marketplace fields.
#
# Per plugin, not per PR: grepping the diff for any "version" line let one
# plugin's bump cover another plugin's unbumped change. check-manifests.sh
# holds the two manifests in sync.
#
# Fails closed: the path list is read raw (-z; git otherwise quotes non-ASCII
# paths, which then match no pattern) and without rename detection (which
# reports only a moved file's destination), and an unreadable diff or
# marketplace.json is an error, never "not applicable".
#
# Usage: check-release-rule.sh <base-ref>   (compares merge-base..HEAD)
set -uo pipefail
base=${1:?usage: check-release-rule.sh <base-ref>}
mb=$(git merge-base "$base" HEAD) || { echo "ERROR: no merge-base with $base" >&2; exit 2; }

fail=0
err() { echo "::error::$*"; fail=1; }

changed=$(git diff --name-only --no-renames -z "$mb" HEAD | tr '\0' '\n') \
  || { echo "ERROR: git diff failed" >&2; exit 2; }
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
semver() { [[ "$1" =~ ^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$ ]]; }
higher() {  # $2 > $1, both plain X.Y.Z; anything else is not a bump
  semver "$1" && semver "$2" || return 1
  local IFS=. a b; read -r -a a <<<"$1"; read -r -a b <<<"$2"
  for i in 0 1 2; do
    [ "${b[i]}" -gt "${a[i]}" ] && return 0
    [ "${b[i]}" -lt "${a[i]}" ] && return 1
  done
  return 1
}

mkt_base=$(at "$mb" "$MKT"); mkt_head=$(at HEAD "$MKT")
[ -n "$mkt_head" ] || { err "$MKT is missing at HEAD"; exit 1; }
STRICT="$(dirname "${BASH_SOURCE[0]}")/strict-json.py"  # exactly one JSON object
python3 "$STRICT" - <<<"$mkt_head" || { err "$MKT at HEAD is not exactly one JSON object"; exit 1; }
# Shape first (the same allowlist check-manifests.sh applies): everything below
# splits names into lines, so a name outside [a-z0-9-] could hide an entry.
shape=$(jq -r -f "$(dirname "${BASH_SOURCE[0]}")/manifest-shape.jq" <<<"$mkt_head" 2>/dev/null) \
  || { err "$MKT at HEAD is missing or not valid JSON"; exit 1; }
if [ -n "$shape" ]; then
  while IFS= read -r v; do err "$MKT at HEAD: $v"; done <<<"$shape"
  exit 1
fi
set_changed=0
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
  if [ -z "$eh" ] || [ -z "$eb" ]; then
    [ -n "$eb$eh" ] || continue               # in neither: check-manifests.sh fails an unlisted dir
    set_changed=1
    if [ -n "$eh" ]; then                     # added (or the new half of a rename)
      v=$(jq -r '.version // empty' <<<"$eh")
      [ "$v" = "1.0.0" ] || err "$name is new since base and must enter at 1.0.0 (has ${v:-none})"
    fi
    continue
  fi
  pj="plugins/$name/.claude-plugin/plugin.json"
  # plugin.json is not shape-checked here; the X.Y.Z test runs inside jq,
  # since $(…) would strip a trailing newline before higher() saw it.
  pver='.version | if type == "string" and test("\\A(0|[1-9][0-9]*)\\.(0|[1-9][0-9]*)\\.(0|[1-9][0-9]*)\\z") then . else "invalid" end'
  pb=$(at "$mb" "$pj" | jq -r "$pver" 2>/dev/null)
  if at HEAD "$pj" | python3 "$STRICT" - 2>/dev/null; then
    ph=$(at HEAD "$pj" | jq -r "$pver" 2>/dev/null)
  else
    ph=invalid                                # not exactly one object: never a bump
  fi
  mb_v=$(jq -r '.version // empty' <<<"$eb"); mh_v=$(jq -r '.version // empty' <<<"$eh")
  higher "$pb" "$ph" || err "$name changed but $pj version was not bumped ($pb -> ${ph:-missing})"
  higher "$mb_v" "$mh_v" || err "$name changed but its marketplace.json version was not bumped ($mb_v -> ${mh_v:-missing})"
done < <({
  sed -nE 's#^plugins/([^/]+)/.*#\1#p' <<<"$changed"
  jq -r '.plugins[]?.name' <<<"$mkt_head"
} | sort -u)

# Names that were only in base's marketplace (removed plugins) also change the set.
while IFS= read -r name; do
  [ -n "$(entry "$mkt_head" "$name")" ] || set_changed=1
done < <(jq -r '.plugins[]?.name' <<<"$mkt_base" 2>/dev/null)
if [ "$set_changed" -eq 1 ]; then
  vb=$(jq -r '.metadata.version // empty' <<<"$mkt_base" 2>/dev/null)
  vh=$(jq -r '.metadata.version // empty' <<<"$mkt_head")
  higher "$vb" "$vh" || err "the plugin set changed but metadata.version was not bumped (${vb:-none} -> ${vh:-none})"
fi

[ "$fail" -eq 0 ] && echo "Release rule satisfied."
exit $fail
