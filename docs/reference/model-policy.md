# Model policy

Which model runs which part of the way-of-work, and how to change it. This is the reference the loops and plugins already encode — change behavior there, document it here.

For what these loops depend on from Claude Code itself — hook contracts, bundled-skill invocation, the tested version — see [compatibility.md](compatibility.md).

## The tiers

| Work | Model | Where it's set |
|------|-------|----------------|
| Main loop / orchestration (`/harness:loop-dev`, `/harness:loop-deploy`) | Session model — whatever the user runs Claude Code with | Not pinned; inherits |
| `security` grader | Session model — **never downgrade** | `loop-dev.md` step 5 |
| `code-review` / `bugs` graders | Mid-tier (e.g. sonnet) when the dispatch tool supports per-subagent model selection | `loop-dev.md` step 5 |
| Review sub-agents (`design-reviewer`, `vuln-scanner`, `regression-scanner`, `deploy-checker`, `security-reviewer`) | `sonnet` | `model:` frontmatter in each `agents/*.md` |
| `finding-verifier` | Session model — **unpinned by design** | no `model:` frontmatter |
| Skills | Inherit the session | No `model:` frontmatter by default |

Rationale: judgment-heavy, adversarial work (security, architecture) gets the biggest model in the room; mechanical review breadth (style, edge-case enumeration) is fine one tier down; nothing below mid-tier ever grades code.

### Fan-out cost (measured 2026-09-08)

Measured over the local transcripts in `~/.claude/projects` by `scripts/measure-token-spend.py`, which prints every table in this section. **Re-run it before acting on any number here, including these** — the first pass at this measurement got two of them wrong, and the script exists so the next reader does not have to trust prose.

| Where the work ran | Share of cost | Turns | $/turn | Median context/turn |
|---|---|---|---|---|
| Interactive session (main thread) | 97.4% | 6,676 | $0.372 | 399k |
| Subagent | 2.6% | 1,534 | $0.044 | 57k |

**What this shows, and what it does not.** A subagent turn costs ~8× less than a main-thread turn because it works in a 57k context instead of a 399k one. That is close to definitionally true, and it is **not** a refutation of Systima's "The Subagent Tax" ([systima.ai/blog/subagent-tax](https://systima.ai/blog/subagent-tax), ~2026-07), which measured *the same work* done sequentially versus fanned out at 2.6×–5.9× the tokens. This sample contains no sequential counterfactual, and per-locus accounting cannot produce one: a subagent's report lands in the parent's context and is re-read on every later parent turn, and that cost is charged to the parent, never to the subagent.

What the sample does support is narrower and still decides the question: **subagents were 2.6% of all spend.** No grader panel in this repo is a material cost line. The scaling rules in `loop-dev.md` step 5 stay as they are, but their justification is latency and review noise, not cost — **never skip a grader to save tokens.**

**Where the cost is: session length.** Per-turn cost rises with the conversation, so a session's total rises faster than its turn count.

| Session | Main turns | Median ctx, first 25 turns | Last 25 turns | Growth |
|---|---|---|---|---|
| largest | 3,580 | 47k | 433k | 9.3× |
| | 1,263 | 79k | 125k | 1.6× |
| | 1,014 | 60k | 747k | 12.5× |
| | 341 | 75k | 473k | 6.3× |
| | 217 | 75k | 248k | 3.3× |

Median growth excluding the largest session is **4.8×**, so this is not an artifact of one runaway session. Note what it is *not* evidence of: the largest session was 57% of measured spend but also 53% of main-thread turns, so its cost is roughly *proportional* to its length. The effect is within a session, turn over turn, not across sessions.

No harness gate catches this. The gates fire only on an armed loop, and the expensive sessions are unarmed interactive ones; Claude Code already shows context usage in the UI. Treat it as a practice — hand off at a PR or issue boundary — rather than something to build.

**Rejected — routing large file reads to a cheap worker model.** Spotify's "shunt" pattern (engineering.atspotify.com, 2026-09-03) blocks reads over 350 lines with a `PreToolUse` hook and hands them to a cheap model, measured at ~90% savings on a Java monorepo full of large files. Derivation of why it cannot pay here:

