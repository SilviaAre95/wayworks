#!/usr/bin/env bash
# Tests for loop-dev-preflight.sh. Each blocking condition must actually block,
# and each legitimate setup must actually pass — a preflight that always exits 0
# is worse than none, because it reads as confirmation.
set -uo pipefail
SCRIPT=$(cd "$(dirname "$0")/../hooks/scripts" && pwd)/loop-dev-preflight.sh
fail=0
ok()  { echo "ok   - $*"; }
bad() { echo "FAIL - $*"; fail=1; }

TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT

# Fresh git repo with a main branch, so base resolution succeeds by default.
newrepo() {
  d="$TMP/$1"; rm -rf "$d"; mkdir -p "$d"
  git -C "$d" init -q -b main
  git -C "$d" -c user.email=t@t -c user.name=t commit -q --allow-empty -m init
  echo "$d"
}
run() { OUT=$(bash "$SCRIPT" "$@" 2>&1); RC=$?; }

# --- happy path -------------------------------------------------------------
d=$(newrepo happy)
echo "make check" > "$d/.cc-verify"
printf 'graders: [code-review, security, bugs]\nbase: main\n' > "$d/.cc-dev.yaml"
run "$d"
[ "$RC" = "0" ] && ok "valid config passes" || bad "valid config passes (rc=$RC: $OUT)"

# grader list is handed back for the agent-side availability check, naming the
# plugin each one needs — "bugs did not resolve" is not actionable on its own.
run "$d"
{ echo "$OUT" | grep -q "bugs -> qa:bug-review" \
  && echo "$OUT" | grep -q "needs qa@wayworks" \
  && echo "$OUT" | grep -q "security -> security:code-audit" \
  && echo "$OUT" | grep -q "code-review -> /code-review"; } \
  && ok "emits grader -> skill -> plugin mapping" || bad "emits mapping (got: $OUT)"

# an unrecognised grader still reports, without inventing a plugin name
d=$(newrepo custom)
echo "make check" > "$d/.cc-verify"
printf 'graders: [custom-thing]\nbase: main\n' > "$d/.cc-dev.yaml"
run "$d"
echo "$OUT" | grep -q "custom-thing -> skill named 'custom-thing'" \
  && ok "unknown grader maps to a same-named skill" || bad "unknown grader mapping (got: $OUT)"

# --- the npm-default trap ---------------------------------------------------
d=$(newrepo nonode)
printf 'graders: [code-review]\nbase: main\n' > "$d/.cc-dev.yaml"
run "$d"   # no .cc-verify, no package.json
{ [ "$RC" = "1" ] && echo "$OUT" | grep -q "npm commands this repo cannot run"; } \
  && ok "no .cc-verify in a non-Node repo blocks" || bad "no .cc-verify in a non-Node repo blocks (rc=$RC)"

# a Node repo may legitimately rely on the default
d=$(newrepo node)
echo '{}' > "$d/package.json"
printf 'base: main\ngraders: [code-review]\n' > "$d/.cc-dev.yaml"
run "$d"
{ [ "$RC" = "0" ] && echo "$OUT" | grep -q "falling back to"; } \
  && ok "Node repo without .cc-verify warns but passes" || bad "Node repo without .cc-verify warns but passes (rc=$RC)"

# --- empty gate -------------------------------------------------------------
d=$(newrepo emptygate)
: > "$d/.cc-verify"
run "$d"
[ "$RC" = "1" ] && ok "empty .cc-verify blocks" || bad "empty .cc-verify blocks"

# --- unresolvable base ------------------------------------------------------
d=$(newrepo badbase)
echo "make check" > "$d/.cc-verify"
printf 'graders: [code-review]\nbase: nope-not-a-branch\n' > "$d/.cc-dev.yaml"
run "$d"
{ [ "$RC" = "1" ] && echo "$OUT" | grep -q "does not resolve"; } \
  && ok "unresolvable base blocks" || bad "unresolvable base blocks (rc=$RC)"

# --- graders key present but empty ------------------------------------------
d=$(newrepo nograders)
echo "make check" > "$d/.cc-verify"
printf 'graders:\nbase: main\n' > "$d/.cc-dev.yaml"
run "$d"
{ [ "$RC" = "1" ] && echo "$OUT" | grep -q "no value"; } \
  && ok "empty graders list blocks" || bad "empty graders list blocks (rc=$RC)"

