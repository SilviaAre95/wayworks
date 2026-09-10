# First-party overlap audit

Audited 2026-08-05 against the 39 Anthropic-authored plugins in `claude-plugins-official`, the bundled skills (`/verify`, `/code-review`, `/doctor`, `/batch`, `/debug`, `/loop`, `/claude-api`), and `superpowers`.

wayworks was written when almost none of this existed. Some of it now does the same job, occasionally better. This records what overlaps, what the call was, and why — so the question isn't re-litigated from scratch every time the official marketplace grows.

## The rule this produced

**If deleting a skill would cost a *gate*, keep it. If it would only cost a *checklist*, delegate it.**

A checklist for OWASP or React review is something a capable model produces on request, and Anthropic now ships those first-party for free. What nobody else ships is the enforcement: Stop hooks that make "done" mean a passing command, marker fingerprinting that invalidates a review when the tree moves, circuit breakers that bound retries, and the repo ↔ vault ↔ tracker triangle. That is the part worth maintaining.

## Verdicts

### Adopt — first-party does this better

**`claude-security` vs `security:code-audit` + `@finding-verifier`**  
*(`@vuln-scanner` was removed in marketplace 5.0.0 — its OWASP list was a subset of `code-audit`'s own checklist, so it scanned the same ground twice.)*

Its description: *"every finding challenged before it is reported and the verification tally computed in code… targeted patches, each verified by a panel of agents."* That is a superset of what `code-audit` does after XARI-92, and its tally is computed in code rather than asserted by a model — which is strictly more trustworthy than our version. It also offers effort tiers we don't have.

We shipped XARI-92 (2026-08-05) reimplementing the falsification pattern this plugin already had. That was not wasted — it taught us the asymmetry that matters, that a refuted-but-real finding is far more costly than a false positive — but it should not be re-derived a second time.

**Action:** trial `claude-security` against a repo with known findings, compare against `code-audit`, and if it holds up, make `code-audit` a thin dispatcher to it and keep only the wayworks-specific framing (severity gating, the Refuted section). Do not delete until the trial happens; an unverified swap of a security tool is worse than the duplication.

### Wrap — keep the interface, delegate the work

**`pr-review-toolkit` / `code-review` vs `qa:bug-review`, `edge-case-finder`, `regression-check`**  
*(`@regression-scanner` was removed in marketplace 5.0.0 — its four steps were a strict subset of `regression-check`'s own.)*

`pr-review-toolkit` ships review agents for comments, tests, error handling, type design, quality, and simplification. `code-review` adds confidence-based scoring to filter false positives. Together they cover most of what the `qa` plugin does, with more specialisation.

But `/harness:loop-dev`'s `bugs` grader is a *gate* — its findings block the loop. The gate is ours; the reviewing doesn't have to be.

**Action:** keep the `bugs` grader name and its blocking semantics, change what it dispatches. Same shape as the `code-review` grader, which already dispatches Anthropic's bundled skill rather than a wayworks-authored one.

**`skill-creator` vs `shared:create-skill`**

`skill-creator` does more: creation, improvement, evals, and benchmark variance analysis. `create-skill` does none of that.

What `create-skill` uniquely carries is the *house pattern* — `Steps → Output Format → Constraints`, the ~300–450 word budget, quoted descriptions, `$ARGUMENTS` over positionals — which `scripts/lint-skills.sh` mechanically enforces. A skill scaffolded by `skill-creator` would fail our own linter.

**Action:** keep `create-skill` as the house-conformance layer, and point it at `skill-creator` for evals and benchmarking, which we have no answer to. Worth adding a line to that effect rather than leaving the gap silent.

### Keep — no real first-party equivalent

**`claude plugin validate` vs `scripts/lint-skills.sh`** — checked 2026-09-08 against Claude Code 2.1.263 (XARI-109).

The built-in has validated skill frontmatter since 2.1.77 and gained bare-`.claude/skills` scanning in 2.1.233, so the question was whether `lint-skills.sh` still earns its place. Measured on a fixture tree that breaks every rule the linter enforces:

| Fixture | `claude plugin validate --strict` | `lint-skills.sh` |
|---|---|---|
| Unterminated quote in `description` (whole block fails to parse) | error | error (as "must be quoted") |
| No frontmatter block | warning | error |
| Bare `description` containing `:` and `#` | silent | error |
| Missing `name` | silent | error |
| `name` ≠ directory | silent | error |
| Missing `user-invocable` | silent | error |
| Reads `$ARGUMENTS`, no `argument-hint` | silent | error |
| Positional `$0`/`$1` | silent | error |
| House keys fine, unrelated key `[unterminated` | silent | silent |
| Duplicate `description` key | silent | silent |

The built-in checks one thing: does the YAML block parse at all. It does not know or enforce any house rule, and it missed two of the three parse-failure variants tried. Its one genuine addition — a block where every house key is well-formed but some *other* line breaks the parse, so the runtime drops all metadata — is a class the awk linter cannot see and the built-in only sometimes does.

Scope also matters: run from the repo root it validates `marketplace.json` and **nothing else** — a marketplace fixture whose plugin contained broken skills passed clean. It scans `skills/` only when pointed at a plugin root or a skills directory directly.

**Verdict: keep `lint-skills.sh` unchanged.** Nothing to thin. `claude plugin validate --strict plugins/<name>` is worth running by hand before a release for the parse-failure class, and stays out of `make check` for the same reason `check-ruleset.sh` does: CI has no `claude` binary, and a step that silently skips in CI would make "`make check` is what CI runs" false.

- **`harness`** (all four commands + hooks). `ralph-loop` is the nearest thing and is a different mechanism entirely: it repeats a task until the model judges it complete. The harness gates on *measurable* outcomes — a passing `.cc-verify`, a fingerprinted review marker — and refuses to stop until they hold. Self-assessed completion is exactly what the harness exists to not trust. This is the moat.
- **`feature-bank`.** Nothing first-party does spec-preflight/postflight gating on code edits.
- **`devops`** (`ci-pipeline`, `dockerfile`, `infra-review`), **`data-engineer`**, **`backend-dev`**, **`pm`**, **`tech-writer`**, **`test-builder`**. No first-party equivalents.
- **`architect`.** `feature-dev` covers architecture design inside a feature workflow, but nothing first-party writes or manages ADRs.
- **`shared:conventions`** and **`/shared:wayworks-init`**. `claude-md-management` maintains CLAUDE.md quality and `claude-code-setup` recommends automations; neither installs a specific opinionated fleet. Complementary, not competing.
- **`design`** and **`frontend-dev`** review skills (`layout-review`, `heuristic-eval`, `accessibility-check`, `styling-review`). `frontend-design` *generates* interfaces; ours *review* them. Different direction. `component-builder` is the one genuine overlap on the generation side and is the weaker of the two — flag, don't rush.
- **`security:security-scan`.** Audits `.claude/` configuration. `security-guidance` reviews application code via hooks. Different targets.

## Two things this audit turned up

**`session-report` invalidates the XARI-93 rescope.** It generates a report of *"tokens, cache efficiency, subagents, skills, and the most expensive prompts"* from local `~/.claude/projects` transcripts.

XARI-93 asked for the grader panel's fan-out cost measured against real diffs. It was closed on 2026-08-05 with the reasoning that no available tooling could produce those numbers, and Systima's external multiplier was recorded instead — explicitly labelled as not a wayworks measurement. That reasoning was wrong: the numbers were sitting in local transcripts the whole time. **Measured and recorded 2026-09-08, refreshed 2026-09-10** in `model-policy.md`, by `scripts/measure-token-spend.py` rather than by this plugin — the transcripts are plain JSONL with `usage` objects, so no plugin is needed. The headline: subagents were ~5% of spend, and the external multiplier that stood in for a measurement pointed the wrong way for our traffic. `session-report` remains the better tool for per-prompt attribution, which the script does not do.

**`security-guidance` overlaps the harness security grader architecturally.** It runs pattern warnings on edits plus an LLM diff review *on Stop* — the same hook wayworks gates on. Two Stop hooks both reviewing security could double-report or interact badly. Not resolved here; worth checking before recommending both in one fleet.

## What this audit is not

A migration plan. Nothing has been adopted or deleted. Every "adopt" and "wrap" verdict above is a *trial*, and each one trades maintenance burden for a dependency on someone else's release cadence — the same cadence that silently degraded a grader in XARI-86. Owning a duplicate skill is a legitimate choice when the alternative is a gate you don't control.

Re-run this audit when the official marketplace adds plugins in wayworks' territory. Record the date above.
