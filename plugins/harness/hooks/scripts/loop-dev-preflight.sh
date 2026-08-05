#!/usr/bin/env bash
# Arm-time preflight for /loop-dev: catch broken configuration BEFORE the build
# stage instead of at the review stage, where a bad grader name costs an entire
# implementation first.
#
# Covers only what a script can know for certain. Whether a configured grader
# resolves to an *available* skill depends on which plugins are enabled in the
# session, which no shell can see — loop-dev.md step 1 makes the agent check
# that itself. This handles the deterministic half.
#
# Exit 0 = safe to proceed (warnings may still print). Exit 1 = stop.
set -uo pipefail
DIR="${1:-$PWD}"
CFG="$DIR/.cc-dev.yaml"

fail=0
err()  { echo "BLOCK: $*" >&2; fail=1; }
warn() { echo "warn:  $*" >&2; }
ok()   { echo "ok:    $*"; }

# --- deterministic gate -----------------------------------------------------
# .cc-verify is optional, but its fallback is npm-specific. In a repo that is
# not a Node project that default fails forever: the loop can never go green,
# and it looks like a broken build rather than a missing config file.
if [ -f "$DIR/.cc-verify" ]; then
  gate=$(head -c 200 "$DIR/.cc-verify")
  [ -n "${gate// /}" ] && ok ".cc-verify: $gate" || err ".cc-verify is empty — the deterministic gate has no command to run"
elif [ -f "$DIR/package.json" ]; then
  warn "no .cc-verify — falling back to 'npm run lint && npm run build && npm test'"
else
  err "no .cc-verify and no package.json — the gate would default to npm commands this repo cannot run, and the loop could never reach green. Create .cc-verify with the real check command (e.g. 'make check')."
fi

# --- config -----------------------------------------------------------------
if [ ! -f "$CFG" ]; then
  warn "no .cc-dev.yaml — defaults apply (graders: code-review, security, bugs; base: main; open_pr: true)"
  graders="code-review, security, bugs"
  base="main"
else
  ok ".cc-dev.yaml found"
  graders=$(grep -E '^graders:' "$CFG" | head -1 | sed -E 's/^graders:[[:space:]]*//; s/[[:space:]]*#.*$//; s/^\[//; s/\]$//')
  base=$(grep -E '^base:' "$CFG" | head -1 | sed -E 's/^base:[[:space:]]*//; s/[[:space:]]*#.*$//')
  [ -n "$graders" ] || err ".cc-dev.yaml has a 'graders:' key with no value — every review stage would be skipped silently"
fi
base="${base:-main}"

# --- base ref ---------------------------------------------------------------
# The gate stamps a marker anchored on `git merge-base <base> HEAD`. A base that
# does not resolve fails at stamp time, i.e. after all the work is done.
if git -C "$DIR" rev-parse --git-dir >/dev/null 2>&1; then
  if git -C "$DIR" rev-parse --verify --quiet "$base" >/dev/null 2>&1; then
    ok "base '$base' resolves"
  elif git -C "$DIR" rev-parse --verify --quiet "origin/$base" >/dev/null 2>&1; then
    warn "base '$base' exists only as origin/$base — fetch it locally or merge-base may fail at stamp time"
  else
    err "base '$base' does not resolve here. The reviews marker is anchored on 'git merge-base $base HEAD' and would fail after the work is finished."
  fi
else
  warn "not a git repo — the marker falls back to the trust-based 'touch' escape hatch"
fi

# --- stale state from a killed run ------------------------------------------
# A marker left by a previous run is anchored to a different tree. The gate
# re-fingerprints and rejects it, but the arm step already cleared these — a
# survivor means something wrote them back.
for f in .cc-dev-reviews-passed .cc-loop-dev-rounds; do
  [ -f "$DIR/$f" ] && warn "stale $f present from an earlier run — it will be rejected on stamp"
done
if git -C "$DIR" rev-parse --git-dir >/dev/null 2>&1; then
  for f in .cc-loop-dev-active .cc-dev-reviews-passed .cc-loop-dev-state; do
    git -C "$DIR" ls-files --error-unmatch "$f" >/dev/null 2>&1 \
      && err "$f is TRACKED by git. A tracked marker invalidates its own fingerprint and livelocks the gate — untrack it and add it to .gitignore."
  done
fi

# --- PR stage ---------------------------------------------------------------
if [ ! -f "$CFG" ] || ! grep -qE '^open_pr:[[:space:]]*false' "$CFG" 2>/dev/null; then
  if ! command -v gh >/dev/null 2>&1; then
    warn "open_pr is on but 'gh' is not installed — the loop will reach green and then fail to open a PR"
  elif ! gh auth status >/dev/null 2>&1; then
    warn "open_pr is on but 'gh' is not authenticated — run 'gh auth login'"
  fi
fi

# --- hand the grader list back for the agent-side check ---------------------
echo
echo "GRADERS_TO_RESOLVE: $graders"
if [ "$fail" -eq 0 ]; then
  echo "PREFLIGHT OK — now confirm each grader above maps to a skill you actually have."
else
  echo "PREFLIGHT FAILED — fix the above before building."
fi
exit $fail