# --- config without a graders key uses the defaults ---------------------------
# Only a PRESENT key with no value is the silent-skip trap above. A .cc-dev.yaml
# written just to set require_design (harness-init does exactly that) has no
# graders key at all, and must fall back to the documented defaults.
d=$(newrepo nograderskey)
echo "make check" > "$d/.cc-verify"
printf 'require_design: features\n' > "$d/.cc-dev.yaml"
run "$d"
{ [ "$RC" = "0" ] \
  && echo "$OUT" | grep -q "code-review -> /code-review" \
  && echo "$OUT" | grep -q "security -> security:code-audit" \
  && echo "$OUT" | grep -q "bugs -> qa:bug-review"; } \
  && ok "config with no graders key uses the default graders" || bad "no graders key uses defaults (rc=$RC: $OUT)"

# --- tracked loop state (livelocks the gate) --------------------------------
d=$(newrepo tracked)
echo "make check" > "$d/.cc-verify"
printf 'graders: [code-review]\nbase: main\n' > "$d/.cc-dev.yaml"
touch "$d/.cc-loop-dev-active"
git -C "$d" add -f .cc-loop-dev-active
git -C "$d" -c user.email=t@t -c user.name=t commit -q -m "oops"
run "$d"
{ [ "$RC" = "1" ] && echo "$OUT" | grep -q "TRACKED by git"; } \
  && ok "tracked loop-state file blocks" || bad "tracked loop-state file blocks (rc=$RC)"

# --- missing config falls back to documented defaults -----------------------
d=$(newrepo nocfg)
echo "make check" > "$d/.cc-verify"
run "$d"
{ [ "$RC" = "0" ] \
  && echo "$OUT" | grep -q "code-review -> /code-review" \
  && echo "$OUT" | grep -q "security -> security:code-audit" \
  && echo "$OUT" | grep -q "bugs -> qa:bug-review"; } \
  && ok "absent .cc-dev.yaml uses documented defaults" || bad "absent .cc-dev.yaml uses defaults (rc=$RC)"

# --- stale marker warns, does not block -------------------------------------
d=$(newrepo stale)
echo "make check" > "$d/.cc-verify"
printf 'graders: [code-review]\nbase: main\n' > "$d/.cc-dev.yaml"
touch "$d/.cc-dev-reviews-passed"
run "$d"
{ [ "$RC" = "0" ] && echo "$OUT" | grep -q "stale .cc-dev-reviews-passed"; } \
  && ok "stale marker warns without blocking" || bad "stale marker warns without blocking (rc=$RC)"

# --- bundled graders resolve without a plugin -------------------------------
# The graders list accepts Claude Code's bundled skills. Before 1.10.1 the case
# block had no arm for them, so `security-review` fell through to "needs
# whichever plugin provides it" and loop-dev step 1 sent the agent hunting for a
# plugin that cannot exist — or halting the loop before it built anything.
d=$(newrepo bundled)
echo "make check" > "$d/.cc-verify"
printf 'graders: [code-review, security, security-review, bugs]\nbase: main\n' > "$d/.cc-dev.yaml"
run "$d"
{ [ "$RC" = "0" ] && echo "$OUT" | grep -q "security-review -> /security-review"; } \
  && ok "bundled security-review resolves without a plugin" \
  || bad "bundled security-review resolves without a plugin (rc=$RC: $OUT)"
echo "$OUT" | grep -q "security-review.*needs whichever plugin" \
  && bad "security-review must not fall through to the unknown-grader arm" \
  || ok "security-review does not fall through to the unknown-grader arm"

# --- a mutating grader is refused ------------------------------------------
# /simplify's contract is "review ... then apply the fixes". Graders run
# concurrently and their edits are not findings the parent fixed, so a mutating
# grader edits the tree mid-review and lands inside the marker fingerprint with
# no grader having read it.
d=$(newrepo mutating)
echo "make check" > "$d/.cc-verify"
printf 'graders: [code-review, simplify]\nbase: main\n' > "$d/.cc-dev.yaml"
run "$d"
# Assert the EXIT CODE, not just the message. The first version of this test
# grepped only for the string, which is exactly why the guard shipped calling
# `echo` instead of `err`: it printed BLOCK, then printed PREFLIGHT OK, and
# exited 0. This file's own header says a preflight that always exits 0 is
# worse than none, because it reads as confirmation.
{ [ "$RC" = "1" ] && echo "$OUT" | grep -q "applies its own fixes"; } \
  && ok "mutating grader (simplify) blocks with exit 1" \
  || bad "mutating grader (simplify) blocks with exit 1 (rc=$RC: $OUT)"
