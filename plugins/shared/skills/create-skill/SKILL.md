---
name: create-skill
description: "Generate a new SKILL.md file with proper frontmatter, structure, and $ARGUMENTS support"
user-invocable: true
argument-hint: "<skill-name> <plugin-name> [description]"
---

# Create a New Skill

Create a new skill from: `$ARGUMENTS` (expected: skill-name, plugin-name, and optionally a description — parse them from the argument string).

## Instructions

1. Create the directory: `plugins/<plugin-name>/skills/<skill-name>/`
2. Create the `SKILL.md` there using the template below
3. If a description was provided, use it verbatim in the frontmatter

## SKILL.md Template

Use this exact structure for the new skill file:

```markdown
---
name: <skill-name>
description: "<One line: what it does and when Claude should use it. Max 250 chars.>"
user-invocable: true
argument-hint: "<placeholder args the user passes, e.g. [target] [options]>"
---

# <Skill Title>

<Clear, imperative instructions for Claude. Write as if briefing a senior engineer.>

## When to use

<1-3 bullet points describing trigger conditions>

## Inputs

- `$ARGUMENTS` — full argument string from the user; parse parameters from it in prose (positional `$0`/`$1` only populate for typed slash commands and leak literally when the model invokes the skill — never use them)

## Steps

1. <Step one>
2. <Step two>
3. <Step three>

## Output format

<What the skill should produce: code, markdown doc, structured analysis, etc.>

## Constraints

- <Guard rails, things to avoid, scope limits>
```

## Frontmatter Reference

| Field | Required | Description |
|-------|----------|-------------|
| `name` | Yes | Kebab-case identifier |
| `description` | Yes | When Claude should invoke this (max 250 chars) |
| `user-invocable` | No | `true` (default) = user can call via `/skill-name` |
| `disable-model-invocation` | No | `true` = only user can trigger, Claude won't auto-invoke |
| `argument-hint` | No | Shown in autocomplete, e.g. `[file] [--verbose]` |
| `allowed-tools` | No | Space-separated tool names Claude can use without prompts |
| `model` | No | Force a specific model: `sonnet`, `opus`, `haiku` |
| `effort` | No | `low`, `medium`, `high`, `max` |
| `context` | No | `fork` = run in isolated subagent |
| `paths` | No | Glob patterns for auto-loading |

## Verbosity note (Claude 5+ models)

Anthropic's context-engineering research (2026-07) shows newer Claude model families tolerate significantly less system prompt verbosity — deleting ~80% of Claude Code's system instructions with no eval loss. The house pattern's ~300–450-word structure remains mandatory so skills work across all models (including local/older ones), but be aware:

- **Load-bearing structure** (keep explicit): gating conditions, tool constraints, output schemas, `$ARGUMENTS` handling — these prevent real failures regardless of model capability
- **Likely redundant on Claude 5+**: over-explained rationales, repeated warnings, step-by-step prose rephrasing the same point — frontier models infer these from terse instructions

When writing for exclusively frontier-model consumers, consider trimming rationale and repetition while keeping guardrails explicit. For marketplace-wide skills (like this plugin), lean toward the full structure so less-capable models don't misbehave. Use `claude doctor` (`/doctor` in Claude Code session) to detect redundant or conflicting instructions before shipping.

## Tips

- Keep descriptions under 250 characters — they're used for skill matching
- Use `$ARGUMENTS` for dynamic input — never positional `$0`/`$1` (they only populate for typed slash commands and leak literally on model invocation)
- Use `disable-model-invocation: true` for destructive or opinionated skills
- Add a `## Constraints` section to prevent scope creep
- Reference files with `${CLAUDE_SKILL_DIR}` for co-located templates
