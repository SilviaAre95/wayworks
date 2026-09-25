#!/usr/bin/env bash
# Render a design's design.md into a local, tabbed HTML page.
#
# It renders the file itself rather than generating a map from it: the page
# shows exactly the diagrams and decision lines design-check.sh reads, so no
# model redraws anything and there is nothing extra to review. Output is local
# and gitignored (.wayworks/), never hosted — a hosted copy would leak
# unreleased designs or go stale under a URL something points at.
#
# Usage: render-map.sh [--open] <design-dir> [out-dir]   (out-dir default: .wayworks/maps)
#   --open  also open the page (macOS `open`, else `xdg-open`, else just print)
# Prints the written path. Exit 0 ok, 1 bad input, 2 usage.
set -uo pipefail
usage() { echo "usage: render-map.sh [--open] <design-dir> [out-dir]" >&2; exit 2; }
OPEN=0; DIR=""; OUT_DIR=""; npos=0
for a in "$@"; do
  case "$a" in
    --open) OPEN=1 ;;
    -*) usage ;;
    *) npos=$((npos + 1))
       case "$npos" in 1) DIR="$a" ;; 2) OUT_DIR="$a" ;; *) usage ;; esac ;;
  esac
done
[ "$npos" -ge 1 ] || usage
OUT_DIR="${OUT_DIR:-.wayworks/maps}"
DESIGN="$DIR/design.md"
TEMPLATE="$(cd "$(dirname "$0")/.." && pwd)/templates/map.html"
die() { echo "render-map: $*" >&2; exit 1; }

[ -f "$DESIGN" ] || die "$DESIGN not found"
[ -f "$TEMPLATE" ] || die "template missing: $TEMPLATE"
command -v jq >/dev/null 2>&1 || die "needs jq — install it with your package manager (https://jqlang.org/download/)"

# The slug becomes a filename, so it is validated, not trusted.
slug=$(awk 'NR==1 && $0!="---"{exit} NR>1 && $0=="---"{exit} NR>1' "$DESIGN" \
  | sed -nE 's/^slug:[[:space:]]*//p' | head -1 | sed -E 's/[[:space:]]+$//')
[ -n "$slug" ] || slug=$(basename "$DIR")
[[ "$slug" =~ ^[a-z0-9][a-z0-9-]*$ ]] || die "slug '$slug' must be kebab-case [a-z0-9-]"

# Split on '## ' headings; each becomes {title, md}. A '## ' line inside a
# code fence is content, not a tab, so awk marks only the real headings with a
# record-separator byte (stripped from the input first, so a design cannot
# forge one) and jq splits on the mark. Fences follow CommonMark, the same
# rules design-check.sh uses: 0–3 spaces of indent, a run of 3+ backticks or
# tildes (a backtick info string holds no backtick), closed only by a run of
# the same character at least as long with nothing after it. Every
# '<' is escaped so nothing in the design can close the
# <script type="application/json"> it sits in.
json=$(awk '
  function fence(s,   n) {  # 1 if s is a fence line; sets FR (the run) and FI (the rest)
    match(s, /^ */); n = RLENGTH; if (n > 3) return 0
    s = substr(s, n + 1)
    if (substr(s, 1, 1) == "`") match(s, /^`+/); else if (substr(s, 1, 1) == "~") match(s, /^~+/); else return 0
    if (RLENGTH < 3) return 0
    FR = substr(s, 1, RLENGTH); FI = substr(s, RLENGTH + 1); return 1
  }
  { gsub(/\036/, "") }
  fence($0) {
    if (!f) { if (!(substr(FR, 1, 1) == "`" && index(FI, "`"))) { f = 1; fc = substr(FR, 1, 1); fl = length(FR) } }
    else if (substr(FR, 1, 1) == fc && length(FR) >= fl && FI ~ /^[ \t]*$/) f = 0
    print; next
  }
  !f && /^## / { print "\036" $0; next }
  { print }' "$DESIGN" | jq -Rs '
  sub("^---\n[\\s\\S]*?\n---\n"; "")
  | ("\n" + .) | split("\n\u001e## ") | .[1:]
  | map(split("\n") as $l | {title: ($l[0] | sub("\\s+$"; "")), md: ($l[1:] | join("\n"))})
  | tojson | gsub("<"; "\\u003c")' -r) || die "could not parse $DESIGN"

mkdir -p "$OUT_DIR" || die "cannot create $OUT_DIR"
out="$OUT_DIR/$slug.html"
# .wayworks/maps is a predictable path: never write through a symlink planted
# there, and write a temp file beside the target then rename it into place.
[ -L "$out" ] && die "$out is a symlink — refusing to write through it"
data=$(mktemp) || die "mktemp failed"
tmp=$(mktemp "$OUT_DIR/.render-map.XXXXXX") || { rm -f "$data"; die "mktemp in $OUT_DIR failed"; }
trap 'rm -f "$data" "$tmp"' EXIT
printf '%s\n' "$json" > "$data"
awk -v jf="$data" -v slug="$slug" '
  /__DESIGN_SECTIONS__/ { while ((getline l < jf) > 0) print l; next }
  { gsub(/__SLUG__/, slug); print }' "$TEMPLATE" > "$tmp" || die "write failed: $tmp"
mv -f "$tmp" "$out" || die "write failed: $out"
echo "$out"
if [ "$OPEN" -eq 1 ]; then
  if [ "$(uname -s)" = "Darwin" ] && command -v open >/dev/null 2>&1; then open "$out"
  elif command -v xdg-open >/dev/null 2>&1; then xdg-open "$out" >/dev/null 2>&1
  fi
fi
