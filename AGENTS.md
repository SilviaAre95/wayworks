# wayworks

Claude Code plugin marketplace: 14 plugins under `plugins/`, manifest at `.claude-plugin/marketplace.json`, per-plugin manifests at `plugins/<name>/.claude-plugin/plugin.json`. Public repo, consumed by other people — treat every merge as a release.

These instructions apply to any coding agent working in this repo. The plugin *format* (manifests, hooks, skills) targets Claude Code — that is the product being built, so its file layout and variable names (e.g. `${CLAUDE_PLUGIN_ROOT}`) stay as-is regardless of which agent edits them.

This file is the agent-facing summary; [CONTRIBUTING.md](CONTRIBUTING.md) is the canonical contributor guide (philosophy, PR expectations, full release rule). If they ever disagree, CONTRIBUTING.md wins — fix the drift.

## Checks

Run `make check` before every push or handoff — the exact script CI runs. Work on a feature branch and open a PR; never push directly to `main`.

`make check` includes `scripts/lint-skills.sh`, which enforces skill frontmatter. Its rules, and why each exists:

- `name` required and must match the skill's directory.
- `description` required and **quoted** — a bare scalar containing a colon or `#` breaks the YAML parse silently.
- `user-invocable` required and explicit (`true`/`false`) — it gates the argument rules, so leaving it to the default makes invocability an accident.
- A skill that reads `$ARGUMENTS` must declare `argument-hint`; one that does not read them must not be forced to invent one.
- Positional `$0`/`$1` are an error anywhere (only `$ARGUMENTS` is valid).

Two checks are **warnings** and never fail the build: a description over 250 chars (long descriptions are legitimate when the description is the model-invocation trigger surface), and an `argument-hint` the body never reads (real drift, but fixing it changes skill behavior, so it is surfaced rather than enforced).

Commands are linted separately and more loosely — they derive their name from the filename and use bare descriptions, so the skill rules do not apply to them.

`make check` also runs `scripts/check-skill-rules.sh`, which asserts that a skill still contains its **load-bearing rules**. Length and frontmatter checks cannot see a dropped rule: trimming `linear-update` twice removed one while every check stayed green, and only a four-grader panel reading the diff caught it. A manifest at `scripts/skill-rules/<plugin>__<skill>.rules` lists, one per line, `<what the rule is> :: <regex that must match SKILL.md>`. Patterns match the operative token rather than the sentence, so rewording passes and deletion fails — a failure names the rule in words.

**Write the manifest and baseline it BEFORE you trim, not after.** Both bugs found this way surfaced at baseline, not at the end: `create-skill` never stated that a description must be quoted (a hard lint error that silently drops every frontmatter key), and the linter's own self-test was using a skill that later became exempt as its non-exempt fixture. Not every skill has a manifest yet; add one whenever you are about to restructure a skill, and never loosen a pattern to make a trim pass without checking the rule actually survived.

`make check` also asserts that `ci.yml`'s job names match `.github/required-checks.txt`. Those names are status check *contexts* required by the branch ruleset on `main`, which lives in repo settings and cannot be seen from the repo. Rename a CI job without updating both and the ruleset keeps requiring a context nothing produces — GitHub shows it as "Expected — waiting for status to be reported" forever and every PR is blocked by a check that will never run. **Renaming a CI job means updating `required-checks.txt` and the ruleset in the same PR.**

The reverse direction — someone edits the ruleset in GitHub's UI — changes no file and triggers no workflow, so CI cannot catch it. `bash scripts/check-ruleset.sh` compares the live ruleset against the contract; run it after touching branch protection, or when a PR shows a check that never reports. It is deliberately outside `make check`, since reading a ruleset needs admin permission CI's token does not have, and a step that silently skipped in CI would make "make check is what CI runs" false.

## Before adding a skill

Check [docs/reference/first-party-overlap.md](docs/reference/first-party-overlap.md) — the official marketplace now ships 39 Anthropic-authored plugins, several in wayworks' territory. The rule it records: **if deleting a skill would cost a gate, keep it; if it would only cost a checklist, delegate it.** Checklists are commodity now; the enforcement is not.

## Upstream changes

[docs/reference/compatibility.md](docs/reference/compatibility.md) records the Claude Code version wayworks was last verified against and the specific contracts the gates depend on — hook events and output shapes, `${CLAUDE_PLUGIN_ROOT}` expansion, bundled-skill invocation, frontmatter keys. Read it before changing a hook or a loop command. Its "Tested against" table has **two rows with different evidentiary bars**: *checks and docs* moves when `make check` and the doc audits pass on a new version, but *gates exercised live* moves **only** after a real `/harness:loop-dev` run drives the `Stop` hooks end to end. Never advance the second row on the strength of a green `make check` — that erases the only distinction the table exists to make.

**Issues generated from release notes are leads, not specifications.** Three of five in the 2026-08-05 batch were materially wrong — a command that did not exist, a file deleted weeks earlier, a measurement nothing could produce. Verify the claim at its primary source, verify the repo still matches the description, and correct the issue when it is wrong. Confident phrasing is not evidence.

## Release rule (non-negotiable)

Any change under `plugins/` or `.claude-plugin/` must land in the same commit/PR with:

1. **Version bump** in the plugin's `plugin.json` AND its entry in `marketplace.json` (they must stay in sync). Semver per the policy at the top of `CHANGELOG.md`: patch = fixes/docs, minor = new skills/commands/hooks, major = breaking. New plugin enters at `1.0.0`.
2. **Marketplace bump** (`metadata.version` in `marketplace.json`) when the plugin set changes or a plugin ships a notable release.
3. **CHANGELOG entry** in `CHANGELOG.md`, newest first, grouped by plugin, Keep-a-Changelog format.
4. **README counts** — if the number of plugins/skills/agents changed, update the counts and tables in `README.md`.

Docs-only changes outside `plugins/` (this file, `docs/`, README wording) need no bump.

## Conventions

- Skills follow the house pattern: frontmatter (`name`, quoted `description`, `user-invocable`, `argument-hint`) then `Steps → Output Format → Constraints`, ~300–450 words. Scaffold with `shared:create-skill`. **Only the 450 ceiling is linted, and only as a warning** — a skill past it either trims or moves detail into `references/` (progressive disclosure), which exempts it. There is no floor: brevity is not a defect, and the six skills under 300 all carry the full pattern. Stack profiles are exempt from both, being auto-loaded reference rather than invoked procedures.
- Use `$ARGUMENTS` for argument substitution in skills, never positional `$0`/`$1` (positional only populates for typed slash commands, and leaks literally when model-invoked).
- Agents are read-only reviewers with a narrow `tools:` list — **comma-separated**, e.g. `tools: Read, Glob, Grep`. `allowed-tools` is a *skill* key and is silently ignored in agent frontmatter, which left both shipped reviewers running with every tool until 2026-09-09; `lint-skills.sh` now rejects it. Hooks reference scripts via `${CLAUDE_PLUGIN_ROOT}`.
- Never commit loop-state files (`.cc-loop-*`, `.cc-dev-reviews-passed`) or `.superpowers/` working artifacts.
