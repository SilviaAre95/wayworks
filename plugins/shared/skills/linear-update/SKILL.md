---
name: linear-update
description: "Use when posting to an existing Linear issue or moving its state — work started, a PR opened or merged, a loop stood down, work blocked on a decision, a deploy landed, a wrong lead corrected — whether the user asked or a loop step calls for it"
user-invocable: true
argument-hint: "<issue-key> <started|pr-opened|merged|stood-down|blocked|deployed|corrected> [details]"
---

# Linear update

## Steps

1. **Parse** `$ARGUMENTS`: issue key, event, details (URL, breaker, attempts, branch, what failed).
2. **Check for a duplicate by the event marker.** Every comment must end with the marker line from the format below, e.g. `_(linear-update: pr-opened)_`. `list_comments`, then suppress only when a comment carries **this same marker and the same URL**; otherwise post.
3. **Write the comment** in the form below, to a scratch file, and `wc -w` it: under 80 words.
4. **Set the state** from the table. Never guess a state name; if the workspace's names differ, read them with `list_issue_statuses`.
5. **Attach the PR whenever the event names one** — `pr-opened`, `merged`, any `corrected` or `blocked` citing a PR: `save_issue` with `links: [{url, title}]`.
6. **Submit**: `save_comment`, then `save_issue` with `state` (and `links` where step 5 applies).

## Output format

```
<What happened, one sentence, past tense, with the numbers that matter.>
<bare URL on its own line — PR, deployment, or run — when there is one>
Next: <the one thing a human must do, or "nothing">
_(linear-update: <event>)_
```

| Event | First sentence carries | State |
|---|---|---|
| started | no comment | In Progress |
| pr-opened | PR number and CI result | In Review |
| merged | which PR merged, what shipped in one clause | Done |
| stood-down | which breaker, after how many attempts, what is still failing in one clause, which branch holds the work | stays In Progress |
| blocked | the decision needed, the options in one line | stays In Progress |
| deployed | target and verify result | Done |
| corrected | what the ticket claimed, what the source says, the source | unchanged |

## Constraints

- The comment never restates the diff, the root cause, or the ticket.
- Options fit in one line. The design choice goes back to the user in session; the ticket records only that one is needed.
- Done needs a verified deploy or a merged PR; In Review needs an open PR URL in the comment. Never set Done from `pr-opened` — the human merges.
- Every event naming a PR attaches it with `links`. Work that shipped without a PR attachment is not finished being updated.
- Nothing about what the agent tried, felt, or would do next time.
