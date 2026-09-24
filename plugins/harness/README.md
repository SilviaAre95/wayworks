# harness

Tiered autonomy + a build-test-fix loop, so development becomes "kick off a workflow and walk away."

## Tiers (switch with Shift+Tab)

| Tier | Permission mode | Behavior |
|------|-----------------|----------|
| explore | `plan` | read/search only |
| build | `acceptEdits` | auto-accept edits + auto-run your allow list |
| ship | `default` | interactive; only hard gates prompt |
| escape | `bypassPermissions` | full auto (floor `deny` still applies) |

## The loop

`/harness:loop-build <task>` arms a `Stop` hook that runs your verify gate
(`.cc-verify`, default `npm run lint && npm run build && npm test`) and won't let
Claude stop until it's green — fixing and retrying up to 5 times, then summarizing.
Read-only tools are auto-approved in every tier so exploration never stalls.

### `/harness:shape <topic> [--stage <name>] [--publish]`

Moves human supervision *before* code, so `/harness:loop-dev` can build unattended. Walks a topic through nine stages — discover (`shared:discover`, code preset) → scope (in/out review) → attack scope (`harness:attack --target scope`) → feature questions (brainstorming discipline) → plan (`superpowers:writing-plans`) → what-ifs (`harness:attack --target plan`) → byproducts (undirected work, acknowledged) → map (Mermaid flow + component diagrams) → lock — writing `docs/designs/<slug>/design.md` and `plan.md`. Attack and triage stages produce numbered findings and batch-decided lines (`- [x|~| ] <A|Q|W|B><n> · ... · decided-by: ...`); resumable via frontmatter `stage:`, and `--stage <name>` re-opens from any point (re-opening `plan` re-runs what-ifs and byproducts too, since a new plan can create new ones).

**The gate**, `scripts/design-check.sh`, is deterministic — no model in the loop. It reads decision lines only from the `## Decisions` section (bullets and to-dos elsewhere are ignored) and blocks on: a missing or duplicated `## Decisions` section, any open (`- [ ]`) item, a non-canonical checkbox there (indented, blockquoted, `*`, `+`, numbered) or an unclosed code fence, a decided item with no `decided-by: you|accepted-default`, an unacknowledged byproduct, and a decided what-if (`W`) with no matching task in `plan.md`. Locking requires the gate green **and** the user's explicit yes. A `shipped` design never re-opens: `shipped` means loop-dev built from it and is opening its PR, so a change of mind is a new slug.

**`require_design`** in `.cc-dev.yaml` gates `/harness:loop-dev` on a shaped design: `never` (absent key defaults here — existing repos are unaffected) does no classification. A *design plan* is a `--plan` inside `docs/designs/`. `features` has the agent classify the task as feature vs. fix/chore/docs and blocks a feature with no design plan; `always` blocks any build without one. In every mode, `--plan` is resolved to a real path first (`docs/./designs`, `//` and symlinks). One outside the repo under a `docs/designs/` directory — another repo's design — is blocked before anything else runs; any other out-of-repo plan (plan mode writes `~/.claude/plans/*.md`) is an ordinary plan. A design plan must be the design's own `plan.md` passed by its real path (a symlink into or out of `docs/designs/`, a `.` or `..` segment after an optional leading `./`, or a `--plan` ending in `/`, blocks), its `design.md` must also resolve inside the repo, and the locked design must pass `design-check.sh`. loop-dev commits the locked design before building and commits the fold and `shipped` flip before stamping; a re-run of the same `--plan` passes without `--require-locked` only when a locked version is in history and the committed `shipped` version differs from the merge-base — otherwise it blocks on `shipped != locked`.

**`--publish`** renders `design.md` itself — the Mermaid flow, components, and scope board — to a local HTML page via `scripts/render-map.sh --open`, which opens it with `open` (macOS) or `xdg-open` where present and otherwise just prints the path. It needs `jq`. The page lands in `.wayworks/maps/`, which is git-ignored; nothing is hosted or committed, and it never writes through a symlink there. The page's three CDN scripts are version-pinned and carry SRI hashes.

### `/harness:loop-dev <task> [--check-plan]`

Extends `/harness:loop-build` into a full staged dev loop: read the task (a bare
tracker key is fetched, never guessed at), spec preflight, plan (pass
`--plan <path>` to hand it a written plan, e.g. from superpowers; a design
plan from `docs/designs/` is gated as above), build,
**review stages** (`code-review`, `security`, `bugs` by default; add `design`
for frontend repos — any grader name maps to the same-named skill) each run
as a dispatched subagent against the diff, then a **dev-test stage** that
exercises the change the way the product is used (feature-spec `test_plan`,
browser flow, endpoint checks, or `pipeline-verify` for data pipelines) and a
**feature-bank postflight** before the marker is stamped. Its `Stop` hook won't let Claude
finish until `.cc-verify` is green **and** `.cc-dev-reviews-passed` exists —
a failing `.cc-verify` clears the marker, so a broken build forces reviews to
re-run. In a git repo the marker is stamped with an anchor commit (the
merge-base with `base`, frozen at stamp time), a working-tree fingerprint
against it, and the commit every grader echoed as reviewed. The hook
re-verifies both at stop time — tracked changes landing after the graders
passed, committed or not, invalidate it, and so does a reviewed commit that is
not exactly the certified tree (a grader whose worktree sat on `main`, or
uncommitted tracked changes no worktree grader saw; untracked files are not
fingerprinted). That each grader read that commit
rests on its echoed report. An empty (`touch`ed) marker is the non-git escape hatch and is
trust-based. On success it
pushes the branch, opens a PR (unless `open_pr: false`), and watches the PR's
CI checks to green before handing over. Config — graders, `max_retries`, diff
`base`, `open_pr` — lives in `.cc-dev.yaml`. Pass `--check-plan` to pause
after the plan step for your approval before it builds.

