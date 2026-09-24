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
DIR="$PWD"; PLAN=""
while [ $# -gt 0 ]; do
  case "$1" in
    --plan)
      [ $# -ge 2 ] && [ -n "$2" ] || { echo "BLOCK: --plan needs a path" >&2; echo "PREFLIGHT FAILED — fix the above before building."; exit 1; }
      PLAN="$2"; shift 2 ;;
    *) DIR="$1"; shift ;;
  esac
done
DESIGN_CHECK="$(cd "$(dirname "$0")/../.." && pwd)/scripts/design-check.sh"
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
  base=$(grep -E '^base:' "$CFG" | head -1 | sed -E 's/^base:[[:space:]]*//; s/[[:space:]]*#.*$//')
  # An ABSENT graders key means the defaults (a config written only to set
  # require_design has none). A PRESENT key with no value is the trap: every
  # review stage would be skipped silently.
  if grep -qE '^graders:' "$CFG"; then
    graders=$(grep -E '^graders:' "$CFG" | head -1 | sed -E 's/^graders:[[:space:]]*//; s/[[:space:]]*#.*$//; s/^\[//; s/\]$//')
    [ -n "$graders" ] || err ".cc-dev.yaml has a 'graders:' key with no value — every review stage would be skipped silently"
  else
    graders="code-review, security, bugs"
  fi
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

# --- design gate ------------------------------------------------------------
# A --plan inside docs/designs/ came from /harness:shape, so its design must be
# locked and pass design-check before anything is built — in every mode. The
# mode only decides what happens WITHOUT such a plan: never = nothing,
# always = block, features = the agent classifies the task (a shell cannot tell
# a feature from a fix) and logs the call in the PR body. An absent key is
# `never` so an upgrade does not start blocking existing repos.
require_design=never
if [ -f "$CFG" ]; then
  v=$(grep -E '^require_design:' "$CFG" | head -1 | sed -E 's/^require_design:[[:space:]]*//; s/[[:space:]]*#.*$//')
  [ -n "$v" ] && require_design="$v"
fi
case "$require_design" in
  never|features|always) ;;
  *) err "require_design '$require_design' is not never|features|always"; require_design=never ;;
