---
name: security-scan
description: "Scan your Claude Code configuration (.claude/ directory) for security vulnerabilities, misconfigurations, and injection risks using AgentShield. Checks CLAUDE.md, settings.json, MCP servers, hooks, and agent definitions."
user-invocable: true
argument-hint: "[path-to-.claude-dir] [--min-severity low|medium|high]"
---

# Security Scan Skill

Audit your Claude Code configuration for security issues using [AgentShield](https://github.com/affaan-m/agentshield) (adapted from ECC).

> **External dependency**: this skill shells out to the third-party npm package `ecc-agentshield` — it is NOT bundled with the plugin. First run downloads it via `npx` (network required). If the download or the tool fails, report that the scan could not run and stop — do not improvise a manual scan and present it as AgentShield output.

## Running the scan

Invoked with: `$ARGUMENTS`

**Parse that string — never interpolate it.** Its values reach a shell command, so pasting it in whole turns any argument into arbitrary shell execution. Match tokens against exactly two forms and build the command from what matched:

- **A bare path** (no leading `-`) → `--path "<path>"`. If it does not exist, stop and say so — never fall back to the current directory, which reports a clean grade for somewhere the user never asked about.
- **`--min-severity`** → only `low`, `medium`, or `high`; any other value, stop.
- **Empty** → `npx ecc-agentshield scan` against the current project's `.claude/`.

Stop and report anything else — shell metacharacters (`;`, `|`, `&`, backticks, `$(`), unrecognized flags, extra positionals. Never guess. `--format`, `--fix`, and `--opus` are real capabilities but are not wired to this skill's arguments; point at the documented commands below to run those directly.

Report what the command actually returned. Never describe a scan as filtered or scoped when that argument was not applied.

## When to Activate

- Setting up a new Claude Code project
- After modifying `.claude/settings.json`, `CLAUDE.md`, or MCP configs
- Before committing configuration changes
- When onboarding to a new repository with existing Claude Code configs
- Periodic security hygiene checks

## What It Scans

| File | Checks |
|------|--------|
| `CLAUDE.md` | Hardcoded secrets, auto-run instructions, prompt injection patterns |
| `settings.json` | Overly permissive allow lists, missing deny lists, dangerous bypass flags |
| `mcp.json` | Risky MCP servers, hardcoded env secrets, npx supply chain risks |
| `hooks/` | Command injection via interpolation, data exfiltration, silent error suppression |
| `agents/*.md` | Unrestricted tool access, prompt injection surface, missing model specs |

## Running it directly

Install, output formats (`--format json|markdown|html`), `--fix`, the `--opus` adversarial pipeline, `init`, the GitHub Action, the A–F grade scale, and how to read each severity: `references/agentshield-cli.md`. Prefer pinning a reviewed version (`npm install -g ecc-agentshield@<version>`) over floating `npx` in CI or shared environments.
