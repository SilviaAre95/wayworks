#!/usr/bin/env bash
# Asserts marketplace.json and every plugins/<name>/.claude-plugin/plugin.json
# agree: each entry resolves to a manifest and each plugin dir is listed, and
# name, version and description match.
#
# plugin.json is the source of truth for the description. The marketplace copy
# is what a browsing user reads before installing, so a stale one misdescribes
# the plugin — shared and design both drifted for weeks while only name and
# version were compared.
#
# Root override (for the self-test): MANIFEST_ROOT=<dir>.
set -uo pipefail
cd "${MANIFEST_ROOT:-$(dirname "$0")/..}" || { echo "ERROR: cannot cd to manifest root" >&2; exit 2; }

fail=0
err() { echo "ERROR: $*" >&2; fail=1; }

MKT=.claude-plugin/marketplace.json
while IFS= read -r name; do
  # The name becomes a path; anything but [a-z0-9-] could split or escape it.
  [[ "$name" =~ ^[a-z0-9][a-z0-9-]*$ ]] || { err "marketplace plugin name '$name' is not [a-z0-9-]"; continue; }
  manifest="plugins/$name/.claude-plugin/plugin.json"
  if [ ! -f "$manifest" ]; then
    err "marketplace lists '$name' but $manifest does not exist"; continue
  fi
  entry=$(jq -c --arg n "$name" '.plugins[] | select(.name==$n)' "$MKT")
  pn=$(jq -r .name "$manifest")
  [ "$pn" = "$name" ] || err "$manifest: name '$pn' != marketplace entry '$name'"
  pv=$(jq -r .version "$manifest")
  mv=$(jq -r .version <<<"$entry")
  [ "$mv" = "$pv" ] || err "$manifest: version $pv != marketplace version $mv"
  pd=$(jq -r '.description // empty' "$manifest")
  md=$(jq -r '.description // empty' <<<"$entry")
  if [ -z "$pd" ]; then
    err "$manifest: no description (it is the source of truth for the marketplace entry)"
  elif [ "$md" != "$pd" ]; then
    err "$manifest: description differs from its marketplace entry — copy plugin.json's into marketplace.json"
    echo "  plugin.json:      $pd" >&2
    echo "  marketplace.json: $md" >&2
  fi
done < <(jq -r '.plugins[].name' "$MKT")
for dir in plugins/*/; do
  name=$(basename "$dir")
  jq -e --arg n "$name" '.plugins[] | select(.name==$n)' "$MKT" >/dev/null \
    || err "plugins/$name exists but is not listed in marketplace.json"
done
exit $fail
