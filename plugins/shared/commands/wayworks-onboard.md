---
description: Onboard a project from any starting point — link Linear project + vault note + repo, creating whatever is missing
allowed-tools: Read, Edit, Write, Bash(git:*), Bash(ls:*), Bash(mkdir:*), Bash(jq:*), ToolSearch
---

Onboard the project: **$ARGUMENTS** (a name, an existing repo path, or just an idea described in a sentence).

The goal state is a linked triangle: **Linear project ↔ vault note ↔ repo**. Start by taking inventory, create only what's missing, then wire the links. Confirm each creation before doing it — Linear projects and vault notes are visible artifacts.

1. **Inventory** — determine what already exists and report it as a checklist before creating anything:
   - **Repo**: does a directory/git repo exist for this project? (Check the path given, or `~/ventures/code/<name>`.)
   - **Vault note**: does `02-Projects/<name>.md` exist in the vault? (Vault location comes from the user's global CLAUDE.md — never hardcode it.)
   - **Linear project**: load Linear MCP tools via ToolSearch and check `list_projects` for a matching name.

2. **Create what's missing** (in this order — knowledge first, tracking second, code last):
   - **Vault note**: instantiate the vault's `_templates/tpl-project.md` (fill `created`/`updated` with today, write a real one-line `summary:` — it's what agents scan). Sections: Goal, Context, Tasks, Log, Resources. Follow the vault's `_agent/INSTRUCTIONS.md` rules and link the note from `_index/MOC-Projects.md`.
   - **Linear project**: create it with `/shared:linear-project` — it owns the description pattern (bold type line, 2–3 sentence scope, `Local repo:` and `Vault note:` pointer lines), the first milestone, and the 3–5 starter issues, each written with `/shared:linear-issue`. If starting from just an idea, seed the starter issues from the vault note's Tasks section. Write each one with `/shared:linear-issue` so they stay short.
   - **Repo**: if none exists and the user wants one now, create the directory, `git init`, and add a README stub. If it's idea-stage only, skip — the vault note and Linear project are enough; note in both where the repo will live when created.

3. **Wire the links** (idempotent — fix stale links on projects that already have all three):
   - Vault note frontmatter/Resources: repo path + Linear project URL.
   - Linear project description: `Vault note:` + `Local repo:` lines (update if present but wrong).
   - Repo: run `/wayworks-init` (plugin fleet + CLAUDE.md header with the vault-note name and Linear project name).

4. **Report** — table of the triangle: each vertex → existed / created / skipped, plus the links written.

## Adapt to the user's setup

This command must work for any user, not one specific workflow. The second brain (Obsidian vault) is the recommended knowledge core; the tracker is pluggable. Detect capabilities and degrade gracefully:
- **No Linear MCP** (ToolSearch finds no Linear tools): the tracker vertex is pluggable — ask which the user prefers, recommending in this order: (1) **Obsidian issue management**: a `## Backlog` section in the project's vault note (or a `<project>-backlog.md` beside it) using `- [ ]` checkboxes, so tasks live in the second brain; (2) another connected tracker (GitHub Issues via `gh`, or any tracker MCP ToolSearch finds); (3) `docs/BACKLOG.md` in the repo as the minimal fallback. Wire the triangle links to whichever is chosen.
- **No vault** (global CLAUDE.md declares none): skip the vault vertex; put the Goal/Context content in the repo's `docs/` or the tracker's project description instead. Suggest an Obsidian vault as the recommended knowledge layer, but never require it.
- **Different vault structure**: read the vault's own entry-point file (root CLAUDE.md / agent context) and follow ITS template and folder conventions rather than assuming `02-Projects/` + `_templates/`.

## Constraints

- Ask before creating the tracker project (external, workspace-visible) — show the name + description you intend to write.
- **Branch discipline for repo commits**: never commit config onto whatever branch the repo happens to be on. Check `git branch --show-current` first. If the repo has a remote, create `chore/wayworks-onboard` from the default branch, commit there, push, and open a PR. If there is no remote, commit to the default branch directly. If the working tree is dirty or mid-feature, say so and let the user choose.
- Committed repo files get relative vault-note names only; absolute personal paths stay in the vault and tracker.
- Never overwrite an existing vault note or tracker description — merge missing pointer lines only.
- Idea-stage projects get vault note + tracker only; do not scaffold empty repos nobody asked for.
