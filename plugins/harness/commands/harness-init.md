---
description: Set up the harness in this project — permission policy, verify gate, gitignore
allowed-tools: Read, Edit, Write, Bash(cat:*), Bash(ls:*)
---

Set up the harness in the current project. Make each change visible and ask before overwriting existing values.

1. **Verify gate** — if `.cc-verify` does not exist, create it containing the project's green-gate command. Default for a Node/npm repo:
   ```
   npm run lint && npm run build && npm test
   ```
   If the project is not Node, infer the correct command (e.g. `pytest`, `cargo test`) and confirm with the user.

2. **Git-ignore loop state** — ensure `.gitignore` contains these lines (append if missing):
   ```
   .cc-loop-active
   .cc-loop-state
   .cc-loop.log
   .cc-loop-dev-active
   .cc-loop-dev-state
   .cc-dev-reviews-passed
   .cc-loop-dev.log
   .cc-deploy-active
   .cc-deploy-state
   .cc-deploy.log
   .cc-loop-standdowns.log
   .cc-loop-gate.lock*
   ```
   `.cc-verify` is project config (not transient state) and **should be committed** so a fresh clone retains the correct gate command. Do NOT add it to `.gitignore`.

3. **Dev loop config** — if `.cc-dev.yaml` does not exist at the project root, copy it from the plugin's `templates/.cc-dev.yaml`. This is committed config (like `.cc-verify`) — do NOT add it to `.gitignore`.

4. **Deploy loop config** — if `.cc-deploy.yaml` does not exist at the project root, generate it by **detecting where this repo deploys**, then confirm the detected target with the user before writing:
   - **Railway** — `railway.json`, `railway.toml`, or a linked Railway project present → copy `templates/.cc-deploy.railway.yaml`.
   - **Vercel, single app** — `vercel.json` or `.vercel/` at the repo root, and no app-level links (below) → copy `templates/.cc-deploy.vercel.yaml` as-is.
   - **Vercel, monorepo** — `.vercel/` or `vercel.json` inside app directories (check at least `apps/*/` and `packages/*/`; a root link may or may not also exist, and `.vercel/` is gitignored, so on a fresh clone a `vercel.json` may be the only visible signal). Each linked directory is its own Vercel project, so the single-app template would silently deploy only one of them. Copy `templates/.cc-deploy.vercel.yaml`, then rewrite the commands to cover every app, following the template's MONOREPO comment: `deploy` scoped per app with the global `--cwd <app-dir>` flag and chained with `&&`; `watch` set to `"true"` (each chained deploy already blocks until it resolves — the root-scoped default would fail with no root link); `verify` composing every app's health/smoke checks with `&&`; `rollback` scoped per app using the template's flag chain (`r=0; … || r=1; …; test $r -eq 0`) so every app's rollback is attempted and any single failure still fails the whole command — the gate treats rollback exit 0 as "prod safe", so never `&&` (skips apps) or `;` (masks failures). If the root link is itself a deployable app, include it too (`--cwd .`). Confirm the list of deployable apps with the user — every app must appear in `deploy`, `verify`, and `rollback`. These command strings are later `eval`'d by the deploy gate: only embed app paths matching `[A-Za-z0-9._/-]+` — if a detected directory name contains anything else (spaces, quotes, `$`, backticks, `&`, `;`), do not compose the command; show the raw name to the user and have them write the commands themselves.
   - **Neither detected** → copy the neutral `templates/.cc-deploy.yaml`. Its `deploy`/`verify`/`rollback` commands are guarded placeholders that exit non-zero on purpose, so the loop refuses to run until the user fills them in. Tell the user the deploy loop cannot run until they set these for wherever the repo actually deploys.

   If more than one target matches (e.g. `railway.toml` at the root plus Vercel-linked apps), do not pick one silently — surface every match to the user and compose commands covering each target they confirm.

   Whichever variant you copy, land it as `.cc-deploy.yaml` at the project root and replace its example domain/commands with the project's real ones where you can infer them. This is committed config (like `.cc-verify`) — do NOT add it to `.gitignore`.

5. **Project allow list** — merge the `permissions.allow` block from the harness permission policy into this project's `.claude/settings.json` (create the file if absent). Do NOT duplicate entries already present. The canonical block is:
   ```json
   "allow": [
     "Bash(npm run *)", "Bash(npm install*)", "Bash(npm test*)",
     "Bash(git add *)", "Bash(git commit *)", "Bash(git status*)",
     "Bash(git diff*)", "Bash(git log*)", "Bash(git push *)",
     "Read(*)", "Grep(*)", "Glob(*)"
   ]
   ```
   Add project-specific deploy-tool reads (e.g. `Bash(railway status*)`) only if that tooling is present.

6. **Remind the user** that the universal floor (`deny`) and hard gates (`ask`) belong in `~/.claude/settings.json` (global), not the project — point them to `docs/reference/permission-policy.md` in the wayworks repo, and note that this command intentionally does not edit global settings.

Report a summary of exactly which files you changed.
