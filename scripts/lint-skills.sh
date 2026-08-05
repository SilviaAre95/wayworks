#!/usr/bin/env bash
# Frontmatter linter for skills and commands. Dependency-free (awk/grep only),
# same contract as check.sh: errors set the exit code, warnings never do.
#
# Skills and commands follow deliberately different conventions:
#   - Skills declare `name` (matching their directory) and a *quoted* description.
#   - Commands derive their name from the filename, and their descriptions are
#     bare scalars. Applying the skill rules to them would invent violations.
set -uo pipefail
# LINT_ROOT lets the test suite point the linter at a fixture tree; unset in
# normal use, where it lints this repo.
cd "${LINT_ROOT:-$(dirname "$0")/..}"

fail=0
warn_count=0
err()  { echo "ERROR: $*" >&2; fail=1; }
warn() { echo "warning: $*" >&2; warn_count=$((warn_count+1)); }

# House guidance in shared:create-skill. Advisory: a description is also the
# model-invocation trigger surface, and skills that must auto-fire on many
# phrasings legitimately run long. Bloat is worth knowing about, not worth
# failing a build over.
MAX_DESC=250

# Files allowed to contain positional-looking tokens because they *document*
# the prohibition rather than use it. Keep this list as short as possible.
positional_exempt() {
  case "$1" in
    plugins/shared/skills/create-skill/SKILL.md) return 0 ;;
    *) return 1 ;;
  esac
}

has_frontmatter() { head -1 "$1" 2>/dev/null | grep -q '^---$'; }

# Read one frontmatter key's raw value. Stops at the closing delimiter so body
# text can never be mistaken for frontmatter.
fm() {
  awk -v k="$2" '
    NR==1 && $0 != "---" { exit }
    NR>1  && $0 == "---" { exit }
    NR>1 { if ($0 ~ "^"k":[ \t]*") { sub("^"k":[ \t]*", ""); print; exit } }
  ' "$1"
}

# Quoted "..." / '...' or a YAML block scalar (>, |) are all acceptable.
# A bare scalar is not: an unquoted description containing a colon or a `#`
# silently truncates or breaks the parse.
is_quoted() {
  case "$1" in
    '"'*'"') return 0 ;;
    "'"*"'") return 0 ;;
    '>'*|'|'*) return 0 ;;
    *) return 1 ;;
  esac
}

# Strip surrounding quotes so length is measured on the value, not the syntax.
unquote() {
  case "$1" in
    '"'*'"'|"'"*"'") printf '%s' "${1:1:${#1}-2}" ;;
    *) printf '%s' "$1" ;;
  esac
}

echo "== Skill frontmatter"
skill_count=0
while IFS= read -r f; do
  skill_count=$((skill_count+1))
  rel="$f"
  dir=$(basename "$(dirname "$f")")

  if ! has_frontmatter "$f"; then
    err "$rel: no frontmatter block (file must start with ---)"
    continue
  fi

  name=$(fm "$f" name)
  desc=$(fm "$f" description)
  uinv=$(fm "$f" user-invocable)
  ahint=$(fm "$f" argument-hint)

  [ -n "$name" ]  || err "$rel: missing required field 'name'"
  [ -n "$name" ] && [ "$name" != "$dir" ] && \
    err "$rel: name '$name' does not match its directory '$dir'"

  if [ -z "$desc" ]; then
    err "$rel: missing required field 'description'"
  else
    is_quoted "$desc" || err "$rel: description must be quoted"
    bare=$(unquote "$desc")
    if [ "${#bare}" -gt "$MAX_DESC" ]; then
      warn "$rel: description is ${#bare} chars (house guidance: $MAX_DESC)"
    fi
  fi

  # user-invocable gates the argument-hint rules, so it must be explicit rather
  # than left to the default — otherwise invocability is an accident.
  if [ -z "$uinv" ]; then
    err "$rel: missing required field 'user-invocable' (true or false)"
  elif [ "$uinv" != "true" ] && [ "$uinv" != "false" ]; then
    err "$rel: user-invocable must be exactly 'true' or 'false', got '$uinv'"
  fi

  # argument-hint is tied to whether the skill actually consumes arguments, not
  # merely to invocability: some invocable skills legitimately take none, and
  # forcing a hint on those would document an argument that does not exist.
  uses_args=false
  grep -q 'ARGUMENTS' "$f" && uses_args=true
  if [ "$uinv" = "true" ]; then
    if [ "$uses_args" = true ] && [ -z "$ahint" ]; then
      err "$rel: consumes \$ARGUMENTS but declares no 'argument-hint'"
    elif [ "$uses_args" = false ] && [ -n "$ahint" ]; then
      # The XARI-55 drift check: a hint promising arguments the body never
      # reads means the user's input is silently discarded.
      warn "$rel: declares argument-hint $ahint but never reads \$ARGUMENTS — typed arguments are ignored"
    fi
  elif [ -n "$ahint" ]; then
    warn "$rel: declares argument-hint but is not user-invocable"
  fi

  if ! positional_exempt "$rel" && grep -qE '\$[0-9]' "$f"; then
    err "$rel: uses positional \$0/\$1 — only \$ARGUMENTS is valid (positionals populate for typed slash commands only, and leak literally when model-invoked)"
  fi
done < <(find plugins -name SKILL.md | sort)

echo "== Command frontmatter"
cmd_count=0
for f in plugins/*/commands/*.md; do
  [ -f "$f" ] || continue
  cmd_count=$((cmd_count+1))

  if ! has_frontmatter "$f"; then
    err "$f: no frontmatter block (file must start with ---)"
    continue
  fi

  desc=$(fm "$f" description)
  [ -n "$desc" ] || err "$f: missing required field 'description'"
  if [ -n "$desc" ] && [ "${#desc}" -gt "$MAX_DESC" ]; then
    warn "$f: description is ${#desc} chars (house guidance: $MAX_DESC)"
  fi

  if grep -qE '\$[0-9]' "$f"; then
    err "$f: uses positional \$0/\$1 — only \$ARGUMENTS is valid"
  fi
done

echo "-- linted $skill_count skills, $cmd_count commands ($warn_count warning(s))"
exit $fail
