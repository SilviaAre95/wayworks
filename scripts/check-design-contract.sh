#!/usr/bin/env bash
# Asserts the string contract between the design pipeline's three halves.
#
# Also: the loop commands' allowed-tools allowlist (see that section).
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
for f in "$LOOP" "$PRE" "$SHAPE" "$TPL" plugins/harness/commands/loop-deploy.md plugins/harness/commands/loop-build.md; do
  [ -f "$f" ] || { err "$f is missing"; }
done
[ "$fail" -eq 0 ] || exit 1

# --- preflight tokens: emitted by the script, read by the command ------------
for tok in REQUIRE_DESIGN DESIGN_ALREADY_FOLDED; do
  grep -qE "echo \"$tok: " "$PRE" || err "$PRE no longer prints '$tok: ' — $LOOP reads it"
  grep -qF "$tok" "$LOOP" || err "$LOOP no longer reads $tok — $PRE still prints it"
done

# --- loop commands' allowed-tools: an allowlist, not an rm blocklist ---------
# A loop runs unattended, so what it may do without a prompt is fixed here.
# Every allowed-tools entry must be one of:
#   Bash(${CLAUDE_PLUGIN_ROOT}/hooks/scripts/<name>.sh:*)  for a script that ships
#   Bash(rm -f .cc-<file> ...)  the disarm, verbatim, and only where one is expected
# Anything else fails: Bash(*), bare Bash, Bash(rm:*), Bash(cat:*), a non-Bash
# tool. An allowlist needs no list of rm spellings to keep up with. The disarm
# grant must equal the one rm command in the body: a grant that drifts from the
# body prompts (or fails) exactly when the loop must abort. The frontmatter
# may hold only known keys on single lines — an indented continuation or a
# misspelled key would put grants where a one-line read never looks.
RE_SCRIPT='^Bash\(\$\{CLAUDE_PLUGIN_ROOT\}/hooks/scripts/([a-z0-9-]+\.sh):\*\)$'
RE_DISARM='^Bash\((rm -f( \.cc-[a-z0-9-]+)+)\)$'
check_grants() { # $1=command file  $2=required|none (is a disarm expected)
  local f=$1 mode=$2 fm body line entry disarms="" cmds nd nc
  fm=$(awk 'NR==1 && $0!="---"{exit} NR>1 && $0=="---"{exit} NR>1' "$f")
  body=$(awk 'NR>1 && $0=="---"{b=1; next} b' "$f")
  while IFS= read -r line; do
    printf '%s\n' "$line" | grep -qE '^(description|argument-hint|allowed-tools):( |$)' \
      || err "$f: frontmatter line '$line' is not a known single-line key" # rule:frontmatter-keys
  done <<<"$fm"
  [ "$(printf '%s\n' "$fm" | grep -c '^allowed-tools:')" -eq 1 ] \
    || err "$f: expected exactly one allowed-tools line, found $(printf '%s\n' "$fm" | grep -c '^allowed-tools:') allowed-tools lines" # rule:one-allowed-tools
  while IFS= read -r entry; do
    if [[ $entry =~ $RE_SCRIPT ]]; then
      [ -f "plugins/harness/hooks/scripts/${BASH_REMATCH[1]}" ] \
        || err "$f: grant '$entry' names a script that does not exist" # rule:script-exists
    elif [[ $entry =~ $RE_DISARM ]]; then
      disarms="$disarms${BASH_REMATCH[1]}"$'\n'
    else
      err "$f: grant '$entry' is not on the allowlist (a hooks/scripts script, or the disarm verbatim)" # rule:allowlist
    fi
  done < <(printf '%s\n' "$fm" | sed -n 's/^allowed-tools:[[:space:]]*//p' | head -1 \
    | awk '{d=0; cur=""; for (i=1; i<=length($0); i++) { c=substr($0,i,1); if (c=="(") d++; if (c==")") d--;
            if (c=="," && d==0) { print cur; cur="" } else cur=cur c } print cur }' \
    | sed -E 's/^[[:space:]]+//; s/[[:space:]]+$//')
  nd=$(printf '%s' "$disarms" | grep -c .)
  if [ "$mode" = none ]; then
    [ "$nd" -eq 0 ] || err "$f: expected no rm grant, found: $disarms" # rule:no-disarm
    return
  fi
  # The body's rm commands: inline `rm ...` spans and whole-line rm commands.
  cmds=$( { printf '%s\n' "$body" | grep -oE '`rm [^`]*`' | tr -d '`'
            printf '%s\n' "$body" | sed -nE 's/^[[:space:]]*(rm [^`]*[^[:space:]`])[[:space:]]*$/\1/p'; } | sort -u)
  nc=$(printf '%s\n' "$cmds" | grep -c .)
  if [ "$nd" -ne 1 ]; then
    err "$f: expected exactly one disarm grant 'Bash(rm -f .cc-…)', found $nd" # rule:disarm-grant
  elif [ "$nc" -ne 1 ]; then
    err "$f: expected exactly one rm command in the body (the disarm), found $nc: ${cmds:-none}" # rule:disarm-body
  elif [ "$cmds" != "${disarms%$'\n'}" ]; then
    err "$f: rm grant 'Bash(${disarms%$'\n'})' does not match the disarm command '$cmds' verbatim" # rule:disarm-verbatim
  fi
}
check_grants "$LOOP" required
check_grants plugins/harness/commands/loop-deploy.md required
check_grants plugins/harness/commands/loop-build.md none

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

[ "$fail" -eq 0 ] && echo "-- design contract: tokens, $nn stages, template seed '$seed', loop grants agree"
exit $fail
