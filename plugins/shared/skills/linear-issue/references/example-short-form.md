# Short-form example

A worked `bug` ticket, replacing a 380-word draft of the same defect. It shows the line order, how Evidence compresses three sources onto one line, and how Fix and Acceptance stay bullets.

```
bug - Ristretto: a stage timeout discards all uncommitted work

A build stage that hits its 3600s budget is killed with its worktree uncommitted; the run reads as a model failure and finished work is thrown away.

Evidence: `src/flow/stage.ts:212` kills on timeout · `src/flow/report.ts:88` reports `build failed: exit 124` · run 66 (`t_6fc071bc`): 9 files + a 225-line test complete in the worktree at kill
Refs: `src/flow/worktree.ts` · `docs/flows.md#stage-budget`
Risk: a WIP commit on the task branch lands in the PR if the next stage does not squash it
Open: is the budget per stage or per flow once it is configurable?

Fix:
- Commit the worktree (WIP) before reporting; at minimum put the diffstat in the task
- Blocked reason says timeout and file count, not exit code
- Stage budget configurable per repo (kaffecard spends 15–30 min of the hour on `npm ci` + `prisma generate`)

Acceptance:
- A timed-out stage leaves its work on the branch
- The blocked reason distinguishes "timed out with work" from "failed"
- Timeout is configurable per repo
```
