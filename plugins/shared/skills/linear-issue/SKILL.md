---
name: linear-issue
description: "Use before creating or rewriting a Linear issue or sub-issue — bug, feature, chore, docs, trend lead, or spec — whether the user asked for a ticket or you are about to call save_issue yourself"
user-invocable: true
argument-hint: "[spec] <what happened, or what is wanted>"
---

# Linear issue

Write the issue from `$ARGUMENTS`. If the first word is `spec`, it is a spec; otherwise decide by step 1.

A ticket is what someone reads to decide whether to pick the work up. What justifies the fix belongs in the PR that makes it.

## Steps

1. **Classify.** It is a **spec** only if the input contains decisions — choices made where another option existed, with the reason each went the way it did. Findings, a fix, and acceptance criteria do not make a spec. When neither form clearly fits, write the short form.
2. **Title** is `<type> - <App>: <sentence>` — type is one of `bug`, `feat`, `chore`, `docs`, `spec`, `trend`; App is the project's short name; the sentence states the defect or the ask, not a label: `bug - Ristretto: a stage timeout discards all uncommitted work`.
3. **Body in the form below.**
4. **Count.** Write the body to a scratch file and run `wc -w`. Short form over 150 words: cut in this order until under — rationale, the narrative of how it was found, restated code that a `path:line` already points at, the fourth acceptance criterion. Never cut evidence.
5. **Submit** with `save_issue`, or hand the text over if a draft was asked for. Link related issues with `relatedTo`, not prose.
6. **Sub-issues**, only for a spec whose Fix lists ordered slices: one sub-issue per slice via `parentId`, each in the short form, titled `feat - <App>: <slice>`, with no Decisions table — the parent holds it. Bugs and tasks are never split unless the user asks.

## Output format

**Short form** (bug, task, chore, lead) — no headers, no tables, under 150 words:

```
<Problem: what is wrong or wanted, one or two sentences.>

Evidence: `path:line` — what it does · `command` → what it printed · (no code yet: the brief's sentence)

Fix:
- <bullet>

Acceptance:
- <at most three>
```

**Spec** — the same four parts, plus a `Decisions` table (`Question | Decision | Why`) between Problem and Fix, and open risks as bullets after it. No word cap. Still no Context section and no restated code.

Short-form example (replaces a 380-word draft of the same bug):

```
bug - Ristretto: a stage timeout discards all uncommitted work

A build stage that hits its 3600s budget is killed with its worktree uncommitted; the run reads as a model failure and finished work is thrown away.

Evidence: `src/flow/stage.ts:212` kills on timeout · `src/flow/report.ts:88` reports `build failed: exit 124` · run 66 (`t_6fc071bc`): 9 files + a 225-line test complete in the worktree at kill

Fix:
- Commit the worktree (WIP) before reporting; at minimum put the diffstat in the task
- Blocked reason says timeout and file count, not exit code
- Stage budget configurable per repo (kaffecard spends 15–30 min of the hour on `npm ci` + `prisma generate`)

Acceptance:
- A timed-out stage leaves its work on the branch
- The blocked reason distinguishes "timed out with work" from "failed"
- Timeout is configurable per repo
```

## Constraints

- No `## Context`, `## Why it matters`, or `## How this was found` sections. The evidence line carries the how; the PR carries the why.
- Never lower a spec to the short form by deleting its decisions; never raise a bug to a spec to keep its rationale.
- The count in step 4 is measured, not estimated.
- A sub-issue never repeats the parent's Problem or Evidence beyond one sentence; it links up.
