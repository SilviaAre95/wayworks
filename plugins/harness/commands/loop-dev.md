---
description: Arm the staged dev loop — implement a task through spec/code/review/security/bugs to a PR
argument-hint: <task description> [--plan <path>] [--check-plan]
allowed-tools: Bash(touch:*), Bash(echo:*), Bash(cat:*), Bash(rm:*)
---

Arm the dev loop for this project:

!`touch .cc-loop-dev-active && echo 0 > .cc-loop-dev-state && rm -f .cc-dev-reviews-passed .cc-loop-dev-rounds && echo "loop-dev armed"`

The staged dev loop is **ARMED**. Config lives in `.cc-dev.yaml` (graders, max_retries, base, open_pr) — read it now if present.

Work in the `acceptEdits` tier (Shift+Tab) so edits and the allowlist run without prompts. Then execute these stages for the task below:

1. **Read the task.** If the task names a tracker issue (`ABC-123`, an issue URL, `#456`), **read it** — the Linear MCP `get_issue` tool, else `gh issue view <n>`. Reading is cheap and never wrong; a task's own summary routinely omits an acceptance criterion the ticket spells out. **The ticket adds, it does not redirect.** Requirements it states that your task omitted are in scope — catching those is the whole point of reading. What it cannot do is change *what you are working on*: a reference in passing (`"same fix as PR #12"`, `RFC-2119`, a commit SHA) is context, not a new assignment. If ticket and task genuinely conflict about what to build — not merely differ in detail — stop and say so instead of picking one.
   Authority runs the other way only when the task is *bare* — a key, a URL, or a key plus a title, with no instructions of its own. Then the issue body IS the spec, and if you cannot read it (no tracker MCP available, no network, unknown tracker), **stop and report exactly that, changing nothing.** Never reconstruct scope from the branch name, recent commits, or surrounding code: that ships a plausible, well-reviewed, wrong change that passes every downstream gate. A failed lookup on a task that already carries its own instructions is not a reason to stop — note it and proceed on the task as written.
2. **Preflight (specs).** If `docs/features/INDEX.md` exists, run the `feature-bank` preflight: identify affected feature(s), confirm the change satisfies their `acceptance_criteria` and violates no `non_goals`. On a spec mismatch, STOP and surface the diff-first escape hatch — do not code around the spec.
3. **Plan.** If the invocation included `--plan <path>`, read that plan file (e.g. a superpowers `writing-plans` document) and adopt it — follow its tasks in order; it outranks your own ideas about sequencing. Otherwise write a short implementation plan. Either way, if the invocation included `--check-plan`, post the plan and WAIT for the user's approval before building.
4. **Build.** Implement the task, then **commit before moving on** — reviews and fixes are later commits. Anything uncommitted dies with the session, and a run killed at its wall-clock limit has lost a finished implementation that way. Three rules on how you commit:
   - **Stay on the checked-out branch.** Never create or switch branches, and never push a branch name you invented — the caller chose the branch, and PR lookups key on it.
   - **Stage explicit paths.** Never `git add -A` or `git add .`: they sweep in unrelated edits and stale index entries, which is how an unrelated revert reaches a PR.
   - **Never commit loop state.** `.cc-loop-dev-*` and `.cc-dev-reviews-passed` stay untracked — a tracked marker invalidates its own fingerprint and livelocks the gate. (`.cc-verify` and `.cc-dev.yaml` are the opposite: tracked project config, committed like any other file.)
