# Design pipeline — design

**Status:** draft for review · **Date:** 2026-09-23 · **Sub-project:** C of 3 (A = release/fleet hygiene, B = repo bootstrap + command set)

## Goal

Move all human supervision to *before* code. A feature goes through a design pipeline the user steers; once the design is locked, coding subagents run to a PR without needing the user. The pipeline earns its place over first-party checklists by being **gated**: `loop-dev` refuses to build a feature whose design is missing or unresolved.

## Pipeline

`/harness:design <topic|slug> [--stage <name>] [--publish]` walks the stages in order, writes each into `docs/designs/<slug>/design.md`, and resumes at the first unfinished stage on re-run. `--stage` re-opens one stage (e.g. re-attack after the plan changed).

| # | Stage | Does | Human? |
|---|---|---|---|
| 1 | **Discover** | `shared:discover` with the code preset (technical + product lenses) | no |
| 2 | **Scope** | Draft in/out-of-scope from the topic, brief, and `docs/features/` | review |
| 3 | **Attack scope** | `harness:attack --target scope` | triage |
| 4 | **Feature questions** | Open functional questions, superpowers-brainstorming discipline | triage |
| 5 | **Plan** | `superpowers:writing-plans` → `docs/designs/<slug>/plan.md` | review |
| 6 | **What-ifs** | `harness:attack --target plan` (failure lenses) | triage |
| 7 | **Byproducts** | Diff plan against scope: everything built that nobody explicitly asked for | triage (ack) |
| 8 | **Map** | Render diagrams into `design.md`; optionally publish | no |
| 9 | **Lock** | `design-check.sh` green + user says lock → `status: locked`; print the `loop-dev` handoff | confirm |

Handoff: `/harness:loop-dev --plan docs/designs/<slug>/plan.md`, which executes via subagents. The superpowers skills are **wrapped**, not replaced: stage 4 follows brainstorming's one-topic-at-a-time discipline, stage 5 invokes writing-plans with a fixed output path. superpowers is already in `wayworks-init`'s fleet; `/harness:design` stops with a clear message if it is not installed.

## Components

| Unit | Plugin | Kind | Purpose |
|---|---|---|---|
| `discover` | `shared` | skill, user-invocable | Topic-agnostic research. Lenses inferred from topic, `--lens` overrides. Presets: code = technical + product; article = prior art + counter-arguments + evidence; talk = prior art + audience. One parallel subagent per lens. Brief ends with **"What this changes"**. |
| `attack` | `harness` | skill | Adversarial review of a written artifact. `--target scope` lenses: ambiguity, missing actors, feature-bank conflicts, cheapest cut. `--target plan` lenses: connectivity, concurrency/races, auth/session expiry, partial failure, data limits, abuse. Scaled panel (below). |
| `triage` | `harness` | skill | Batch-decision protocol shared by stages 3, 4, 6, 7. |
| `design` | `harness` | command | Orchestrator above. |
| `design-check.sh` | `harness` | script | Deterministic gate over `design.md` + `plan.md`. |

Skills are drafted with `anthropic-skills:skill-creator`, then made to pass `make check` (quoted description, explicit `user-invocable`, `argument-hint` where `$ARGUMENTS` is read, ≤450 words or `references/`), and each gets a rules manifest in `scripts/skill-rules/` **written and baselined before the body is final**.

### Scaled attack panel

- **Small scope** (≈ one user flow, no new data store or actor): one attacker, all lenses.
- **Larger:** one attacker per lens, in parallel, fresh subagents that did not write the artifact.
- **Merge step:** dedupe, rank by severity, cap triage at the top **15**. The rest land as `deferred` with a one-line reason and can be pulled back.

### Triage protocol

Every item carries a proposed decision. The user replies in batch — `ok 1-7, 8: reject and show retry, 9: ?`. `?` items get discussed individually. Each item records `decided-by: you | accepted-default`, so the design shows which calls were actually considered.

## design.md format

Frontmatter:

```yaml
slug: offline-stamp
status: draft | locked | shipped
stage: what-ifs            # first unfinished stage
discovery: [04-Knowledge/offline-qr.md]   # or docs/discovery/… when no vault
map_url:                   # set by --publish when an artifact exists
```

