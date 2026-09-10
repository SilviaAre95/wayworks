---
name: linear-issue
description: "Use before creating or rewriting a Linear issue or sub-issue — bug, feature, chore, docs, trend lead, or spec — whether the user asked for a ticket or you are about to call save_issue yourself"
user-invocable: true
argument-hint: "[spec] <what happened, or what is wanted>"
---

# Linear issue

Write the issue from `$ARGUMENTS`. If the first word is `spec`, it is a spec; otherwise decide by step 1. A ticket is what someone reads to decide whether to pick the work up. What justifies the fix belongs in the PR.

## Steps

1. **Classify.** It is a **spec** only if the input contains decisions — choices made where another option existed, with the reason each went the way it did. Findings, a fix and acceptance criteria do not make a spec. When neither fits, write the short form.
2. **Title** is `<type> - <App>: <sentence>` — type is one of `bug`, `feat`, `chore`, `docs`, `spec`, `trend`; App is the project's short name; the sentence states the defect or the ask, not a label.
3. **Body in the form below.** Optional lines are written only when there is something to put on them.
4. **Priority** goes in the field, never the body: `1` Urgent when production users, data, money or security are affected now; `2` High when a feature is broken or fails silently; `3` Medium otherwise; `4` Low for `docs`, `chore`, `trend`. An issue that `blocks` another takes the blocked issue's priority.
5. **Relations** go in fields, never prose: `blockedBy` / `blocks`, `relatedTo` for context. A dependency that is not an issue — an env var, a decision, a vendor — is an `Open:` or `Risk:` line.
6. **Count.** Write the body to a scratch file and run `wc -w`. Short form over 180 words: cut explanation only, in this order — rationale, the narrative of how it was found, restated code that a `path:line` already points at, filler. Fix bullets, Acceptance, Evidence, Refs, Risk and Open are instructions and are never cut. Still over with only instructions left: it stays one ticket, runs over, and you say so.
7. **One ticket by default.** A fix bullet becomes its own issue only when it can be closed without the others *and* one must land first — then link it with `blocks`. Nothing else splits: not length, not bullet count.
8. **Submit** with `save_issue`, or hand the text over if a draft was asked for.
9. **Sub-issues**, only for a spec whose Fix lists ordered slices, or when asked: one per slice via `parentId`, short form, titled `feat - <App>: <slice>`, no Decisions table and no Risk line — the parent carries both. A bug or task is never split into sub-issues.

## Output format

**Short form** (bug, task, chore, lead) — no headers, no tables, under 180 words. Worked example: `references/example-short-form.md`.

```
<Problem: what is wrong or wanted, one or two sentences.>

Evidence: `path:line` — what it does · `command` → what it printed
Refs: <files the fix touches> · <vendor doc or PRD> · <vault note>
Risk: <what the fix can break, or what stays broken while it waits>
Open: <a question to answer before or during the fix; at most two>

Fix:
- <bullet>

Acceptance:
- <at most three>
```

**Spec** — the same lines, with a `Decisions` table (`Question | Decision | Why`) between the Open line and Fix. Risk and Open stay lines. No word cap, no Context section, no restated code.

## Constraints

- No `## Context`, `## Why it matters` or `## How this was found` sections. Evidence carries the how; the PR carries the why.
- Severity lives in the priority field; dependencies on issues live in relations. Neither is repeated in the body.
- Never lower a spec to the short form by deleting its decisions; never raise a bug to a spec to keep its rationale.
- The count in step 6 is measured, not estimated. The cap bounds explanation, never scope.
- A sub-issue never repeats the parent's Problem or Evidence beyond one sentence; it links up.
