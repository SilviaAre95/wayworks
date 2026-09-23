#!/usr/bin/env bash
# Asserts the string contract between the design pipeline's three halves.
#
# Why this exists: loop-dev.md reacts to tokens the preflight prints
# (REQUIRE_DESIGN, DESIGN_ALREADY_FOLDED), shape.md resumes from a frontmatter
# `stage:` that must name a row of its own stage table, and the design template
# seeds that field. Each side is prose or a script edited on its own, so a
# rename on one side leaves the other matching nothing — and a prose command
# that never sees its token does not fail, it silently takes the other branch.
#
# Root override (for the self-test): CONTRACT_ROOT=<dir>.
set -uo pipefail
cd "${CONTRACT_ROOT:-$(dirname "$0")/..}"

fail=0
err() { echo "ERROR: $*" >&2; fail=1; }

LOOP=plugins/harness/commands/loop-dev.md
PRE=plugins/harness/hooks/scripts/loop-dev-preflight.sh
SHAPE=plugins/harness/commands/shape.md
TPL=plugins/harness/templates/design.md
for f in "$LOOP" "$PRE" "$SHAPE" "$TPL"; do
  [ -f "$f" ] || { err "$f is missing"; }
done
[ "$fail" -eq 0 ] || exit 1

# --- preflight tokens: emitted by the script, read by the command ------------
for tok in REQUIRE_DESIGN DESIGN_ALREADY_FOLDED; do
  grep -qE "echo \"$tok: " "$PRE" || err "$PRE no longer prints '$tok: ' — $LOOP reads it"
  grep -qF "$tok" "$LOOP" || err "$LOOP no longer reads $tok — $PRE still prints it"
done

# --- shape stage names vs. its stage table -----------------------------------
# The `stage:` list and the table must name the same stages in the same order.
# A table title is normalised (lowercase, spaces -> '-') and must equal the
# stage name or end in '-<name>' ("Feature questions" -> questions).
names=$(grep -E '^`stage:` names, in order:' "$SHAPE" | head -1 | sed -E 's/^[^:]*:[^:]*:[[:space:]]*//' \
  | grep -oE '`[a-z0-9-]+`' | tr -d '`')
titles=$(grep -E '^\| [0-9]+ \| \*\*[^*]+\*\* \|' "$SHAPE" \
  | sed -E 's/^\| [0-9]+ \| \*\*([^*]+)\*\*.*/\1/' | tr 'A-Z' 'a-z' | tr ' ' '-')
nn=$(printf '%s\n' "$names" | grep -c .)
nt=$(printf '%s\n' "$titles" | grep -c .)
if [ "$nn" -eq 0 ] || [ "$nt" -eq 0 ]; then
  err "$SHAPE: could not parse the stage list ($nn) or the stage table ($nt) — the check is broken, not the command"
elif [ "$nn" -ne "$nt" ]; then
  err "$SHAPE: $nn stage names but $nt table rows"
else
  i=0
  while IFS= read -r name; do
    i=$((i + 1))
    title=$(printf '%s\n' "$titles" | sed -n "${i}p")
    case "$title" in "$name"|*"-$name") ;; *) err "$SHAPE: stage $i is '$name' in the list but '$title' in the table" ;; esac
  done <<<"$names"
fi

# --- the template's starting stage is a real stage ---------------------------
seed=$(awk 'NR==1 && $0!="---"{exit} NR>1 && $0=="---"{exit} NR>1' "$TPL" | sed -nE 's/^stage:[[:space:]]*([a-z0-9-]+).*/\1/p' | head -1)
printf '%s\n' "$names" | grep -qxF -- "${seed:-<none>}" \
  || err "$TPL seeds 'stage: ${seed:-<none>}', which is not a stage in $SHAPE"

[ "$fail" -eq 0 ] && echo "-- design contract: tokens, $nn stages, template seed '$seed' agree"
exit $fail
