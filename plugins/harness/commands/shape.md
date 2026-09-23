---
description: Shape a feature before code — discover, scope, attack, questions, plan, what-ifs, byproducts, map, lock — into a gated design loop-dev will build
argument-hint: <topic|slug> [--stage <name>] [--publish]
allowed-tools: Read, Write, Edit, Glob, Grep, Bash(${CLAUDE_PLUGIN_ROOT}/scripts/design-check.sh:*), Bash(${CLAUDE_PLUGIN_ROOT}/scripts/render-map.sh:*), Bash(mkdir:*), Bash(open:*)
---

Shape the feature below into a locked design at `docs/designs/<slug>/design.md` + `plan.md`. All human supervision happens here, before code, so the coding loop can run unattended. This command orchestrates; each stage's skill owns its own procedure.

## Preconditions

1. **superpowers must resolve.** If `superpowers:writing-plans` is not available in this session, stop with: *"/harness:shape needs the superpowers plugin (stages 4–5). Install: /plugin install superpowers@claude-plugins-official"*.
2. **Derive `<slug>`** from the topic: kebab-case, `[a-z0-9-]` only, stripping `/`, `..` and every other path or shell character — it becomes a directory name. An argument that is already a valid slug is used as-is. Only the slug ever reaches a path or a shell command; the raw topic never does.
3. **Resume or start.**
   - `docs/designs/<slug>/design.md` exists → resume at its frontmatter `stage:`.
   - Otherwise `mkdir -p docs/designs/<slug>`, then Read `${CLAUDE_PLUGIN_ROOT}/templates/design.md` and Write it there, replacing `__SLUG__` with the slug and `__TITLE__` with a short title for the topic.
4. **Status rules.**
   - `shipped` → never re-open. Stop and say to start a new slug; a shipped design is an immutable decision record.
   - `locked` with no `--stage` → re-run the Lock stage's check and print the handoff line; nothing else.
   - `--stage <name>` re-opens that stage; on a `locked` design it first sets `status: draft`. Re-opening `plan` also re-runs `what-ifs` and `byproducts` — a new plan can create new what-ifs and byproducts.

## Stages

| # | Stage | Does | Human? |
|---|---|---|---|
| 1 | **Discover** | `shared:discover` with the code preset (technical + product lenses) | no |
| 2 | **Scope** | Draft in/out-of-scope from the topic, brief, and `docs/features/` | review |
| 3 | **Attack scope** | `harness:attack --target scope` | triage |
| 4 | **Feature questions** | Open functional questions, superpowers-brainstorming discipline | triage |
| 5 | **Plan** | `superpowers:writing-plans` → `docs/designs/<slug>/plan.md` | review |
| 6 | **What-ifs** | `harness:attack --target plan` (failure lenses) | triage |
| 7 | **Byproducts** | Diff plan against scope: everything built that nobody explicitly asked for | triage (ack) |
| 8 | **Map** | Write the flow + what-ifs and components diagrams (Mermaid) and the scope board (table) into `design.md` | no |
| 9 | **Lock** | `design-check.sh` green + user says lock → `status: locked`; print the `loop-dev` handoff | confirm |

`stage:` names, in order: `discover`, `scope`, `attack-scope`, `questions`, `plan`, `what-ifs`, `byproducts`, `map`, `lock`.

1. **Discover** — `/shared:discover <topic> --preset code`. Add the brief's path to frontmatter `discovery:` and freeze a verbatim copy of its `## What this changes` under `## Discovery`, below a link line to the brief. If the brief reports `partial`, add the frontmatter key `discovery-status: partial` (absent means complete). A partial result does not stop the pipeline.
2. **Scope** — draft the In/Out table from the topic, the brief and `docs/features/` (when present). The user reviews it before you continue.
3. **Attack scope** — `/harness:attack --target scope docs/designs/<slug>`, then `harness:triage` on its list.
4. **Feature questions** — follow brainstorming's discipline: one topic at a time. Record each open functional question as a `Q` item, then `harness:triage`.
5. **Plan** — invoke `superpowers:writing-plans` with output path `docs/designs/<slug>/plan.md`. The user reviews it.
6. **What-ifs** — `/harness:attack --target plan docs/designs/<slug>`, then `harness:triage`. **Then** amend `plan.md` so every `[x] W<n>` has a task whose test names `W<n>`.
7. **Byproducts** — diff the plan against Scope. Everything built that nobody explicitly asked for becomes a `B` item, proposed `ack`. `harness:triage`.
8. **Map** — write a Mermaid flow plus the what-ifs under `## Flow & what-ifs`, a Mermaid component diagram under `## Components`, and fill the `## Scope board` table.
9. **Lock** — run `"${CLAUDE_PLUGIN_ROOT}/scripts/design-check.sh" docs/designs/<slug>`.
   - Any `BLOCK:` → return to the stage that owns the item (`A`→3, `Q`→4, `W`→6, `B`→7) and set `stage:` to it.
   - Green → ask *"lock?"*. Only on an explicit yes: set `status: locked`. Then, if the user's global CLAUDE.md declares a vault, append one line to the project note's `## Log` (the note the repo's CLAUDE.md names), written per the vault's `_agent/INSTRUCTIONS.md`. No vault or no project note → skip silently.
   - Print the handoff as the last line: `/harness:loop-dev --plan docs/designs/<slug>/plan.md`

**After each stage**, set frontmatter `stage:` to the next unfinished stage and save `design.md`. That is what makes the command resumable when the user walks away mid-triage — unaddressed items stay `- [ ]` and the design stays `draft`.

## --publish

Run `"${CLAUDE_PLUGIN_ROOT}/scripts/render-map.sh" docs/designs/<slug>` and `open` the path it prints. The page lands in `.wayworks/maps/`, which is never committed.

## Constraints

- Never write `decided-by: you` for an item the user did not address.
- Never set `locked` without a green design-check **and** the user's explicit yes.
- Never start coding. The handoff line is the last output.

Topic: $ARGUMENTS
