# Changelog

All notable changes to the **wayworks** marketplace and its plugins.
Format follows [Keep a Changelog](https://keepachangelog.com/); the marketplace and each plugin follow [Semantic Versioning](https://semver.org/).

## Versioning policy

- **Per plugin** (`plugins/<name>/.claude-plugin/plugin.json` **and** its `marketplace.json` entry — keep them in sync): bump **patch** for fixes/docs, **minor** for new backward-compatible skills/commands/hooks, **major** for breaking changes to a plugin's interface.
- **Marketplace** (`metadata.version`): bump when the set of plugins changes or a plugin ships a notable release — generally the largest bump of that release.
- A **brand-new plugin** enters at `1.0.0`.
- Record every release below, newest first, grouped by plugin.

---

## [marketplace 4.2.0] — 2026-07-27

Quality-hooks release — write-time feedback loops, selectively ported from the ideas in [everything-claude-code](https://github.com/WorldFlowAI/everything-claude-code) rather than installing it wholesale (its agents/commands/rules duplicate the existing fleet).

### Added
- **`harness` `1.6.0`** — three always-on quality hooks (no arming needed, all with cheap no-op paths outside their scope): (1) **stray-doc gate** — `PreToolUse` on `Write`: creating a *new* `.md`/`.txt` outside the standard set (README/CLAUDE/AGENTS/CONTRIBUTING/CHANGELOG/LICENSE/SKILL basenames; `docs/`, `.claude/`, `.github/`, `skills/`, `commands/`, `agents/`, `memory/`, scratchpad paths) surfaces an explicit Approve prompt (`permissionDecision: ask`) instead of letting agent-generated summaries accumulate silently; (2) **write-time type-check** — `PostToolUse` on TS edits: runs the project's *own* `tsc --noEmit` (only when `tsconfig.json` and a local `node_modules/.bin/tsc` exist — never npx-installs) and feeds back up to 10 errors *in the edited file only*, so type breakage surfaces at edit time instead of at the loop's verify gate; (3) **console.log sweep** — `Stop`: non-blocking `systemMessage` warning listing modified tracked JS/TS files that still contain `console.log` — never blocks the stop; blocking stays the loop gates' job. Each hook ships its own dependency-free test suite (`test/block-stray-docs.test.sh`, `test/tsc-check.test.sh`, `test/console-log-scan.test.sh`).

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
