---
name: discover
description: "Research a topic through parallel lenses (presets: code, article, talk) and write a brief ending in 'What this changes' — to the vault when one is declared, else docs/discovery/"
user-invocable: true
argument-hint: "<topic> [--preset code|article|talk] [--lens <name>...]"
---

# Discover

Research **$ARGUMENTS**: `<topic> [--preset code|article|talk] [--lens <name> …]`. Topic-agnostic — the first stage of `/harness:shape`, but equally used for researching an article or a talk outside any repo.

## Steps

1. **Pick the lenses.** Infer them from the topic, take a preset, or take `--lens <name> …` — `--lens` always overrides inference or a preset. See `references/presets.md` for what each lens looks for.
   - `code` preset: technical + product lenses.
   - `article` preset: prior art + counter-arguments + evidence lenses.
   - `talk` preset: prior art + audience lenses.
2. **Find the vault** the way `wayworks-onboard` does: declared in the user's global CLAUDE.md, never hardcoded. If declared, follow its own `_agent/INSTRUCTIONS.md` for where knowledge notes live, not an assumed folder name.
3. **Reuse a recent brief.** If one exists (vault or fallback path) under 30 days old, reuse it — re-run only the lenses needed to check for anything new.
4. **Dispatch one parallel subagent per lens.** Each returns sources + findings as text for its lens only; none writes the brief file.
5. **Merge.** Assemble sources per lens, then findings, into the brief. A lens that fails or comes back empty is named explicitly, never dropped, and marks the frontmatter `discovery: partial`.
6. **Write the brief.** First slugify the topic to kebab-case (`[a-z0-9-]`, stripping `/`, `..`, and other path characters) before using it as `<topic>` below.
   - Vault declared and writable → its knowledge folder, per `INSTRUCTIONS.md`.
   - Vault write denied → fall back to `docs/discovery/<topic>.md` in the repo, and report the fallback.
   - No vault declared → `docs/discovery/<topic>.md` in the repo, or `./<topic>.md` in the current directory when working outside a repo.
7. **Report** the brief's path, and `partial` when any lens failed or found nothing.

## Output Format

```
---
topic: <topic>
date: <today>
lenses: [technical, product]
discovery: complete | partial
---

## <Lens name>
Sources: ...
Findings: ...

## What this changes
- <claim the design can rest on>
- ...
```

`## What this changes` holds 3–7 standalone claims, not summary sentences — `harness:shape` freezes this section verbatim into `design.md`, so it must read on its own.

## Constraints

- Never hardcode the vault path — resolve it fresh, following only the vault's own `INSTRUCTIONS.md`.
- Never write the raw topic into a path or shell command — always the slugified form; `/`, `..`, and shell metacharacters must never reach a path or a subprocess.
