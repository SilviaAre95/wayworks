---
name: linear-update
description: "Use when posting to an existing Linear issue or moving its state — work started, a PR opened, a loop stood down, work blocked on a decision, a deploy landed, a wrong lead corrected — whether the user asked or a loop step calls for it"
user-invocable: true
argument-hint: "<issue-key> <started|pr-opened|stood-down|blocked|deployed|corrected> [details]"
---

# Linear update

One comment per event, and the state the event implies. The ticket records what happened and what a human must do next. The PR holds the change, the log holds the trace, the session holds the reasoning.

## Steps

1. **Parse** `$ARGUMENTS`: issue key, event, details (URL, breaker, attempts, branch, what failed).
2. **Check for a duplicate.** `list_comments` on the issue. If a comment already carries this event's URL or the same first line, post nothing and only set the state. A re-run must not double-post.
3. **Write the comment** in the form below. Write it to a scratch file and `wc -w` it: under 80 words.
4. **Set the state** from the table. Never guess a state name; if the workspace's names differ, read them with `list_issue_statuses`.
5. **Submit**: `save_comment`, then `save_issue` with `state`.

## Output format

```
<What happened, one sentence, past tense, with the numbers that matter.>
<bare URL on its own line — PR, deployment, or run — when there is one>
Next: <the one thing a human must do, or "nothing">
```

| Event | First sentence carries | State |
|---|---|---|
| started | no comment | In Progress |
| pr-opened | PR number and CI result | In Review |
| stood-down | which breaker, after how many attempts, what is still failing in one clause, which branch holds the work | stays In Progress |
| blocked | the decision needed, and the options in one line | stays In Progress |
| deployed | target and verify result | Done |
| corrected | what the ticket claimed, what the source says, the source | unchanged |

Example, stood-down (43 words):

```
Deterministic gate still red after 3 attempts: 2 tests in src/flow/__tests__/stage.test.ts assert a clean worktree after a stage, which the WIP commit on timeout now violates. Work is on branch xari-118-timeout-wip-commit, no PR.
Next: decide whether the invariant or the fix gives way.
```

## Constraints

- The comment never restates the diff, the root cause, or the ticket. The PR description carries the change; the ticket already carries the problem.
- Options fit in one line. The design choice itself goes back to the user in the session; the ticket only records that one is needed.
- Done needs a verified deploy or a merged PR. In Review needs an open PR URL in the comment.
- Nothing about what the agent tried, felt, or would do next time.
