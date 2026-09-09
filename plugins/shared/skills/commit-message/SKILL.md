---
name: commit-message
description: "Use when writing a git commit message or deciding how to split work into commits — enforces one logical change per commit, a conventional-commit subject under 60 characters, and a body that says why rather than what"
user-invocable: true
argument-hint: "[staged|<paths>] — defaults to the staged diff"
---

# Commit message

Write the message for: **$ARGUMENTS** (defaults to the staged diff).

## Steps

1. **Read the diff.** `git diff --cached`, or the named paths.
2. **Check it is one logical change.** If the diff does two unrelated things, stop and say how to split it — one commit each. A fix and a refactor that touched the same file are two commits, not one.
3. **Pick the type from the diff, not the intent**: `feat`, `fix`, `docs`, `refactor`, `test`, `chore`. Append `!` for a breaking change.
4. **Write the subject**: `type(scope): imperative summary`, 60 characters or fewer, no trailing period.
5. **Write a body only if the subject leaves a real question** — four lines at most, giving the condition that made the change necessary.

## Output format

```
type(scope): imperative summary under 60 chars

Why this was needed, four lines at most: the condition that
forced it, not the edits that resulted.
```

## Constraints

- One logical change per commit. Reviews and fixes are later commits.
- The body says *why*. The diff already says *what*, and `git show --stat` already lists the files.
- No account of how the change was reached — no review chronology, no what-was-tried-first, no confessions.
- Numbers only if measured this session.
- Wrap the body at 72 characters.
