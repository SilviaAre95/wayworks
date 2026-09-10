#!/usr/bin/env bash
# Asserts that a skill still contains its load-bearing rules.
#
# Why this exists: trimming a skill to the house ceiling has twice silently
# dropped a rule while every word-count and frontmatter check stayed green.
# linear-update lost the marker line's *mandate* and the "in the comment"
# placement, and only a four-grader panel reading the diff caught them. A word
# count cannot see that; this can.
#
# What it is NOT: an eval. It verifies that a rule's text survived, not that a
# model still behaves correctly. `claude plugin eval --ablation with-without`
# is the real measurement and supersedes this when available; the manifests
# here become its grader criteria rather than being thrown away.
#
# Manifest format — scripts/skill-rules/<plugin>__<skill>.rules
#   # comments and blank lines are ignored
#   <what the rule is, in words> :: <extended regex that must match SKILL.md>
# The description is what a failure prints, so write it for whoever broke it.
set -uo pipefail
cd "${RULES_ROOT:-$(dirname "$0")/..}"

fail=0
err() { echo "ERROR: $*" >&2; fail=1; }

shopt -s nullglob
manifests=(scripts/skill-rules/*.rules)
if [ ${#manifests[@]} -eq 0 ]; then
  echo "-- no skill-rule manifests"
  exit 0
fi

checked=0
rules_total=0
for m in "${manifests[@]}"; do
  base=$(basename "$m" .rules)
  case "$base" in
    *__*) plugin="${base%%__*}"; skill="${base#*__}" ;;
    *) err "$m: filename must be <plugin>__<skill>.rules"; continue ;;
  esac
  target="plugins/$plugin/skills/$skill/SKILL.md"
  if [ ! -f "$target" ]; then
    err "$m: names $target, which does not exist"
    continue
  fi

  # A manifest that asserts nothing passes everything — the exact failure this
  # script exists to prevent, so it is an error rather than a quiet success.
  n=0
  while IFS= read -r line; do
    case "$line" in ''|'#'*) continue ;; esac
    [[ "$line" == *"::"* ]] || { err "$m: no '::' separator in: $line"; continue; }
    desc="${line%%::*}"; pat="${line#*::}"
    # trim surrounding whitespace
    desc="${desc#"${desc%%[![:space:]]*}"}"; desc="${desc%"${desc##*[![:space:]]}"}"
    pat="${pat#"${pat%%[![:space:]]*}"}";  pat="${pat%"${pat##*[![:space:]]}"}"
    [ -n "$pat" ] || { err "$m: empty pattern for rule: $desc"; continue; }
    n=$((n+1))
    grep -qE -- "$pat" "$target" || err "$target: lost rule — $desc"
  done < "$m"

  [ "$n" -eq 0 ] && err "$m: contains no rules; an empty manifest asserts nothing"
  checked=$((checked+1))
  rules_total=$((rules_total+n))
done

echo "-- checked $checked skill(s), $rules_total rule(s)"
exit $fail
