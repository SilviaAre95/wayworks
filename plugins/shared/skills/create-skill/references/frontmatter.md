# Frontmatter reference and verbosity guidance

Field-by-field lookup for skill, command and agent frontmatter, plus how much prose a skill needs on Claude 5+ models. The rules that must not drift stay in SKILL.md; this is the table you consult while writing one.

## Frontmatter Reference

| Field | Required | Description |
|-------|----------|-------------|
| `name` | Yes | Kebab-case identifier |
| `description` | Yes | When Claude should invoke this (max 250 chars) |
| `user-invocable` | No | `true` (default) = user can call via `/skill-name` |
| `disable-model-invocation` | No | `true` = only user can trigger, Claude won't auto-invoke |
| `argument-hint` | No | Shown in autocomplete, e.g. `[file] [--verbose]` |
| `allowed-tools` | No | **Comma**-separated tool grants usable without prompts, e.g. `Read, Edit, Bash(git:*)`. Skills and commands only — **agents use `tools:` instead, and `allowed-tools` is silently ignored there**, which left both shipped agents with every tool until 2026-09-09 |
| `model` | No | Force a specific model: `sonnet`, `opus`, `haiku` |
| `effort` | No | `low`, `medium`, `high`, `max` |
| `context` | No | `fork` = run in isolated subagent |
| `paths` | No | Glob patterns for auto-loading |


## Verbosity note (Claude 5+ models)

Anthropic's context-engineering research (2026-07) shows newer Claude model families tolerate significantly less system prompt verbosity — deleting ~80% of Claude Code's system instructions with no eval loss. The house pattern's ~300–450-word structure remains mandatory so skills work across all models (including local/older ones), but be aware:

- **Load-bearing structure** (keep explicit): gating conditions, tool constraints, output schemas, `$ARGUMENTS` handling — these prevent real failures regardless of model capability
- **Likely redundant on Claude 5+**: over-explained rationales, repeated warnings, step-by-step prose rephrasing the same point — frontier models infer these from terse instructions

When writing for exclusively frontier-model consumers, consider trimming rationale and repetition while keeping guardrails explicit. For marketplace-wide skills (like this plugin), lean toward the full structure so less-capable models don't misbehave. Use `claude doctor` (`/doctor` in Claude Code session) to detect redundant or conflicting instructions before shipping.