echo "$OUT" | grep -q "PREFLIGHT OK" \
  && bad "a blocked preflight must not also print PREFLIGHT OK" \
  || ok "a blocked preflight does not also print PREFLIGHT OK"

# --- require_design ---------------------------------------------------------
# The design gate is what lets loop-dev run unsupervised: a --plan inside
# docs/designs/ must point at a locked design that passes design-check, in every
# mode. `always` also refuses a task with no design plan at all. An ABSENT key
# means `never`, so existing installs are not blocked by an upgrade.
mkdesign() { # $1=repo $2=status
  dd="$1/docs/designs/offline-stamp"; mkdir -p "$dd"
  printf -- '---\nslug: offline-stamp\nstatus: %s\nstage: lock\n---\n## Decisions\n- [x] W1 · high · offline scan queues · decided-by: you\n' "$2" > "$dd/design.md"
  printf '### Task 1: queue (W1)\n' > "$dd/plan.md"
}
cfg() { echo "make check" > "$1/.cc-verify"; printf 'graders: [code-review]\nbase: main\n%s\n' "$2" > "$1/.cc-dev.yaml"; }
PLANREL=docs/designs/offline-stamp/plan.md

d=$(newrepo rd-absent); cfg "$d" ""; run "$d"
{ [ "$RC" = "0" ] && grep -q "REQUIRE_DESIGN: never" <<<"$OUT"; } \
  && ok "absent require_design means never" || bad "absent key (rc=$RC: $OUT)"

d=$(newrepo rd-always-noplan); cfg "$d" "require_design: always"; run "$d"
{ [ "$RC" = "1" ] && grep -q "/harness:shape" <<<"$OUT"; } \
  && ok "always without a design plan blocks" || bad "always without plan (rc=$RC: $OUT)"

d=$(newrepo rd-always-locked); cfg "$d" "require_design: always"; mkdesign "$d" locked; run "$d" --plan "$PLANREL"
{ [ "$RC" = "0" ] && grep -q "passes design-check" <<<"$OUT"; } \
  && ok "always with a locked design passes (relative --plan resolves against dir)" || bad "always+locked (rc=$RC: $OUT)"

d=$(newrepo rd-always-other); cfg "$d" "require_design: always"; run "$d" --plan docs/superpowers/plans/x.md
[ "$RC" = "1" ] && ok "always with a plan outside docs/designs blocks" || bad "always+other plan (rc=$RC: $OUT)"

d=$(newrepo rd-features); cfg "$d" "require_design: features"; run "$d"
{ [ "$RC" = "0" ] && grep -q "REQUIRE_DESIGN: features" <<<"$OUT"; } \
  && ok "features hands classification to the agent without blocking" || bad "features (rc=$RC: $OUT)"

d=$(newrepo rd-never-draft); cfg "$d" "require_design: never"; mkdesign "$d" draft; run "$d" --plan "$PLANREL"
{ [ "$RC" = "1" ] && grep -q "not locked" <<<"$OUT"; } \
  && ok "a draft design blocks even under never" || bad "never+draft (rc=$RC: $OUT)"
grep -q "PREFLIGHT OK" <<<"$OUT" && bad "blocked design must not print PREFLIGHT OK" || ok "blocked design does not print PREFLIGHT OK"

d=$(newrepo rd-bad); cfg "$d" "require_design: sometimes"; run "$d"
[ "$RC" = "1" ] && ok "invalid require_design value blocks" || bad "invalid mode (rc=$RC: $OUT)"

d=$(newrepo rd-noval); cfg "$d" ""; run "$d" --plan
[ "$RC" = "1" ] && ok "--plan without a path blocks" || bad "--plan no value (rc=$RC: $OUT)"

