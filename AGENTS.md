# wayworks

Claude Code plugin marketplace: 14 plugins under `plugins/`, manifest at `.claude-plugin/marketplace.json`, per-plugin manifests at `plugins/<name>/.claude-plugin/plugin.json`. Public repo, consumed by other people — treat every merge as a release.

These instructions apply to any coding agent working in this repo. The plugin *format* (manifests, hooks, skills) targets Claude Code — that is the product being built, so its file layout and variable names (e.g. `${CLAUDE_PLUGIN_ROOT}`) stay as-is regardless of which agent edits them.

This file is the agent-facing summary; [CONTRIBUTING.md](CONTRIBUTING.md) is the canonical contributor guide (philosophy, PR expectations, full release rule). If they ever disagree, CONTRIBUTING.md wins — fix the drift.

## Checks

Run `make check` before every push or handoff — the exact script CI runs. Work on a feature branch and open a PR; never push directly to `main`.

## Release rule (non-negotiable)

Any change under `plugins/` or `.claude-plugin/` must land in the same commit/PR with:

1. **Version bump** in the plugin's `plugin.json` AND its entry in `marketplace.json` (they must stay in sync). Semver per the policy at the top of `CHANGELOG.md`: patch = fixes/docs, minor = new skills/commands/hooks, major = breaking. New plugin enters at `1.0.0`.
2. **Marketplace bump** (`metadata.version` in `marketplace.json`) when the plugin set changes or a plugin ships a notable release.
3. **CHANGELOG entry** in `CHANGELOG.md`, newest first, grouped by plugin, Keep-a-Changelog format.
4. **README counts** — if the number of plugins/skills/agents changed, update the counts and tables in `README.md`.

Docs-only changes outside `plugins/` (this file, `docs/`, README wording) need no bump.

## Conventions

- Skills follow the house pattern: frontmatter (`name`, quoted `description`, `user-invocable`, `argument-hint`) then `Steps → Output Format → Constraints`, ~300–450 words. Scaffold with `shared:create-skill`.
- Use `$ARGUMENTS` for argument substitution in skills, never positional `$0`/`$1` (positional only populates for typed slash commands, and leaks literally when model-invoked).
- Agents are read-only reviewers with narrow `allowed-tools`; hooks reference scripts via `${CLAUDE_PLUGIN_ROOT}`.
- Never commit loop-state files (`.cc-loop-*`, `.cc-dev-reviews-passed`) or `.superpowers/` working artifacts.
