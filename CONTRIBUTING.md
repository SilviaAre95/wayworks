# Contributing to wayworks

Thanks for considering a contribution. wayworks is an opinionated way of work — contributions that sharpen the opinions are welcome; contributions that dilute them into a neutral toolkit will be declined kindly.

## Philosophy

- **Conventions-first, minimal abstractions.** Skills encode opinions and workflows, not knowledge the model already has (no language tutorials).
- **Skills are small.** House pattern: frontmatter (`name`, quoted `description`, `user-invocable`, `argument-hint`) → `Steps → Output Format → Constraints`, ~300–450 words. Anything bigger uses progressive disclosure (`references/` files loaded on demand).
- **`$ARGUMENTS` only** — never positional `$0`/`$1` (they leak literally when a skill is model-invoked).
- **Portable by default.** No hardcoded personal paths, no undeclared external dependencies, no assumptions about which tracker or vault the user has.

## Development workflow

1. Create a feature branch from `main`.
2. Run `make check` before every push or handoff — it is the exact script CI
   runs, so a green local run means a green CI run.
3. Open a pull request; never push changes directly to `main` unattended.

## Scaffolding a new skill

Use the meta-skill: `/create-skill <skill-name> <plugin-name> "<description>"` — it generates the correct frontmatter and structure. New plugins enter at `1.0.0` with a `.claude-plugin/plugin.json` matching the existing ones.

## The release rule (CI-enforced)

Any PR touching `plugins/` or `.claude-plugin/` must include, in the same PR:

1. A **version bump** in the plugin's `plugin.json` **and** its `marketplace.json` entry (kept in sync; semver policy at the top of `CHANGELOG.md`).
2. A **marketplace bump** (`metadata.version`) when the plugin set changes or the release is notable.
3. A **CHANGELOG entry** (Keep-a-Changelog format, newest first).
4. Updated **README counts/tables** if the number of plugins/skills/commands changed.

CI validates manifests (JSON, name+version sync both ways, hook script paths), lints skill and command frontmatter, runs the harness shell tests, and fails PRs that change `plugins/` without a CHANGELOG + version bump. All of it except the PR-only release rule is `make check` — run that locally.

The frontmatter linter (`scripts/lint-skills.sh`) enforces `name` (matching the directory), a quoted `description`, an explicit `user-invocable`, and `argument-hint` on any skill that reads `$ARGUMENTS`; positional `$0`/`$1` are rejected outright. Over-long descriptions and argument hints the skill never reads are reported as warnings, not failures — see AGENTS.md for why each rule is shaped the way it is.

## PR expectations

- One logical change per PR; conventional commit titles (`feat:`, `fix:`, `docs:`, `refactor:`, `chore:`; `!` for breaking).
- Breaking changes (removed plugins/commands, renamed keys) need a **Migration** section in the CHANGELOG entry.
- If your skill shells out to anything external, declare it prominently in the skill and README, and make the skill fail honestly when the dependency is missing.

## Safety boundary

Do not include tokens, private logs, personal task data, employer data, or machine-specific paths in skills, tests, fixtures, documentation, or commits. Skills must stay portable: no hardcoded personal paths and no assumptions about a specific user's vault, tracker, or machine.
