---
name: conventions
description: "Apply wayworks working conventions: simplicity-first, root-cause fixes, explicit error handling, conventional commits. Language-agnostic — stack specifics load via stack profiles."
user-invocable: true
argument-hint: "[focus-area e.g. review|commits|errors]"
---

# Xari Working Conventions

Apply these conventions to all code you write or review, in any language. Stack-specific conventions (TypeScript, React, Prisma, Expo, GCP, Terraform) load automatically via stack profiles — do not restate them here. Optional focus: `$ARGUMENTS`

## General Principles

- **Simplicity first** — minimal changes, find root causes, no hacky fixes
- **No over-engineering** — if the simple fix is correct, use it
- **No speculative abstractions** — three similar lines > a premature abstraction
- **Delete dead code** — no `_unused` vars, no `// removed` comments, no re-exports for backwards compat
- **Delegate exploration, not editing or review** — when the question is *where does X live* or *does Y exist anywhere*, send it to a subagent and take the answer; the parent pays one small turn instead of many large ones. Read files directly when you are about to **edit** them (the edit needs the file in your own context) or **review** them (a reviewer must see the code, never a summary of it)

## Error Handling

- Handle the error case explicitly — no silent catches, no swallowed promises
- Return early on errors; keep the happy path last and unindented
- Validate inputs at system boundaries (user input, external APIs); trust internal calls
- Error messages state what failed and what the caller can do about it

## Git & Commits

Commit and pull-request text have their own skills — use them rather than restating the rules here: `shared:commit-message` for a commit, `shared:pr-description` for a PR body.

## Code Review Checklist

When reviewing code, check for:
1. Security: no secrets in code, proper input validation, no injection vectors
2. Error handling: explicit, not silent
3. Simplicity: could this be simpler?
4. Tests: are edge cases covered?
5. Consistency: does it read like the surrounding code?
