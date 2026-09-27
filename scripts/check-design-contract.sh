#!/usr/bin/env bash
# Asserts the string contract between the design pipeline's three halves.
#
# Also: the loop commands' pinned allowed-tools (see that section).
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

# --- loop commands' allowed-tools: pinned, entry for entry -----------------
# A loop runs unattended, so what it may do without a prompt is fixed here:
# each loop command's allowed-tools must be exactly its pinned list below — a
# changed grant means editing this file, on purpose. A pattern allowlist was
# not enough: every hooks/scripts entry would pass, and the gate scripts eval
# config the loop itself can write, so granting one is Bash(*) without a
# prompt; a pattern for the disarm let it delete another loop's files.
# The pinned disarm must also equal the one rm command in the body: a grant
# that drifts from the body prompts (or fails) exactly when the loop must abort.
# A backticked rm in the prose (an example, a warning) counts as a second rm
# command — reword it without backticks.
# The frontmatter may hold only known keys on single lines, and no control
# bytes: an indented continuation, a misspelled key, or a lone CR (YAML breaks
# lines on it, awk and grep do not) would put a second allowed-tools where a
# one-line read never looks.
PIN_ARM='Bash(${CLAUDE_PLUGIN_ROOT}/hooks/scripts/loop-arm.sh:*)'
check_grants() { # $1=command file  $2=pinned entries, one per line
  local f=$1 pinned=$2 fm body line entry entries disarm cmds nc s
  perl -ne 'exit 1 if /[\x00-\x08\x0b-\x1f\x7f]/' "$f" \
    || err "$f: contains a control byte (CR, VT, FF, ...) that YAML may read as a line break" # rule:control-bytes
  fm=$(awk 'NR==1 && $0!="---"{exit} NR>1 && $0=="---"{exit} NR>1' "$f")
  body=$(awk 'NR>1 && $0=="---"{b=1; next} b' "$f")
  # Fail safe the other way too: Claude Code ends the frontmatter at the first
  # "---" even mid-line, and a Unicode line separator makes it unparseable —
  # either way the loop silently loses its grants. So: ASCII only (control bytes are the rule above).
  printf '%s\n' "$fm" | perl -ne 'exit 1 if /[\x80-\xff]/' \
    || err "$f: frontmatter has a non-ASCII byte — Claude Code may not parse it" # rule:fm-ascii
  printf '%s\n' "$fm" | grep -qF -- '---' \
    && err "$f: frontmatter has '---' inside a line — Claude Code ends the frontmatter there" # rule:fm-dashes
  while IFS= read -r line; do
    printf '%s\n' "$line" | grep -qE '^(description|argument-hint|allowed-tools):( |$)' \
      || err "$f: frontmatter line '$line' is not a known single-line key" # rule:frontmatter-keys
  done <<<"$fm"
  [ "$(printf '%s\n' "$fm" | grep -c '^allowed-tools:')" -eq 1 ] \
    || err "$f: expected exactly one allowed-tools line, found $(printf '%s\n' "$fm" | grep -c '^allowed-tools:') allowed-tools lines" # rule:one-allowed-tools
  entries=$(printf '%s\n' "$fm" | sed -n 's/^allowed-tools:[[:space:]]*//p' | head -1 \
    | awk '{d=0; cur=""; for (i=1; i<=length($0); i++) { c=substr($0,i,1); if (c=="(") d++; if (c==")") d--;
            if (c=="," && d==0) { print cur; cur="" } else cur=cur c } print cur }' \
    | sed -E 's/^[[:space:]]+//; s/[[:space:]]+$//')
  while IFS= read -r entry; do
    printf '%s\n' "$pinned" | grep -qxF -- "$entry" \
      || err "$f: grant '$entry' is not in its pinned list in $0" # rule:pinned
  done <<<"$entries"
  while IFS= read -r entry; do
    printf '%s\n' "$entries" | grep -qxF -- "$entry" \
      || err "$f: pinned grant '$entry' is missing from allowed-tools" # rule:pinned
    case "$entry" in 'Bash(${CLAUDE_PLUGIN_ROOT}/hooks/scripts/'*)
      s=${entry#'Bash(${CLAUDE_PLUGIN_ROOT}/'}; s=${s%:\*)}
      [ -f "plugins/harness/$s" ] || err "$f: pinned grant '$entry' names a script that does not exist" # rule:script-exists
    esac
  done <<<"$pinned"
  # The body is checked against the file's own disarm grant (the pinned rule
  # above holds that grant to its list), so each rule catches one thing.
  printf '%s\n' "$pinned" | grep -q '^Bash(rm ' || return 0
  disarm=$(printf '%s\n' "$entries" | sed -n 's/^Bash(\(rm .*\))$/\1/p' | head -1)
  [ -n "$disarm" ] || return 0   # a missing grant is the pinned rule's to report
  # The body's rm commands: inline `rm ...` spans and whole-line rm commands.
  cmds=$( { printf '%s\n' "$body" | grep -oE '`rm [^`]*`' | tr -d '`'
            printf '%s\n' "$body" | sed -nE 's/^[[:space:]]*(rm [^`]*[^[:space:]`])[[:space:]]*$/\1/p'; } | sort -u)
  nc=$(printf '%s\n' "$cmds" | grep -c .)
  if [ "$nc" -ne 1 ]; then
    err "$f: expected exactly one rm command in the body (the disarm), found $nc: ${cmds:-none}" # rule:disarm-body
  elif [ "$cmds" != "$disarm" ]; then
    err "$f: the body's disarm '$cmds' does not match its grant 'Bash($disarm)' verbatim" # rule:disarm-verbatim
  fi
}
DISARM_DEV='rm -f .cc-loop-dev-active .cc-loop-dev-state .cc-loop-dev-rounds'
DISARM_DEPLOY='rm -f .cc-deploy-active .cc-deploy-state'
check_grants "$LOOP" "$PIN_ARM
Bash($DISARM_DEV)
Bash(\${CLAUDE_PLUGIN_ROOT}/hooks/scripts/loop-dev-preflight.sh:*)"
check_grants plugins/harness/commands/loop-deploy.md "$PIN_ARM
Bash($DISARM_DEPLOY)"
check_grants plugins/harness/commands/loop-build.md "$PIN_ARM"

# A gate that blocks tells the stuck loop how to disarm. That text must be the
# granted disarm too, or the abort prompts exactly when the loop is stuck.
for pair in "loop-dev-gate.sh:$DISARM_DEV" "loop-deploy-gate.sh:$DISARM_DEPLOY"; do
  gate=plugins/harness/hooks/scripts/${pair%%:*}; disarm=${pair#*:}
  [ -f "$gate" ] || { err "$gate is missing — its disarm hints go unchecked"; continue; } # rule:gate-exists
  while IFS= read -r said; do
    [ -z "$said" ] || [ "$said" = "$disarm" ] \
      || err "$gate tells the loop to disarm with '$said', but the granted disarm is '$disarm'" # rule:hook-disarm
  done < <(grep -oE 'rm( -[a-z]+)?( \.cc-[a-z0-9-]+)+' "$gate" | sort -u)
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

[ "$fail" -eq 0 ] && echo "-- design contract: tokens, $nn stages, template seed '$seed', loop grants agree"
exit $fail
