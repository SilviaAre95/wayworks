---
name: pr-description
description: "Use when opening or updating a pull request — produces a PR body carrying a one-line summary, what changed, why, the change type, files affected, and tests, short enough that a reviewer reads it before merging"
user-invocable: true
argument-hint: "[<pr-number>|<base-branch>] — defaults to the current branch against main"
---

# PR description

Write the PR body for: **$ARGUMENTS** (defaults to the current branch against `main`).

## Steps

1. **Read the change**: `git diff <base>...HEAD --stat`, then the diff, then `git log <base>..HEAD --oneline`.
2. **Write the one-liner first.** If it will not fit in one sentence, the PR is doing too much — say so instead of writing a longer sentence.
3. **Fill each section below exactly once.** All six are required; a section with nothing to report gets `None`.
4. **Cut anything a reviewer would not act on.** This body is a merge decision aid, not a record of the work.

## Output format

```
<One sentence: what this does.>

**What changed** — 2-4 bullets, one per logical change.
**Why** — the problem being solved, in 1-2 sentences.
**Type** — feat | fix | refactor | docs | chore; name any breaking change.
**Files** — `path` — one clause on what each file's change does.
**Tests** — what was run and what it proved, or `None`.
```

## Constraints

- Under 250 words. A body that gets skimmed gates nothing.
- No chronology: not what review caught, not how many rounds it took, not what was tried first. Findings belong in review threads.
- No self-assessment and no confessions. A defect fixed before merge is not PR content.
- Do not walk the diff file by file beyond the `Files` clauses.
- Numbers only if measured this session; cite how.
