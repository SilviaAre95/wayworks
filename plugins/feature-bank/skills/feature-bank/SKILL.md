---
name: feature-bank
description: 'Prevent agent drift and silent feature mutation by enforcing a source-of-truth feature bank. Trigger this skill WHENEVER you are about to edit, create, or delete code in /src, /app, /lib, /api, /components, /pages, or similar code directories — no matter how small the change. Also trigger on requests like "add a feature", "implement X", "remove Y", "refactor Z", "change how X works", "populate the feature bank", "backfill features", or when the user describes product behavior. The skill runs a hard preflight check against /docs/features/ before any code is written, blocks scope creep via explicit non_goals, requires a diff-first approval flow for intentional spec changes, and runs a postflight to update metadata and changelog. For existing codebases with no feature bank, it runs an interactive Backfill flow to reverse-engineer a V0 from the code. Do NOT skip this skill to "move faster"; skipping is the drift it is designed to prevent.'
user-invocable: true
---

# Feature Bank

**Mental model**: prescriptive, not descriptive — what the product *must* and *must not* do (`project-docs` describes how it's built). Two gates bracket every code change. Drift has two shapes, both caught here: scope creep (unspec'd additions) and silent mutation (unflagged changes to spec'd behavior).

## Layout

```
/docs/features/
  INDEX.md                    ← always read first
  <feature-id>.md             ← full spec (frontmatter + prose)
  <feature-id>.CHANGELOG.md   ← append-only history
```

IDs are kebab-case, domain-prefixed (`auth-login`, `billing-invoice`). For spec frontmatter fields, INDEX.md and changelog formats, read `references/spec-format.md`. Templates live in `templates/`.

## Gate 1 — Preflight (MANDATORY before writing any code)

1. Read `/docs/features/INDEX.md`. If missing → Bootstrap (below).
2. Map the code you'll touch to feature IDs. Unclear → ask the user.
3. Load each affected `/docs/features/<id>.md` fully.
4. State in one short block: feature IDs touched, intended behavior change, `acceptance_criteria` satisfied, no `non_goals` violated.
5. Scan `non_goals` across all features in INDEX.md for keywords matching your plan. Any hit → STOP, invoke Gate 2.
6. Deviation check: if the request differs from the spec → STOP, invoke Gate 2. Never silently "fix" the spec by coding the new request.

Edit code only after all six pass.

## Gate 2 — Escape hatch (diff-first spec change)

For any request/spec mismatch, or an intentional feature change:

1. Do NOT edit code yet.
2. Produce a unified diff of the proposed feature-file change plus a one-line behavioral impact summary (example: `references/examples.md`).
3. Wait for explicit approval in chat ("yes", "approved", "go"). Never assume.
4. On approval: apply the diff, bump `last_modified`, append a changelog entry, then code. If rejected/modified, iterate on the spec — never code against an unsigned spec.

## Gate 3 — Postflight (MANDATORY after writing code)

1. Update frontmatter of every touched feature file: `last_modified` = today, `status` if it changed.
2. Append to `<feature-id>.CHANGELOG.md` (create if missing) — format: `references/spec-format.md`.
3. Re-verify: restate each acceptance criterion and confirm it's satisfied or was explicitly spec-updated; run the spec's `test_plan` when present.
4. Report: features updated, files changed, changelog entry.

## Scaffolding a new feature

When the user describes new behavior:

1. Don't jump to code. Generate a feature file from `templates/feature.md`; pick an ID (confirm if ambiguous).
2. Fill `acceptance_criteria` (concrete, testable behaviors — not implementation) and `depends_on`. Propose a `test_plan` — how an agent verifies this in dev (flows to drive, commands over sample data), per project type.
3. `non_goals` is the most important anti-drift field: list what the feature will NOT do. Push the user; suggest 3–5 plausible ones if needed (`references/examples.md`).
4. Add an INDEX.md entry (status=`proposed`, summary, top 2 non_goals); create `<id>.CHANGELOG.md` with an initial entry.
5. Show the user the file; get confirmation before implementing.

## Bootstrap and backfill

If `/docs/features/` doesn't exist: create it and `INDEX.md` from `templates/INDEX.md`, then detect context. New/empty project → scaffold the requested feature now. Existing codebase → strongly recommend the interactive Backfill flow (reverse-engineers a V0 bank from the code); if declined, scaffold only the current request and note the bank is incomplete. For the four-phase backfill (sizing → interactive inventory → per-feature scaffolding → wrap-up) and its anti-patterns, read `references/backfill.md`.

## Hard rules

- Never skip preflight because "the change is tiny" — tiny changes are where drift hides.
- Never code first and update the feature file to match after — that is drift.
- Never rewrite the feature body during postflight — history goes in the CHANGELOG; the body changes only via Gate 2.
- Never leave `non_goals` empty — a feature without boundaries scope-creeps forever.
- No vague acceptance criteria ("works well", "is fast") — criteria must be checkable.
- Don't merge feature-bank contents into `/docs/architecture/` — different skills own different folders.

## When NOT to run the gates

- Pure refactors changing no behavior (renames, file moves) — note in commit only.
- Build config, CI, dependency bumps — code, but not features.
- Spikes in `/spike/` or `/scratch/` — keep outside the bank.

If in doubt, run the gates: a 30-second preflight beats shipping drifted behavior.
