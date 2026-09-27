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
HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)  # before the cd below
SHAPE=$HERE/manifest-shape.jq
strict() { python3 "$HERE/strict-json.py" "$1"; }  # exactly one JSON object
cd "${MANIFEST_ROOT:-$(dirname "$0")/..}" || { echo "ERROR: cannot cd to manifest root" >&2; exit 2; }

fail=0
err() { echo "ERROR: $*" >&2; fail=1; }

MKT=.claude-plugin/marketplace.json
# Shape first, on the JSON: every later step splits names into lines and would
# be fooled by one that is not a unique [a-z0-9-] string.
strict "$MKT" || { err "$MKT is not exactly one JSON object"; exit 1; }
shape=$(jq -r -f "$SHAPE" "$MKT") || { err "$MKT is not valid JSON"; exit 1; }
if [ -n "$shape" ]; then
  while IFS= read -r v; do err "$MKT: $v"; done <<<"$shape"
  exit 1
fi
while IFS= read -r name; do
  manifest="plugins/$name/.claude-plugin/plugin.json"
  if [ ! -f "$manifest" ]; then
    err "marketplace lists '$name' but $manifest does not exist"; continue
  fi
  strict "$manifest" || { err "$manifest is not exactly one JSON object"; continue; }
  entry=$(jq -c --arg n "$name" '.plugins[] | select(.name==$n)' "$MKT")
  # Compared as JSON, inside jq: $(…) strips a trailing newline, so a bash
  # comparison would take "2.3.8\n" for "2.3.8". The entry already passed the
  # shape check, so matching it exactly makes plugin.json X.Y.Z too.
  pn=$(jq -c .name "$manifest"); mn=$(jq -c .name <<<"$entry")
  [ "$pn" = "$mn" ] || err "$manifest: name $pn != marketplace entry $mn"
  pv=$(jq -c .version "$manifest"); mv=$(jq -c .version <<<"$entry")
  [ "$pv" = "$mv" ] || err "$manifest: version $pv != marketplace version $mv"
  pd=$(jq -c '.description // empty' "$manifest")
  md=$(jq -c '.description // empty' <<<"$entry")
  if [ -z "$pd" ] || [ "$pd" = '""' ]; then
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