# --- shipped-on-this-branch: the postflight fold must not self-block ---------
# loop-dev's postflight flips design.md to `status: shipped` and commits it on
# the feature branch. Re-running loop-dev with the same --plan (supported: PRs
# must converge to ONE) would otherwise BLOCK forever under --require-locked,
# since shipped != locked. When the flip happened ON THIS BRANCH (design.md
# differs from `git merge-base <base> HEAD`), design-check runs WITHOUT
# --require-locked instead (still validates every decision line) and the script
# prints DESIGN_ALREADY_FOLDED so loop-dev step 7 knows to skip the fold again.
d=$(newrepo rd-folded-branch)
cfg "$d" "require_design: always"
mkdesign "$d" locked
git -C "$d" add -A
git -C "$d" -c user.email=t@t -c user.name=t commit -q -m "design locked"
git -C "$d" checkout -q -b feature
sed -i.bak 's/status: locked/status: shipped/' "$d/docs/designs/offline-stamp/design.md"
rm -f "$d/docs/designs/offline-stamp/design.md.bak"
git -C "$d" add -A
git -C "$d" -c user.email=t@t -c user.name=t commit -q -m "ship design"
run "$d" --plan "$PLANREL"
{ [ "$RC" = "0" ] && grep -q "DESIGN_ALREADY_FOLDED: offline-stamp" <<<"$OUT"; } \
  && ok "(e) locked on main, shipped on this branch: rc 0 + DESIGN_ALREADY_FOLDED" \
  || bad "design shipped on this branch (rc=$RC: $OUT)"

# A design already shipped ON BASE (no diff introduced by this branch) is a
# different case: the fold did not happen here, so it still blocks — shipped
# is not locked.
d=$(newrepo rd-shipped-on-base)
cfg "$d" "require_design: always"
mkdesign "$d" shipped
git -C "$d" add -A
git -C "$d" -c user.email=t@t -c user.name=t commit -q -m "design shipped on main"
git -C "$d" checkout -q -b feature2
run "$d" --plan "$PLANREL"
{ [ "$RC" = "1" ] && ! grep -q "DESIGN_ALREADY_FOLDED" <<<"$OUT"; } \
  && ok "design already shipped on base still blocks" \
  || bad "design already shipped on base still blocks (rc=$RC: $OUT)"

# --- containment: a design plan must resolve inside this repo ----------------
# A relative --plan can walk out of the repo with `../`, and an absolute
# --plan can point straight into a different repo's docs/designs/ entirely.
# Either is another repo's design passing as this one's, so an out-of-repo
# --plan under a docs/designs/ directory blocks.
# Before this fix, `! git -C "$DIR" diff --quiet "$mb" -- "$design_file"`
# treated ANY non-zero exit (including git's own error exit, typically 128,
# for a path outside the repo) as "differs" -> already_folded=1 -> fail-open:
# an out-of-repo shipped design would print DESIGN_ALREADY_FOLDED and pass.
mkdesign_at() { # $1=absolute target dir $2=status
  mkdir -p "$1"
  printf -- '---\nslug: offline-stamp\nstatus: %s\nstage: lock\n---\n## Decisions\n- [x] W1 · high · offline scan queues · decided-by: you\n' "$2" > "$1/design.md"
  printf '### Task 1: queue (W1)\n' > "$1/plan.md"
}

# (c) relative --plan escaping the repo via `../`, status shipped — the exact
# fail-open shape reported: reproduces the "outside the repo, status shipped"
# case via a relative path.
d=$(newrepo rd-outside-rel)
other=$(newrepo rd-outside-rel-external)
mkdesign_at "$other/docs/designs/offline-stamp" shipped
cfg "$d" "require_design: always"
run "$d" --plan "../$(basename "$other")/docs/designs/offline-stamp/plan.md"
{ [ "$RC" = "1" ] && ! grep -q "DESIGN_ALREADY_FOLDED" <<<"$OUT" && grep -q "outside this repo" <<<"$OUT"; } \
  && ok "relative --plan escaping the repo (../) blocks as outside this repo" \
  || bad "relative --plan escaping the repo (rc=$RC: $OUT)"

