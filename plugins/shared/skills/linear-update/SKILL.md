---
name: linear-update
description: "Use when posting to an existing Linear issue or moving its state — work started, a PR opened or merged, a loop stood down, work blocked on a decision, a deploy landed, a wrong lead corrected — whether the user asked or a loop step calls for it"
user-invocable: true
argument-hint: "<issue-key> <started|pr-opened|merged|stood-down|blocked|deployed|corrected> [details]"
---

# Linear update

One comment per event, and the state the event implies. The ticket records what happened and what a human must do next. The PR holds the change, the log holds the trace, the session holds the reasoning.

## Steps

1. **Parse** `$ARGUMENTS`: issue key, event, details (URL, breaker, attempts, branch, what failed).
2. **Check for a duplicate by the event marker.** Every comment ends with the marker line from the format below, e.g. `_(linear-update: pr-opened)_`. `list_comments`, then suppress only when a comment carries **this same marker and the same URL**; otherwise post.
   Neither half alone works, and both failures are silent. Matching on URL alone swallows `merged`, whose URL `pr-opened` already posted, so the issue reaches Done with no record of the merge. Matching on the first line alone double-posts `pr-opened`, because `loop-dev` step 7 re-runs it after fixing red CI and the CI result in that first line has changed. The marker is the only signal in the comment text that survives both.
3. **Write the comment** in the form below. Write it to a scratch file and `wc -w` it: under 80 words.
4. **Set the state** from the table. Never guess a state name; if the workspace's names differ, read them with `list_issue_statuses`.
5. **Attach the PR whenever the event names one** — `pr-opened`, `merged`, and any `corrected` or `blocked` whose comment cites a PR: `save_issue` with `links: [{url, title}]`. A bare URL in a comment is prose; the attachment is what shows on the issue and survives scrolling. Re-attaching the same URL updates the existing attachment rather than adding a second, so a re-run is safe.
6. **Submit**: `save_comment`, then `save_issue` with `state` (and `links` where step 5 applies).

## Output format

```
<What happened, one sentence, past tense, with the numbers that matter.>
<bare URL on its own line — PR, deployment, or run — when there is one>
Next: <the one thing a human must do, or "nothing">
_(linear-update: <event>)_
```

The marker line is required on every comment and is what step 2 matches on. It is the only thing that makes a re-run idempotent without making a *different* event on the same PR invisible.

| Event | First sentence carries | State |
|---|---|---|
| started | no comment | In Progress |
| pr-opened | PR number and CI result | In Review |
| merged | which PR merged, and what shipped in one clause | Done |
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
- Done needs a verified deploy (`deployed`) or a merged PR (`merged`). In Review needs an open PR URL in the comment. Never set Done from `pr-opened` — the human merges.
- Every event that names a PR attaches it with `links`. An issue whose work shipped and that carries no PR attachment is not finished being updated.
- Nothing about what the agent tried, felt, or would do next time.
