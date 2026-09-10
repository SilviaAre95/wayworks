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
4. **Quote the description.** A bare scalar containing a colon or a `#` breaks the YAML parse silently — the runtime drops every frontmatter key and the skill stops resolving. `scripts/lint-skills.sh` rejects an unquoted description outright; this is an error, not a warning.

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

## Agents are not skills

If you are scaffolding an `agents/*.md` file rather than a skill, the frontmatter differs: `name` must match the **filename**, and the tool grant is `tools:` — comma-separated, and **required**, because an agent with no tool list resolves with every tool including `Write` and `Bash`. `allowed-tools` is silently ignored in agent frontmatter. `scripts/lint-skills.sh` enforces all three.

## Frontmatter reference

Field-by-field tables for skills, commands and agents, and the Claude 5+ verbosity guidance: `references/frontmatter.md`. Two rules from it are load-bearing enough to repeat here: agents take a comma-separated `tools:` list (`allowed-tools` is a skill key, silently ignored in agent frontmatter, so the agent resolves with every tool), and the description must be quoted.

## Tips

- Keep descriptions under 250 characters — they're used for skill matching
- Use `$ARGUMENTS` for dynamic input — never positional `$0`/`$1` (they only populate for typed slash commands and leak literally on model invocation)
- Use `disable-model-invocation: true` for destructive or opinionated skills
- Add a `## Constraints` section to prevent scope creep
- Reference files with `${CLAUDE_SKILL_DIR}` for co-located templates
