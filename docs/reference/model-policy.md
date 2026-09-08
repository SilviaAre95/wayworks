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

Measured over the 79 local transcripts in `~/.claude/projects` — about 2.9B tokens, roughly $2.5k at Anthropic list rates — covering ristretto, pilates-flow, wayworks, kaffecard and obex work. Reproduce with a script over the `usage` objects in those transcripts; `session-report` produces the same shape.

| Where the work ran | Share of cost | Turns | Cost/turn | Median context/turn |
|---|---|---|---|---|
| Interactive session (main thread) | 97.7% | 6,577 | $0.374 | 396k |
| Subagent | 2.3% | 1,347 | $0.043 | 56k |

**Subagent fan-out is ~9× cheaper per turn, not more expensive.** A subagent works in a small fresh context; a main-thread turn re-reads the whole conversation. Systima's "The Subagent Tax" ([systima.ai/blog/subagent-tax](https://systima.ai/blog/subagent-tax), ~2026-07) measured fan-out at **2.6×–5.9× the tokens** of sequential work, blaming each subagent re-paying its own system prompt and tool set. That overhead is real, and it is dwarfed by the variable their setup holds constant: what a long parent conversation costs to re-read every turn. Their number is not wrong about their rig; it is the wrong variable for ours.

Consequence: the panel-scaling rules in `loop-dev.md` step 5 stay as they are, but their justification changes — they bound latency and review noise, not cost. **Never skip a grader to save tokens; the saving is not there.** Prefer dispatching read-heavy work to a subagent over doing it on the main thread.

**Where the cost actually is: session length.** Per-turn cost grows with the conversation, so a session's total grows with the square of its length.

| Turn number | Median context/turn |
|---|---|
| 0–24 | 68k |
| 100–124 | 152k |
| 200–224 | 248k |
| 300+ | 534k |

Three quarters of sampled main-thread turns sat past turn 300. A single 3,516-turn interactive session was **57% of all measured spend**. The lever is handing off at a natural boundary — a PR, an issue — rather than carrying one session for hours. No harness gate catches this: the expensive sessions were never armed, and Claude Code already shows context usage in the UI.

**Fork dispatch for graders — argued against by this data.** v2.1.232 made `subagent_type: "fork"` the default, and a fork inherits the parent's full conversation and prompt cache. That removes the system-prompt overhead Systima blamed, but it swaps a 56k grader context for the parent's, which the first table says is exactly where the money goes. A fork also always runs on the parent's model, so the tiering above cannot apply to it, and a grader that inherits the author's reasoning is not an independent reviewer. Keep graders on fresh subagents.

**Rejected — routing large file reads to a cheap worker model.** Spotify's "shunt" pattern (engineering.atspotify.com, 2026-09-03) blocks reads over 350 lines with a `PreToolUse` hook and hands them to a cheap model, measured at ~90% savings on a Java monorepo full of large files. It cannot pay here: all tool results across the 79 transcripts total ~996k tokens, of which `Read` is 208k — so blocking every large read saves ~0.16% of spend. `Bash` output is ~3× `Read` volume, so even the tool ranking does not transfer, and only 3–8 files per repo exceed 350 lines. Do not re-propose this from a release-notes scan without re-measuring.

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