Arming runs a **config preflight** first, because every one of these failures
was otherwise found at the review stage — after a full implementation had been
built: a `base` that cannot resolve (the marker is anchored on `merge-base
<base> HEAD`), a missing `.cc-verify` in a non-Node repo (the gate falls back to
`npm run lint && npm run build && npm test` and can never go green), a tracked
loop-state file (a tracked marker invalidates its own fingerprint and livelocks
the hook), and a `graders:` key with no value. It also prints the configured
grader list so the agent can confirm each one resolves to a skill that is
actually enabled — a shell script cannot see the session's plugin set, and a
grader naming a skill you do not have is the common case (`bugs` needs
`qa@wayworks`).

> **Upgrade-sensitive:** the default `code-review` grader dispatches Anthropic's
> *bundled* `/code-review` skill by name. Bundled-skill invocation policy is set
> by Claude Code, not by this plugin — v2.1.215 stopped auto-running `/verify`
> and `/code-review` from description-matching alone. Re-check this grader
> actually fires after a Claude Code upgrade: a degraded grader still stamps the
> marker, so the loop cannot detect it for you.

### `/harness:loop-deploy [--env prod|staging]`

Deploys, watches the rollout, then verifies prod (health + smoke + error-rate)
and won't let Claude stop while verification is failing — it fixes the problem
(optionally via `/harness:loop-dev`) and redeploys until healthy. After
`max_redeploys` failed attempts the `Stop` hook runs `rollback`, disarms the
loop, and escalates instead of looping forever, so prod is never left broken.
Deploying to prod is a hard Approve/Deny gate, and a deploy that runs a DB
migration needs a **second** explicit approval when `migrations_gate` is true.
On success it syncs the knowledge surfaces — repo docs, the project's vault
note log, the Linear issue via `/shared:linear-update` — before announcing on Slack.
Config — `deploy`, `watch`, `verify`, `rollback`, `max_redeploys`,
`migrations_gate` — lives in `.cc-deploy.yaml`.

## Quality hooks

Always-on (no arming needed), each with cheap no-op paths outside its scope:

- **Stray-doc gate** — creating a *new* `.md`/`.txt` outside the standard set
  (README/CLAUDE/AGENTS/CONTRIBUTING/CHANGELOG/LICENSE/SKILL basenames;
  `docs/`, `.claude/`, `.github/`, `skills/`, `commands/`, `agents/`,
  `memory/`, scratchpad paths) prompts for approval instead of landing
  silently. Editing an existing doc is never gated.
- **Write-time type-check** — after a TypeScript edit, runs the project's own
  `tsc --noEmit` (only when `tsconfig.json` and a local `node_modules/.bin/tsc`
  exist — never npx-installs) and feeds back errors *in the edited file only*,
  max 10 lines, so type breakage surfaces at edit time instead of at the
  verify gate.
- **console.log sweep** — on stop, warns (never blocks) about `console.log`
  left in modified tracked JS/TS files.

## Setup

1. Enable the plugin (it's in the `wayworks` marketplace).
2. Run `/harness:harness-init` in each project to create `.cc-verify`, git-ignore loop
   state, scaffold `.cc-dev.yaml` and `.cc-deploy.yaml`, and seed the project
   allow list.
3. Add the **permission policy** to your settings — a plugin cannot grant
   permissions. See `docs/reference/permission-policy.md`: the floor (`deny`) and
   hard gates (`ask`) go in `~/.claude/settings.json`.

## State files

**Git-ignored (transient):** `.cc-loop-active` sentinel (every sentinel holds the id of the Claude Code session that armed it; a `Stop` from any other session in the checkout is not gated and gets a one-line notice naming the owner — an empty sentinel, armed without an id, is gated for every session) · `.cc-loop-state` counter · `.cc-loop.log` last gate output · `.cc-loop-dev-active` sentinel · `.cc-loop-dev-state` counter · `.cc-loop-dev-rounds` review-round counter · `.cc-dev-reviews-passed` marker · `.cc-loop-dev.log` last gate output · `.cc-deploy-active` sentinel · `.cc-deploy-state` counter · `.cc-deploy.log` last gate output · `.cc-loop-gate.lock/` gate mutex (all gates serialize on it; stale locks are reclaimed automatically) · `.cc-loop-standdowns.log` stand-down audit trail — one line per circuit-breaker trip (`timestamp loop breaker detail head= diff=`), and one `reclaimed from=<old> by=<new>` line when an arm takes a loop over from another session, append-only, never deleted by a gate. A loop that ended by exhausting its breaker looks identical to a clean green run from the outside; this file is how a reviewer tells them apart after the fact.

**Committed (project config):** `.cc-verify` — the gate command run on every stop attempt; commit it so a fresh clone keeps the right gate and its contents are trusted (they're `eval`'d by the loop gate) · `.cc-dev.yaml` — `/harness:loop-dev` config (graders, max_retries, base, open_pr) · `.cc-deploy.yaml` — `/harness:loop-deploy` config (deploy, watch, verify, rollback, max_redeploys, migrations_gate).