# (d) absolute --plan into a second repo, status LOCKED (not shipped) — this
# one never touches the shipped/diff-exit-code path at all, so it only ever
# blocks via containment. It shows containment is load-bearing on its own,
# not just a second guard on the same shipped-fold bug: a foreign design that
# is genuinely, validly locked must still not be treated as this repo's.
d=$(newrepo rd-outside-abs)
other2=$(newrepo rd-outside-abs-external)
mkdesign_at "$other2/docs/designs/offline-stamp" locked
cfg "$d" "require_design: always"
run "$d" --plan "$other2/docs/designs/offline-stamp/plan.md"
{ [ "$RC" = "1" ] && ! grep -q "DESIGN_ALREADY_FOLDED" <<<"$OUT" && grep -q "outside this repo" <<<"$OUT"; } \
  && ok "absolute --plan into a second repo blocks (even when validly locked there)" \
  || bad "absolute --plan into a second repo (rc=$RC: $OUT)"

# Any OTHER out-of-repo --plan is an ordinary plan: Claude Code's plan mode
# writes to ~/.claude/plans/, and blocking every out-of-repo path refused it.
# It gets require_design's ordinary-plan treatment, like an in-repo one.
P="$TMP/home/.claude/plans"; mkdir -p "$P"; printf '### Task 1: fix the thing\n' > "$P/fix-thing.md"
for mode in never features; do
  d=$(newrepo "rd-planmode-$mode"); cfg "$d" "require_design: $mode"
  run "$d" --plan "$P/fix-thing.md"
  { [ "$RC" = "0" ] && grep -q "REQUIRE_DESIGN: $mode" <<<"$OUT" && ! grep -q "outside this repo" <<<"$OUT"; } \
    && ok "$mode: a plan-mode plan outside the repo passes as an ordinary plan" \
    || bad "$mode: out-of-repo ordinary plan (rc=$RC: $OUT)"
done
d=$(newrepo rd-planmode-always); cfg "$d" "require_design: always"
run "$d" --plan "$P/fix-thing.md"
{ [ "$RC" = "1" ] && grep -q "does not point at a design" <<<"$OUT"; } \
  && ok "always: a plan-mode plan outside the repo blocks for lack of a design" \
  || bad "always: out-of-repo ordinary plan (rc=$RC: $OUT)"

# Symlinks are followed to their end first: a plan-mode path that links into
# another repo's docs/designs/ is still that repo's design.
ln -s "$other2/docs/designs/offline-stamp/plan.md" "$P/linked-design.md"
d=$(newrepo rd-planmode-link); cfg "$d" "require_design: never"
run "$d" --plan "$P/linked-design.md"
{ [ "$RC" = "1" ] && grep -q "outside this repo" <<<"$OUT"; } \
  && ok "an out-of-repo plan symlinked to another repo's design blocks" \
  || bad "out-of-repo plan linked to a foreign design (rc=$RC: $OUT)"

# --- a design plan may not be a symlink --------------------------------------
# loop-dev.md takes <slug> from the --plan as given, the preflight gates the
# file it resolves to. Whenever either side is under docs/designs/ they must be
# the same file, or the loop folds and ships a design nobody gated.
NOSYM="design plan must be passed by its real path, not a symlink"
d=$(newrepo rd-planmode-ownlink); cfg "$d" "require_design: never"; mkdesign "$d" draft
ln -s "$d/$PLANREL" "$P/own-design.md"
run "$d" --plan "$P/own-design.md"
{ [ "$RC" = "1" ] && grep -q "$NOSYM" <<<"$OUT"; } \
  && ok "an out-of-repo link into this repo's docs/designs blocks" \
  || bad "out-of-repo link to own draft design (rc=$RC: $OUT)"
d=$(newrepo rd-planmode-ownlink-locked); cfg "$d" "require_design: always"; mkdesign "$d" locked
ln -s "$d/$PLANREL" "$P/own-locked.md"
run "$d" --plan "$P/own-locked.md"
{ [ "$RC" = "1" ] && grep -q "$NOSYM" <<<"$OUT"; } \
  && ok "an out-of-repo link to this repo's LOCKED design blocks too" \
  || bad "out-of-repo link to own locked design (rc=$RC: $OUT)"
d=$(newrepo rd-inrepo-ownlink); cfg "$d" "require_design: never"; mkdesign "$d" draft
mkdir -p "$d/docs/plans"; ln -s ../designs/offline-stamp/plan.md "$d/docs/plans/x.md"
run "$d" --plan docs/plans/x.md
{ [ "$RC" = "1" ] && grep -q "$NOSYM" <<<"$OUT"; } \
  && ok "an in-repo link to a design's plan.md blocks" \
  || bad "in-repo link to own draft design (rc=$RC: $OUT)"
