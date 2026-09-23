#!/usr/bin/env bash
# Render a design's design.md into a local, tabbed HTML page.
#
# It renders the file itself rather than generating a map from it: the page
# shows exactly the diagrams and decision lines design-check.sh reads, so no
# model redraws anything and there is nothing extra to review. Output is local
# and gitignored (.wayworks/), never hosted — a hosted copy would leak
# unreleased designs or go stale under a URL something points at.
#
# Usage: render-map.sh <design-dir> [out-dir]   (out-dir default: .wayworks/maps)
# Prints the written path. Exit 0 ok, 1 bad input, 2 usage.
set -uo pipefail
usage() { echo "usage: render-map.sh <design-dir> [out-dir]" >&2; exit 2; }
[ $# -ge 1 ] && [ $# -le 2 ] || usage
DIR="$1"; OUT_DIR="${2:-.wayworks/maps}"
DESIGN="$DIR/design.md"
TEMPLATE="$(cd "$(dirname "$0")/.." && pwd)/templates/map.html"
die() { echo "render-map: $*" >&2; exit 1; }

[ -f "$DESIGN" ] || die "$DESIGN not found"
[ -f "$TEMPLATE" ] || die "template missing: $TEMPLATE"
command -v jq >/dev/null 2>&1 || die "needs jq (e.g. 'brew install jq')"

# The slug becomes a filename, so it is validated, not trusted.
slug=$(awk 'NR==1 && $0!="---"{exit} NR>1 && $0=="---"{exit} NR>1' "$DESIGN" \
  | sed -nE 's/^slug:[[:space:]]*//p' | head -1 | sed -E 's/[[:space:]]+$//')
[ -n "$slug" ] || slug=$(basename "$DIR")
[[ "$slug" =~ ^[a-z0-9][a-z0-9-]*$ ]] || die "slug '$slug' must be kebab-case [a-z0-9-]"

# Split on '## ' headings; each becomes {title, md}. Every '<' is escaped so
# nothing in the design can close the <script type="application/json"> it sits in.
json=$(jq -Rs '
  sub("^---\n[\\s\\S]*?\n---\n"; "")
  | ("\n" + .) | split("\n## ") | .[1:]
  | map(split("\n") as $l | {title: ($l[0] | sub("\\s+$"; "")), md: ($l[1:] | join("\n"))})
  | tojson | gsub("<"; "\\u003c")' -r "$DESIGN") || die "could not parse $DESIGN"

mkdir -p "$OUT_DIR" || die "cannot create $OUT_DIR"
out="$OUT_DIR/$slug.html"
data=$(mktemp) || die "mktemp failed"
trap 'rm -f "$data"' EXIT
printf '%s\n' "$json" > "$data"
awk -v jf="$data" -v slug="$slug" '
  /__DESIGN_SECTIONS__/ { while ((getline l < jf) > 0) print l; next }
  { gsub(/__SLUG__/, slug); print }' "$TEMPLATE" > "$out" || die "write failed: $out"
echo "$out"
