# Compatibility

What wayworks depends on from Claude Code, and what breaks when those change.

Skills are portable prose; the **gates are not**. Hooks, plugin manifests, and slash-command execution are Claude Code contracts, and when one shifts the failure is usually silent — a gate that stops gating still lets you ship, so nothing tells you it stopped working.

## Tested against

| | Version | Date | What that covers |
|---|---|---|---|
| **Checks and docs** | **2.1.265** | 2026-09-08 | `make check` (manifests, frontmatter lint, harness shell tests), the `claude plugin validate` audit, and the Agent-tool/fork contract recorded below |
| **Gates exercised live** | **2.1.281** | 2026-09-24 | A real `/harness:loop-dev` run driving the `Stop` hooks end to end (kaffecard XARI-148, harness 2.3.0, `require_design` absent). The design gate ran live 2026-09-24 on kaffecard XARI-131 (PR #36): `/harness:shape` locked a design, then `/harness:loop-dev --plan docs/designs/<slug>/plan.md` passed the preflight's locked + `design-check` gate, folded the design and flipped it to `shipped` — interactively, in auto mode, not headless. The same day a headless `claude -p` loop-dev under `require_design: features`, given a feature task with no `--plan`, classified it as a feature, disarmed and stopped with "run /harness:shape" before building (session `5cca1c49`). A headless loop-dev with `--plan` on an unlocked (`status: draft`) design printed `BLOCK: … not locked`, disarmed and built nothing (CC 2.1.282, session `ff4764a4`). Under `require_design: always`, a headless loop-dev with no `--plan` ("fix a typo in the README") got `BLOCK: require_design: always, but --plan does not point at a design …` from the preflight's `!` block (harness-emitted, not model text), disarmed and built nothing (CC 2.1.282, harness 2.3.0, session `6aa6a882`) |

The two rows are deliberately separate, because they answer different questions and only one of them can be automated. `make check` passing on a new version says our own logic is intact; it says nothing about whether Claude Code still interprets a `Stop` hook's output the way the gates assume. **Only a live loop run moves the second row.** When you do one, move it and say so.

Neither row is a floor or a ceiling, and nothing enforces either. Older or newer versions may work fine — the point of this file is that when they don't, the list below is where to look.

## What we depend on

### Hooks — the load-bearing surface

Every gate is a hook. If any of this changes, the loops stop enforcing and keep reporting success.

| Contract | Used by |
|---|---|
| Events `PreToolUse`, `PostToolUse`, `Stop` | all gates |
| Output `{decision: "block", reason: ...}` | 14 sites across the gate scripts |
| Output `{hookSpecificOutput: {permissionDecision, permissionDecisionReason}}` | `auto-approve-reads`, `block-stray-docs` |
| Output `{systemMessage: ...}` | `console-log-scan` (non-blocking warning), `gate-owner` (a foreign session's stop was not gated) |
| Input `stop_hook_active` | `loop-dev-gate` — multi-turn stop suppression |
| Input `session_id` on `Stop`, equal to `CLAUDE_CODE_SESSION_ID` in a command's `!` block (verified 2.1.282; `--resume` keeps it) | `gate-owner` — a loop is gated only for the session that armed it. Either one missing falls back to gating every session |
| Input `background_tasks` on `Stop`: entries `{type: "subagent", status: "running", …}` while a background subagent runs (verified 2.1.282 headless: listed at the stop that launched it; `claude -p` stays open and fires `Stop` again when it finishes). Not yet verified: that the bundled `/code-review` fork is listed as `subagent` in an interactive session (`-p` runs it in the foreground) | `loop-dev-gate` — a stop on unchanged code while a grader subagent runs is a free wait, not a review round. Field missing → every stop charges, as before |
| Output `{systemMessage: ...}` on an allowed `Stop` | `loop-dev-gate` — tells the user a grader wait was allowed and the loop is still armed |
| Input `tool_name`, `tool_input`, `cwd`, `file_path` | `PreToolUse`/`PostToolUse` scripts |
| `${CLAUDE_PLUGIN_ROOT}` expansion in `hooks.json` | every hook registration |

**The dangerous failure mode:** a `Stop` hook whose output is no longer understood does not error. It stops blocking, and the loop finishes as if every gate passed. `plugins/harness/test/*.test.sh` asserts the gate blocks under each condition, so `make check` catches a regression in *our* logic — but not a change in how Claude Code interprets the output. That needs a live run.

### Slash commands

- `!\`...\`` pre-execution in a command body — arms the loops.
- `${CLAUDE_PLUGIN_ROOT}` expansion in a command body and in `allowed-tools`. Precedent: Anthropic's own `ralph-loop`, `hookify`, `plugin-dev`, and `code-modernization` plugins use this.
- **Verified 2026-08-09 against 2.1.226:** `${CLAUDE_PLUGIN_ROOT}` *does* expand inside `!` pre-execution. A real `/harness:loop-dev` run printed the preflight's output in full. Both the arm script and the preflight rely on this.
- `$ARGUMENTS` substitution. Positional `$0`/`$1` populate only for *typed* commands and leak literally under model invocation, which is why `scripts/lint-skills.sh` rejects them outright.

### Bundled skills

`/harness:loop-dev` invokes Anthropic's **bundled** skills by name for two graders now, not one: `code-review` and (where configured, as in this repo) `security-review`. Bundled-skill policy is Claude Code's, not ours, and the blast radius therefore includes a *security* grader:

- **v2.1.215** stopped auto-running `/verify` and `/code-review` from description matching. That silently degraded the grader into an improvised generic review — the marker still stamped, so nothing downstream noticed (XARI-86).
- **v2.1.218** made `/code-review` a *background* fork: the Skill call returns only `Skill "code-review" launched (forked execution, running in the background)`, and the findings arrive later as a notification (code-review docs, "Run in the foreground"; skills docs, `background` key — only the skill's own frontmatter can make a fork wait in-turn). A grader subagent that invokes it therefore reports before the review exists. Seen live on v2.1.281 (the subagent got nothing; the loop re-ran it in the main session), again in the 2026-09-24 grader panel (the grader reported "none", the fork's finding arrived afterwards as an addendum), and reproduced deliberately on **v2.1.282** (grader finalized "none received"; findings landed ~4 min later). Fix (XARI-150): loop-dev step 5 launches `/code-review <base>...<REVIEWED_SHA>` from the main session and treats the launch line as no result. The ref-range target is documented ("a ref range such as `main...my-feature`") and held live on v2.1.282: in XARI-150's own review panel the fork reported a finding on a line that exists only in that range. The fork has its own context, so the reviewer stays independent of the implementer.
- `/security-review` is **not** a fork (checked on v2.1.282): it expands inline as a prompt over the invoker's diff, so a grader subagent receives its result in-turn and it stays a subagent grader. If a future version forks it, it needs the `/code-review` treatment.
- `disableBundledSkills` turns them off entirely, which would break every bundled grader outright — including `security-review`, whose absence a reviews marker would still stamp over.

Re-check after any Claude Code upgrade. A degraded grader looks identical to a working one from the outside.

### Third-party skills invoked by name

`/harness:shape` invokes one third-party skill by name: `superpowers:writing-plans`, in stage 5 (plan). Stage 4 (feature questions) follows `superpowers:brainstorming`'s one-topic-at-a-time discipline as written in `shape.md` — it does not invoke that skill. A rename of `writing-plans` in the `superpowers` marketplace breaks `shape`. The guard is `shape.md`'s precondition, a model instruction rather than a hard check: it tells the agent to confirm `superpowers:writing-plans` resolves before stage 1 and to stop with an install hint when it doesn't. No script enforces it, so a model that skips the check reaches stage 5 and fails there. Unlike the bundled-skill risk above, there is still no marker to stamp over the missing dependency — the plan stage cannot produce `plan.md`, and `design-check.sh` blocks the lock without it.

### Frontmatter fields in use

`description`, `name`, `user-invocable`, `argument-hint`, `allowed-tools` (6, all in commands), `tools` (2, both agents), `model`, `paths`. Enforced by `scripts/lint-skills.sh`, which checks *our* conformance — not whether Claude Code still honours these keys. Counts are deliberately coarse now; the previous exact figures went stale silently.

**Agent frontmatter is a different contract from skills, and getting it wrong fails silently.** Verified 2026-09-09 against 2.1.265: an agent takes a **comma-separated `tools:`** list; `allowed-tools` (the skill/command key) is *ignored* there, and so is an absent `tools`, and in both cases the agent resolves with **every** tool including `Write` and `Bash`. Confirmed by reading the live agent registry, which reported wayworks' two agents as "Tools: All tools" while an agent using `tools: Read, Glob, Grep` reported exactly those three. Whitespace inside a comma-separated element makes that element one bogus tool name and drops the tools it meant to grant. All three are now hard linter errors.

Model values are aliases (`sonnet`/`opus`/`haiku`), never dated IDs, because dated IDs rot.

`claude plugin validate` (skill frontmatter checks since 2.1.77, bare `.claude/skills` scanning since 2.1.233) is **not** a substitute for the linter and does not replace it: verified 2026-09-08 on 2.1.263 that it flags only a whole-block YAML parse failure, enforces no house rule, and scans skills only when pointed at a plugin root or a skills directory — from the repo root it validates `marketplace.json` alone. Full comparison in `first-party-overlap.md`.

### No shell redirection inside a command's `!` block

Somewhere between 2.1.222 and 2.1.226, output redirection in `!` pre-execution became a hard permission failure:

> Shell command permission check failed … Output redirection to `'.../.cc-loop-dev-state'` was blocked.

Declaring `Bash(echo:*)` does not help — *running* `echo` and *redirecting it into a file* are checked separately, and the redirect is denied regardless of the working directory. All three loops armed this way (`touch .cc-…-active && echo 0 > .cc-…-state`), so **none of them could arm at all**.

The fix, and the pattern to reuse: put the work in a script and grant the script path. Redirection inside a script is never parsed by the permission checker, because the grant is on invoking the path. `hooks/scripts/loop-arm.sh` now does the arming for all three loops, and `allowed-tools` names it instead of `touch`/`echo`.

A related trap: **`cd` does not widen a session's write sandbox.** The allowed directories are fixed at launch from the starting cwd, so `cd` into a repo and then writing there still fails. Launch from the repository root, or use `/add-dir`.

### Plugin manifests: declare only what is NOT conventional

Claude Code auto-discovers `commands/`, `skills/`, `agents/`, and `hooks/hooks.json`. Declaring those same paths in `plugin.json` makes it load them **twice**, and the second load is a hard error:

> Duplicate hooks file detected: `./hooks/hooks.json` resolves to already-loaded file … The standard `hooks/hooks.json` is loaded automatically, so `manifest.hooks` should only reference *additional* hook files.

All 14 wayworks plugins shipped this for months. The manifests were valid JSON, every declared path existed, and `make check` was green throughout — the failure is only visible in `/plugin` in a live session, which nothing in CI simulates. `scripts/check.sh` now rejects the conventional paths while still allowing genuinely additional ones (`hooks: "./hooks/extra.json"` is fine).

Anthropic's own plugins declare none of these keys. When in doubt, match their manifest shape.

### Enabling a plugin is not installing it

`.claude/settings.json` declares *intent*; `~/.claude/plugins/installed_plugins.json` records the actual per-project registration. Listing a plugin under `enabledPlugins` that was never installed for that project is a **silent no-op** — no warning, no error, the skills simply are not there.

Observed 2026-08-09: `ristretto-ai` listed `qa@wayworks: true` for days while the only registration was for a different project. Six of the seven plugins in that same file auto-registered; `qa` was the only one that already had a cache directory on disk from the other project, which is the likely reason its per-project registration was skipped. The result reads as healthy from every angle — valid manifest, populated cache, `true` in settings — and the skill still does not resolve.

**Verify by invoking, never by reading config.** `/harness:loop-dev`'s preflight says as much in its output. Fix with `/plugin install <name>@<marketplace>`.

### Plugin updates need a session restart

Commands and skills are registered at session start. `claude plugin marketplace update` and `/plugin → Update now` change what is on disk but do **not** re-register anything in the running session, so a freshly-updated command reports as an unknown command until you restart. A plugin can also be pinned per-project: `~/.claude/plugins/installed_plugins.json` records `version` and `gitCommitSha` per `projectPath`, so one project can sit on an old version while another is current, and `/plugin` surfaces the stale project's error globally.

### Slash commands from plugins are namespaced

`harness:loop-dev`, not `loop-dev`. Same for skills (`security:code-audit`) and `shared:wayworks-init`.

### Other

- `marketplace.json` schema — validated structurally by `scripts/check.sh`, but against our expectations, not a published schema.
- `acceptEdits` permission tier — the loops assume it exists.
- Concurrent subagent dispatch, optionally with per-subagent model selection. `model-policy.md` treats that selection as best-effort ("when your dispatch tool supports it"), so losing it degrades cost, not correctness.
- **Fork subagents** (`subagent_type: "fork"`): the child inherits the *full parent conversation and prompt cache* instead of a fresh isolated context, and always runs on the parent's model — a `model` override is ignored. **v2.1.232 made this available by default**, lifting the `CLAUDE_CODE_FORK_SUBAGENT=1` gate from v2.1.117; it did **not** make every subagent a fork. Any other `subagent_type`, or omitting it, still starts a fresh agent — so the loops' grader dispatches are fresh contexts, not forks. (An earlier version of this line said forking itself was the default. It is not; corrected 2026-09-08 after review.) Same release backgrounded non-teammate agent spawns by default in interactive sessions. See the fan-out note in `model-policy.md` before adopting fork dispatch for graders — the measurement there argues against it.

## Upstream claims are unverified until checked

Issues generated from release notes and changelogs are **leads, not specifications.** Measured across the 2026-08-05 batch, three of five were materially wrong:

- **XARI-88** gave the command as `ollama launch <model> claude` (actually `ollama launch claude`) and the requirement as v0.32.0 (Ollama's docs say v0.15+). Both stated as fact. Acting on it as written would have shipped a broken command into these docs.
- **XARI-54** described deduplicating a skill that had been deleted weeks earlier.
- **XARI-93** asked for token measurements no available tooling could produce.

So before acting on any upstream-drift issue:

1. **Confirm the claim at its primary source.** Vendor docs over release notes, release notes over secondary coverage.
2. **Confirm the repo still matches** what the issue describes. Files move and get deleted; the issue does not update itself.
3. **Confirm the proposed change is possible** with tooling you actually have. "Measure X" is worth nothing if nothing measures X.
4. **Correct the issue** when it is wrong, so the next reader does not re-derive it.

An issue's confident tone carries no evidence. Ship what you verified, not what it claimed.
