# Changelog

All notable changes to the **wayworks** marketplace and its plugins.
Format follows [Keep a Changelog](https://keepachangelog.com/); the marketplace and each plugin follow [Semantic Versioning](https://semver.org/).

## Versioning policy

- **Per plugin** (`plugins/<name>/.claude-plugin/plugin.json` **and** its `marketplace.json` entry — keep them in sync): bump **patch** for fixes/docs, **minor** for new backward-compatible skills/commands/hooks, **major** for breaking changes to a plugin's interface.
- **Marketplace** (`metadata.version`): bump when the set of plugins changes or a plugin ships a notable release — generally the largest bump of that release.
- A **brand-new plugin** enters at `1.0.0`.
- Record every release below, newest first, grouped by plugin.

---

## [marketplace 4.5.4] — 2026-08-09

Livelock fix — from the loop's first real end-to-end run.

### Fixed
- **`harness` `1.7.5`** — `/loop-dev`'s Stop gate no longer demands a reviews marker when there is nothing to review. It read "deterministic gate is green" as *"work is done and verified"* when on an empty diff it actually means *"no work exists"*, and then blocked the stop until a marker appeared. The only way to satisfy that is a marker certifying `code-review`, `security`, and `bugs` all passed on a change nobody made — indistinguishable afterwards from a real green run. Observed live: the same hook message fired three times in a row on a run that stopped at preflight, and the session could not exit.

  The marker's tree fingerprint already guards against edits landing *after* a stamp. This is the same failure reached from the other side — a stamp landing before any edits at all.

  The check is deliberately conservative: **untracked files count as work**, so a run that only added new files is still graded. Only loop-state files (`.cc-*`) are ignored, since they exist in every armed run. When there is genuinely nothing, the gate allows the stop and says why rather than exiting silently.

  Three of the six new tests assert the gate still *demands* reviews — for a tracked diff, for an untracked new file, and that loop state alone is not work. One pre-existing test (`hostile base: falls back to main`) had been relying on the old behaviour to reach the stamp message from a repo with no diff; its fixture now makes a change first, which is what it meant to test all along.

- **`harness` `1.7.5`** — the preflight now warns that enabling a plugin in `.claude/settings.json` is a no-op if it was never *installed* for that project, and tells you to verify by invoking rather than by reading config.

### Changed
- **`docs/reference/compatibility.md`** — `${CLAUDE_PLUGIN_ROOT}` inside `!` pre-execution is now **verified** against 2.1.226 (a real `/loop-dev` printed the preflight output in full), and a new section records that enabling ≠ installing: `settings.json` declares intent, `installed_plugins.json` records registration, and the gap is silent. Observed on `ristretto-ai`, where six of seven plugins auto-registered and the one that already had a cache directory from another project did not.

## [marketplace 4.5.3] — 2026-08-08

Arm fix — none of the three loops could start.

### Fixed
- **`harness` `1.7.4`** — `/loop-dev`, `/loop-build`, and `/loop-deploy` all armed with shell output redirection inside their `!` pre-execution block (`touch .cc-…-active && echo 0 > .cc-…-state`). Somewhere between Claude Code 2.1.222 and 2.1.226 that became a hard permission failure — *"Output redirection to '…/.cc-loop-dev-state' was blocked"* — so **no loop could arm at all**. Declaring `Bash(echo:*)` does not help: running `echo` and redirecting it into a file are checked separately, and the redirect is denied regardless of the working directory.

  Arming now runs through `hooks/scripts/loop-arm.sh`, and `allowed-tools` grants that script path instead of `touch`/`echo` — redirection inside a script is never parsed by the permission checker. Same shape as the preflight added in 1.7.0.

  The script also fails *loudly and completely*: if it cannot write, it removes any sentinel it already created and names the real cause ("start Claude Code from the repository root, or add this directory with `/add-dir`"). A sentinel without its state file arms the Stop hook against a loop that never initialised, which livelocks the session — strictly worse than not arming.

  Ships `test/loop-arm.test.sh` — 10 cases covering all three loops, stale-marker clearing, cross-loop isolation (arming `build` must not delete `dev`'s marker), bad and missing arguments, an unwritable directory, and the assertion that a failed arm leaves **no** partial state behind.

### Changed
- **`docs/reference/compatibility.md`** — verified version 2.1.222 → **2.1.226**, and records the redirection restriction plus a related trap: `cd` does **not** widen a session's write sandbox. Allowed directories are fixed at launch from the starting cwd, so `cd` into a repo and writing there still fails; launch from the repo root or use `/add-dir`.

## [marketplace 4.5.2] — 2026-08-07

Manifest fix — every plugin was failing to load one of its components.

### Fixed
- **All 14 plugins** (patch bump each) — removed the `commands`, `skills`, and `hooks` keys from every `plugin.json`. Claude Code auto-discovers `commands/`, `skills/`, `agents/`, and `hooks/hooks.json`; declaring those same paths makes it load them twice, and the second load is a hard error: *"Duplicate hooks file detected … The standard hooks/hooks.json is loaded automatically, so manifest.hooks should only reference additional hook files."* Every enabled wayworks plugin showed **"Needs attention · 1 error"** in `/plugin`, and `harness` failed to load its hooks entirely — meaning the Stop gates the whole harness depends on were not being registered.

  Every declared path was the conventional one (`./skills/`, `./commands/`, `./hooks/hooks.json`), so all 14 were pure redundancy. `architect` already had an undeclared `agents/` directory that loaded fine, which is the proof the convention needs no declaration. Anthropic's own plugins declare none of these keys.

  **CI was green the entire time this shipped.** The manifests were valid JSON and every declared path resolved — `scripts/check.sh` had nothing to object to, because it validated our expectations rather than Claude Code's loader. The failure was visible only in `/plugin` in a live session. `check.sh` now rejects the conventional paths in any of their spellings (`./skills/`, `./skills`, `skills/`, `skills`) while still allowing genuinely additional ones, such as `hooks: "./hooks/extra.json"`.

### Added
- **`docs/reference/compatibility.md`** — three contracts learned the hard way: manifests must declare only non-conventional paths; plugin updates need a **session restart** because commands register at session start (and `installed_plugins.json` pins version + commit *per project*, so one project can sit stale while another is current); and plugin slash commands are **namespaced** — `harness:loop-dev`, not `loop-dev`.

## [marketplace 4.5.1] — 2026-08-06

### Fixed
- **README** — the documented core fleet omitted `qa`, while the default `.cc-dev.yaml` template ships `graders: [code-review, security, bugs]` and `bugs` maps to `qa:bug-review`. Anyone following wayworks' own setup instructions therefore got a grader that silently never ran, and the reviews marker stamps regardless, so nothing surfaced the short panel. Found in `ristretto-ai`, which had been running two of its three configured graders. `qa` is now core, with a note saying *why* `security` and `qa` are core rather than leaving it to be rediscovered.
- **`harness` `1.7.2`** — the `/loop-dev` preflight now prints the plugin each configured grader needs, not just the grader names. "`bugs` did not resolve" is not actionable on its own; "`bugs -> qa:bug-review (needs qa@wayworks)`" is. The mapping was previously only in `loop-dev.md` prose, so diagnosing a missing grader meant going to read the command file. `templates/.cc-dev.yaml` carries the same mapping inline, where someone editing the grader list will actually see it.

## [marketplace 4.5.0] — 2026-08-06

### Added
- **`devops` `1.1.0`** — new `repo-protection` skill: generate or review GitHub repository protection, mirroring how `ci-pipeline` generates or reviews CI configs. Covers the whole surface rather than branch rules alone — default-branch ruleset (deletion, force-push, required reviews, required status checks), secret scanning and push protection, vulnerability alerts and Dependabot security updates, and Actions token hardening. Ships `templates/ruleset-oss.json` and `templates/ruleset-private.json`.

  The two presets differ on one real decision: the private/solo template **drops the review requirement**. An approval only you can grant is ceremony bypassed on every merge, and a rule routinely bypassed trains its owner to ignore the prompt. History protection and green CI still hold, and the rule goes back the moment a second person can review.

  Three constraints encode failures already seen in this repo: required status checks are derived from *observed check runs*, never guessed from workflow YAML, because a required context nothing produces parks every PR at "Expected — waiting for status to be reported" (wayworks hit exactly this between PRs #26 and #27, and merged past two stranded checks unnoticed); `bypass_actors` must not be empty on a solo repo or the maintainer cannot merge their own work; and `PUT /rulesets/<id>` replaces the entire rules array, so the existing ruleset is read and merged rather than blind-written.

## [marketplace 4.4.1] — 2026-08-05

### Added
- **`docs/reference/compatibility.md`** — what wayworks depends on from Claude Code, and what breaks silently when those contracts change. Skills are portable prose; the gates are not. Records the version last verified against (2.1.222), the hook surface the loops are built on (events, `{decision, reason}` output at 14 sites, `hookSpecificOutput`/`permissionDecision`, `stop_hook_active`), `${CLAUDE_PLUGIN_ROOT}` expansion, bundled-skill invocation, and the frontmatter keys in use. The failure mode it exists for: a `Stop` hook whose output is no longer understood does not error — it stops blocking, and the loop reports success as if every gate passed.

  It also records the rule that upstream-drift issues are leads rather than specifications. Three of five in the 2026-08-05 batch were materially wrong — a command that did not exist, a file deleted weeks earlier, and a measurement no available tooling could produce — so a verification step now precedes acting on any of them. Cross-linked from `AGENTS.md` and `model-policy.md`.

### Fixed
- **`harness` `1.7.1`** — `/loop-dev` scoped its preflight permission from `Bash(bash:*)` down to the single script path, matching the pattern Anthropic's own `ralph-loop` uses. The broad form granted the command permission to run *any* bash command; only the preflight was ever intended. Found while cataloguing the `${CLAUDE_PLUGIN_ROOT}` contract for the compatibility record.

## [marketplace 4.4.0] — 2026-08-05

Fail-early release — `/loop-dev` validates its configuration before it builds, not after.

### Added
- **`harness` `1.7.0`** — arm-time config preflight for `/loop-dev` (`hooks/scripts/loop-dev-preflight.sh`). Every condition it checks was previously discovered at the *review* stage, meaning a full implementation had already been written and committed before the loop reported that it could not finish. Blocking conditions: a `base` that does not resolve (the reviews marker is anchored on `git merge-base <base> HEAD`, so it fails at stamp time — after the work); no `.cc-verify` in a repo with no `package.json` (the gate falls back to `npm run lint && npm run build && npm test`, which such a repo can never make green); an empty `.cc-verify`; a `graders:` key with no value; and a loop-state file tracked by git, which invalidates its own fingerprint and livelocks the Stop hook. Non-blocking warnings cover a stale marker, a base that exists only on the remote, and `open_pr` with `gh` missing or unauthenticated.

  The split is deliberate. A shell script cannot see which plugins are enabled in a session, so it cannot tell whether a configured grader resolves to an available skill — it prints the grader list and `loop-dev.md` makes the agent check that half, stopping if any name does not resolve. That is the failure this was built for: a `.cc-dev.yaml` declaring `graders: [code-review, security, bugs]` in a session without `qa@wayworks` silently loses the `bugs` grader, and the marker still stamps, so nothing downstream notices the panel ran short.

  Ships with `test/loop-dev-preflight.test.sh` — 10 cases asserting each blocking condition blocks and each legitimate setup passes, including a Node repo that may rightly rely on the npm default. A preflight that always exits 0 is worse than none, since it reads as confirmation.

## [marketplace 4.3.0] — 2026-08-05

Falsification release — `code-audit` stops shipping unverified findings.

### Added
- **`security` `1.1.0`** — new `finding-verifier` sub-agent, and a verification pass in `code-audit` that uses it. The checklist audit was single-pass, so every finding inherited that pass's false-positive rate with nothing downstream to catch it. Each **Critical** and **High** finding is now handed to an independent verifier subagent (one per finding, dispatched concurrently) whose only job is to try to disprove it: trace where the value actually originates, whether it truly reaches the sensitive operation, and whether a framework, an upstream guard, or unreachability already mitigates it. Medium and Low skip the pass — the cost outweighs their blast radius. `--no-verify` skips it entirely (XARI-92).

  Three decisions worth knowing, because the naive version of this feature is dangerous:

  - **The verifier is a separate agent, not a second pass in the same context.** A model that has just argued for a finding is the worst available judge of it. The verifier is given the claim, its severity, and its `file:line` — deliberately *not* the reasoning that produced it — so it re-reads the code rather than grading an argument.
  - **The default is that the finding stands.** This inverts the usual adversarial-verify pattern, which biases toward refutation. Here the asymmetry runs the other way: a false positive costs the reader a few minutes of triage, while a real vulnerability argued away vanishes from the report and nothing catches it again. Refutation requires a concrete, checkable reason; "seems unlikely" and exploit difficulty are explicitly not grounds, and a partly-wrong finding returns `stands` with a correction rather than being dropped.
  - **Refuted findings are demoted, never deleted.** They appear in a new **Refuted** report section with the verifier's reasoning, and the Risk Summary states how many candidates were verified and how many refuted — so a wrong refutation is visible and reviewable instead of silent.

  `finding-verifier` is the only wayworks agent with no `model:` pin, inheriting the session model instead. Disproving a Critical/High security finding is judgment-heavy adversarial work, and a cheaper model that rubber-stamps or over-refutes is worse than running no verification at all — the same reasoning that keeps the `security` grader off mid-tier. Documented in `docs/reference/model-policy.md`.

## [marketplace 4.2.3] — 2026-08-05

### Fixed
- **`security` `1.0.4`** — `security-scan` now actually consumes its arguments. It advertised `argument-hint: "[path-to-.claude-dir] [--min-severity low|medium|high]"` but never referenced `$ARGUMENTS`, so `/security-scan ~/proj/.claude --min-severity high` silently scanned the current directory at default severity — the user believed they had scoped the scan and had not. Root cause was structural: the skill was a pure CLI reference with no instruction for what to run when invoked, so there was nothing for the arguments to reach. Adds a "Running the scan" section that parses the argument string and builds the command from it (bare path → `--path`, `--min-severity` restricted to `low`/`medium`/`high`, empty → current project). A non-existent path now stops the run rather than falling back to the current directory and reporting a clean grade for somewhere the user never named (XARI-104).

  The parse is deliberately an allowlist, not an interpolation: these values reach a shell command, so substituting the raw argument string would have made a security skill's own entry point a command-injection vector. Shell metacharacters, unrecognized flags, and extra positionals stop the run. `--format`, `--fix`, and `--opus` remain documented CLI capabilities and are intentionally *not* argument-wired — `--fix` mutates configuration files, which should not be reachable by a mistyped slash command.

## [marketplace 4.2.2] — 2026-08-05

Frontmatter-lint release — skills can no longer drift out of the house pattern unnoticed.

### Added
- **`scripts/lint-skills.sh`** — dependency-free frontmatter linter over all 43 skills and 6 commands, wired into `scripts/check.sh` so it runs in `make check` and CI. Errors: missing/mismatched `name`, missing or unquoted `description` (a bare scalar containing a colon or `#` breaks the parse silently), missing or non-boolean `user-invocable`, a skill that reads `$ARGUMENTS` without declaring `argument-hint`, and positional `$0`/`$1` anywhere. Warnings that never fail the build: descriptions over 250 chars, and an `argument-hint` the body never reads. Ships with `scripts/lint-skills.test.sh` — 18 fixture-driven cases asserting every violation class actually fails and every legitimate exception actually passes, because a linter whose field extractor silently returned empty would report the whole repo clean (XARI-51, absorbing XARI-55).

  Three rules are shaped by what the repo actually contains rather than by the abstract pattern: skills nest (the five `shared/stack-profiles/*` live a level deeper than the obvious glob reaches), `argument-hint` is tied to whether a skill *reads* `$ARGUMENTS` rather than to invocability (some invocable skills legitimately take none, and requiring a hint would document an argument that does not exist), and the positional-argument check exempts `shared:create-skill`, whose prose documents the prohibition it would otherwise be flagged for.

### Fixed
- **`feature-bank` `1.2.1`** — frontmatter was the repo's only house-pattern violation: an unquoted `description` (parse-fragile, and it contains 16 double quotes) and no `user-invocable`. Now single-quoted and explicitly `user-invocable: true`, matching the `/feature-bank` command the README already documents. Its 948-char description is deliberately left intact — that description *is* the skill's model-invocation trigger surface, listing the phrasings that make it auto-fire, so trimming it to the 250-char house guidance would degrade the behavior the skill exists to provide. The linter reports it as a warning.

### Known
- `security:security-scan` declares `argument-hint: "[path-to-.claude-dir] [--min-severity low|medium|high]"` but never reads `$ARGUMENTS`, so arguments typed after the command are silently discarded. Surfaced by the new linter as a warning; the fix changes skill behavior and belongs in its own PR against the `security` plugin.

## [marketplace 4.2.1] — 2026-08-05

Upstream-drift release — three external changes (Claude Code v2.1.215, `actions/checkout` defaults, `ollama launch`) that each invalidated an assumption written into a plugin or doc.

### Fixed
- **`harness` `1.6.1`** — `/loop-dev`'s default `code-review` grader no longer relies on description-matching to fire Anthropic's bundled `/code-review` skill. Claude Code v2.1.215 stopped auto-running the bundled `/verify` and `/code-review` skills, so step 5's old "(or the `/code-review` skill)" phrasing could silently degrade into an improvised generic review — undetectable downstream, because the reviews marker stamps as long as *a* review happened. The dispatched subagent is now told to invoke the slash command by name and to report a missing command rather than substitute for it. `README.md` gains an upgrade-sensitivity note, since this grader's behavior is set by Claude Code's bundled-skill policy, not by this plugin (XARI-86).
- **`devops` `1.0.2`** — `ci-pipeline` gains a "pwn request" review check. The skill both generates and reviews GitHub Actions configs, but had no guard against the classic `pull_request_target`/`workflow_run` privilege-escalation shape: a privileged workflow that checks out the fork's ref and then executes it. Review mode now flags that pattern with the exploitable YAML shape and three concrete remediations, and notes that `actions/checkout` blocks the fetch by default as of 2026-07-20 — so an affected workflow may now be *failing* rather than merely unsafe (XARI-87).
- **`docs/reference/model-policy.md`** — grader tier table pointed at `loop-dev.md` "step 4"; the review stages are step 5.

### Changed
- **`docs/reference/model-policy.md`** — the local-model section now leads with `ollama launch claude` (Ollama v0.15+, no env vars or config files) instead of the manual LiteLLM-proxy setup, and documents the direct `ANTHROPIC_BASE_URL=http://localhost:11434` path as the no-launcher alternative — Ollama's endpoint is Anthropic-compatible, so the intermediate proxy was never required. Adds the 64k-context guidance and flags multi-turn tool-call reliability (not raw model quality) as the binding constraint for running skill files locally. The architectural limit is unchanged and restated: Claude Code still cannot route individual stages or graders to a local model, only whole sessions — `ollama launch` solves setup, not routing (XARI-88).
- **`docs/reference/model-policy.md`** — records Systima's published subagent fan-out measurement (2.6×–5.9× tokens vs. sequential) next to the tiering table, explicitly attributed as *external* data rather than a wayworks measurement, with no threshold changes: our own panel has never been instrumented, and the grader-scaling heuristics stay as-is until it is (XARI-93).

## [marketplace 4.2.0] — 2026-07-27

Quality-hooks release — write-time feedback loops, selectively ported from the ideas in [everything-claude-code](https://github.com/WorldFlowAI/everything-claude-code) rather than installing it wholesale (its agents/commands/rules duplicate the existing fleet).

### Added
- **`harness` `1.6.0`** — three always-on quality hooks (no arming needed, all with cheap no-op paths outside their scope): (1) **stray-doc gate** — `PreToolUse` on `Write`: creating a *new* `.md`/`.txt` outside the standard set (README/CLAUDE/AGENTS/CONTRIBUTING/CHANGELOG/LICENSE/SKILL basenames; `docs/`, `.claude/`, `.github/`, `skills/`, `commands/`, `agents/`, `memory/`, scratchpad paths) surfaces an explicit Approve prompt (`permissionDecision: ask`) instead of letting agent-generated summaries accumulate silently; (2) **write-time type-check** — `PostToolUse` on TS edits: runs the project's *own* `tsc --noEmit` (only when `tsconfig.json` and a local `node_modules/.bin/tsc` exist — never npx-installs) and feeds back up to 10 errors *in the edited file only*, so type breakage surfaces at edit time instead of at the loop's verify gate; (3) **console.log sweep** — `Stop`: non-blocking `systemMessage` warning listing modified tracked JS/TS files that still contain `console.log` — never blocks the stop; blocking stays the loop gates' job. Each hook ships its own dependency-free test suite (`test/block-stray-docs.test.sh`, `test/tsc-check.test.sh`, `test/console-log-scan.test.sh`).

## [shared 2.1.3] — 2026-07-28

### Added
- **`create-skill`** — context-engineering verbosity note for Claude 5+ models. Anthropic deleted ~80% of system prompt text with no eval loss; the note documents when the house pattern's structure is load-bearing vs potentially redundant on newer frontier models, without changing the mandatory template itself. Refer to `claude doctor` (`/doctor`) for skill diagnostics before shipping.

## [marketplace 4.1.1] — 2026-07-20

Loop-durability release — five failure modes observed across production runs (kaffecard XARI-70/71).

### Fixed
- **`harness` `1.5.1`** — `/loop-dev` hardening from live runs that shipped the wrong change twice and lost an hour of finished work. (1) **Read the task**: the loop is routinely handed a bare tracker issue key as its entire task; it now reads the issue whenever one is named (Linear MCP `get_issue`, else `gh issue view`) — the ticket adds requirements the task omitted but never redirects the work, and a genuine task/ticket conflict stops the run. For a *bare* key it is the spec outright, so an unreadable one **stops** the run: previously the loop reconstructed scope from the branch name and shipped plausible, well-reviewed, wrong changes that passed every downstream gate. The PR stage no longer assumes a tracker key exists, so self-contained tasks finish without a Linear update. (2) **Commit before reviews**: the implementation is committed at the end of the build stage, so a run killed at its wall-clock limit no longer loses uncommitted work. (3) **Branch discipline**: work stays on the checked-out branch — no creating, switching, or pushing an invented branch name, which breaks the PR-first lookup that makes re-runs idempotent. (4) **Never stage blindly**: explicit paths only, never `git add -A`/`git add .` (they sweep unrelated edits and stale index entries into a PR), and loop-state files stay untracked — a tracked marker invalidates its own fingerprint and livelocks the gate. (5) **Grader dedup**: exactly one subagent per grader per round, and re-review re-runs only the graders whose findings were fixed — plus `security` whenever a fix touches any surface the panel rule calls security-relevant (executable code, hooks, auth/permissions, deploy templates, secrets handling), since a fix aimed at one grader's finding routinely lands in another's domain.

## [marketplace 4.1.0] — 2026-07-17

Pipeline-gaps release — closes the gaps between the documented way-of-working and what the loops actually execute (2026-07-17 inspection).

### Added
- **`harness` `1.5.0`** — `/loop-dev` grows three stages of coverage: (1) **`--plan <path>`** hands the loop a written implementation plan (e.g. superpowers `writing-plans` output) instead of the loop's own short plan — the documented handoff from brainstorm/spec to the loop; (2) a **dev-test stage** between reviews and finish that exercises the change the way the product is used — the feature spec's `test_plan` first, else stack-inferred (browser flow via built-in tooling/`chrome-devtools-mcp`, endpoint checks, or `data-engineer:pipeline-verify` for pipelines) — recorded as the PR's "How verified"; (3) **PR CI watch** (`gh pr checks --watch --fail-fast`) — red checks are loop work, Slack ping only after green. Grader panel is now extensible: `design` maps to `design:layout-review` (+`heuristic-eval` for new flows), any other grader name maps to the same-named skill, unknown names stop the loop instead of being skipped. The finish stage now runs the `feature-bank` postflight (Gate 3) before stamping the reviews marker, so spec docs are fingerprinted with the code. `/loop-deploy` success is now a **knowledge sync**: repo docs confirmed current, a dated log line appended to the project's vault note (when a vault is declared), Linear issue to Done — then the Slack announce. `templates/.cc-dev.yaml` documents the `design` grader and `max_review_rounds`.
- **`feature-bank` `1.2.0`** — optional `test_plan:` frontmatter field on feature specs: concrete, agent-executable dev checks (flows to drive, commands over sample data), consumed by `/loop-dev`'s dev-test stage; scaffolding proposes it, postflight runs it.
- **`data-engineer` `1.1.0`** — new `/pipeline-verify` skill: run a pipeline against a bounded sample in dev and assert schema conformance, row accounting (in = out + rejected), null/dupe rates, DLQ state, idempotency on re-run, and clean logs. The data-platform counterpart of driving a web app in a browser.
- **`docs/reference/model-policy.md`** — which model runs which stage (grader tiers, agent pins, frontmatter pinning rules) and the local-model path (per-session proxy; stages can't route to local models).

### Fixed
- **`security` `1.0.3`** — `security-scan` no longer claims a dated model version for the external scanner's `--opus` mode.
- README: stale `/web-verify` reference from before the 4.0.0 web-tester removal; settings template now includes `superpowers@claude-plugins-official` (matching `/wayworks-init`); CLAUDE.md plugin count 15 → 14.

## [marketplace 4.0.1] — 2026-07-16

### Fixed
- **`shared` `2.1.2`** — `expo-mobile` stack profile gains a **Testing** section: jest-expo's major is locked to the Expo SDK major (SDK 57 ↔ jest-expo ~57), so test deps must be installed with `npx expo install jest-expo jest` and re-checked with `npx expo install --check` after SDK upgrades — a stale jest-expo fails install with an `ERESOLVE` peer conflict (XARI-83).

## [marketplace 4.0.0] — 2026-07-16

### Removed
- **`web-tester`** (breaking — the plugin set shrinks to 14). Its single skill (`/web-verify`, Playwright-MCP browser verification) is superseded three ways: Claude's built-in browser tooling (Claude in Chrome), the official `chrome-devtools-mcp` plugin in the Anthropic marketplace, and the `vercel` plugin's full-story `verification` skill. If you depend on `/web-verify`, install `chrome-devtools-mcp` and drive the same flow from its browser tools.

### Changed
- **`shared` `2.1.1`** — `/wayworks-init` no longer recommends `web-tester` for web frontends; points at the built-in browser tooling / `chrome-devtools-mcp` instead.

## [marketplace 3.4.1] — 2026-07-16

### Fixed
- **`harness` `1.4.1`** — Vercel deploy config no longer assumes a single app (XARI-82). `/harness-init` deploy-target detection now distinguishes a root-linked single Vercel app from a monorepo with app-level links (`apps/*/.vercel`, `apps/*/vercel.json`, …), which it previously missed entirely. For monorepos it rewrites the whole config: `deploy` scoped per app with Vercel's global `--cwd <app-dir>` flag and chained with `&&`, `watch` set to `"true"` (chained deploys already block; the root-scoped default fails with no root link), `verify` composing every app's checks, and `rollback` per app via a flag chain (`r=0; … || r=1; …; test $r -eq 0`) so every rollback is attempted and any single failure still fails the whole command (`&&` would skip apps; `;` would mask failures from the gate's rolled-back-vs-act-now verdict) — confirming the app list with the user (an app missing from `rollback` stays broken on rollback). Because these strings are later `eval`'d by the deploy gate, detected app paths are restricted to `[A-Za-z0-9._/-]+`; anything else falls back to user-written commands. Multiple matching targets (e.g. Railway root + Vercel apps) are surfaced instead of silently picking one. `templates/.cc-deploy.vercel.yaml` documents the single-app assumption and shows the monorepo shape.

## [marketplace 3.4.0] — 2026-07-16

### Changed
- **`harness` `1.4.0`** — loop-dev token-efficiency release, from an audit of the first four production runs (~840k output tokens for 3 PRs). (1) **Grader scaling**: the review panel now scales to the diff — docs-only diffs run `code-review` alone, small non-sensitive code diffs skip `security`, and the full panel still always runs when the diff touches hooks, auth, deploy templates, or secrets handling. (2) **Grader model tiers**: `code-review`/`bugs` graders may run on a mid-tier model when the dispatch tool supports it; `security` always inherits the session model. (3) **Review circuit breaker**: grading is now bounded like the deterministic gate — after `max_review_rounds` (`.cc-dev.yaml`, default 3) stop attempts without a clean stamped marker, the gate disarms and instructs the agent to summarize outstanding findings instead of dispatching more graders (previously unbounded; only wall-clock limits contained a non-converging grade-fix loop). New transient state file `.cc-loop-dev-rounds` (gitignored via `/harness-init`, reset on arm).

## [marketplace 3.3.1] — 2026-07-15

### Fixed
- **`harness` `1.3.1`** — Stop-gate race hardening (XARI-81). All three loop gates now serialize on a shared mkdir-based mutex (`.cc-loop-gate.lock`, stale-lock recovery by holder PID), so Stop-parallel sibling gates and overlapping sessions can no longer run the verify command concurrently, double-count attempts, or race the sentinel/marker deletions; a contended lock blocks without consuming a retry. `/loop-dev`'s reviews marker is now stamped with the merge-base anchor commit plus a working-tree fingerprint against it, and re-verified at stop time **against the stored anchor** — changes landing after the graders passed (late background jobs, extra commits) invalidate the marker and force a re-review instead of silently bypassing it, and a moving base ref (`base: HEAD`, or the checked-out branch itself) cannot collapse the check. A non-empty marker that is not the two-line stamped format fails closed (treated as stale). Empty (`touch`ed) markers remain accepted as the non-git/legacy escape hatch; the fingerprint is commit-invariant on feature branches (tracked files only — untracked-only changes are not fingerprinted). Stale locks are stolen by atomic rename (never `rm`+`mkdir`, which let two contenders both acquire) and the lock is released on hook timeout/interrupt, not just clean exit. `.cc-dev.yaml` `base:` is quote-stripped like the deploy config and validated against a ref-name charset before reaching `git merge-base` or the stamp command echoed to the agent (a quoted `base: "main"` used to silently disable the check; a hostile value could inject shell). `/harness-init` now gitignores `.cc-loop-gate.lock*` in consumer projects. Gate tests pin `CLAUDE_PROJECT_DIR` to their temp dirs — under a Stop hook the env leaks the real project dir, making the gates recurse into the armed loop instead of the test fixture.

## [marketplace 3.3.0] — 2026-07-12

### Changed
- **`harness` `1.3.0`** — `/loop-dev` step 6 is idempotent: reuse an existing open PR for the branch (never create a second) and skip the Linear PR comment when one already exists. Required for durable kanban re-runs (ristretto durable-dev-work spec, Guards 1–2).

## [marketplace 3.2.0] — 2026-07-10

### Changed
- **`harness` `1.2.0`** — `/harness-init` now **detects the deploy target** instead of defaulting to Vercel. It writes a Railway config when it sees `railway.json`/`railway.toml`, a Vercel config when it sees `vercel.json`/`.vercel/`, and otherwise a neutral default whose `deploy`/`verify`/`rollback` commands are guarded to exit non-zero until filled in — so an unconfigured deploy loop refuses to run rather than silently "succeeding". Adds `templates/.cc-deploy.railway.yaml` and `templates/.cc-deploy.vercel.yaml`; the generic `templates/.cc-deploy.yaml` is now the provider-neutral fallback.

## [marketplace 3.1.0] — 2026-07-10

Open-source readiness release.

### Added
- **CONTRIBUTING.md** — philosophy, skill scaffolding, the CI-enforced release rule, PR expectations.
- **README "How it's used"** — one-time setup, per-project bootstrap/onboarding, daily loops, and the adaptability story.

### Changed
- **`shared` `2.1.0`** — `/wayworks-onboard`: the tracker vertex is now explicitly pluggable (recommended order: Obsidian backlog in the vault note → any connected tracker/GitHub Issues → `docs/BACKLOG.md`); Obsidian stays the recommended knowledge core but is never required. Both `/wayworks-onboard` and `/wayworks-init` gain **branch discipline**: config commits go to a `chore/` branch + PR when a remote exists, never onto whatever feature branch the repo happens to be on.
- Historical design doc sanitized of absolute personal paths.

## [marketplace 3.0.0] — 2026-07-10

**The project is now `wayworks`** (was `xari-plugins`) — an open-source way of work for AI-assisted building: plugins + second-brain (Obsidian) support + tracker (Linear) integration.

### Breaking / Migration
- Marketplace renamed: every consumer key changes from `<plugin>@xari-plugins` to `<plugin>@wayworks`, and the marketplace source is now `SilviaAre95/wayworks` (old GitHub URLs redirect). Update `.claude/settings.json`: `extraKnownMarketplaces` entry + all `enabledPlugins` keys.
- **`shared` `2.0.0`** — commands renamed: `/xari-init` → `/wayworks-init`, `/xari-onboard` → `/wayworks-onboard`. The CLAUDE.md header they scaffold is now `## Wayworks config`.

### Changed
- All plugin `repository` URLs, README, and docs updated to the new identity. Historical CHANGELOG entries below intentionally keep the old name.

## [marketplace 2.0.1] — 2026-07-09

### Fixed
- **All skills standardized on `$ARGUMENTS`** — 24 skills across 10 plugins dropped positional `$0`/`$1` interpolation (which only populates for typed slash commands and leaks literally when the model invokes a skill). `shared/create-skill` `1.3.2` now teaches `$ARGUMENTS`-only. Patch bumps: backend-dev/data-engineer/design/devops/pm/qa/test-builder 1.0.1, frontend-dev 1.1.1, security 1.0.2, tech-writer 2.0.1.

## [marketplace 2.0.0] — 2026-07-09

Consolidation release (context-budget lean-up). **Breaking**: two plugins removed.

### Breaking / Migration
- **`ui-designer` and `ux-researcher` removed** — merged into the new **`design` `1.0.0`** plugin. Migrate `.claude/settings.json`: replace `ui-designer@xari-plugins` / `ux-researcher@xari-plugins` with `design@xari-plugins`.
- **`tech-writer` `2.0.0`** — `adr-template` skill removed; its init/list/status modes now live in `architect/adr-writer`.

### Changed
- **`design` `1.0.0`** — 4 skills: `layout-review` (absorbs `responsive-audit`: mobile-first checks, breakpoint matrix, touch targets), `design-system`, `heuristic-eval`, `user-flow-analysis`.
- **`frontend-dev` `1.1.0`** — `accessibility-check` gains an `experience` mode (the former `ux-researcher/accessibility-audit`: screen-reader/keyboard/low-vision/motor/cognitive walkthroughs) alongside WCAG code compliance.
- **`architect` `1.1.0`** — `adr-writer` absorbs ADR infrastructure setup + list/status modes; one ADR skill instead of two.
- **`feature-bank` `1.1.0`** — SKILL.md trimmed 2,309 → 800 words via progressive disclosure; full backfill flow, spec format, and worked examples moved to `references/` (loaded only when needed). Frontmatter unchanged, so triggering is identical.
- **`shared` `1.3.1`** — `/xari-init` fleet list references `design` instead of `ui-designer`.
- README: core vs extended plugin tiers documented. Counts: 15 plugins / 43 skills. Closes XARI-73 (and XARI-54 via the ADR merge).

## [marketplace 1.4.0] — 2026-07-09

### Changed
- **`shared` `1.3.0`** — `conventions` is now language-agnostic (simplicity-first, error handling, commits, review checklist); TypeScript/React/Tailwind/Prisma specifics moved into the `nextjs-vercel` stack profile where they auto-load only in matching repos. New `expo-mobile` stack profile (Expo Router, secure storage, permissions, EAS) — mobile conventions no longer squat in a web profile. Closes XARI-72.

## [marketplace 1.3.1] — 2026-07-09

### Fixed
- **`security` `1.0.1`** — `security-scan` frontmatter normalized to house standard (quoted description, `user-invocable`, `argument-hint`; non-standard `origin` key removed) and its external `ecc-agentshield` dependency surfaced explicitly: not bundled, `npx` downloads on first run, fail-and-report if unavailable, version-pinning advised for CI. Closes XARI-52.

## [marketplace 1.3.0] — 2026-07-09

### Added
- **`shared` `1.2.0`** — new `/xari-onboard` command: onboard a project from any starting point (existing repo, existing vault note, or a bare idea) into the linked triangle **Linear project ↔ vault note ↔ repo**. Takes inventory first, creates only what's missing (knowledge → tracking → code), wires the cross-links idempotently, and degrades gracefully for users without an Obsidian vault or Linear connection.

## [marketplace 1.2.0] — 2026-07-09

### Added
- **`web-tester` plugin `1.0.0`** — live web-app verification. Declares the marketplace's first MCP server (Playwright, headless via `npx @playwright/mcp`) and ships `/web-verify`: drive the critical user flow in a real browser, assert console + network are clean, screenshot evidence.
- **`shared` `1.1.0`** — new `/xari-init` command: bootstrap any repo as a xari workspace (plugin fleet in `.claude/settings.json` via `extraKnownMarketplaces` + `enabledPlugins`, CLAUDE.md header template with stack/vault-note/Linear/verify pointers, harness handoff).

### Fixed
- **README** backfilled to reality (was 13 plugins/38 skills): now 16 plugins / 45 skills, documents `harness`, `feature-bank`, `web-tester`, and `security-scan`; settings templates corrected from the invalid `"plugins": []` key to the real `enabledPlugins` schema.

## [marketplace 1.1.0] — 2026-07-08

### Added
- **`feature-bank` plugin `1.0.0`** — source-of-truth feature specs with preflight/postflight gates that stop agent drift; ships a portable `check-bank.sh` validator.
- **`harness` `1.1.0`** — two new commands extending the build-test-fix loop into a full work-loop system:
  - **`/loop-dev`** — staged verification loop: spec preflight → plan (`--check-plan` autonomy dial) → build → code-review / security / bug-hunt subagents → fix → PR. A `Stop` hook enforces the deterministic gate (`.cc-verify`) plus a reviews-passed marker; circuit breaker after `max_retries`. Config in `.cc-dev.yaml`.
  - **`/loop-deploy`** — production verify loop: deploy → watch → verify (health + smoke + error-rate) → fix→redeploy until healthy; after `max_redeploys` it runs `rollback` and escalates, so an exhausted loop never leaves prod broken. Prod deploy + DB migrations are hard Approve/Deny gates. Config in `.cc-deploy.yaml`.
  - `harness-init` now scaffolds `.cc-dev.yaml` / `.cc-deploy.yaml` and git-ignores the new loop state files.

## [harness 1.0.0] — earlier

### Added
- **`harness` plugin** — tiered autonomy (explore / build / ship / escape) + the `/loop-build` build-test-fix loop with a `Stop`-hook verify gate and circuit breaker.
- **`security` `security-scan` skill** — supply-chain scan via `ecc-agentshield`.

## [marketplace 1.0.0] — 2026-04-08

### Added
- Initial release: 13 plugins (`shared`, `architect`, `ui-designer`, `ux-researcher`, `backend-dev`, `frontend-dev`, `data-engineer`, `test-builder`, `qa`, `security`, `devops`, `tech-writer`, `pm`) — 39 skills, 5 sub-agents, 4 stack profiles.
