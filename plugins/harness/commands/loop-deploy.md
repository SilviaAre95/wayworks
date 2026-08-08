---
description: Deploy, watch, verify prod, and fix→redeploy until healthy (or roll back + escalate)
argument-hint: [--env prod|staging]
allowed-tools: Bash(${CLAUDE_PLUGIN_ROOT}/hooks/scripts/loop-arm.sh:*), Bash(cat:*), Bash(rm:*)
---

Read `.cc-deploy.yaml` (deploy, watch, verify, rollback, max_redeploys, migrations_gate). If it is missing, stop and ask the user to create it — do not guess deploy commands.

Then arm the deploy loop:

!`"${CLAUDE_PLUGIN_ROOT}/hooks/scripts/loop-arm.sh" deploy`

The deploy loop is **ARMED**. Execute these stages for the target below:

1. **Approve (hard gate).** Deploying to production is a risky action — get an explicit Approve/Deny first. If this deploy runs a **database migration** and `.cc-deploy.yaml` `migrations_gate` is true, get a **second** explicit approval that names the migration. Never deploy prod or run a migration unattended. If you deny the deploy or deny a required migration approval, disarm the loop first: run `rm -f .cc-deploy-active .cc-deploy-state`, then stop. (If invoked with `--env staging`, a single Approve is enough — the prod hard-gate and the migration double-gate apply only to production.)
2. **Deploy.** Run the `deploy` command. Post to Slack a "🚀 deploying <target>" start ping (bare URLs only).
3. **Watch.** Run the `watch` command until the deploy resolves. If it fails or times out, do not loop back to redeploy inline — attempt to finish instead, so the `Stop` hook runs `verify` and counts the attempt against `max_redeploys`.
4. **Verify.** When you attempt to finish, the `Stop` hook runs the `verify` command (health + smoke + error-rate). If it fails, it blocks: fix the problem (you may run `/loop-dev` for a code fix) and **redeploy**. Do not stop until prod verifies healthy.
5. **Exhaustion.** After `max_redeploys` failed attempts the hook runs the `rollback` command, disarms, and tells you to stop — then post to `#alerts`: "⚠️ <target> failed to deploy, rolled back — <one-line why>". Never leave prod broken.
6. **Success (knowledge sync).** When verify passes, the loop closes. Before announcing, sync the three knowledge surfaces:
   - **Repo**: confirm the docs reflect what shipped — feature-bank postflight done for touched features; README/CHANGELOG updated if the change is user-facing.
   - **Second brain**: if the user's global CLAUDE.md declares a vault, append a dated one-line entry to the project's vault note (Log section), following the vault's own write rules. No vault → skip.
   - **Tracker**: move the Linear issue to Done.
   Then post to Slack: "🚀 <target> deployed, prod healthy" with the bare deployment URL.

The `Stop` hook enforces the verify gate — you cannot finish while prod verification is failing, and you cannot exceed the redeploy budget without a rollback.

Target: $ARGUMENTS