| | |
|---|---|
| File-read text reaching context | **702k tokens** — 468k via Bash (`cat`/`head`/`sed -n`/`tail`), 234k via the `Read` tool |
| Share of all tool-result text | 64% |
| Average re-read amplification (`cache_read` ÷ `cache_creation`) | 21.9× |
| Amplified file-read cost | 15.4M of 2,872M `cache_read` tokens |
| **Share of spend a perfect shunt could address** | **0.54%** |

Two traps that first pass fell into, recorded so the next one does not. **Do not measure file reads from the `Read` tool alone** — agents read files through Bash constantly, and Bash carries twice the file-read volume of `Read` here, which is also why the raw per-tool ranking puts Bash on top. And **do not count `toolUseResult` json length as tokens** — the largest of those records are base64 screenshots, where chars÷4 overstates tokens by orders of magnitude. Only 3–8 files per repo in this workspace exceed 350 lines at all. Do not re-propose the shunt from a release-notes scan without re-running the script.

**Why delegation still pays when the shunt does not.** They are different mechanisms and the numbers are not in conflict. A shunt removes tool-result *bytes* from the parent, worth ~0.5%. Delegation removes *turns* from the parent: exploration that takes fifteen turns costs fifteen turns at the parent's context size, versus fifteen at a subagent's 57k with only the conclusion coming back. The saving is in the turn count, not the payload.

**Fork dispatch for graders.** v2.1.232 made forked subagents available without the `CLAUDE_CODE_FORK_SUBAGENT=1` env var that had gated them since v2.1.117. It did **not** make every subagent a fork: `subagent_type: "fork"` forks the caller, while any other type — or omitting it — starts a fresh agent. A grader dispatch that names no type is therefore already a fresh context, which is what the 57k above measures. Keep it that way. A fork would swap that 57k for the parent's context, always runs on the parent's model so the tiering above cannot apply to it, and inherits the author's reasoning, which is the opposite of an independent review.

## Pinning a model

- **Agents**: `model: sonnet | opus | haiku` in the agent frontmatter. Five of the six wayworks agents pin `sonnet`. The exception is `security:finding-verifier`, which is deliberately unpinned so it inherits the session model: its job is to disprove a Critical/High security finding, and a cheaper model that either rubber-stamps or over-refutes is worse than running no verification at all — an over-eager refutation deletes a real vulnerability from the report. This is the same reasoning that keeps the `security` grader on the session model.
- **Skills**: same `model:` frontmatter field (see `shared:create-skill`). Pin only when a skill is deliberately mechanical (haiku) or deliberately heavyweight; unpinned is the right default — the user's session choice should win.
- Model names are aliases, not versions — never write dated model IDs into skills or agents; they rot (this is why `security-scan` carries no model-version claims).

## Local models (Ollama etc.)

Claude Code cannot route individual stages, graders, or sub-agents to a local model — model selection only picks Claude tiers. **The local path is per-session, not per-stage.** Nothing below changes that; they only make session setup easier.

Ollama now ships a first-party launcher, which is the entry point to use:

```bash
ollama launch claude
```

It picks the model interactively and needs no env vars or config files (Ollama v0.15+; `claude`, `opencode`, `codex`, and `droid` are the supported targets). Set the context length to **64k or higher** — Ollama's own guidance for larger repos, and skill files are long.

Without the launcher, point Claude Code straight at Ollama's Anthropic-compatible endpoint — no LiteLLM in between:

```bash
ANTHROPIC_AUTH_TOKEN=ollama ANTHROPIC_BASE_URL=http://localhost:11434 ANTHROPIC_API_KEY="" claude
```

Two caveats that decide whether this is usable for real work:

- **Tool-call reliability is the binding constraint, not raw model quality.** Skill files are multi-turn tool loops; a model that drops a tool-response continuation halfway through fails the loop in a way that looks like a bad answer. Ollama v0.32.1 fixed exactly this class of bug for Gemma 4 — worth knowing when a small model behaves erratically inside a skill rather than assuming the skill is at fault.
- **Treat a local session as a different tool.** Fine for mechanical batch work (doc summarization, log triage); not wired into the harness loops, which assume a model strong enough to fix its own review findings.

Status: the local-model track (unified Ollama store, which workloads move local) is still an open work item — see the Linear backlog. `ollama launch` solves setup, not routing.