Sections: Discovery (links + frozen copy of each brief's "What this changes"), Scope (in / out table), Flow & what-ifs (Mermaid), Components (Mermaid), Scope board (table), Decisions.

**Decision items are checklist lines** so a shell script can parse them and GitHub/Obsidian render them:

```
- [x] W3 · high · QR scanned offline → queue locally, sync on reconnect, shop sees "pending" · decided-by: you
- [x] B2 · byproduct · local stamp queue (new storage + sync code) · ack · decided-by: accepted-default
- [~] A9 · low · second device for same shop · deferred: single-device shops only in v1
- [ ] Q4 · med · reward expiry? · open
```

ID prefixes: `A` scope attack, `Q` feature question, `W` what-if, `B` byproduct.

## The gate — design-check.sh

Exit non-zero (with a `BLOCK:` line naming the item) when any of:

1. Any `- [ ]` item remains.
2. A `[x]` item lacks `decided-by:`, or a `B` item lacks `ack`.
3. A decided `W` item's ID does not appear in `plan.md`. The plan must turn every what-if decision into a task with a test. This is what makes unsupervised code verifiable, and it is checkable by `grep`.
4. `status` is not `locked` (when invoked from `loop-dev`).

`loop-dev-preflight.sh` calls it when `--plan` points inside `docs/designs/`. New `.cc-dev.yaml` key:

```yaml
require_design: features   # never | features | always
```

`features`: the loop classifies the task first; fixes, chores, and docs pass, and anything adding behavior without a locked design is blocked with "run /harness:design first". The classification is a model judgement, so every "classified as fix, design skipped" is logged in the PR body for audit. `harness-init` writes `features` as the default.

## Map

Canonical view is **Mermaid + a markdown table inside `design.md`**. It renders in GitHub PRs, Obsidian, and VS Code, and cannot drift from what the gate reads. `--publish` produces a tabbed interactive HTML view (flow + what-ifs, components, scope board) generated from `design.md`:

- **Artifact tool available:** a private claude.ai artifact, and its URL is written to `map_url`. Republish keeps the same URL.
- **Otherwise:** `.wayworks/maps/<slug>.html` (gitignored), opened locally.

GitHub Pages is excluded: it is public by default and would leak unreleased designs.

## Durable memory

| Artifact | Home | Why |
|---|---|---|
| `design.md`, `plan.md` | repo, feature branch | the gate reads them; the PR shows intent beside code |
| discovery briefs | vault `04-Knowledge/<topic>.md` | knowledge outlives a repo; 30-day reuse works across repos |
| locked / shipped events | one line in the project note's `## Log` | the user's "update the vault when done" rule, automated; links, not copies |

The vault is found the way `wayworks-onboard` finds it: declared in the user's global CLAUDE.md, never hardcoded. The skills follow the vault's own `_agent/INSTRUCTIONS.md` rather than assuming a layout. **No vault:** briefs go to `docs/discovery/<topic>.md` (or the current directory outside a repo), log lines are skipped, and the gate never depends on the vault.

**Brief reuse:** a brief under 30 days old is reused and only checked for anything new.

## Lifecycle

`draft → locked → shipped`. On ship, `loop-dev`'s feature-bank postflight **folds the design into `docs/features/`**: `W`/`Q` decisions become `acceptance_criteria` and out-of-scope items become `non_goals`. It then sets `status: shipped`. A shipped design is an immutable decision record (ADR-like) and is never edited again. feature-bank is the living truth; the repo-level map is sub-project B's generated view of it.

## Error handling

- Research subagent fails or finds nothing → brief says so explicitly; scope proceeds, and discovery is marked `partial` in frontmatter.
- User abandons mid-triage → items stay `[ ]`; the design stays `draft`; re-run resumes.
- Plan changes after lock → `status` returns to `draft` and stages 6–7 re-run (a new plan can create new what-ifs and byproducts).
- Vault write denied → brief falls back to `docs/discovery/`, which is reported.

## Known limits

- `decided-by: you` is written by the model; the gate cannot prove the human said it. The per-item record plus the triage transcript is the audit trail, not a guarantee.
- The `features` classification is a model judgement (logged, not enforced).
- Mermaid gets cramped past ~25 nodes; `--publish` is the escape hatch.

## Testing

- `design-check.test.sh` with fixtures, and it **proves it can fail**: an open item, a missing `decided-by`, an unacked byproduct, a `W` ID absent from the plan, a wrong status, and malformed lines. The same contract as `check-skill-rules.test.sh`.
- `loop-dev-preflight.test.sh` extended for `require_design` in all three modes.
- Rules manifests for `discover`, `attack`, `triage`.
- A live `/harness:design` → `loop-dev` run on one real kaffecard feature before release. The compatibility "gates exercised live" row moves only on that run.

## Release

`shared` minor (new `discover`), `harness` minor (new command, skills, script, config key), marketplace minor, CHANGELOG, README counts. All in one PR per the release rule.

## Out of scope (this spec)

- Command renames and the `/wayworks:*` command family: sub-project B. Note that `/harness:design` sits next to an existing `design` plugin (UI skills); B decides the final name.
- Repo-level generated map from feature-bank: B.
- Version-drift detection across repos: A.
