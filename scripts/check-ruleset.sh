#!/usr/bin/env bash
# Compare the required status checks LIVE on the default branch against
# .github/required-checks.txt.
#
# Deliberately NOT part of `make check`. Reading a ruleset needs admin
# permission that CI's default token does not have, and `make check` is
# documented as the exact script CI runs — a step that silently skips in CI
# would make that claim false. Run this by hand after touching branch
# protection, or when a PR shows a required check that never reports.
#
# Usage:  bash scripts/check-ruleset.sh [owner/repo]
set -uo pipefail
cd "$(dirname "$0")/.."

REPO="${1:-$(gh repo view --json nameWithOwner --jq .nameWithOwner 2>/dev/null)}"
CONTRACT=.github/required-checks.txt

die() { echo "ERROR: $*" >&2; exit 2; }

command -v gh >/dev/null || die "gh is not installed"
command -v jq >/dev/null || die "jq is not installed"
[ -n "$REPO" ] || die "could not determine the repo — pass it: $0 owner/repo"
[ -f "$CONTRACT" ] || die "$CONTRACT is missing"

# This script exists to be run deliberately, so a failure to read the rules
# is a hard error, not a skip. A silent skip here would look identical to
# "everything is in sync", which is the exact failure this guards against.
#
# It reads the rules GitHub applies to the default branch, not every ruleset
# in the repo: a ruleset can target other branches (`release/*`), and pooling
# them let one aimed elsewhere make main look protected. The endpoint returns
# only active rulesets' rules, each tagged with the ruleset it came from.
branch=$(gh api "repos/$REPO" --jq .default_branch 2>&1) \
  || die "could not read $REPO's default branch. Response: $branch"
rules=$(gh api "repos/$REPO/rules/branches/$branch" 2>&1) \
  || die "could not read the rules on $branch for $REPO. Needs read access on the repo — check \`gh auth status\`.
Response: $rules"

checks=$(printf '%s' "$rules" | jq -c '[.[] | select(.type=="required_status_checks")]') \
  || die "unexpected response for the rules on $branch: $rules"
echo "rules on $branch: $(printf '%s' "$rules" | jq -r '[.[].type] | unique | join(", ")')"
required=$(printf '%s' "$checks" | jq -r '.[].parameters.required_status_checks[]?.context')
printf '%s\n' "$required" | sed '/^$/d; s/^/  requires: /'
# Strict must hold on every rule that requires checks, not just one of them.
if printf '%s' "$checks" | jq -e 'length > 0 and all(.[]; .parameters.strict_required_status_checks_policy == true)' >/dev/null; then
  strict=true
else
  strict=false
fi

live=$(printf '%s\n' "$required" | sed '/^$/d' | sort -u)
want=$(grep -vE '^\s*(#|$)' "$CONTRACT" | sort -u)

echo
if [ -z "$live" ]; then
  echo "No active ruleset requires any status check."
  echo "Contract expects:"; printf '%s\n' "$want" | sed 's/^/  /'
  echo
  echo "MISMATCH — nothing is actually gating merges."
  exit 1
fi

if [ "$live" = "$want" ]; then
  # check-release-rule.sh compares versions against base; without "require
  # branches to be up to date" two PRs green against the same old main can
  # merge under one version.
  if [ "$strict" != true ]; then
    echo "MISMATCH — the checks are required but not strict. Turn on \"Require branches"
    echo "to be up to date before merging\"; the release check's guarantee depends on it."
    exit 1
  fi
  echo "IN SYNC — live ruleset matches $CONTRACT, strict."
  exit 0
fi

echo "MISMATCH between the live ruleset and $CONTRACT:"
diff <(printf '%s\n' "$want") <(printf '%s\n' "$live") \
  | sed 's/^</  in contract, NOT required by the ruleset (nothing gates it): /; s/^>/  required by the ruleset, NOT in contract (may never report): /'
echo
echo "A required context that no CI job produces stays 'Expected — waiting for status"
echo "to be reported' forever, blocking every PR. Reconcile the ruleset, $CONTRACT,"
echo "and ci.yml — \`make check\` covers the contract-vs-ci.yml half."
exit 1
