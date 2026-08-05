# First-party overlap audit

Audited 2026-08-05 against the 39 Anthropic-authored plugins in `claude-plugins-official`, the bundled skills (`/verify`, `/code-review`, `/doctor`, `/batch`, `/debug`, `/loop`, `/claude-api`), and `superpowers`.

wayworks was written when almost none of this existed. Some of it now does the same job, occasionally better. This records what overlaps, what the call was, and why — so the question isn't re-litigated from scratch every time the official marketplace grows.

## The rule this produced

**If deleting a skill would cost a *gate*, keep it. If it would only cost a *checklist*, delegate it.**

A checklist for OWASP or React review is something a capable model produces on request, and Anthropic now ships those first-party for free. What nobody else ships is the enforcement: Stop hooks that make "done" mean a passing command, marker fingerprinting that invalidates a review when the tree moves, circuit breakers that bound retries, and the repo ↔ vault ↔ tracker triangle. That is the part worth maintaining.

## Verdicts

### Adopt — first-party does this better

**`claude-security` vs `security:code-audit` + `@vuln-scanner` + `@finding-verifier`**

Its description: *"every finding challenged before it is reported and the verification tally computed in code… targeted patches, each verified by a panel of agents."* That is a superset of what `code-audit` does after XARI-92, and its tally is computed in code rather than asserted by a model — which is strictly more trustworthy than our version. It also offers effort tiers we don't have.

We shipped XARI-92 (2026-08-05) reimplementing the falsification pattern this plugin already had. That was not wasted — it taught us the asymmetry that matters, that a refuted-but-real finding is far more costly than a false positive — but it should not be re-derived a second time.

**Action:** trial `claude-security` against a repo with known findings, compare against `code-audit`, and if it holds up, make `code-audit` a thin dispatcher to it and keep only the wayworks-specific framing (severity gating, the Refuted section). Do not delete until the trial happens; an unverified swap of a security tool is worse than the duplication.

### Wrap — keep the interface, delegate the work

**`pr-review-toolkit` / `code-review` vs `qa:bug-review`, `edge-case-finder`, `regression-check`, `@regression-scanner`**

`pr-review-toolkit` ships review agents for comments, tests, error handling, type design, quality, and simplification. `code-review` adds confidence-based scoring to filter false positives. Together they cover most of what the `qa` plugin does, with more specialisation.

But `/loop-dev`'s `bugs` grader is a *gate* — its findings block the loop. The gate is ours; the reviewing doesn't have to be.

**Action:** keep the `bugs` grader name and its blocking semantics, change what it dispatches. Same shape as the `code-review` grader, which already dispatches Anthropic's bundled skill rather than a wayworks-authored one.

**`skill-creator` vs `shared:create-skill`**

`skill-creator` does more: creation, improvement, evals, and benchmark variance analysis. `create-skill` does none of that.

What `create-skill` uniquely carries is the *house pattern* — `Steps → Output Format → Constraints`, the ~300–450 word budget, quoted descriptions, `$ARGUMENTS` over positionals — which `scripts/lint-skills.sh` mechanically enforces. A skill scaffolded by `skill-creator` would fail our own linter.

**Action:** keep `create-skill` as the house-conformance layer, and point it at `skill-creator` for evals and benchmarking, which we have no answer to. Worth adding a line to that effect rather than leaving the gap silent.

### Keep — no real first-party equivalent

- **`harness`** (all four commands + hooks). `ralph-loop` is the nearest thing and is a different mechanism entirely: it repeats a task until the model judges it complete. The harness gates on *measurable* outcomes — a passing `.cc-verify`, a fingerprinted review marker — and refuses to stop until they hold. Self-assessed completion is exactly what the harness exists to not trust. This is the moat.
- **`feature-bank`.** Nothing first-party does spec-preflight/postflight gating on code edits.
- **`devops`** (`ci-pipeline`, `dockerfile`, `infra-review`), **`data-engineer`**, **`backend-dev`**, **`pm`**, **`tech-writer`**, **`test-builder`**. No first-party equivalents.
- **`architect`.** `feature-dev` covers architecture design inside a feature workflow, but nothing first-party writes or manages ADRs.
- **`shared:conventions`** and **`/wayworks-init`**. `claude-md-management` maintains CLAUDE.md quality and `claude-code-setup` recommends automations; neither installs a specific opinionated fleet. Complementary, not competing.
- **`design`** and **`frontend-dev`** review skills (`layout-review`, `heuristic-eval`, `accessibility-check`, `styling-review`). `frontend-design` *generates* interfaces; ours *review* them. Different direction. `component-builder` is the one genuine overlap on the generation side and is the weaker of the two — flag, don't rush.
- **`security:security-scan`.** Audits `.claude/` configuration. `security-guidance` reviews application code via hooks. Different targets.

## Two things this audit turned up

**`session-report` invalidates the XARI-93 rescope.** It generates a report of *"tokens, cache efficiency, subagents, skills, and the most expensive prompts"* from local `~/.claude/projects` transcripts.

XARI-93 asked for the grader panel's fan-out cost measured against real diffs. It was closed on 2026-08-05 with the reasoning that no available tooling could produce those numbers, and Systima's external multiplier was recorded instead — explicitly labelled as not a wayworks measurement. That reasoning was wrong: this plugin measures exactly that, from transcripts we already have. The measurement is now available, and `model-policy.md` says where to record it.

**`security-guidance` overlaps the harness security grader architecturally.** It runs pattern warnings on edits plus an LLM diff review *on Stop* — the same hook wayworks gates on. Two Stop hooks both reviewing security could double-report or interact badly. Not resolved here; worth checking before recommending both in one fleet.

## What this audit is not

A migration plan. Nothing has been adopted or deleted. Every "adopt" and "wrap" verdict above is a *trial*, and each one trades maintenance burden for a dependency on someone else's release cadence — the same cadence that silently degraded a grader in XARI-86. Owning a duplicate skill is a legitimate choice when the alternative is a gate you don't control.

Re-run this audit when the official marketplace adds plugins in wayworks' territory. Record the date above.
