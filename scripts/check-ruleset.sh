#!/usr/bin/env bash
# Compare the LIVE branch ruleset's required status checks against
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

# This script exists to be run deliberately, so a failure to read the ruleset
# is a hard error, not a skip. A silent skip here would look identical to
# "everything is in sync", which is the exact failure this guards against.
rulesets=$(gh api "repos/$REPO/rulesets" 2>&1) \
  || die "could not list rulesets for $REPO. Needs admin read on the repo — check \`gh auth status\`.
Response: $rulesets"

ids=$(printf '%s' "$rulesets" | jq -r '.[] | select(.target=="branch") | .id' 2>/dev/null)
[ -n "$ids" ] || die "no branch rulesets found on $REPO — if branch protection is configured the classic way instead, this script does not cover it"

required=""
for id in $ids; do
  detail=$(gh api "repos/$REPO/rulesets/$id" 2>&1) \
    || die "could not read ruleset $id.
Response: $detail"
  name=$(printf '%s' "$detail" | jq -r '.name')
  enforcement=$(printf '%s' "$detail" | jq -r '.enforcement')
  contexts=$(printf '%s' "$detail" | jq -r '
    .rules[]? | select(.type=="required_status_checks")
    | .parameters.required_status_checks[]?.context')

  echo "ruleset: $name (id $id, enforcement: $enforcement)"
  if [ "$enforcement" != "active" ]; then
    echo "  not active — its required checks are not enforced, and are ignored here"
    continue
  fi
  if [ -z "$contexts" ]; then
    echo "  declares no required status checks"
    continue
  fi
  printf '%s\n' "$contexts" | sed 's/^/  requires: /'
  required=$(printf '%s\n%s' "$required" "$contexts")
done

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
  echo "IN SYNC — live ruleset matches $CONTRACT."
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
