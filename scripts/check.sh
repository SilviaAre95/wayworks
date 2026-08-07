#!/usr/bin/env bash
# Single entry point for everything CI checks: manifest validation + harness
# shell tests. `make check` and .github/workflows/ci.yml both run this, so a
# green local run means a green CI run (same contract as ristretto-ai).
set -uo pipefail
cd "$(dirname "$0")/.."
fail=0
err() { echo "ERROR: $*" >&2; fail=1; }

echo "== JSON parses"
jq empty .claude-plugin/marketplace.json || err ".claude-plugin/marketplace.json: invalid JSON"
for f in plugins/*/.claude-plugin/plugin.json plugins/*/hooks/hooks.json; do
  [ -f "$f" ] || continue
  jq empty "$f" || err "$f: invalid JSON"
done

echo "== Marketplace entries resolve and versions are in sync"
for name in $(jq -r '.plugins[].name' .claude-plugin/marketplace.json); do
  manifest="plugins/$name/.claude-plugin/plugin.json"
  if [ ! -f "$manifest" ]; then
    err "marketplace lists '$name' but $manifest does not exist"; continue
  fi
  mv=$(jq -r --arg n "$name" '.plugins[] | select(.name==$n) | .version' .claude-plugin/marketplace.json)
  pv=$(jq -r .version "$manifest")
  pn=$(jq -r .name "$manifest")
  [ "$pn" = "$name" ] || err "$manifest: name '$pn' != marketplace entry '$name'"
  [ "$mv" = "$pv" ] || err "$manifest: version $pv != marketplace version $mv"
done
for dir in plugins/*/; do
  name=$(basename "$dir")
  jq -e --arg n "$name" '.plugins[] | select(.name==$n)' .claude-plugin/marketplace.json >/dev/null \
    || err "plugins/$name exists but is not listed in marketplace.json"
done

echo "== No redundant conventional paths in plugin manifests"
# Claude Code auto-discovers commands/, skills/, agents/, and hooks/hooks.json.
# Declaring those same paths in plugin.json makes it load them TWICE, and the
# second load is a hard error: "Duplicate hooks file detected ... The standard
# hooks/hooks.json is loaded automatically, so manifest.hooks should only
# reference additional hook files." Every wayworks plugin shipped this for
# months — the manifests were valid JSON and every path resolved, so nothing
# here caught it. Only `/plugin` in a live session showed the failure.
conventional() { # $1=value $2=dirname -> 0 if it points at the auto-discovered path
  case "$1" in
    "./$2/"|"./$2"|"$2/"|"$2") return 0 ;;
    *) return 1 ;;
  esac
}
for f in plugins/*/.claude-plugin/plugin.json; do
  [ -f "$f" ] || continue
  for key in commands skills agents; do
    v=$(jq -r --arg k "$key" '.[$k] // empty' "$f")
    [ -n "$v" ] && conventional "$v" "$key" && \
      err "$f: declares '$key: $v' — that path is auto-discovered; remove the key"
  done
  hv=$(jq -r '.hooks // empty' "$f")
  case "$hv" in
    "./hooks/hooks.json"|"hooks/hooks.json") \
      err "$f: declares 'hooks: $hv' — the standard hooks/hooks.json loads automatically; declare only ADDITIONAL hook files" ;;
  esac
done

echo "== Hook script paths resolve"
for hooks in plugins/*/hooks/hooks.json; do
  [ -f "$hooks" ] || continue
  plugin_dir=$(dirname "$(dirname "$hooks")")
  for cmd in $(jq -r '.. | .command? // empty' "$hooks"); do
    script="${cmd/\$\{CLAUDE_PLUGIN_ROOT\}/$plugin_dir}"
    [ -f "$script" ] || err "$hooks: script not found: $script"
  done
done

echo "== CI job names match the required-checks contract"
# The branch ruleset requires status contexts by exact name, but lives outside
# the repo — nothing here can see it. Renaming a CI job therefore silently
# strands a required context that never reports again. Guard the half we can
# see offline; scripts/check-ruleset.sh covers the live-ruleset half.
contract=.github/required-checks.txt
if [ ! -f "$contract" ]; then
  err "$contract is missing — the CI/ruleset contract has no source of truth"
else
  # Job display names sit at exactly four spaces under `jobs:`; step names are
  # deeper and dash-prefixed, the workflow name is at column 0.
  ci_names=$(awk '/^jobs:/{j=1;next} j && /^    name: /{sub(/^    name: /,"");print}' .github/workflows/ci.yml)
  want=$(grep -vE '^\s*(#|$)' "$contract" | sort)
  got=$(printf '%s\n' "$ci_names" | sed '/^$/d' | sort)

  # A parse that finds nothing must fail loudly. Silently comparing two empty
  # sets would report agreement forever and defeat the entire check.
  if [ -z "$got" ]; then
    err "could not parse any job names from .github/workflows/ci.yml — the guard is broken, not the workflow"
  elif [ "$want" != "$got" ]; then
    err "ci.yml job names do not match $contract"
    diff <(printf '%s\n' "$want") <(printf '%s\n' "$got") \
      | sed 's/^</  only in contract (ruleset requires it, no job produces it): /; s/^>/  only in ci.yml (job runs, ruleset ignores it): /' >&2
    echo "  Fix both this file and the branch ruleset, or the mismatch becomes a permanently pending check." >&2
  fi
fi

echo "== Skill/command frontmatter"
bash scripts/lint-skills.sh || err "frontmatter lint failed"

echo "== Frontmatter linter self-test"
bash scripts/lint-skills.test.sh || err "lint-skills.test.sh failed"

echo "== Harness shell tests"
for t in plugins/harness/test/*.test.sh; do
  echo "-- $t"
  bash "$t" || fail=1
done

if [ "$fail" -eq 0 ]; then echo "CHECK GREEN"; else echo "CHECK FAILED"; fi
exit $fail
