---
name: discover
description: "Research a topic through parallel lenses (presets: code, article, talk) and write a brief ending in 'What this changes' — to the vault when one is declared, else docs/discovery/"
user-invocable: true
argument-hint: "<topic> [--preset code|article|talk] [--lens <name>...]"
---

# Discover

Research **$ARGUMENTS**: `<topic> [--preset code|article|talk] [--lens <name> …]`. Topic-agnostic — the first stage of `/harness:shape`, but equally used for researching an article or a talk outside any repo.

## Steps

1. **Pick the lenses.** Infer them from the topic's shape, or take a preset, or take `--lens <name> …` verbatim — `--lens` always overrides inference or a preset when given. Read `references/presets.md` for what each lens looks for before dispatching it.
   - `code` preset: technical + product lenses.
   - `article` preset: prior art + counter-arguments + evidence lenses.
   - `talk` preset: prior art + audience lenses.
2. **Find the vault** the way `wayworks-onboard` finds it: declared in the user's global CLAUDE.md, never hardcoded. If one is declared, read its own `_agent/INSTRUCTIONS.md` for where knowledge notes live and follow that layout rather than assuming a folder name.
3. **Reuse a recent brief.** If a brief for this topic already exists (vault or fallback path) and is under 30 days old, reuse it — re-run only the lenses needed to check for anything new, instead of researching from scratch.
4. **Dispatch one parallel subagent per lens.** Each researches only its lens and hands back sources + findings as text; none of them write the brief file.
5. **Merge.** Assemble sources per lens, then findings, into the brief. If a lens's subagent fails or comes back empty, say so explicitly under that lens — never drop it silently — and mark the brief's frontmatter `discovery: partial`.
6. **Write the brief:**
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

`## What this changes` holds 3–7 bullets, each a standalone claim rather than a summary sentence — `harness:shape`'s discover stage freezes this section verbatim into `design.md`, so it has to read on its own.

## Constraints

- `--lens` always wins over a preset or inferred lenses; never silently ignore it.
- Check the vault's `_agent/INSTRUCTIONS.md` before writing to it — assuming a layout breaks the moment the user's vault differs from the reference one.
- A lens that fails or finds nothing is reported under its own heading, not dropped — `partial` is the honest state, not a failure to hide.
- If the vault write is denied, fall back once and report it; don't retry the vault silently.
- Keep `## What this changes` short enough to freeze into a design: 3–7 bullets, no more.
