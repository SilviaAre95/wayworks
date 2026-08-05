# Model policy

Which model runs which part of the way-of-work, and how to change it. This is the reference the loops and plugins already encode — change behavior there, document it here.

## The tiers

| Work | Model | Where it's set |
|------|-------|----------------|
| Main loop / orchestration (`/loop-dev`, `/loop-deploy`) | Session model — whatever the user runs Claude Code with | Not pinned; inherits |
| `security` grader | Session model — **never downgrade** | `loop-dev.md` step 5 |
| `code-review` / `bugs` graders | Mid-tier (e.g. sonnet) when the dispatch tool supports per-subagent model selection | `loop-dev.md` step 5 |
| Review sub-agents (`design-reviewer`, `vuln-scanner`, `regression-scanner`, `deploy-checker`, `security-reviewer`) | `sonnet` | `model:` frontmatter in each `agents/*.md` |
| Skills | Inherit the session | No `model:` frontmatter by default |

Rationale: judgment-heavy, adversarial work (security, architecture) gets the biggest model in the room; mechanical review breadth (style, edge-case enumeration) is fine one tier down; nothing below mid-tier ever grades code.

### Fan-out cost (external data, not ours)

Subagent fan-out is not free, and the panel-scaling rules in `loop-dev.md` step 5 (docs-only → `code-review` alone; small non-sensitive → skip `security`) exist to bound it. Those thresholds are set by diff *type*, not by measured overhead — we have never instrumented our own panel.

The only numbers we have are external: Systima's "The Subagent Tax" ([systima.ai/blog/subagent-tax](https://systima.ai/blog/subagent-tax), ~2026-07) measured Claude Code subagent fan-out at **2.6×–5.9× the tokens** of the same work done sequentially, never faster in their timed tasks, with each subagent re-paying its own system prompt and tool-set overhead; pinning subagents to a small model cut their bill ~37%. Treat this as a directional caveat from someone else's rig, **not** a wayworks measurement — our panel is at most four graders on a single diff, which is a different shape from what they benchmarked.

Consequence for now: none. The thresholds stay as they are until someone measures *this* panel. If you do that, record the numbers here and adjust `loop-dev.md` step 5 in the same PR.

## Pinning a model

- **Agents**: `model: sonnet | opus | haiku` in the agent frontmatter. All five wayworks agents pin `sonnet` today.
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
