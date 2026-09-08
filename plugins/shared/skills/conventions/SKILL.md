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
- **Delegate reading, keep the main thread thin** — exploration spanning more than a couple of files goes to a subagent that returns the conclusion, not the file contents. A subagent carries a fraction of the context, so it costs a fraction of the per-turn price, and the main thread stays cheap for the turns that need judgment

## Error Handling

- Handle the error case explicitly — no silent catches, no swallowed promises
- Return early on errors; keep the happy path last and unindented
- Validate inputs at system boundaries (user input, external APIs); trust internal calls
- Error messages state what failed and what the caller can do about it

## Git & Commits

- Conventional commits: `feat:`, `fix:`, `docs:`, `refactor:`, `test:`, `chore:`
- Commit messages explain *why*, not *what*
- One logical change per commit

## Code Review Checklist

When reviewing code, check for:
1. Security: no secrets in code, proper input validation, no injection vectors
2. Error handling: explicit, not silent
3. Simplicity: could this be simpler?
4. Tests: are edge cases covered?
5. Consistency: does it read like the surrounding code?
