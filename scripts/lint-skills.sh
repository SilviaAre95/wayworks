#!/usr/bin/env bash
# Frontmatter linter for skills, agents and commands. Dependency-free (awk/grep
# only), same contract as check.sh: errors set the exit code, warnings never do.
#
# All three follow deliberately different conventions:
#   - Skills declare `name` (matching their directory) and a *quoted* description.
#   - Agents declare `name` (matching their filename) and a comma-separated
#     `tools:` list. `allowed-tools` here is silently ignored, which is the bug
#     the agent section exists to catch.
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

# Skill length. Only a CEILING is checked, and only as a warning.
#
# The house range is ~300-450, but the floor measured the wrong thing. Its
# stated purpose (create-skill, from XARI-94) is that skills stay explicit
# enough for older and local models — and what those models need is the
# structure, not more prose. Every skill under 300 here carries a full
# Steps / Output Format / Constraints set; padding them to a number would add
# exactly the "over-explained rationale" that same section calls redundant.
# So there is no floor. A structure check was tried in its place and reverted:
# matching literal `## Steps` / `## Output format` headings warned on 14 skills
# that use equally valid shapes (bug-review's Diagnose/Verify-Fix modes), which
# is more noise than the floor it replaced. Catching real under-specification
# needs something smarter than heading names.
#
# The ceiling is real: the model reads the whole skill, so a long one competes
# with itself for attention and gets partially followed. CONTRIBUTING.md
# already names the escape hatch — "anything bigger uses progressive
# disclosure (references/ files loaded on demand)" — so a skill that ships
# references/ has opted into that design and is exempt.
MAX_WORDS=450

# Accepted overruns. A standing warning nobody acts on is how the length gap
# survived unnoticed for a month, so an overrun is either fixed or recorded
# here WITH ITS REASON — never left to warn forever. Adding an entry means
# arguing the case in this comment; if you cannot, trim the skill instead.
length_accepted() {
  case "$1" in
    # 455 words, five over. Measured twice: every version under 450 lost a
    # load-bearing rule — first the marker line's mandate (leaving stood-down,
    # the one event with no URL, without a suppression key), then the "on its
    # own line" placement. Structure alone is 223 words before a rule is
    # written. See CHANGELOG marketplace 6.1.2.
    plugins/shared/skills/linear-update/SKILL.md) return 0 ;;

    # 520 words. Its templates are already external (templates/ruleset-*.json)
    # and there is no commodity block left to extract — every step is a
    # distinct API operation with a named failure mode attached: a required
    # context that no job produces blocks every PR forever, an empty
    # bypass_actors locks a solo maintainer out of merging, and ruleset must be
    # applied before settings because each depends on the one before. The 70
    # words over the ceiling are those failure modes, not explanation.
    plugins/devops/skills/repo-protection/SKILL.md) return 0 ;;

    # 513 words, of which 132 are the output format — the shape of the artifact
    # the skill exists to produce, which is specification rather than prose.
    # The remainder is a 189-word procedure and 96 words of constraints, with
    # no reference-shaped block to move out. 13% over, and the only way down is
    # to cut a rule.
    plugins/shared/skills/linear-project/SKILL.md) return 0 ;;
    *) return 1 ;;
  esac
}

# Accepted long descriptions, same contract as length_accepted.
desc_accepted() {
  case "$1" in
    # The description IS the trigger surface for a skill that must fire on
    # "add a feature", "implement X", "remove Y", "refactor Z", "change how X
    # works" and more. Shortening it buys 700 characters and loses the
    # invocations the gate exists to catch.
    plugins/feature-bank/skills/feature-bank/SKILL.md) return 0 ;;
    *) return 1 ;;
  esac
}