5. **Review stages (run in PARALLEL, scaled to the diff).** First look at the diff vs `base` and pick the panel from `.cc-dev.yaml` `graders` (default `code-review`, `security`, `bugs`):
   - **Docs-only diff** (markdown/docs, no executable code or config): `code-review` only.
   - **Small code diff** (under ~50 changed lines) that touches no hooks, auth, security, templates, or secrets handling: `code-review` + `bugs`.
   - **Everything else — and ALWAYS when the diff touches hooks, auth/permissions, deploy templates, or secrets handling**: the full configured panel.
   Dispatch **exactly one subagent per selected grader — never two for the same grader in one round** — **all at once, in a single batch of concurrent Task calls, not one after another** — each reviewing the diff against `base` (default `main`):
   - `code-review` → correctness/quality review (or the `/code-review` skill).
   - `security` → the `security:code-audit` skill (OWASP, injection, authz, secrets).
   - `bugs` → the `qa:bug-review` skill (edge cases, logic errors).
   - `design` → the `design:layout-review` skill on UI diffs (add `design:heuristic-eval` when the diff introduces a new user flow). Enable per-repo in `graders` for frontend projects.
   Any other grader name maps to the skill of the same name (`plugin:skill`, or a plain skill name). If no such skill exists, STOP and ask — never silently skip a configured grader.
   Model tiers: when your dispatch tool supports per-subagent model selection, run `code-review` and `bugs` on a mid-tier model (e.g. sonnet); `security` always inherits the session model — never downgrade it.
   Wait for all of them, then collect every blocking finding across all graders into one list; fix them (committing the fixes); re-review — again in parallel, still exactly one subagent each — until all are clean. Re-run the graders whose findings you fixed, **plus `security` whenever a fix touches anything the panel rule above calls security-relevant** — executable code, hooks, auth/permissions, deploy templates, or secrets handling: a fix aimed at one grader's finding routinely lands in another's domain (a null-check rewritten as string interpolation is a `bugs` fix and a `security` regression), and `security` is the one grader whose miss you cannot walk back after merge. An untouched domain does not re-run. Running the graders concurrently is the point — do not serialize them.
6. **Dev test (project-shaped).** Unit tests belong to the deterministic gate; this stage exercises the change the way the product is actually used. Pick the method in this order:
   - The affected feature specs' `test_plan` field (feature-bank) — run exactly what it lists.
   - No `test_plan`: infer from the stack. Web app → drive the changed flow in a real browser (built-in browser tooling or the `chrome-devtools-mcp` plugin), console and network clean on the happy path. API service → hit the affected endpoints on the running dev server and assert the responses. Data pipeline → run `data-engineer:pipeline-verify` against a bounded sample.
   Record what you ran and what you observed — it becomes the PR body's "How verified" section. If the flow cannot run in this dev environment, say so explicitly in the PR body; never skip silently.
7. **Finish.** Run the `feature-bank` postflight (Gate 3) for every touched feature: bump `last_modified`, append the `<id>.CHANGELOG.md` entry, re-verify each acceptance criterion — spec docs land in the same state the marker will fingerprint. Then, when the deterministic gate (`.cc-verify`) is green AND all graders are clean AND you have made no further edits, stamp the marker with the anchor commit and tree fingerprint so late changes invalidate it:
   `mb=$(git merge-base <base> HEAD) && { echo "$mb"; git diff "$mb" | git hash-object --stdin; } > .cc-dev-reviews-passed`
   (outside a git repo: `touch .cc-dev-reviews-passed`). The Stop hook re-fingerprints the tree against the anchor stored in the marker; if anything changed after stamping — committed or not — the marker is rejected and you must re-run the affected graders.
8. **PR** (if `.cc-dev.yaml` `open_pr` is not false). Push the branch. Then check for an existing PR first — re-runs must converge to ONE PR, never two:
   `gh pr list --head <branch> --json url,state --jq '.[] | select(.state=="OPEN") | .url'`
   - If a URL comes back: reuse it. Do NOT run `gh pr create`. Update the PR body if the diff changed materially.
   - Only if empty: open the PR with `gh pr create`.
   Then watch CI on the PR: `gh pr checks <branch> --watch --fail-fast`. Red checks are loop work — fix, push, re-watch (pushed fixes invalidate the reviews marker, so affected graders re-run). Never hand over a red PR. Only when checks are green (or the repo has none configured), post to Slack: a one-line "what changed", the **bare** PR URL on its own line, and the tracker issue key. If the task has no tracker issue (stage 1), post the same message without a key and skip the rest of this paragraph. Otherwise, on the issue: move it to "In Review" and add the PR-link comment ONLY if no comment with this PR URL already exists — a re-run must not double-post. Never merge — that is the user's call from their phone.

The `Stop` hook enforces this: you cannot finish until `.cc-verify` is green and `.cc-dev-reviews-passed` exists. If the deterministic gate fails it feeds the errors back; after `max_retries` a circuit breaker trips — then summarize what is still broken. Grading is bounded too: after `max_review_rounds` (`.cc-dev.yaml`, default 3) stop attempts without a clean stamped marker, the review circuit breaker disarms the loop — summarize outstanding findings instead of dispatching more graders.

Task: $ARGUMENTS
