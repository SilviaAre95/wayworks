---
name: linear-project
description: "Use when creating or scaffolding a Linear project for a venture, client job, or internal tool — from a brief, an idea, or an existing repo — including its description, first milestone, and starter issues"
user-invocable: true
argument-hint: "<project name or brief> [repo path] [vault note]"
---

# Linear project

A project record is a pointer, not a document: it says what the thing is, where the code and the note live, and what the first milestone proves. The vault note holds the thinking; the issues hold the work.

## Steps

1. **Parse** `$ARGUMENTS`: name, one-line scope, stack, repo path, vault note, first milestone. Missing repo or note: leave the pointer line out, do not invent a path.
2. **Check** `list_projects` for the name. If it exists, update only missing pointer lines and stop; never overwrite a description.
3. **Write the description** in the form below and show it to the user with the name. Creating a project is workspace-visible: wait for a yes.
4. **Create** with `save_project`; lead is the user; state from the workspace's own names via the project's status list — the planning state when a repo or milestone exists, the backlog state for an idea.
5. **Milestone**: one, only if the brief names one, titled as the brief does, description one sentence ending in its exit criterion. Never add a second milestone the brief did not name.
6. **Seed issues**: three to five, each written with `/shared:linear-issue` (short form, `feat - <App>: …`), attached to the milestone, ordered by dependency. The first is the repo scaffold only when no repo exists; the last is the end-to-end walkthrough of the milestone. Confirm the list before creating.

## Output format

Description, under 80 words:

```
**<Kind> — <stack shape>.**  (Kind: Venture, Client, Internal, Experiment)

<Two or three sentences: who it is for, what it does, what it proves first.>

Local repo: <path>
Vault note: <vault-relative note path>
```

Example:

```
**Venture — fullstack.**

B2B marketplace for specialty coffee: roasters list green-coffee lots, cafés pre-order by the kilo. Roasters get demand signal before roasting; cafés get freshness. First milestone proves the two-sided loop with no payments.

Local repo: ~/ventures/code/crema-connect
Vault note: 02-Projects/crema-connect/crema-connect.md
```

Starter issues for that brief, titles only: `feat - Crema Connect: scaffold Next.js + Vercel + Supabase`, `… roaster and café roles at sign-up`, `… a roaster publishes a lot`, `… a café reserves kilos against an open lot`, `… walk the list-and-reserve loop on a preview deploy`.

## Constraints

- No stack section, no "why", no roadmap in the description. Stack fits in the bold line; the roadmap is the milestone; the why is the vault note.
- Absolute personal paths stay in Linear and the vault; they never reach committed repo files.
- Issues come from the brief's milestone, not from what a generic app needs. Auth, schema, CI appear only when the milestone cannot be walked without them.
- Ask before every creation. A project, a milestone, and five issues are three separate confirmations at most: name and description, milestone, issue list.
