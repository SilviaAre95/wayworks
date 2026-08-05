# Compatibility

What wayworks depends on from Claude Code, and what breaks when those change.

Skills are portable prose; the **gates are not**. Hooks, plugin manifests, and slash-command execution are Claude Code contracts, and when one shifts the failure is usually silent — a gate that stops gating still lets you ship, so nothing tells you it stopped working.

## Tested against

| | |
|---|---|
| Claude Code | **2.1.222** |
| Last verified | 2026-08-05 |

This is the version wayworks was last exercised on, not a floor or a ceiling. Nothing enforces it. Older or newer versions may work fine — the point of this file is that when they don't, the list below is where to look.

## What we depend on

### Hooks — the load-bearing surface

Every gate is a hook. If any of this changes, the loops stop enforcing and keep reporting success.

| Contract | Used by |
|---|---|
| Events `PreToolUse`, `PostToolUse`, `Stop` | all gates |
| Output `{decision: "block", reason: ...}` | 14 sites across the gate scripts |
| Output `{hookSpecificOutput: {permissionDecision, permissionDecisionReason}}` | `auto-approve-reads`, `block-stray-docs` |
| Output `{systemMessage: ...}` | `console-log-scan` (non-blocking warning) |
| Input `stop_hook_active` | `loop-dev-gate` — multi-turn stop suppression |
| Input `tool_name`, `tool_input`, `cwd`, `file_path` | `PreToolUse`/`PostToolUse` scripts |
| `${CLAUDE_PLUGIN_ROOT}` expansion in `hooks.json` | every hook registration |

**The dangerous failure mode:** a `Stop` hook whose output is no longer understood does not error. It stops blocking, and the loop finishes as if every gate passed. `plugins/harness/test/*.test.sh` asserts the gate blocks under each condition, so `make check` catches a regression in *our* logic — but not a change in how Claude Code interprets the output. That needs a live run.

### Slash commands

- `!\`...\`` pre-execution in a command body — arms the loops.
- `${CLAUDE_PLUGIN_ROOT}` expansion in a command body and in `allowed-tools`. Precedent: Anthropic's own `ralph-loop`, `hookify`, `plugin-dev`, and `code-modernization` plugins use this.
- **Unverified:** whether `${CLAUDE_PLUGIN_ROOT}` expands inside `!` pre-execution specifically. `loop-dev`'s preflight relies on it. It degrades safely — the invocation fails, `|| true` swallows it, and the command tells the agent to check the config by hand — but the deterministic half would silently not run. Worth confirming on the next real `/loop-dev`.
- `$ARGUMENTS` substitution. Positional `$0`/`$1` populate only for *typed* commands and leak literally under model invocation, which is why `scripts/lint-skills.sh` rejects them outright.

### Bundled skills

`/loop-dev`'s default `code-review` grader invokes Anthropic's **bundled** `/code-review` skill by name. Bundled-skill policy is Claude Code's, not ours:

- **v2.1.215** stopped auto-running `/verify` and `/code-review` from description matching. That silently degraded the grader into an improvised generic review — the marker still stamped, so nothing downstream noticed (XARI-86).
- `disableBundledSkills` turns them off entirely, which would break this grader outright.

Re-check after any Claude Code upgrade. A degraded grader looks identical to a working one from the outside.

### Frontmatter fields in use

`description` (55), `name` (49), `user-invocable` (43), `argument-hint` (40), `allowed-tools` (12), `model` (5), `paths` (4). Enforced by `scripts/lint-skills.sh`, which checks *our* conformance — not whether Claude Code still honours these keys.

Model values are aliases (`sonnet`/`opus`/`haiku`), never dated IDs, because dated IDs rot.

### Other

- Plugin manifest + `marketplace.json` schema — validated structurally by `scripts/check.sh`, but against our expectations, not a published schema.
- `acceptEdits` permission tier — the loops assume it exists.
- Concurrent subagent dispatch, optionally with per-subagent model selection. `model-policy.md` treats that selection as best-effort ("when your dispatch tool supports it"), so losing it degrades cost, not correctness.

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