esac
# Prints the physical path of $1 with every symlink along it followed to its
# final target (bash 3.2 / macOS has no `readlink -f`). Empty on failure: a
# dangling or looping link does not resolve.
resolve_path() {
  local p="$1" t d i=0
  while [ -L "$p" ]; do
    i=$((i + 1)); [ "$i" -gt 40 ] && return 1
    t=$(readlink "$p") || return 1
    case "$t" in /*) p="$t" ;; *) p="$(dirname "$p")/$t" ;; esac
  done
  d=$(cd -P "$(dirname "$p")" 2>/dev/null && pwd -P) || return 1
  printf '%s/%s\n' "$d" "$(basename "$p")"
}
# The --plan path is resolved to a real (symlink-free) path BEFORE anything is
# matched against it: `docs/./designs/` and `docs//designs/` name the same
# directory as `docs/designs/`, and a lexical match on the raw string missed
# both — skipping the design gate for a draft design. Containment is about
# designs: a relative --plan can walk out of the repo with `../` and an
# absolute one can point into a different repo, so an out-of-repo path under a
# docs/designs/ directory — another repo's design — blocks in every mode. Any
# other out-of-repo path (Claude Code's plan mode writes ~/.claude/plans/*.md)
# is an ordinary plan, subject to require_design like an in-repo one.
design_dir=""
if [ -n "$PLAN" ]; then
  case "$PLAN" in /*) plan_path="$PLAN" ;; *) plan_path="$DIR/$PLAN" ;; esac
  plan_dir_real=$(cd "$(dirname "$plan_path")" 2>/dev/null && pwd -P)
  repo_real=$(cd "$DIR" 2>/dev/null && pwd -P)
  if [ -z "$plan_dir_real" ] || [ -z "$repo_real" ]; then
    err "--plan does not resolve to an existing directory: $PLAN"
  else
    plan_real="$plan_dir_real/$(basename "$plan_path")"
    plan_target=$(resolve_path "$plan_path")
    case "$plan_real" in
      "$repo_real/"*)
        case "$plan_real" in "$repo_real/docs/designs/"*/*) design_dir="$plan_dir_real" ;; esac ;;
    esac
    # A plan that is, or links to, another repo's design blocks.
    for p in "$plan_real" "$plan_target"; do
      case "$p" in
        "$repo_real/"*) ;;
        */docs/designs/*) err "--plan is outside this repo: $PLAN"; break ;;
      esac
    done
  fi
fi
# Prints the frontmatter status of a design.md read on stdin.
fm_status() {
  awk 'NR==1 && $0!="---"{exit} NR>1 && $0=="---"{exit} NR>1{print}' \
    | sed -nE 's/^status:[[:space:]]*([A-Za-z]+).*/\1/p' | head -1
}
if [ -n "$design_dir" ]; then
  # Containment above resolved the design's directory; design.md itself can
  # still be a symlink to a design this repo never shaped. A missing design.md
  # is left to design-check, which blocks on it.
  design_md_out=""
  if [ -e "$design_dir/design.md" ] || [ -L "$design_dir/design.md" ]; then
    design_md_real=$(resolve_path "$design_dir/design.md")
    case "$design_md_real" in
      "$repo_real/"*) ;;
      *) design_md_out="${design_md_real:-<unresolvable link>}" ;;
    esac
  fi
  # design-check vouches for plan.md; any other file in the folder is a plan
  # nobody checked, built under the design's name.
  if [ "$(basename "$plan_real")" != "plan.md" ]; then
    err "--plan must be the design's plan.md, not $(basename "$plan_real")"
  elif [ -n "$design_md_out" ]; then
    err "design.md resolves outside this repo: $design_md_out"
  elif [ ! -f "$DESIGN_CHECK" ]; then
    err "design-check.sh not found at $DESIGN_CHECK — the harness install is incomplete"
  else
    # loop-dev's postflight flips design.md to `status: shipped` and commits
    # it with the fold on the feature branch (loop-dev.md step 7). Re-running
    # loop-dev with the same --plan — the caller must converge to ONE PR —
    # would otherwise BLOCK forever under --require-locked, since shipped !=
    # locked. It counts as "already folded here" only when ALL hold:
    #   - the COMMITTED design at HEAD is shipped, and the working tree matches
    #     it (an uncommitted flip is not a fold, and a shipped design does not
    #     change afterwards);
    #   - some committed version was locked — the merge-base version or one of
    #     this branch's commits touching it (committed straight as shipped
    #     means it skipped locking, and so skipped the design gate);
    #   - HEAD's version differs from the merge-base: `git diff --quiet` exits
    #     1 for that, 0 for no diff, and >1 on error. Only rc=1 counts — the
    #     first version read any non-zero as "differs", so every error was a
    #     fold, fail-open. A design already shipped when this branch forked is
    #     a different design as far as this branch is concerned.
    # Anything else falls through to --require-locked, which blocks.
    already_folded=0
    design_file="$design_dir/design.md"
    top=$(git -C "$DIR" rev-parse --show-toplevel 2>/dev/null) && top=$(cd "$top" && pwd -P) || top=""
    if [ -f "$design_file" ] && [ -n "$top" ]; then
      rel="${design_file#"$top"/}"
      mb=$(git -C "$top" merge-base "$base" HEAD 2>/dev/null) || mb=""
      if [ -n "$mb" ] \
         && [ "$(fm_status < "$design_file")" = "shipped" ] \
         && [ "$(git -C "$top" show "HEAD:$rel" 2>/dev/null | fm_status)" = "shipped" ] \
         && git -C "$top" diff --quiet HEAD -- "$rel" 2>/dev/null; then
        ever_locked=0
        [ "$(git -C "$top" show "$mb:$rel" 2>/dev/null | fm_status)" = "locked" ] && ever_locked=1
        if [ "$ever_locked" -eq 0 ]; then
          for c in $(git -C "$top" rev-list "$mb..HEAD" -- "$rel" 2>/dev/null); do
            [ "$(git -C "$top" show "$c:$rel" 2>/dev/null | fm_status)" = "locked" ] && { ever_locked=1; break; }
          done
        fi
        if [ "$ever_locked" -eq 1 ]; then
          git -C "$top" diff --quiet "$mb" HEAD -- "$rel" 2>/dev/null; dr=$?
          [ "$dr" -eq 1 ] && already_folded=1
        fi
      fi
    fi
    if [ "$already_folded" -eq 1 ]; then
      if dc=$(bash "$DESIGN_CHECK" "$design_dir" 2>&1); then
        ok "design $(basename "$design_dir") already shipped on this branch — design-check passes without --require-locked"
        echo "DESIGN_ALREADY_FOLDED: $(basename "$design_dir")"
      else
        while IFS= read -r l; do err "design: ${l#BLOCK: }"; done < <(printf '%s\n' "$dc" | grep '^BLOCK:')
        err "design $(basename "$design_dir") failed design-check even though already shipped on this branch"
      fi
    elif dc=$(bash "$DESIGN_CHECK" "$design_dir" --require-locked 2>&1); then
      ok "design $(basename "$design_dir") is locked and passes design-check"
    else
      while IFS= read -r l; do err "design: ${l#BLOCK: }"; done < <(printf '%s\n' "$dc" | grep '^BLOCK:')
      err "design $(basename "$design_dir") is not ready — finish it with /harness:shape $(basename "$design_dir")"
    fi
  fi
elif [ "$require_design" = "always" ]; then
  err "require_design: always, but --plan does not point at a design in docs/designs/ — run /harness:shape first"
fi
echo "REQUIRE_DESIGN: $require_design"

# --- hand the grader list back for the agent-side check ---------------------
# The script cannot see which plugins are enabled, but it does know which
# plugin each grader needs. Naming it turns "grader `bugs` did not resolve"
# into something the user can act on without going to read loop-dev.md.
echo
echo "GRADERS_TO_RESOLVE:"
for g in $(printf '%s' "$graders" | tr ',' ' '); do
  case "$g" in
    code-review) echo "  $g -> /code-review (bundled with Claude Code; no plugin)" ;;
    security)    echo "  $g -> security:code-audit    (needs security@wayworks)" ;;
    bugs)        echo "  $g -> qa:bug-review          (needs qa@wayworks)" ;;
    design)      echo "  $g -> design:layout-review   (needs design@wayworks)" ;;
    security-review) echo "  $g -> /security-review      (bundled with Claude Code; no plugin)" ;;
    simplify)    err "grader '$g' applies its own fixes — a grader must be read-only, because the panel runs concurrently and self-applied edits land inside the reviews marker with no grader having read them. Remove it from .cc-dev.yaml and run it after the loop closes." ;;
    *)           echo "  $g -> skill named '$g'       (needs whichever plugin provides it)" ;;
  esac
done

if [ "$fail" -eq 0 ]; then
  echo "PREFLIGHT OK — now confirm each skill above is available in this session."
  echo "  Invoke one to check; do not infer from .claude/settings.json. Enabling a"
  echo "  plugin there is a no-op if it was never INSTALLED for this project, and"
  echo "  that failure is silent — the cache directory may exist from another repo."
  echo "  Fix with: /plugin install <name>@<marketplace>"
else
  echo "PREFLIGHT FAILED — fix the above before building."
fi
exit $fail