# Stack profiles are auto-loaded reference material, not invoked procedures:
# they carry stack opinions, deliberately have no Steps/Output/Constraints,
# and are exempt from both checks. Judging them by a procedure's shape is a
# category error, not a finding.
reference_shaped() {
  case "$1" in
    plugins/shared/skills/stack-profiles/*) return 0 ;;
    *) return 1 ;;
  esac
}

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
    if [ "${#bare}" -gt "$MAX_DESC" ] && ! desc_accepted "$rel"; then
      warn "$rel: description is ${#bare} chars (house guidance: $MAX_DESC)"
    fi
  fi

  # Length ceiling, and the structure check that replaces the old floor.
  # Counted with wc -w over the whole file, which is how AGENTS.md and every
  # CHANGELOG measurement state it — markdown table pipes count as words, and
  # that is deliberate: they are real budget a table-shaped skill spends.
  if ! reference_shaped "$rel"; then
    words=$(wc -w < "$f" | tr -d ' ')
    if [ "$words" -gt "$MAX_WORDS" ] && [ ! -d "$(dirname "$f")/references" ] && ! length_accepted "$rel"; then
      warn "$rel: $words words (house ceiling: $MAX_WORDS; use references/ for progressive disclosure)"
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

echo "== Agent frontmatter"
# Agents take `tools:` (comma-separated), NOT the skills' `allowed-tools:`.
# An `allowed-tools` key in agent frontmatter is silently ignored, so the agent
# resolves with EVERY tool available — a read-only reviewer that can write.
# Both shipped agents had this for months; nothing caught it because this
# linter only looked at skills and commands. Same class as the inert deny
# rules in 45bd58c: valid YAML, plausible key, no effect, no warning.
agent_count=0
for f in plugins/*/agents/*.md; do
  [ -f "$f" ] || continue
  agent_count=$((agent_count+1))
  base=$(basename "$f" .md)

  if ! has_frontmatter "$f"; then
    err "$f: no frontmatter block (file must start with ---)"
    continue
  fi

  name=$(fm "$f" name)
  desc=$(fm "$f" description)
  tools=$(fm "$f" tools)
  bad_tools=$(fm "$f" allowed-tools)

  [ -n "$name" ] || err "$f: missing required field 'name'"
  [ -n "$name" ] && [ "$name" != "$base" ] && \
    err "$f: name '$name' does not match its filename '$base'"
  [ -n "$desc" ] || err "$f: missing required field 'description'"

  [ -n "$bad_tools" ] && \
    err "$f: uses 'allowed-tools' — that is a SKILL/COMMAND key and is silently ignored here, so this agent gets every tool. Use comma-separated 'tools:' instead (e.g. tools: Read, Glob, Grep)"

  # `tools` is REQUIRED, not just correctly-spelled-when-present. Rejecting
  # `allowed-tools` while allowing its absence leaves the identical hole: an
  # agent with only name+description also resolves with every tool, and lints
  # clean. AGENTS.md promises "read-only reviewers with a narrow tools list";
  # this is what makes that promise enforced rather than aspirational.
  if [ -z "$tools" ] && [ -z "$bad_tools" ]; then
    err "$f: missing required field 'tools' — an agent with no tool list resolves with EVERY tool, including Write and Bash. Declare the narrow set, comma-separated (e.g. tools: Read, Glob, Grep)"
  fi

  # Whitespace inside any comma-separated element is the real failure: that
  # element parses as one bogus tool name and the tools it meant to name are
  # silently absent. Checking only values with NO comma missed
  # `tools: Read, Glob Grep`, which passed while dropping Grep.
  if [ -n "$tools" ]; then
    IFS=',' read -r -a _tool_parts <<< "$tools"
    for _t in "${_tool_parts[@]}"; do
      _t="${_t#"${_t%%[![:space:]]*}"}"; _t="${_t%"${_t##*[![:space:]]}"}"   # trim
      case "$_t" in
        *[[:space:]]*) err "$f: 'tools' entry '$_t' contains whitespace — every tool needs its own comma (got: $tools)" ;;
      esac
    done
  fi
done

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

echo "-- linted $skill_count skills, $cmd_count commands, $agent_count agents ($warn_count warning(s))"
exit $fail
