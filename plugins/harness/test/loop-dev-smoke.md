# loop-dev gate — end-to-end smoke scenario

The `loop-dev-gate.sh` Stop hook drives an LLM through a two-stage loop:
a deterministic gate (`.cc-verify`) must go green, then the agent must run
the review stages and mark them done (`.cc-dev-reviews-passed`) before the
gate allows Stop. The LLM review stage can't be exercised by a shell unit
test (see `loop-dev-gate.test.sh`, which stubs the deterministic gate via
`CC_GATE_CMD` and never actually runs graders). This doc is the manual,
reproducible complement: a real scratch project, a real `.cc-verify`
command, and the gate driven by hand through all three transitions an
agent would encounter in practice.

## Setup

Every call pins `CLAUDE_PROJECT_DIR="$d"`: a shell inside a Claude Code
session inherits the real project dir, and the gate would resolve to it.

```bash
GATE=/path/to/wayworks/plugins/harness/hooks/scripts/loop-dev-gate.sh
d=$(mktemp -d)

# deterministic gate for this scratch project: pass once a LICENSE file exists
echo "test -f LICENSE" > "$d/.cc-verify"

# arm the loop (what /loop-dev or equivalent does at start)
touch "$d/.cc-loop-dev-active"
echo 0 > "$d/.cc-loop-dev-state"
```

## Transition 1: armed, deterministic gate fails (no LICENSE yet)

```bash
printf '{"cwd":"%s"}' "$d" | CLAUDE_PROJECT_DIR="$d" bash "$GATE"
```

Expected output (mirrors `loop-dev-gate.test.sh` step 2 — `det-fail blocks` /
`det-fail feedback`):

```json
{
  "decision": "block",
  "reason": "Deterministic gate failed (attempt 1/3): test -f LICENSE\nFix the failures and continue; do not stop until green.\n"
}
```

- `decision` is `"block"`.
- `reason` contains `attempt 1/3`.
- `$d/.cc-loop-dev-state` now contains `1`.

## Transition 2: LICENSE created, deterministic gate is green, no reviews marker yet

```bash
echo "hello" > "$d/LICENSE"
printf '{"cwd":"%s"}' "$d" | CLAUDE_PROJECT_DIR="$d" bash "$GATE"
```

Expected output (mirrors `loop-dev-gate.test.sh` step 3 — `green-no-marker
asks reviews` / `green-no-marker keeps sentinel`):

```json
{
  "decision": "block",
  "reason": "Deterministic gate is green. Now run the review stages: [code-review, security, bugs]. Commit everything, record REVIEWED_SHA=$(git rev-parse HEAD), and launch every grader at once, one each. Invoke /code-review main...<REVIEWED_SHA> yourself, not in a subagent, and wait for its findings notification (the launch line is not a result). Dispatch one subagent per grader other than code-review with that SHA — each must confirm its HEAD matches it and echo it in its report. Fix every blocking finding and re-verify. When ALL graders are clean, every grader subagent echoed the same REVIEWED_SHA, /code-review ran on that SHA's range, it still equals HEAD, and the tree is clean, stamp the marker with that SHA:\n\n  sha=<REVIEWED_SHA> && mb=$(git merge-base main HEAD) && { echo \"$mb\"; git diff --no-ext-diff --no-textconv --ignore-submodules=dirty \"$mb\" | git hash-object --stdin; echo \"$sha\"; } > .cc-dev-reviews-passed\n\n(outside a git repo: touch .cc-dev-reviews-passed)\n\nDo NOT create the marker before the reviews are actually clean."
}
```

- `decision` is `"block"`.
- `reason` contains `review stages`.
- `$d/.cc-loop-dev-active` (the sentinel) still exists — the loop stays armed.

## Transition 3: reviews marker created — gate allows Stop and cleans up

```bash
touch "$d/.cc-dev-reviews-passed"
printf '{"cwd":"%s"}' "$d" | CLAUDE_PROJECT_DIR="$d" bash "$GATE"
```

Expected output (mirrors `loop-dev-gate.test.sh` step 4 — `green+marker
allows` / `green+marker disarms`):

```
(empty — no stdout)
```

- stdout is empty, so Stop is allowed.
- `$d/.cc-loop-dev-active`, `$d/.cc-loop-dev-state`, and
  `$d/.cc-dev-reviews-passed` are all removed (state cleaned).

## Cleanup

```bash
rm -rf "$d"
```

---

## Verified run

Actually executed on 2026-09-24 (harness 2.3.3) against
`plugins/harness/hooks/scripts/loop-dev-gate.sh` in a fresh `mktemp -d`
scratch dir (outside any git repo, so the touched marker is the
non-git escape hatch), following the exact steps above.

**Setup:**

```
$ ls -la "$d"
total 16
drwxr-xr-x   5 ... .
drwx------  12 ... ..
-rw-r--r--   1 ...   0 .cc-loop-dev-active
-rw-r--r--   1 ...   2 .cc-loop-dev-state
-rw-r--r--   1 ...  16 .cc-verify
```

**Transition 1 (armed, no LICENSE) — actual stdout:**

```json
{
  "decision": "block",
  "reason": "Deterministic gate failed (attempt 1/3): test -f LICENSE\nFix the failures and continue; do not stop until green.\n"
}
```

Exit code: `0`. `.cc-loop-dev-state` contents after: `1`. Matches the
documented expectation exactly.

**Transition 2 (LICENSE created) — actual stdout:**

```json
{
  "decision": "block",
  "reason": "Deterministic gate is green. Now run the review stages: [code-review, security, bugs]. Commit everything, record REVIEWED_SHA=$(git rev-parse HEAD), and launch every grader at once, one each. Invoke /code-review main...<REVIEWED_SHA> yourself, not in a subagent, and wait for its findings notification (the launch line is not a result). Dispatch one subagent per grader other than code-review with that SHA — each must confirm its HEAD matches it and echo it in its report. Fix every blocking finding and re-verify. When ALL graders are clean, every grader subagent echoed the same REVIEWED_SHA, /code-review ran on that SHA's range, it still equals HEAD, and the tree is clean, stamp the marker with that SHA:\n\n  sha=<REVIEWED_SHA> && mb=$(git merge-base main HEAD) && { echo \"$mb\"; git diff --no-ext-diff --no-textconv --ignore-submodules=dirty \"$mb\" | git hash-object --stdin; echo \"$sha\"; } > .cc-dev-reviews-passed\n\n(outside a git repo: touch .cc-dev-reviews-passed)\n\nDo NOT create the marker before the reviews are actually clean."
}
```

Exit code: `0`. Sentinel `.cc-loop-dev-active` still present. Matches the
documented expectation exactly.

**Transition 3 (`.cc-dev-reviews-passed` touched) — actual stdout:**

```
(empty)
```

Exit code: `0`. After this run:

```
$ ls -la "$d"
total 16
drwxr-xr-x   4 ... .
drwx------  12 ... ..
-rw-r--r--   1 ...  16 .cc-verify
-rw-r--r--   1 ...   6 LICENSE
```

`.cc-loop-dev-active`, `.cc-loop-dev-state`, and `.cc-dev-reviews-passed`
are all gone — state fully cleaned. Matches the documented expectation
exactly.

**Result: all three transitions verified, output byte-for-byte as
documented above.**