# I-2: docs/designs/a/plan.md -> docs/designs/b/plan.md, a draft, b locked.
d=$(newrepo rd-crosslink); cfg "$d" "require_design: never"; mkdesign "$d" locked
mkdesign_at "$d/docs/designs/a" draft; rm "$d/docs/designs/a/plan.md"
ln -s ../offline-stamp/plan.md "$d/docs/designs/a/plan.md"
run "$d" --plan docs/designs/a/plan.md
{ [ "$RC" = "1" ] && grep -q "$NOSYM" <<<"$OUT"; } \
  && ok "a design's plan.md linked to another design's plan.md blocks" \
  || bad "cross-linked design plans (rc=$RC: $OUT)"
# The same through a directory link: docs/designs/a -> offline-stamp.
d=$(newrepo rd-dirlink); cfg "$d" "require_design: never"; mkdesign "$d" locked
ln -s offline-stamp "$d/docs/designs/a"
run "$d" --plan docs/designs/a/plan.md
{ [ "$RC" = "1" ] && grep -q "$NOSYM" <<<"$OUT"; } \
  && ok "a design folder that is a directory link blocks" \
  || bad "directory-linked design folder (rc=$RC: $OUT)"
# A trailing slash made lstat follow the link, so it skipped resolution.
d=$(newrepo rd-trailing-slash); cfg "$d" "require_design: never"; mkdesign "$d" draft
run "$d" --plan "$P/own-design.md/"
{ [ "$RC" = "1" ] && grep -q "must name a file" <<<"$OUT"; } \
  && ok "a --plan ending in / blocks" || bad "trailing slash (rc=$RC: $OUT)"

# --- design.md itself must resolve inside the repo ----------------------------
# Containment resolved the design's DIRECTORY, so an in-repo design folder whose
# design.md is a symlink to a foreign, validly locked design passed the gate
# with a design this repo never shaped.
d=$(newrepo rd-design-symlink); cfg "$d" "require_design: never"; mkdesign "$d" draft
other3=$(newrepo rd-design-symlink-external)
mkdesign_at "$other3/docs/designs/offline-stamp" locked
ln -sf "$other3/docs/designs/offline-stamp/design.md" "$d/docs/designs/offline-stamp/design.md"
run "$d" --plan "$PLANREL"
{ [ "$RC" = "1" ] && grep -q "design.md resolves outside this repo" <<<"$OUT"; } \
  && ok "a design.md symlink pointing outside the repo blocks" || bad "design.md symlink out of repo (rc=$RC: $OUT)"
# A relative link chain that ends outside the repo is followed to its end.
d=$(newrepo rd-design-symlink-chain); cfg "$d" "require_design: never"; mkdesign "$d" draft
ln -s "../../../$(basename "$other3")/docs/designs/offline-stamp/design.md" "$d/docs/designs/hop.md"
ln -sf ../hop.md "$d/docs/designs/offline-stamp/design.md"
run "$d" --plan "$PLANREL"
{ [ "$RC" = "1" ] && grep -q "design.md resolves outside this repo" <<<"$OUT"; } \
  && ok "a relative design.md symlink chain ending outside the repo blocks" || bad "design.md symlink chain (rc=$RC: $OUT)"
# A symlink that stays inside the repo is not containment's business.
d=$(newrepo rd-design-symlink-in); cfg "$d" "require_design: never"; mkdesign "$d" locked
mv "$d/docs/designs/offline-stamp/design.md" "$d/docs/design-real.md"
ln -s ../../design-real.md "$d/docs/designs/offline-stamp/design.md"
run "$d" --plan "$PLANREL"
[ "$RC" = "0" ] && ok "a design.md symlink inside the repo still passes" || bad "in-repo design.md symlink (rc=$RC: $OUT)"

# --- path normalisation and the plan.md requirement --------------------------
# `docs/./designs/` and `docs//designs/` are the same directory as
# `docs/designs/`, but a lexical match on the raw string missed both and so
# skipped the design gate entirely: under never/features a DRAFT design built.
for mode in never features; do
  for p in docs/./designs/offline-stamp/plan.md docs//designs/offline-stamp/plan.md; do
    d=$(newrepo "rd-norm-$mode"); cfg "$d" "require_design: $mode"; mkdesign "$d" draft
    run "$d" --plan "$p"
    [ "$RC" = "1" ] && ok "$mode: --plan $p to a draft design blocks" || bad "$mode: --plan $p (rc=$RC: $OUT)"
  done
