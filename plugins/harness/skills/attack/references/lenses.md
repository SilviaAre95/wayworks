# Attack lenses

Read the lenses for the target you were dispatched against. Each paragraph ends with the question an attacker actually asks while reading — use it, don't just restate the lens name as a finding.

## Scope lenses (`--target scope`, reads `design.md`)

**Ambiguity.** A scope line that reads clearly to its author can still admit two builds. Look for nouns without a definition (what counts as "the shop"?), verbs without a trigger (stamps "when"?), and any Scope-board row whose In/Out split isn't obvious from the row alone. *What sentence in this scope could two competent engineers implement differently?*

**Missing actors.** Discovery and Scope name the actors the author thought of; a design rarely names the ones it forgot — the offline device, the second staff member, the support agent who has to explain a failure, the attacker probing the same flow. *Who touches this flow, or its data, that no sentence in the design mentions?*

**Feature-bank conflicts.** Cross-check the scope against `docs/features/` when it exists — its `acceptance_criteria` and `non_goals` are the standing contract. A new scope line can silently narrow, widen, or contradict an existing feature's non-goals. *Does anything here promise, or rule out, something a shipped feature already decided the other way?*

**Cheapest cut.** Every scope has an unstated most-expensive path baked in as the only path. *What's the smallest version of this that still satisfies the Scope board's "In" column — and why isn't the design that version?*

## Plan lenses (`--target plan`, reads `plan.md`)

**Connectivity.** Any task that assumes a network call succeeds, in order, on the first try. *What does this task do the instant the connection it needs isn't there?*

**Concurrency/races.** Two tasks (or two runs of the same task) touching the same state without an ordering guarantee. *What happens if this task's action fires twice, or fires out of order with a task next to it?*

**Auth/session expiry.** A task that reads as instant but spans a session's lifetime, or that skips re-checking who's allowed once the flow resumes. *Is the actor still who the task thinks they are by the time this step runs?*

**Partial failure.** A task with no rollback, retry, or visible state for "started but didn't finish." *If this task dies halfway, what does the user, and the data, look like afterward?*

**Data limits.** Local storage, queues, and payload sizes the plan assumes are unbounded. *What's the largest input this task could see, and what does the plan do at that size?*

**Abuse.** A task an honest actor uses once but a dishonest one can use repeatedly, or out of its intended order, to their advantage. *How does someone make this task do something for them it wasn't meant to?*