done

# Any file in a locked design's folder is not that design's plan: loop-dev
# would build whatever evil.md says while design-check vouched for plan.md.
d=$(newrepo rd-evil); cfg "$d" "require_design: never"; mkdesign "$d" locked
printf '### Task 1: something else entirely\n' > "$d/docs/designs/offline-stamp/evil.md"
run "$d" --plan docs/designs/offline-stamp/evil.md
{ [ "$RC" = "1" ] && grep -q "plan.md" <<<"$OUT"; } \
  && ok "--plan to a non-plan.md file in a design folder blocks" || bad "--plan evil.md (rc=$RC: $OUT)"

# --- DESIGN_ALREADY_FOLDED needs a locked history and a committed flip -------
# The fold is only real when some committed version of the design was locked
# (the merge-base version or a commit on this branch) AND the committed shipped
# version at HEAD differs from the merge-base. Without the first, a design
# committed straight as `shipped` skips locking; without the second, an
# uncommitted flip in the working tree reads as a fold.
commit() { git -C "$1" add -A; git -C "$1" -c user.email=t@t -c user.name=t commit -q -m "$2"; }
flip() { sed -i.bak "s/status: $2/status: $3/" "$1/docs/designs/offline-stamp/design.md"; rm -f "$1/docs/designs/offline-stamp/design.md.bak"; }

# (f) shaped on the same branch: locked commit, then shipped commit, both on it.
d=$(newrepo rd-fold-samebranch); cfg "$d" "require_design: always"; commit "$d" cfg
git -C "$d" checkout -q -b feature
mkdesign "$d" locked; commit "$d" "design locked"
flip "$d" locked shipped; commit "$d" "ship design"
run "$d" --plan "$PLANREL"
{ [ "$RC" = "0" ] && grep -q "DESIGN_ALREADY_FOLDED: offline-stamp" <<<"$OUT"; } \
  && ok "(f) locked then shipped, both on this branch: FOLDED" || bad "(f) same-branch fold (rc=$RC: $OUT)"

# (g) committed straight as shipped on the branch, never locked.
d=$(newrepo rd-fold-neverlocked); cfg "$d" "require_design: always"; commit "$d" cfg
git -C "$d" checkout -q -b feature
mkdesign "$d" shipped; commit "$d" "design shipped, never locked"
run "$d" --plan "$PLANREL"
{ [ "$RC" = "1" ] && ! grep -q "DESIGN_ALREADY_FOLDED" <<<"$OUT"; } \
  && ok "(g) shipped but never locked in history blocks" || bad "(g) never locked (rc=$RC: $OUT)"

# (h) locked committed on the branch, flip to shipped left UNCOMMITTED.
d=$(newrepo rd-fold-uncommitted); cfg "$d" "require_design: always"; commit "$d" cfg
git -C "$d" checkout -q -b feature
mkdesign "$d" locked; commit "$d" "design locked"
flip "$d" locked shipped
run "$d" --plan "$PLANREL"
{ [ "$RC" = "1" ] && ! grep -q "DESIGN_ALREADY_FOLDED" <<<"$OUT"; } \
  && ok "(h) uncommitted flip to shipped blocks" || bad "(h) uncommitted flip (rc=$RC: $OUT)"

# FOLDED still runs design-check: an open item added with the flip blocks.
d=$(newrepo rd-fold-open); cfg "$d" "require_design: always"
mkdesign "$d" locked; commit "$d" "design locked"
git -C "$d" checkout -q -b feature
flip "$d" locked shipped
echo '- [ ] Q2 · med · reopened after ship · open' >> "$d/docs/designs/offline-stamp/design.md"
commit "$d" "ship design with an open item"
run "$d" --plan "$PLANREL"
{ [ "$RC" = "1" ] && grep -q "BLOCK: design: Q2" <<<"$OUT" && ! grep -q "DESIGN_ALREADY_FOLDED" <<<"$OUT"; } \
  && ok "folded design that fails design-check blocks" || bad "folded + open item (rc=$RC: $OUT)"

exit $fail
