# Changelog

All notable changes to the **wayworks** marketplace and its plugins.
Format follows [Keep a Changelog](https://keepachangelog.com/); the marketplace and each plugin follow [Semantic Versioning](https://semver.org/).

## Versioning policy

- **Per plugin** (`plugins/<name>/.claude-plugin/plugin.json` **and** its `marketplace.json` entry — keep them in sync): bump **patch** for fixes/docs, **minor** for new backward-compatible skills/commands/hooks, **major** for breaking changes to a plugin's interface.
- **Marketplace** (`metadata.version`): bump when the set of plugins changes or a plugin ships a notable release — generally the largest bump of that release.
- A **brand-new plugin** enters at `1.0.0`.
- Record every release below, newest first, grouped by plugin.

---

## [marketplace 6.2.2] — 2026-09-10

### Fixed
- **`shared` `2.3.4`** — `create-skill` never said to quote the description. An unquoted one is a hard error in `lint-skills.sh` and silently drops every frontmatter key, so the skill stops resolving — yet the skill that scaffolds every new skill only showed quotes inside a template example. Found by baselining its rules manifest before a trim, which is the same shape as the `allowed-tools` bug this file already propagated into both shipped agents.

### Changed
- **`security` `2.0.2`** — `security-scan` 873 → **445 words**. Install commands, output formats, `--fix`, the `--opus` pipeline, `init`, the GitHub Action and the grade scale are lookup material that loaded on every invocation; they move to `references/agentshield-cli.md`. The argument-parsing and honesty rules — never interpolate `$ARGUMENTS`, stop on shell metacharacters, report what the command actually returned — stay in the body and are now asserted by a manifest.
- **`shared` `2.3.4`** — `create-skill` 647 → **441 words**, frontmatter tables and Claude 5+ verbosity guidance to `references/frontmatter.md`, with the two load-bearing rules repeated in the body.
- **`scripts/lint-skills.sh`** — accepted overruns are recorded with their reason rather than warning forever, which is how the length gap went unnoticed for a month. Two entries: `linear-update` (455, the measured floor — every version under 450 lost a rule) and `feature-bank`'s description (the trigger surface for a gate that must fire on many phrasings). The self-test covers both directions, including that an exemption does not leak to a sibling skill.

Warnings are down 18 → 5 across these releases. The five that remain — `code-audit` 616, `heuristic-eval` 527, `repo-protection` 520, `linear-project` 513, `ci-pipeline` 503 — are real and untouched.

## [marketplace 6.2.1] — 2026-09-10

### Added
- **`scripts/check-skill-rules.sh`** — asserts a skill still contains its load-bearing rules, from a manifest per skill in `scripts/skill-rules/`. Trimming has twice dropped a rule while every word-count and frontmatter check stayed green: `linear-update` lost the marker line's mandate and the `In Review` placement clause, and only a four-grader panel reading the diff caught them. Patterns match the operative token rather than the sentence, so rewording passes and deletion fails. Its self-test proves it can fail — dropped rule, empty manifest, comments-only manifest, missing target, malformed line, bad filename — because a checker that always passes is the failure mode it exists to prevent. It is **not** an eval: it verifies text survived, not that behaviour held. `claude plugin eval --ablation with-without` is the real measurement and is gated behind early access on this account; when it lands, these manifests become its grader criteria.

### Changed
- **`shared` `2.3.3`** — `linear-issue` trimmed 952 → 682 words. The 188-word worked example moved to `references/example-short-form.md`, so it loads only when a writer wants it instead of on every invocation, and the prose around the rules is cut. All 35 rules are asserted by the new check and verified intact — it caught one regression during the trim, which turned out to be an over-tight pattern rather than a lost rule, and the pattern was loosened. It does not reach 450 and should not: what remains is 35 distinct rules, not explanation, and `references/` is the documented escape hatch for that.

## [marketplace 6.2.0] — 2026-09-10

### Added
- **`harness` `2.2.0`** — `loop-dev` step 5 now isolates the grader panel, and verifies the read-only claim where it cannot. Preferred: dispatch each grader with per-subagent worktree isolation (`isolation: "worktree"` on Claude Code's Agent tool), so a grader that writes damages only its own copy. Graders read the committed diff against `base`, which a worktree checkout carries, so isolation costs nothing. Where the dispatcher cannot isolate, step 5 verifies instead of trusting. The existing rule only refused graders whose *contract* is to mutate (`/simplify`); it did nothing when a grader that promises to read writes anyway. In a real run the bundled `/code-review` staged and applied a revert of every changed file mid-panel, seen independently by two other graders, one of which restored the tree before finishing. The panel is concurrent, so a grader reviewing a tree another grader is rewriting reviews bytes that were never yours — and the marker would have stamped that as clean. The hazard is broader than a rogue grader: while this very change was being written, a second Claude session checked out its own branch in the same repo, and four just-made commits vanished from the working tree (they were committed and pushed, so nothing was lost — but the tree no longer matched what had been reviewed). A shared checkout is the common cause; a worktree is the fix. Step 5 records `HEAD` and a diff fingerprint before each round and re-checks after; if either moved, the round is re-run and nothing is stamped. Grader prompts also now ask for `git status --porcelain` before and after.
- **`scripts/lint-skills.sh`** — warns when a skill falls outside the 300-450 word house range. Nothing checked it before, so the range read as a rule while behaving as a suggestion. It is a **warning**, matching the description-length precedent: a table-shaped skill pays a large structural cost before its first rule, and a terse skill can sit under the floor without being wrong. **17 of 49 skills currently warn**, which is the finding — either the range is wrong or a third of the repo is.

### Changed
- **`.claude/settings.json`** — deny list gains `dd` and `mkfs`. AgentShield asked for `> /dev/` to be blocked; Bash rules here are prefix-matched, so a `Bash(> /dev/:*)` entry would match only a command *beginning* with a redirect, i.e. nothing. Denying the device-writing commands themselves covers the same risk in a form the matcher actually applies.

## [marketplace 6.1.2] — 2026-09-10

### Fixed
- **`shared` `2.3.2`** — `conventions`' new sweep bullet named three agents a consumer does not have. `qa:regression-scanner` was removed in marketplace 5.0.0 and no `plugins/qa/agents/` directory exists; `explorer` and `security-auditor` are user-level agents in the author's `~/.claude/agents`, not shipped by this marketplace. wayworks ships exactly two agents, `security:finding-verifier` and `architect:design-reviewer`. The bullet now names `Explore` and a general-purpose agent, both of which every caller has, and says why. Its cost figures were re-measured and are correct as written.
- **`docs/reference/model-policy.md`** — still documented the `design-reviewer` model pin that `architect` 2.0.3 removed, in both the tiers table and the pinning section. No agent in this repo pins a model now, and the file says so.

### Changed
- **`docs/reference/model-policy.md`** — fan-out, session-growth and read-shunt figures refreshed against one run of `scripts/measure-token-spend.py` (161 transcripts, 11,243 turns). The section carried three tables from different runs, so its own numbers disagreed with the `shared` skill quoting them. Subagents are 5.1% of spend at ~7x cheaper per turn and ~1/6th the context; a perfect read-shunt would address 0.73%. A claim that the largest session was 57% of spend against 53% of turns is dropped — the script prints no per-session spend, so it cannot be re-derived.

## [marketplace 6.1.1] — 2026-09-10

Both changes come from a token-spend audit of local transcripts, run with `scripts/measure-token-spend.py`.

### Changed
- **`shared` `2.3.1`** — `conventions` gains a bullet on reaching for an agent rather than an inline skill when the task is a sweep. The existing delegation bullet said *what* to delegate; it did not say that the choice of vehicle matters. A skill runs in the caller's context and leaves its whole working set behind, an agent runs in a sidechain and returns only its conclusion: measured across 159 transcripts and 10,886 turns, subagent turns cost ~7x less than interactive ones and carry ~1/6th the context (5.2% of spend against 94.8%). The editing and review carve-outs are unchanged — a reviewer must see the code, never a summary of it.

### Fixed
- **`architect` `2.0.3`** — `design-reviewer` no longer pins `model: sonnet`. Claude Code resolves the alias before dispatch, verified directly: with `ANTHROPIC_BASE_URL` pointed at a local Ollama, `claude --model sonnet` fails with *"There's an issue with the selected model (claude-sonnet-5)"*. Under a ristretto local tier that variable covers the whole process, so the pin asked Ollama for a model it does not serve and the subagent failed mid-stage. It failed *closed* — there is no route from that process to the Anthropic API — but it failed, and preflight could not catch it, because the ristretto check validates the provider's configured model against the endpoint and never sees agent frontmatter.

  Ollama aliases (`ollama cp qwen... claude-sonnet-5`) and conditional dispatch prose were both considered and rejected once the prize was measured: pinning Sonnet across every subagent saves ~3% of spend, which does not buy a cross-provider failure mode. An unpinned agent inherits the run's model and works against any provider — the right default for a plugin that ships to other people. This was the only pinned model in the repo.

## [marketplace 6.1.0] — 2026-09-09

### Added
- **`shared` `2.3.0`** — `commit-message` and `pr-description`. Neither artifact had a house format, so every run improvised one and both ran long. `commit-message` requires one logical change per commit, a conventional subject under 60 characters, and a body that gives the reason rather than the diff. `pr-description` fixes six sections — one-liner, what changed, why, type, files, tests — under 250 words.

### Changed
- **`shared` `2.3.0`** — `conventions` carried three commit bullets that nothing pointed at and that were ignored in practice. It now points at `commit-message` rather than restating them, so the rules live in one place.
- **`harness` `2.1.0`** — `loop-dev` steps 4 and 8 wrote their own commit messages and PR bodies, which is where the overlong output came from. Both now delegate to the `shared` skills, and step 8 states that review chronology belongs in review threads, not the PR body.

## [marketplace 6.0.1] — 2026-09-09

### Changed
- **`shared` `2.2.6`** — `linear-update` had grown to 712 words, well past the 300-450 house range, because three rounds of fixes each added a rule and none removed prose. Trimmed to **455** — a 36% cut, but **5 words over the ceiling, deliberately**. Every attempt to land under 450 cost a load-bearing property, so the rules won and the convention did not.

  Every rule is intact: all seven event rows and the state each maps to, the 80-word comment cap, the marker-**and**-URL duplicate check with its marker line — which every comment **must** end with — the `links` attachment step, and all five Constraints bullets.

  What was cut, complete: the worked `stood-down` example; the lead paragraph; the standalone paragraph after the output-format block; the rationale behind steps 2 and 5 (including step 5's note that re-attaching the same URL is idempotent); the explanatory second sentence of the first Constraints bullet; and the inline `` (`deployed`) ``/`` (`merged`) `` parentheticals in the third, whose event mapping the table already carries.

  On the marker mandate specifically, since review pushed on it twice: `main` stated it descriptively in step 2 ("Every comment ends with the marker line") and normatively only in the standalone paragraph. Step 2 now says **must** end with it, so the mandate moved into the step rather than being lost — the standalone paragraph stays cut as redundant restatement, not as a second independent bound. The word "required" no longer appears in the file; the requirement does. Every other difference from the pre-trim revision is a reword that preserves meaning, checked sentence by sentence.

  **Why 450 is not reachable.** Under `wc -w` the file decomposes, reconciling exactly to 455: frontmatter including its `---` delimiters (59), the four Markdown headings (10), the seven-row event table (113, of which 32 are the bare `|` tokens `wc -w` counts as words), the output-format block including its fences (41), the six steps (131), and the five Constraints bullets (101). That is **223 words of structure before a single rule is written**, against **232** for the rules themselves. Two trims did get under the ceiling, and review caught what each one cost: first the mandate that the marker line is *required* — which left `stood-down`, the one event carrying no URL, with no reliable suppression key and reopened the double-post that 2.2.5 shipped to fix — and then the instruction that the URL sits on its own line. Both are restored.

  The range is a convention, not a gate: `lint-skills.sh` has no word-count check, so `make check` is green at 455, at 446, or at 712. If the range is meant to bind, it needs either a lint rule or an exemption for skills whose output contract is a table.

  Still gone, and worth knowing: the reasons behind the rules. The argument that kept a future editor from re-simplifying the two-part duplicate check is no longer in the file, and nothing automated replaces it.

## [marketplace 6.0.0] — 2026-09-09

`/simplify` was recommended as a grader. It applies its own fixes.

**Breaking**: `simplify` was a documented `graders` value in 5.1.0 and the preflight now refuses it, so a consumer who copied that advice gets a blocked loop. Hence the major bump rather than the patch this shipped as at first — caught on review.

### Fixed
- **`harness` `2.0.0`** — the `simplify` guard added earlier in this same release was **advisory only**. It called `echo` instead of `err`, so the preflight printed `BLOCK: …` and then `PREFLIGHT OK` and exited **0** — a BLOCK line and a proceed line in the same output. Reproduced before fixing. The test that was supposed to cover it grepped for the message and never asserted the exit code, which is exactly how it shipped green; it now asserts `RC=1` and that `PREFLIGHT OK` is absent.

- **`scripts/lint-skills.sh`** — the agent section rejected `allowed-tools` but never *required* `tools`, leaving the identical hole: an agent with only `name` and `description` also resolves with every tool, and linted clean (verified). And the whitespace guard only fired when the value contained no comma at all, so `tools: Read, Glob Grep` passed with `Glob Grep` as one bogus tool name, silently dropping Grep. `tools` is now required, and every comma-split element is checked.

- **`shared` `2.2.5`** — `create-skill`'s frontmatter table, which is where `allowed-tools: "Read Grep Glob"` came from, still documented that key as "space-separated" and named no `tools` key at all, so the next author reproduces the bug the rest of this release fixes. The row now says comma-separated, says it is skills and commands only, and a new section covers agent frontmatter. All six `allowed-tools` uses left under `plugins/` are commands, and all are comma-separated.

- **`architect` `2.0.2`** — moving `system-design`'s critique after the output format (correct, since the reviewer needs a design to read) left `## Steps` ending at 5, so a run could satisfy every numbered instruction and stop without ever dispatching `design-reviewer`. A step 6 now points at it.

- **`shared` `2.2.5`** — `linear-update`'s new per-event duplicate rule was not decidable from the data it had. `list_comments` returns text, and nothing in the comment identified the event, so the only usable signal was the first line — which for `pr-opened` carries the CI result and *changes* when `loop-dev` step 7 re-runs after fixing red CI, double-posting. Every comment now ends with a required `_(linear-update: <event>)_` marker, and suppression matches marker **and** URL. `loop-dev` step 7 described the replaced URL-only rule and now matches.

- **`docs/reference/compatibility.md`** — agent frontmatter is a Claude Code contract that fails silently, which is what that file exists to record, and it was not in there. Now documented with the verification: comma-separated `tools:` required, `allowed-tools` ignored, absent `tools` means every tool, whitespace inside an element drops the tools it meant to grant. The exact frontmatter-key census was also stale, so it is coarse now.

- **`README.md`** — the `linear-update` row still listed five events, missing `started` and `merged`.

- **`harness` `2.0.0`** — **5.1.0 recommended a mutating skill as a review grader, and that is a hole in the marker.** `/simplify`'s own contract is "review the changed code … **then apply the fixes**", unlike `/code-review` whose `--fix` is opt-in. Graders are dispatched as one concurrent batch, so a mutating grader edits the tree the other graders are mid-review on; worse, its self-applied edits are not findings *the agent* fixed, so the re-run rule never fires on them and they land inside the reviews marker's fingerprint with **no grader having read them**. That is exactly what the anchor-plus-fingerprint marker exists to prevent. `simplify` is removed from the template, the README and `loop-dev` step 5, replaced by an explicit read-only requirement, and the preflight now emits a `BLOCK:` for it.

- **`harness` `2.0.0`** — 5.1.0 added `security-review` to three prose surfaces and missed the only machine-readable one. `loop-dev-preflight.sh`'s `GRADERS_TO_RESOLVE` case block had no arm for it, so it fell through to "needs whichever plugin provides it" — and `loop-dev` step 1 tells the agent to **STOP** when a grader does not resolve, suggesting `/plugin install`. An agent would hunt for a plugin that cannot exist, or halt before building. This was visible in the arm output of the first real loop run and read past. Four tests added covering both new arms; the previous "verified with a live gate run" exercised `loop-dev-gate.sh`, which echoes the graders string verbatim and never maps names.

- **`harness` `2.0.0`, `docs/reference/model-policy.md`** — the never-downgrade rule named only `security`, so a dispatcher tiering `security-review` by analogy with the other slash-command grader would have run an adversarial security pass on a cheaper model. Both security graders now inherit the session model.

- **`docs/reference/compatibility.md`** — the bundled-skill section still described a single affected grader. After 5.1.0 the blast radius of `disableBundledSkills` or another description-matching change includes a *security* grader, whose absence a reviews marker would still stamp over.

- **`shared` `2.2.4`** — the `merged` event added in 4.8.2 was both unreachable and self-suppressing. Its `description` and `argument-hint` never listed it, so neither a typing user nor a model routing a merge could reach it; and step 2's duplicate check matched on URL alone, so the `merged` comment — which carries the URL `pr-opened` already posted — was silently swallowed and the issue reached Done with no record of the merge. The check is now per *event*, not per URL. Step 5's attachment rule also only fired on two events while the constraint demanded it for any event naming a PR, which skipped the very case that motivated it: XARI-93, corrected with a link to PR #52.

- **`harness` `2.0.0`** — `/harness:loop-dev` had no abort path. Every instruction to stop before the marker is stamped — a `BLOCK:` line, an unresolvable grader, a spec mismatch, an unreadable task — fired *after* the loop had already armed itself, so the `Stop` hook refused the stop on any branch with a diff and the agent was caught between a command ordering it to stop and a hook forbidding it. The only ways out were an undocumented manual disarm or burning three attempts to trip the review breaker, which writes a stand-down line recording work that failed to converge rather than a config never got past. The disarm command is now written out at the `BLOCK:` bullet and referenced from the grader-resolution stop, matching the precedent `/harness:loop-deploy` already set for a denied deploy. Hit for real earlier today.

- **`AGENTS.md`** — still said to "update the version line" after 4.8.2 split `compatibility.md`'s table into two rows with different evidentiary bars. As written, an agent that ran `make check` could advance *gates exercised live*, erasing the only distinction the table exists to make.

- **`CHANGELOG.md`** — the 5.1.0 entry misquoted its own cited source (2.7% where every other record says 2.6%) and used cost to justify a fourth grader, inverting what 4.8.1 concluded: panel decisions rest on latency and review noise, **not** cost. Corrected in place with a note.

## [marketplace 5.1.1] — 2026-09-09

Both surviving sub-agents were running with every tool. The restriction was an inert key.

### Fixed
- **`architect` `2.0.1`, `security` `2.0.1`** — `design-reviewer` and `finding-verifier` declared `allowed-tools: "Read Grep Glob"`. **That is a *skill* key; agents take a comma-separated `tools:` list, and an unrecognised key in agent frontmatter is silently ignored.** So both read-only reviewers resolved with the full tool set — including write and Bash — for as long as they have existed. Confirmed against the live agent registry, which reported both as "Tools: All tools" while an agent using `tools: Read, Glob, Grep` reported exactly those three. Both now use `tools:`.

  Same class as the inert deny rules in 45bd58c: valid YAML, plausible key, no effect, no warning. It mattered more from 5.0.0, which wired `design-reviewer` into `system-design` and so made an unrestricted agent reachable for the first time.

- **`scripts/lint-skills.sh`** — the linter only ever looked at skills and commands, which is why nothing caught the above. It now lints **agents** too: `allowed-tools` is a hard error naming the consequence, `tools:` must be comma-separated (a space-separated list parses as one bogus tool name rather than erroring), and `name` must match the filename. Six tests added, including that a single tool with no comma still passes. Header and the `-- linted N skills, N commands, N agents` line updated.

- **`AGENTS.md`** — documented the inert `allowed-tools` key as though it worked, so anyone following the house convention would reproduce the bug.

- **`architect` `2.0.1`** — `system-design`'s critique step, added in 5.0.0, told you to dispatch `design-reviewer` "against the design you just wrote" but never said to pass the design in, and sat *before* the `## Output Format` section, so at that point no design existed. It is now its own section after the output format and says explicitly to paste the full design text into the subagent prompt, since nothing is written to a file for it to read.

- **`.claude/settings.json`** — did not enable `architect@wayworks`, so 5.0.0's headline addition could not be exercised in the repo that ships it.

- **`docs/reference/model-policy.md`** — still said "Five of the six wayworks agents pin `sonnet`" two paragraphs below the table 5.0.0 had corrected.

## [marketplace 5.1.0] — 2026-09-09

Anthropic's bundled review skills are graders now, and the README says what is actually on disk.

### Added
- **`harness` `1.10.0`** — `/harness:loop-dev` documents Claude Code's **bundled** skills as graders. The `graders` list always resolved any name to the skill of that name, so this needed no code — what it needed was saying so, and naming the trap. `security-review` and `simplify` join `code-review` in the template's mapping comment and in step 5, with the same warning `/code-review` already carries: **invoke a bundled skill by name**, never ask for "a security review" in prose. Bundled skills stopped auto-invoking by description in v2.1.215, so a prose ask gets an improvised review and the marker still stamps.

  Step 5 is explicit that `security-review` runs *alongside* `security`, not instead of it: `security:code-audit` dispatches `@finding-verifier` to try to disprove every Critical/High finding, which the bundled pass does not do. This repo's own `.cc-dev.yaml` now runs `[code-review, security, security-review, bugs]` — the head-to-head trial `first-party-overlap.md` asked for in August and never got. *(Corrected in 5.1.2: this entry originally said subagents are "2.7% of spend" — every other source says **2.6%** — and used cost to justify the fourth grader, which inverts what 4.8.1 actually concluded. Panel decisions are justified by latency and review noise, **not** cost.)*

### Fixed
- **README** — audited every reference against the plugin tree. Counts were already right (14 plugins, 47 skills, 6 commands, 2 sub-agents), nothing pointed at a skill that does not exist, and no skill was undocumented. One drift: `security-scan` was written bare while every sibling carries its namespace. That is the exact class of bug marketplace 4.5.5 fixed across 75 references, and this one was missed — the bare form is an unknown command.

## [marketplace 5.0.0] — 2026-09-09

Four of the six sub-agents were never reachable. Removed.

### Removed
- **`security` `2.0.0`, `qa` `2.0.0`, `devops` `2.0.0`, `architect` `2.0.0`** — `@vuln-scanner`, `@regression-scanner`, `@deploy-checker` and `@security-reviewer` are deleted. **Breaking**: they were dispatchable by name, so anyone invoking one directly must stop.

  Measured before deciding: across 102 local transcripts, 49 `Agent` calls, **not one** named a wayworks sub-agent. That was not just disuse — five of the six had **no dispatch site anywhere in the plugin tree**. Only `security:code-audit → @finding-verifier` was ever wired. The README advertised all six in four plugin sections and in its headline count.

  Each was measured against the skill that should have owned it, using this repo's own rule (keep what costs a *gate*, drop what costs a *checklist*): `@regression-scanner`'s four steps were a strict subset of `regression-check`'s own; `@vuln-scanner`'s OWASP list was a subset of `code-audit`'s checklist, which then falsifies its findings anyway; `@deploy-checker` re-ran build/lint/types, which is the harness verify gate on every stop attempt; `@security-reviewer` overlapped both `@design-reviewer` and `code-audit`. All four restated a checklist their skill already had.

### Added
- **`architect` `2.0.0`** — `system-design` now dispatches `@design-reviewer` against the design it just produced, which is what the agent was written for and what nothing did. It attacks attack surface and auth boundaries, what breaks first at 10× load, zero-downtime deploy and rollback, race conditions and partial failure, and runaway cost. Same generate-then-falsify shape as `code-audit → @finding-verifier`, the one wiring that already existed. A design nobody argued with is a draft.
- **`devops` `2.0.0`** — `infra-review`'s production checklist gains the two `@deploy-checker` checks nothing else covered: no pending migrations on the deploy branch, and no secrets committed (scan the diff, not just `.gitignore`).
- **`.claude/settings.json`** — this repo now enables its own fleet. It had no settings file at all, so `.cc-dev.yaml`'s `security` and `bugs` graders resolved to plugins that were not enabled here, and per `loop-dev` step 1 a run would stop rather than grade with a short panel. The marketplace repo was not eating its own dog food. Note the caveat in `compatibility.md`: enabling is not installing, and the per-project registration still needs `/plugin install`.

### Fixed
- **`shared` `2.2.3`** — `/shared:wayworks-init`'s settings template omitted `qa@wayworks`. Marketplace 4.4.0 made `qa` core precisely because `loop-dev`'s `bugs` grader maps to `qa:bug-review` and silently does not run without it, but that fix landed in the README and never in the command that writes the file. Every repo bootstrapped since has been missing the grader the fix was about.

## [marketplace 4.8.2] — 2026-09-08

Two gaps found by using the skill shipped in 4.8.1 on real work.

### Changed
- **`shared` `2.2.2`** — `linear-update` gains two things it needed the first time it was used:
  - **A `merged` event.** The event list ran `started → pr-opened → deployed`, so a repo that ships by merging rather than deploying had no terminal transition; marking an issue Done after a merge meant going outside the skill. `merged` carries which PR merged and what shipped, and sets Done. The constraint is explicit that `pr-opened` never sets Done, because the human merges.
  - **A required PR attachment.** The skill posted the PR as a bare URL in a comment and stopped there. A comment scrolls away; a Linear attachment shows on the issue. `pr-opened` and `merged` now attach it with `links: [{url, title}]`, which is append-only, so a re-run cannot duplicate it. An issue whose work shipped and that carries no PR attachment is now explicitly unfinished.

### Fixed
- **`docs/reference/compatibility.md`** — the "Tested against" table read `2.1.226 / 2026-08-05` while the workspace ran 2.1.265, so it was 39 releases stale. It is now **two rows**, because the old single row conflated two claims and only one of them can be automated: *checks and docs* verified on **2.1.265** (`make check`, the `claude plugin validate` audit, the Agent-tool fork contract), and *gates exercised live* still on **2.1.226**, which only a real `/harness:loop-dev` run driving the `Stop` hooks can move. `make check` passing on a new version says our logic is intact and says nothing about whether Claude Code still reads a `Stop` hook's output the way the gates assume.

## [marketplace 4.8.1] — 2026-09-08

Measured where the tokens go, and corrected the note that guessed.

### Added
- **`scripts/measure-token-spend.py`** — reads your own `~/.claude/projects` transcripts and prints every table in `model-policy.md`'s fan-out section. Nothing leaves the machine. It exists because the first pass at this measurement published two numbers nobody could reproduce, and a doc that gates a future decision on "re-measure first" has to ship the thing that measures.

### Changed
- **`shared` `2.2.1`** — `conventions` gains one bullet: delegate *exploration* to a subagent and take the answer, but read files directly when you are about to edit them (the edit needs the file in your own context) or review them (a reviewer must see the code, not a summary). The narrower wording is deliberate — the first draft said to delegate reading generally, which would have had a reviewer signing off on code it never read.

### Fixed
- **`docs/reference/model-policy.md`** — the "Fan-out cost" section rested on an external benchmark (Systima's "Subagent Tax", 2.6×–5.9× more tokens for fan-out) and said the thresholds would stay conservative until someone measured our own panel. Measured now: **a subagent turn costs ~$0.044 against ~$0.372 on the main thread**, carrying 57k of context against 399k, and **subagents were 2.6% of all spend**. The section is explicit that this does not refute Systima, who compared the same work sequential versus fanned out — per-locus accounting has no sequential counterfactual, since a subagent's report is re-read in the parent and charged there. What it does settle: no grader panel here is a material cost line, so never skip a grader to save tokens. `loop-dev.md` step 5 is unchanged; its justification is latency and review noise.

  Also recorded: per-turn cost rises with conversation length (median context/turn 47k→433k across the largest session, 4.8× median growth excluding it), while noting that the largest session's 57% of spend is roughly *proportional* to its 53% of turns and so is not itself evidence of the effect. Spotify's read-shunt pattern is **rejected with a derivation**: file-read text is 702k tokens (468k of it via Bash, only 234k via `Read`), amplified 21.9× gives 15.4M of 2,872M `cache_read` — **0.54% of spend**.

- **`docs/reference/model-policy.md`, `docs/reference/compatibility.md`** — both claimed v2.1.232 "made `subagent_type: "fork"` the default". It did not. That release lifted the `CLAUDE_CODE_FORK_SUBAGENT=1` gate, making forks *available* by default; omitting `subagent_type` still starts a fresh agent. As written, a reader would conclude their grader dispatches were silently inheriting the parent's context and model when they are not.

- **`docs/reference/first-party-overlap.md`** — still said the fan-out measurement was available but unrecorded. It is recorded now, and by a committed script rather than by `session-report`, since the transcripts are plain JSONL.

## [marketplace 4.8.0] — 2026-09-08

The loops talk to Linear through one skill.

### Changed
- **`harness` `1.9.0`** — `/harness:loop-dev` and `/harness:loop-deploy` route every Linear write through `/shared:linear-update` instead of carrying their own prose, and the board now reflects the loop's real state:
  - **In Progress on task read.** loop-dev marks the issue when it starts, not when the PR opens. Before this, a loop that stood down left the issue in Backlog as if nobody had touched it.
  - **Stand-downs reach the ticket.** When a circuit breaker trips on a task with a tracker issue, the loop posts the `stood-down` comment — which breaker, after how many attempts, what is still failing, which branch holds the work — before summarizing. Pairs with the `.cc-loop-standdowns.log` record from 4.6.0: the log is the trace, the ticket is what a human reads.
  - **PR-opened and deployed** delegate the In Review and Done transitions, keeping the existing no-double-post guarantee.

  Requires `shared` ≥ 2.2.0, which is core and enabled everywhere `/shared:wayworks-init` runs.

## [marketplace 4.7.0] — 2026-09-08

Linear gets house rules: tickets that fit on one screen, updates that say one thing, projects that point.

### Added
- **`shared` `2.2.0`** — three skills that own every Linear write in the fleet (XARI-122):
  - **`/shared:linear-issue`** — invoked before creating or rewriting an issue. Claude-written tickets were running 400+ words with headers, a rationale section and a retelling of how the bug was found, which buries the ask. The skill states what a ticket *is*: title `<type> - <App>: <sentence>` (`bug`, `feat`, `chore`, `docs`, `spec`, `trend`); problem in one or two sentences; `Evidence:` as `path:line` or a command; `Refs:` for files the fix touches, vendor docs and PRDs; `Risk:` and `Open:` lines when there is one; fix as bullets; at most three acceptance criteria; no headers, no tables; under 180 words measured with `wc -w`. Severity goes in the priority field by rule (an issue that blocks another inherits its priority), dependencies on issues go in `blockedBy`/`blocks`/`relatedTo`, never prose. The cap bounds explanation, never scope: the cut order removes rationale and narrative only, instructions are never cut, and a ticket long because the work is long stays one ticket. A fix bullet becomes its own issue only when it can close alone *and* must land first. A ticket is a **spec** only when the input contains decisions — choices made where another option existed, with the reason each went the way it did; specs keep their Decisions table with no cap, and a spec's ordered slices become short-form sub-issues under it.
  - **`/shared:linear-update`** — one comment per event (`started`, `pr-opened`, `stood-down`, `blocked`, `deployed`, `corrected`), under 80 words: what happened, a bare URL, and the one thing a human must do next, plus the state the event implies. Checks for an existing comment with the same URL first so a re-run never double-posts. The PR carries the change, the log carries the trace; the ticket carries neither.
  - **`/shared:linear-project`** — a project record is a pointer: bold kind-and-stack line, two or three sentences, `Local repo:` and `Vault note:` lines, under 80 words; one milestone only if the brief names one; three to five starter issues written with `linear-issue`. The description pattern moved here out of `/shared:wayworks-onboard`, which now delegates.

  Written test-first: fresh agents given each scenario without the skill, then with it. Bug facts: 401 and 380 words without; 149 / 145 / 126 / 173 / 179 with, all in the form with typed titles, priority set, dependencies as relations. A decisions-heavy input stayed a spec at 334 words with four sub-issues proposed. The split rule was tested both ways on the same five-want bug: a split-on-cap rule produced five tickets and was rejected; the shipped rule produced two — the bug, blocked by the one gating ticket — with the bug running 20 words over and staying whole. A PR-opened comment: 151 words without, 17 with. A stand-down comment: 193 without, 50 with, state left In Progress both times. A project brief: seven untyped free-form issues without; a 57-word pointer description, one milestone and five typed short-form issues with. Skills live in `shared`, not `pm`, because `shared` is enabled in every repo and issues get written from all of them.

---

## [marketplace 4.6.0] — 2026-09-08

A gate that stands down now leaves a record.

### Added
- **`harness` `1.8.0`** — every circuit breaker now appends one line to **`.cc-loop-standdowns.log`** when it trips: `/harness:loop-build`'s verify breaker, `/harness:loop-dev`'s deterministic and review breakers, and `/harness:loop-deploy`'s redeploy breaker (with whether rollback ran, succeeded, or failed) and its no-`verify:`-command disarm. Each line carries a UTC timestamp, the loop, the breaker, its counter, the short `HEAD`, and a hash of `git diff HEAD` — the same fingerprint shape the review marker uses.

  The breakers were doing the right thing — disarm, let the stop through, tell the agent to summarize — but the only record of *why* the loop ended was that one turn's hook output. Whoever merges the PR may never see it, and afterwards a stop reached by exhaustion is indistinguishable from a clean green run. `compatibility.md` already named this failure class in the abstract ("a gate that stops gating still lets you ship, so nothing tells you it stopped working"); this was a live instance of it inside the harness's own scripts (XARI-108, from `great_cto`'s "a stand-down that nobody recorded did not happen").

  The file is append-only and no gate deletes it — a clean run writes nothing, so its presence is the signal. It matches the `.cc-loop-*` gitignore glob; `/harness:harness-init` now lists it explicitly for consumer projects. Ten new shell tests cover every trip site plus the negative case on each loop. Breaker behaviour itself is unchanged.

## [marketplace 4.5.6] — 2026-09-08

Stack-profile fix — the Next.js profile taught a convention Next.js 16 deprecated.

### Fixed
- **`shared` `2.1.5`** — the `nextjs-vercel` stack profile told every Next.js project to put auth and redirects in `middleware.ts`. Next.js 16 renamed the convention to `proxy.ts` with an exported `proxy` function, pinned it to the Node.js runtime (a `runtime` export in the file is now a build error), renamed `skipMiddlewareUrlNormalize` to `skipProxyUrlNormalize`, and ships a codemod for the rename. The profile now documents all of that, moves its stated baseline from Next.js 14+ to 16+, and adds the reference's own warning that a matcher change can silently drop proxy coverage, so auth belongs inside each Server Function as well.

  The lead for this (XARI-107) claimed a leftover `middleware.ts` is silently ignored after upgrading. Checked against the Next.js 16 upgrade guide and the `proxy` file-convention reference: it is not. `middleware.ts` is deprecated but still runs — the upgrade guide tells you to keep it if you need the edge runtime. The profile says what was verified, not what the lead claimed.

## [marketplace 4.5.5] — 2026-08-09

Docs fix — every command and skill reference in the docs was unusable as written.

### Fixed
- **All user-facing docs** — plugin commands and skills are **namespaced**, and the docs documented the bare form throughout: `/loop-dev`, `/wayworks-init`, `/harness-init`, `/code-audit` and 40-odd others. None of them work. The real invocations are `/harness:loop-dev`, `/shared:wayworks-init`, `/security:code-audit`. Anyone following the README hit an unknown-command error on their first try — which is exactly how this was found. 75 references corrected across `README.md`, `AGENTS.md`, `CONTRIBUTING.md`, `docs/reference/*`, and `plugins/harness/README.md` (**`harness` `1.7.6`**), including the two mermaid diagram labels and the references carrying arguments.

  Names were mapped from the plugin tree on disk rather than by hand, and the nine Claude Code **built-ins** — `/code-review`, `/plugin`, `/doctor`, `/verify`, `/loop`, `/batch`, `/debug`, `/add-dir`, `/claude-api` — were deliberately left bare, since those are not namespaced. Verified afterwards that every remaining `plugin:name` resolves to a real skill or command, and that no reference was double-namespaced.

  Historical design records under `docs/plans/`, `docs/specs/`, and `docs/superpowers/` are left as written — they are dated point-in-time documents, not instructions.

## [marketplace 4.5.4] — 2026-08-09

Livelock fix — from the loop's first real end-to-end run.

### Fixed
- **`harness` `1.7.5`** — `/loop-dev`'s Stop gate no longer demands a reviews marker when there is nothing to review. It read "deterministic gate is green" as *"work is done and verified"* when on an empty diff it actually means *"no work exists"*, and then blocked the stop until a marker appeared. The only way to satisfy that is a marker certifying `code-review`, `security`, and `bugs` all passed on a change nobody made — indistinguishable afterwards from a real green run. Observed live: the same hook message fired three times in a row on a run that stopped at preflight, and the session could not exit.

  The marker's tree fingerprint already guards against edits landing *after* a stamp. This is the same failure reached from the other side — a stamp landing before any edits at all.

  The check is deliberately conservative: **untracked files count as work**, so a run that only added new files is still graded. Only loop-state files (`.cc-*`) are ignored, since they exist in every armed run. When there is genuinely nothing, the gate allows the stop and says why rather than exiting silently.

  Three of the six new tests assert the gate still *demands* reviews — for a tracked diff, for an untracked new file, and that loop state alone is not work. One pre-existing test (`hostile base: falls back to main`) had been relying on the old behaviour to reach the stamp message from a repo with no diff; its fixture now makes a change first, which is what it meant to test all along.

- **`harness` `1.7.5`** — the preflight now warns that enabling a plugin in `.claude/settings.json` is a no-op if it was never *installed* for that project, and tells you to verify by invoking rather than by reading config.

### Changed
- **`docs/reference/compatibility.md`** — `${CLAUDE_PLUGIN_ROOT}` inside `!` pre-execution is now **verified** against 2.1.226 (a real `/loop-dev` printed the preflight output in full), and a new section records that enabling ≠ installing: `settings.json` declares intent, `installed_plugins.json` records registration, and the gap is silent. Observed on `ristretto-ai`, where six of seven plugins auto-registered and the one that already had a cache directory from another project did not.

## [marketplace 4.5.3] — 2026-08-08

Arm fix — none of the three loops could start.

### Fixed
- **`harness` `1.7.4`** — `/loop-dev`, `/loop-build`, and `/loop-deploy` all armed with shell output redirection inside their `!` pre-execution block (`touch .cc-…-active && echo 0 > .cc-…-state`). Somewhere between Claude Code 2.1.222 and 2.1.226 that became a hard permission failure — *"Output redirection to '…/.cc-loop-dev-state' was blocked"* — so **no loop could arm at all**. Declaring `Bash(echo:*)` does not help: running `echo` and redirecting it into a file are checked separately, and the redirect is denied regardless of the working directory.

  Arming now runs through `hooks/scripts/loop-arm.sh`, and `allowed-tools` grants that script path instead of `touch`/`echo` — redirection inside a script is never parsed by the permission checker. Same shape as the preflight added in 1.7.0.

  The script also fails *loudly and completely*: if it cannot write, it removes any sentinel it already created and names the real cause ("start Claude Code from the repository root, or add this directory with `/add-dir`"). A sentinel without its state file arms the Stop hook against a loop that never initialised, which livelocks the session — strictly worse than not arming.

  Ships `test/loop-arm.test.sh` — 10 cases covering all three loops, stale-marker clearing, cross-loop isolation (arming `build` must not delete `dev`'s marker), bad and missing arguments, an unwritable directory, and the assertion that a failed arm leaves **no** partial state behind.

### Changed
- **`docs/reference/compatibility.md`** — verified version 2.1.222 → **2.1.226**, and records the redirection restriction plus a related trap: `cd` does **not** widen a session's write sandbox. Allowed directories are fixed at launch from the starting cwd, so `cd` into a repo and writing there still fails; launch from the repo root or use `/add-dir`.

## [marketplace 4.5.2] — 2026-08-07

Manifest fix — every plugin was failing to load one of its components.

### Fixed
- **All 14 plugins** (patch bump each) — removed the `commands`, `skills`, and `hooks` keys from every `plugin.json`. Claude Code auto-discovers `commands/`, `skills/`, `agents/`, and `hooks/hooks.json`; declaring those same paths makes it load them twice, and the second load is a hard error: *"Duplicate hooks file detected … The standard hooks/hooks.json is loaded automatically, so manifest.hooks should only reference additional hook files."* Every enabled wayworks plugin showed **"Needs attention · 1 error"** in `/plugin`, and `harness` failed to load its hooks entirely — meaning the Stop gates the whole harness depends on were not being registered.

  Every declared path was the conventional one (`./skills/`, `./commands/`, `./hooks/hooks.json`), so all 14 were pure redundancy. `architect` already had an undeclared `agents/` directory that loaded fine, which is the proof the convention needs no declaration. Anthropic's own plugins declare none of these keys.

  **CI was green the entire time this shipped.** The manifests were valid JSON and every declared path resolved — `scripts/check.sh` had nothing to object to, because it validated our expectations rather than Claude Code's loader. The failure was visible only in `/plugin` in a live session. `check.sh` now rejects the conventional paths in any of their spellings (`./skills/`, `./skills`, `skills/`, `skills`) while still allowing genuinely additional ones, such as `hooks: "./hooks/extra.json"`.

### Added
- **`docs/reference/compatibility.md`** — three contracts learned the hard way: manifests must declare only non-conventional paths; plugin updates need a **session restart** because commands register at session start (and `installed_plugins.json` pins version + commit *per project*, so one project can sit stale while another is current); and plugin slash commands are **namespaced** — `harness:loop-dev`, not `loop-dev`.

## [marketplace 4.5.1] — 2026-08-06

### Fixed
- **README** — the documented core fleet omitted `qa`, while the default `.cc-dev.yaml` template ships `graders: [code-review, security, bugs]` and `bugs` maps to `qa:bug-review`. Anyone following wayworks' own setup instructions therefore got a grader that silently never ran, and the reviews marker stamps regardless, so nothing surfaced the short panel. Found in `ristretto-ai`, which had been running two of its three configured graders. `qa` is now core, with a note saying *why* `security` and `qa` are core rather than leaving it to be rediscovered.
- **`harness` `1.7.2`** — the `/loop-dev` preflight now prints the plugin each configured grader needs, not just the grader names. "`bugs` did not resolve" is not actionable on its own; "`bugs -> qa:bug-review (needs qa@wayworks)`" is. The mapping was previously only in `loop-dev.md` prose, so diagnosing a missing grader meant going to read the command file. `templates/.cc-dev.yaml` carries the same mapping inline, where someone editing the grader list will actually see it.

## [marketplace 4.5.0] — 2026-08-06

### Added
- **`devops` `1.1.0`** — new `repo-protection` skill: generate or review GitHub repository protection, mirroring how `ci-pipeline` generates or reviews CI configs. Covers the whole surface rather than branch rules alone — default-branch ruleset (deletion, force-push, required reviews, required status checks), secret scanning and push protection, vulnerability alerts and Dependabot security updates, and Actions token hardening. Ships `templates/ruleset-oss.json` and `templates/ruleset-private.json`.

  The two presets differ on one real decision: the private/solo template **drops the review requirement**. An approval only you can grant is ceremony bypassed on every merge, and a rule routinely bypassed trains its owner to ignore the prompt. History protection and green CI still hold, and the rule goes back the moment a second person can review.

  Three constraints encode failures already seen in this repo: required status checks are derived from *observed check runs*, never guessed from workflow YAML, because a required context nothing produces parks every PR at "Expected — waiting for status to be reported" (wayworks hit exactly this between PRs #26 and #27, and merged past two stranded checks unnoticed); `bypass_actors` must not be empty on a solo repo or the maintainer cannot merge their own work; and `PUT /rulesets/<id>` replaces the entire rules array, so the existing ruleset is read and merged rather than blind-written.

## [marketplace 4.4.1] — 2026-08-05

### Added
- **`docs/reference/compatibility.md`** — what wayworks depends on from Claude Code, and what breaks silently when those contracts change. Skills are portable prose; the gates are not. Records the version last verified against (2.1.222), the hook surface the loops are built on (events, `{decision, reason}` output at 14 sites, `hookSpecificOutput`/`permissionDecision`, `stop_hook_active`), `${CLAUDE_PLUGIN_ROOT}` expansion, bundled-skill invocation, and the frontmatter keys in use. The failure mode it exists for: a `Stop` hook whose output is no longer understood does not error — it stops blocking, and the loop reports success as if every gate passed.

  It also records the rule that upstream-drift issues are leads rather than specifications. Three of five in the 2026-08-05 batch were materially wrong — a command that did not exist, a file deleted weeks earlier, and a measurement no available tooling could produce — so a verification step now precedes acting on any of them. Cross-linked from `AGENTS.md` and `model-policy.md`.

### Fixed
- **`harness` `1.7.1`** — `/loop-dev` scoped its preflight permission from `Bash(bash:*)` down to the single script path, matching the pattern Anthropic's own `ralph-loop` uses. The broad form granted the command permission to run *any* bash command; only the preflight was ever intended. Found while cataloguing the `${CLAUDE_PLUGIN_ROOT}` contract for the compatibility record.

## [marketplace 4.4.0] — 2026-08-05

Fail-early release — `/loop-dev` validates its configuration before it builds, not after.

### Added
- **`harness` `1.7.0`** — arm-time config preflight for `/loop-dev` (`hooks/scripts/loop-dev-preflight.sh`). Every condition it checks was previously discovered at the *review* stage, meaning a full implementation had already been written and committed before the loop reported that it could not finish. Blocking conditions: a `base` that does not resolve (the reviews marker is anchored on `git merge-base <base> HEAD`, so it fails at stamp time — after the work); no `.cc-verify` in a repo with no `package.json` (the gate falls back to `npm run lint && npm run build && npm test`, which such a repo can never make green); an empty `.cc-verify`; a `graders:` key with no value; and a loop-state file tracked by git, which invalidates its own fingerprint and livelocks the Stop hook. Non-blocking warnings cover a stale marker, a base that exists only on the remote, and `open_pr` with `gh` missing or unauthenticated.

  The split is deliberate. A shell script cannot see which plugins are enabled in a session, so it cannot tell whether a configured grader resolves to an available skill — it prints the grader list and `loop-dev.md` makes the agent check that half, stopping if any name does not resolve. That is the failure this was built for: a `.cc-dev.yaml` declaring `graders: [code-review, security, bugs]` in a session without `qa@wayworks` silently loses the `bugs` grader, and the marker still stamps, so nothing downstream notices the panel ran short.

  Ships with `test/loop-dev-preflight.test.sh` — 10 cases asserting each blocking condition blocks and each legitimate setup passes, including a Node repo that may rightly rely on the npm default. A preflight that always exits 0 is worse than none, since it reads as confirmation.

## [marketplace 4.3.0] — 2026-08-05

Falsification release — `code-audit` stops shipping unverified findings.

### Added
- **`security` `1.1.0`** — new `finding-verifier` sub-agent, and a verification pass in `code-audit` that uses it. The checklist audit was single-pass, so every finding inherited that pass's false-positive rate with nothing downstream to catch it. Each **Critical** and **High** finding is now handed to an independent verifier subagent (one per finding, dispatched concurrently) whose only job is to try to disprove it: trace where the value actually originates, whether it truly reaches the sensitive operation, and whether a framework, an upstream guard, or unreachability already mitigates it. Medium and Low skip the pass — the cost outweighs their blast radius. `--no-verify` skips it entirely (XARI-92).

  Three decisions worth knowing, because the naive version of this feature is dangerous:

  - **The verifier is a separate agent, not a second pass in the same context.** A model that has just argued for a finding is the worst available judge of it. The verifier is given the claim, its severity, and its `file:line` — deliberately *not* the reasoning that produced it — so it re-reads the code rather than grading an argument.
  - **The default is that the finding stands.** This inverts the usual adversarial-verify pattern, which biases toward refutation. Here the asymmetry runs the other way: a false positive costs the reader a few minutes of triage, while a real vulnerability argued away vanishes from the report and nothing catches it again. Refutation requires a concrete, checkable reason; "seems unlikely" and exploit difficulty are explicitly not grounds, and a partly-wrong finding returns `stands` with a correction rather than being dropped.
  - **Refuted findings are demoted, never deleted.** They appear in a new **Refuted** report section with the verifier's reasoning, and the Risk Summary states how many candidates were verified and how many refuted — so a wrong refutation is visible and reviewable instead of silent.

  `finding-verifier` is the only wayworks agent with no `model:` pin, inheriting the session model instead. Disproving a Critical/High security finding is judgment-heavy adversarial work, and a cheaper model that rubber-stamps or over-refutes is worse than running no verification at all — the same reasoning that keeps the `security` grader off mid-tier. Documented in `docs/reference/model-policy.md`.

## [marketplace 4.2.3] — 2026-08-05

### Fixed
- **`security` `1.0.4`** — `security-scan` now actually consumes its arguments. It advertised `argument-hint: "[path-to-.claude-dir] [--min-severity low|medium|high]"` but never referenced `$ARGUMENTS`, so `/security-scan ~/proj/.claude --min-severity high` silently scanned the current directory at default severity — the user believed they had scoped the scan and had not. Root cause was structural: the skill was a pure CLI reference with no instruction for what to run when invoked, so there was nothing for the arguments to reach. Adds a "Running the scan" section that parses the argument string and builds the command from it (bare path → `--path`, `--min-severity` restricted to `low`/`medium`/`high`, empty → current project). A non-existent path now stops the run rather than falling back to the current directory and reporting a clean grade for somewhere the user never named (XARI-104).

  The parse is deliberately an allowlist, not an interpolation: these values reach a shell command, so substituting the raw argument string would have made a security skill's own entry point a command-injection vector. Shell metacharacters, unrecognized flags, and extra positionals stop the run. `--format`, `--fix`, and `--opus` remain documented CLI capabilities and are intentionally *not* argument-wired — `--fix` mutates configuration files, which should not be reachable by a mistyped slash command.

## [marketplace 4.2.2] — 2026-08-05

Frontmatter-lint release — skills can no longer drift out of the house pattern unnoticed.

### Added
- **`scripts/lint-skills.sh`** — dependency-free frontmatter linter over all 43 skills and 6 commands, wired into `scripts/check.sh` so it runs in `make check` and CI. Errors: missing/mismatched `name`, missing or unquoted `description` (a bare scalar containing a colon or `#` breaks the parse silently), missing or non-boolean `user-invocable`, a skill that reads `$ARGUMENTS` without declaring `argument-hint`, and positional `$0`/`$1` anywhere. Warnings that never fail the build: descriptions over 250 chars, and an `argument-hint` the body never reads. Ships with `scripts/lint-skills.test.sh` — 18 fixture-driven cases asserting every violation class actually fails and every legitimate exception actually passes, because a linter whose field extractor silently returned empty would report the whole repo clean (XARI-51, absorbing XARI-55).

  Three rules are shaped by what the repo actually contains rather than by the abstract pattern: skills nest (the five `shared/stack-profiles/*` live a level deeper than the obvious glob reaches), `argument-hint` is tied to whether a skill *reads* `$ARGUMENTS` rather than to invocability (some invocable skills legitimately take none, and requiring a hint would document an argument that does not exist), and the positional-argument check exempts `shared:create-skill`, whose prose documents the prohibition it would otherwise be flagged for.

### Fixed
- **`feature-bank` `1.2.1`** — frontmatter was the repo's only house-pattern violation: an unquoted `description` (parse-fragile, and it contains 16 double quotes) and no `user-invocable`. Now single-quoted and explicitly `user-invocable: true`, matching the `/feature-bank` command the README already documents. Its 948-char description is deliberately left intact — that description *is* the skill's model-invocation trigger surface, listing the phrasings that make it auto-fire, so trimming it to the 250-char house guidance would degrade the behavior the skill exists to provide. The linter reports it as a warning.

### Known
- `security:security-scan` declares `argument-hint: "[path-to-.claude-dir] [--min-severity low|medium|high]"` but never reads `$ARGUMENTS`, so arguments typed after the command are silently discarded. Surfaced by the new linter as a warning; the fix changes skill behavior and belongs in its own PR against the `security` plugin.

## [marketplace 4.2.1] — 2026-08-05

Upstream-drift release — three external changes (Claude Code v2.1.215, `actions/checkout` defaults, `ollama launch`) that each invalidated an assumption written into a plugin or doc.

### Fixed
- **`harness` `1.6.1`** — `/loop-dev`'s default `code-review` grader no longer relies on description-matching to fire Anthropic's bundled `/code-review` skill. Claude Code v2.1.215 stopped auto-running the bundled `/verify` and `/code-review` skills, so step 5's old "(or the `/code-review` skill)" phrasing could silently degrade into an improvised generic review — undetectable downstream, because the reviews marker stamps as long as *a* review happened. The dispatched subagent is now told to invoke the slash command by name and to report a missing command rather than substitute for it. `README.md` gains an upgrade-sensitivity note, since this grader's behavior is set by Claude Code's bundled-skill policy, not by this plugin (XARI-86).
- **`devops` `1.0.2`** — `ci-pipeline` gains a "pwn request" review check. The skill both generates and reviews GitHub Actions configs, but had no guard against the classic `pull_request_target`/`workflow_run` privilege-escalation shape: a privileged workflow that checks out the fork's ref and then executes it. Review mode now flags that pattern with the exploitable YAML shape and three concrete remediations, and notes that `actions/checkout` blocks the fetch by default as of 2026-07-20 — so an affected workflow may now be *failing* rather than merely unsafe (XARI-87).
- **`docs/reference/model-policy.md`** — grader tier table pointed at `loop-dev.md` "step 4"; the review stages are step 5.

### Changed
- **`docs/reference/model-policy.md`** — the local-model section now leads with `ollama launch claude` (Ollama v0.15+, no env vars or config files) instead of the manual LiteLLM-proxy setup, and documents the direct `ANTHROPIC_BASE_URL=http://localhost:11434` path as the no-launcher alternative — Ollama's endpoint is Anthropic-compatible, so the intermediate proxy was never required. Adds the 64k-context guidance and flags multi-turn tool-call reliability (not raw model quality) as the binding constraint for running skill files locally. The architectural limit is unchanged and restated: Claude Code still cannot route individual stages or graders to a local model, only whole sessions — `ollama launch` solves setup, not routing (XARI-88).
- **`docs/reference/model-policy.md`** — records Systima's published subagent fan-out measurement (2.6×–5.9× tokens vs. sequential) next to the tiering table, explicitly attributed as *external* data rather than a wayworks measurement, with no threshold changes: our own panel has never been instrumented, and the grader-scaling heuristics stay as-is until it is (XARI-93).

## [marketplace 4.2.0] — 2026-07-27

Quality-hooks release — write-time feedback loops, selectively ported from the ideas in [everything-claude-code](https://github.com/WorldFlowAI/everything-claude-code) rather than installing it wholesale (its agents/commands/rules duplicate the existing fleet).

### Added
- **`harness` `1.6.0`** — three always-on quality hooks (no arming needed, all with cheap no-op paths outside their scope): (1) **stray-doc gate** — `PreToolUse` on `Write`: creating a *new* `.md`/`.txt` outside the standard set (README/CLAUDE/AGENTS/CONTRIBUTING/CHANGELOG/LICENSE/SKILL basenames; `docs/`, `.claude/`, `.github/`, `skills/`, `commands/`, `agents/`, `memory/`, scratchpad paths) surfaces an explicit Approve prompt (`permissionDecision: ask`) instead of letting agent-generated summaries accumulate silently; (2) **write-time type-check** — `PostToolUse` on TS edits: runs the project's *own* `tsc --noEmit` (only when `tsconfig.json` and a local `node_modules/.bin/tsc` exist — never npx-installs) and feeds back up to 10 errors *in the edited file only*, so type breakage surfaces at edit time instead of at the loop's verify gate; (3) **console.log sweep** — `Stop`: non-blocking `systemMessage` warning listing modified tracked JS/TS files that still contain `console.log` — never blocks the stop; blocking stays the loop gates' job. Each hook ships its own dependency-free test suite (`test/block-stray-docs.test.sh`, `test/tsc-check.test.sh`, `test/console-log-scan.test.sh`).

## [shared 2.1.3] — 2026-07-28

### Added
- **`create-skill`** — context-engineering verbosity note for Claude 5+ models. Anthropic deleted ~80% of system prompt text with no eval loss; the note documents when the house pattern's structure is load-bearing vs potentially redundant on newer frontier models, without changing the mandatory template itself. Refer to `claude doctor` (`/doctor`) for skill diagnostics before shipping.

## [marketplace 4.1.1] — 2026-07-20

Loop-durability release — five failure modes observed across production runs (kaffecard XARI-70/71).

### Fixed
- **`harness` `1.5.1`** — `/loop-dev` hardening from live runs that shipped the wrong change twice and lost an hour of finished work. (1) **Read the task**: the loop is routinely handed a bare tracker issue key as its entire task; it now reads the issue whenever one is named (Linear MCP `get_issue`, else `gh issue view`) — the ticket adds requirements the task omitted but never redirects the work, and a genuine task/ticket conflict stops the run. For a *bare* key it is the spec outright, so an unreadable one **stops** the run: previously the loop reconstructed scope from the branch name and shipped plausible, well-reviewed, wrong changes that passed every downstream gate. The PR stage no longer assumes a tracker key exists, so self-contained tasks finish without a Linear update. (2) **Commit before reviews**: the implementation is committed at the end of the build stage, so a run killed at its wall-clock limit no longer loses uncommitted work. (3) **Branch discipline**: work stays on the checked-out branch — no creating, switching, or pushing an invented branch name, which breaks the PR-first lookup that makes re-runs idempotent. (4) **Never stage blindly**: explicit paths only, never `git add -A`/`git add .` (they sweep unrelated edits and stale index entries into a PR), and loop-state files stay untracked — a tracked marker invalidates its own fingerprint and livelocks the gate. (5) **Grader dedup**: exactly one subagent per grader per round, and re-review re-runs only the graders whose findings were fixed — plus `security` whenever a fix touches any surface the panel rule calls security-relevant (executable code, hooks, auth/permissions, deploy templates, secrets handling), since a fix aimed at one grader's finding routinely lands in another's domain.

## [marketplace 4.1.0] — 2026-07-17

Pipeline-gaps release — closes the gaps between the documented way-of-working and what the loops actually execute (2026-07-17 inspection).

### Added
- **`harness` `1.5.0`** — `/loop-dev` grows three stages of coverage: (1) **`--plan <path>`** hands the loop a written implementation plan (e.g. superpowers `writing-plans` output) instead of the loop's own short plan — the documented handoff from brainstorm/spec to the loop; (2) a **dev-test stage** between reviews and finish that exercises the change the way the product is used — the feature spec's `test_plan` first, else stack-inferred (browser flow via built-in tooling/`chrome-devtools-mcp`, endpoint checks, or `data-engineer:pipeline-verify` for pipelines) — recorded as the PR's "How verified"; (3) **PR CI watch** (`gh pr checks --watch --fail-fast`) — red checks are loop work, Slack ping only after green. Grader panel is now extensible: `design` maps to `design:layout-review` (+`heuristic-eval` for new flows), any other grader name maps to the same-named skill, unknown names stop the loop instead of being skipped. The finish stage now runs the `feature-bank` postflight (Gate 3) before stamping the reviews marker, so spec docs are fingerprinted with the code. `/loop-deploy` success is now a **knowledge sync**: repo docs confirmed current, a dated log line appended to the project's vault note (when a vault is declared), Linear issue to Done — then the Slack announce. `templates/.cc-dev.yaml` documents the `design` grader and `max_review_rounds`.
- **`feature-bank` `1.2.0`** — optional `test_plan:` frontmatter field on feature specs: concrete, agent-executable dev checks (flows to drive, commands over sample data), consumed by `/loop-dev`'s dev-test stage; scaffolding proposes it, postflight runs it.
- **`data-engineer` `1.1.0`** — new `/pipeline-verify` skill: run a pipeline against a bounded sample in dev and assert schema conformance, row accounting (in = out + rejected), null/dupe rates, DLQ state, idempotency on re-run, and clean logs. The data-platform counterpart of driving a web app in a browser.
- **`docs/reference/model-policy.md`** — which model runs which stage (grader tiers, agent pins, frontmatter pinning rules) and the local-model path (per-session proxy; stages can't route to local models).

### Fixed
- **`security` `1.0.3`** — `security-scan` no longer claims a dated model version for the external scanner's `--opus` mode.
- README: stale `/web-verify` reference from before the 4.0.0 web-tester removal; settings template now includes `superpowers@claude-plugins-official` (matching `/wayworks-init`); CLAUDE.md plugin count 15 → 14.

## [marketplace 4.0.1] — 2026-07-16

### Fixed
- **`shared` `2.1.2`** — `expo-mobile` stack profile gains a **Testing** section: jest-expo's major is locked to the Expo SDK major (SDK 57 ↔ jest-expo ~57), so test deps must be installed with `npx expo install jest-expo jest` and re-checked with `npx expo install --check` after SDK upgrades — a stale jest-expo fails install with an `ERESOLVE` peer conflict (XARI-83).

## [marketplace 4.0.0] — 2026-07-16

### Removed
- **`web-tester`** (breaking — the plugin set shrinks to 14). Its single skill (`/web-verify`, Playwright-MCP browser verification) is superseded three ways: Claude's built-in browser tooling (Claude in Chrome), the official `chrome-devtools-mcp` plugin in the Anthropic marketplace, and the `vercel` plugin's full-story `verification` skill. If you depend on `/web-verify`, install `chrome-devtools-mcp` and drive the same flow from its browser tools.

### Changed
- **`shared` `2.1.1`** — `/wayworks-init` no longer recommends `web-tester` for web frontends; points at the built-in browser tooling / `chrome-devtools-mcp` instead.

## [marketplace 3.4.1] — 2026-07-16

### Fixed
- **`harness` `1.4.1`** — Vercel deploy config no longer assumes a single app (XARI-82). `/harness-init` deploy-target detection now distinguishes a root-linked single Vercel app from a monorepo with app-level links (`apps/*/.vercel`, `apps/*/vercel.json`, …), which it previously missed entirely. For monorepos it rewrites the whole config: `deploy` scoped per app with Vercel's global `--cwd <app-dir>` flag and chained with `&&`, `watch` set to `"true"` (chained deploys already block; the root-scoped default fails with no root link), `verify` composing every app's checks, and `rollback` per app via a flag chain (`r=0; … || r=1; …; test $r -eq 0`) so every rollback is attempted and any single failure still fails the whole command (`&&` would skip apps; `;` would mask failures from the gate's rolled-back-vs-act-now verdict) — confirming the app list with the user (an app missing from `rollback` stays broken on rollback). Because these strings are later `eval`'d by the deploy gate, detected app paths are restricted to `[A-Za-z0-9._/-]+`; anything else falls back to user-written commands. Multiple matching targets (e.g. Railway root + Vercel apps) are surfaced instead of silently picking one. `templates/.cc-deploy.vercel.yaml` documents the single-app assumption and shows the monorepo shape.

## [marketplace 3.4.0] — 2026-07-16

### Changed
- **`harness` `1.4.0`** — loop-dev token-efficiency release, from an audit of the first four production runs (~840k output tokens for 3 PRs). (1) **Grader scaling**: the review panel now scales to the diff — docs-only diffs run `code-review` alone, small non-sensitive code diffs skip `security`, and the full panel still always runs when the diff touches hooks, auth, deploy templates, or secrets handling. (2) **Grader model tiers**: `code-review`/`bugs` graders may run on a mid-tier model when the dispatch tool supports it; `security` always inherits the session model. (3) **Review circuit breaker**: grading is now bounded like the deterministic gate — after `max_review_rounds` (`.cc-dev.yaml`, default 3) stop attempts without a clean stamped marker, the gate disarms and instructs the agent to summarize outstanding findings instead of dispatching more graders (previously unbounded; only wall-clock limits contained a non-converging grade-fix loop). New transient state file `.cc-loop-dev-rounds` (gitignored via `/harness-init`, reset on arm).

## [marketplace 3.3.1] — 2026-07-15

### Fixed
- **`harness` `1.3.1`** — Stop-gate race hardening (XARI-81). All three loop gates now serialize on a shared mkdir-based mutex (`.cc-loop-gate.lock`, stale-lock recovery by holder PID), so Stop-parallel sibling gates and overlapping sessions can no longer run the verify command concurrently, double-count attempts, or race the sentinel/marker deletions; a contended lock blocks without consuming a retry. `/loop-dev`'s reviews marker is now stamped with the merge-base anchor commit plus a working-tree fingerprint against it, and re-verified at stop time **against the stored anchor** — changes landing after the graders passed (late background jobs, extra commits) invalidate the marker and force a re-review instead of silently bypassing it, and a moving base ref (`base: HEAD`, or the checked-out branch itself) cannot collapse the check. A non-empty marker that is not the two-line stamped format fails closed (treated as stale). Empty (`touch`ed) markers remain accepted as the non-git/legacy escape hatch; the fingerprint is commit-invariant on feature branches (tracked files only — untracked-only changes are not fingerprinted). Stale locks are stolen by atomic rename (never `rm`+`mkdir`, which let two contenders both acquire) and the lock is released on hook timeout/interrupt, not just clean exit. `.cc-dev.yaml` `base:` is quote-stripped like the deploy config and validated against a ref-name charset before reaching `git merge-base` or the stamp command echoed to the agent (a quoted `base: "main"` used to silently disable the check; a hostile value could inject shell). `/harness-init` now gitignores `.cc-loop-gate.lock*` in consumer projects. Gate tests pin `CLAUDE_PROJECT_DIR` to their temp dirs — under a Stop hook the env leaks the real project dir, making the gates recurse into the armed loop instead of the test fixture.

## [marketplace 3.3.0] — 2026-07-12

### Changed
- **`harness` `1.3.0`** — `/loop-dev` step 6 is idempotent: reuse an existing open PR for the branch (never create a second) and skip the Linear PR comment when one already exists. Required for durable kanban re-runs (ristretto durable-dev-work spec, Guards 1–2).

## [marketplace 3.2.0] — 2026-07-10

### Changed
- **`harness` `1.2.0`** — `/harness-init` now **detects the deploy target** instead of defaulting to Vercel. It writes a Railway config when it sees `railway.json`/`railway.toml`, a Vercel config when it sees `vercel.json`/`.vercel/`, and otherwise a neutral default whose `deploy`/`verify`/`rollback` commands are guarded to exit non-zero until filled in — so an unconfigured deploy loop refuses to run rather than silently "succeeding". Adds `templates/.cc-deploy.railway.yaml` and `templates/.cc-deploy.vercel.yaml`; the generic `templates/.cc-deploy.yaml` is now the provider-neutral fallback.

## [marketplace 3.1.0] — 2026-07-10

Open-source readiness release.

### Added
- **CONTRIBUTING.md** — philosophy, skill scaffolding, the CI-enforced release rule, PR expectations.
- **README "How it's used"** — one-time setup, per-project bootstrap/onboarding, daily loops, and the adaptability story.

### Changed
- **`shared` `2.1.0`** — `/wayworks-onboard`: the tracker vertex is now explicitly pluggable (recommended order: Obsidian backlog in the vault note → any connected tracker/GitHub Issues → `docs/BACKLOG.md`); Obsidian stays the recommended knowledge core but is never required. Both `/wayworks-onboard` and `/wayworks-init` gain **branch discipline**: config commits go to a `chore/` branch + PR when a remote exists, never onto whatever feature branch the repo happens to be on.
- Historical design doc sanitized of absolute personal paths.

## [marketplace 3.0.0] — 2026-07-10

**The project is now `wayworks`** (was `xari-plugins`) — an open-source way of work for AI-assisted building: plugins + second-brain (Obsidian) support + tracker (Linear) integration.

### Breaking / Migration
- Marketplace renamed: every consumer key changes from `<plugin>@xari-plugins` to `<plugin>@wayworks`, and the marketplace source is now `SilviaAre95/wayworks` (old GitHub URLs redirect). Update `.claude/settings.json`: `extraKnownMarketplaces` entry + all `enabledPlugins` keys.
- **`shared` `2.0.0`** — commands renamed: `/xari-init` → `/wayworks-init`, `/xari-onboard` → `/wayworks-onboard`. The CLAUDE.md header they scaffold is now `## Wayworks config`.

### Changed
- All plugin `repository` URLs, README, and docs updated to the new identity. Historical CHANGELOG entries below intentionally keep the old name.

## [marketplace 2.0.1] — 2026-07-09

### Fixed
- **All skills standardized on `$ARGUMENTS`** — 24 skills across 10 plugins dropped positional `$0`/`$1` interpolation (which only populates for typed slash commands and leaks literally when the model invokes a skill). `shared/create-skill` `1.3.2` now teaches `$ARGUMENTS`-only. Patch bumps: backend-dev/data-engineer/design/devops/pm/qa/test-builder 1.0.1, frontend-dev 1.1.1, security 1.0.2, tech-writer 2.0.1.

## [marketplace 2.0.0] — 2026-07-09

Consolidation release (context-budget lean-up). **Breaking**: two plugins removed.

### Breaking / Migration
- **`ui-designer` and `ux-researcher` removed** — merged into the new **`design` `1.0.0`** plugin. Migrate `.claude/settings.json`: replace `ui-designer@xari-plugins` / `ux-researcher@xari-plugins` with `design@xari-plugins`.
- **`tech-writer` `2.0.0`** — `adr-template` skill removed; its init/list/status modes now live in `architect/adr-writer`.

### Changed
- **`design` `1.0.0`** — 4 skills: `layout-review` (absorbs `responsive-audit`: mobile-first checks, breakpoint matrix, touch targets), `design-system`, `heuristic-eval`, `user-flow-analysis`.
- **`frontend-dev` `1.1.0`** — `accessibility-check` gains an `experience` mode (the former `ux-researcher/accessibility-audit`: screen-reader/keyboard/low-vision/motor/cognitive walkthroughs) alongside WCAG code compliance.
- **`architect` `1.1.0`** — `adr-writer` absorbs ADR infrastructure setup + list/status modes; one ADR skill instead of two.
- **`feature-bank` `1.1.0`** — SKILL.md trimmed 2,309 → 800 words via progressive disclosure; full backfill flow, spec format, and worked examples moved to `references/` (loaded only when needed). Frontmatter unchanged, so triggering is identical.
- **`shared` `1.3.1`** — `/xari-init` fleet list references `design` instead of `ui-designer`.
- README: core vs extended plugin tiers documented. Counts: 15 plugins / 43 skills. Closes XARI-73 (and XARI-54 via the ADR merge).

## [marketplace 1.4.0] — 2026-07-09

### Changed
- **`shared` `1.3.0`** — `conventions` is now language-agnostic (simplicity-first, error handling, commits, review checklist); TypeScript/React/Tailwind/Prisma specifics moved into the `nextjs-vercel` stack profile where they auto-load only in matching repos. New `expo-mobile` stack profile (Expo Router, secure storage, permissions, EAS) — mobile conventions no longer squat in a web profile. Closes XARI-72.

## [marketplace 1.3.1] — 2026-07-09

### Fixed
- **`security` `1.0.1`** — `security-scan` frontmatter normalized to house standard (quoted description, `user-invocable`, `argument-hint`; non-standard `origin` key removed) and its external `ecc-agentshield` dependency surfaced explicitly: not bundled, `npx` downloads on first run, fail-and-report if unavailable, version-pinning advised for CI. Closes XARI-52.

## [marketplace 1.3.0] — 2026-07-09

### Added
- **`shared` `1.2.0`** — new `/xari-onboard` command: onboard a project from any starting point (existing repo, existing vault note, or a bare idea) into the linked triangle **Linear project ↔ vault note ↔ repo**. Takes inventory first, creates only what's missing (knowledge → tracking → code), wires the cross-links idempotently, and degrades gracefully for users without an Obsidian vault or Linear connection.

## [marketplace 1.2.0] — 2026-07-09

### Added
- **`web-tester` plugin `1.0.0`** — live web-app verification. Declares the marketplace's first MCP server (Playwright, headless via `npx @playwright/mcp`) and ships `/web-verify`: drive the critical user flow in a real browser, assert console + network are clean, screenshot evidence.
- **`shared` `1.1.0`** — new `/xari-init` command: bootstrap any repo as a xari workspace (plugin fleet in `.claude/settings.json` via `extraKnownMarketplaces` + `enabledPlugins`, CLAUDE.md header template with stack/vault-note/Linear/verify pointers, harness handoff).

### Fixed
- **README** backfilled to reality (was 13 plugins/38 skills): now 16 plugins / 45 skills, documents `harness`, `feature-bank`, `web-tester`, and `security-scan`; settings templates corrected from the invalid `"plugins": []` key to the real `enabledPlugins` schema.

## [marketplace 1.1.0] — 2026-07-08

### Added
- **`feature-bank` plugin `1.0.0`** — source-of-truth feature specs with preflight/postflight gates that stop agent drift; ships a portable `check-bank.sh` validator.
- **`harness` `1.1.0`** — two new commands extending the build-test-fix loop into a full work-loop system:
  - **`/loop-dev`** — staged verification loop: spec preflight → plan (`--check-plan` autonomy dial) → build → code-review / security / bug-hunt subagents → fix → PR. A `Stop` hook enforces the deterministic gate (`.cc-verify`) plus a reviews-passed marker; circuit breaker after `max_retries`. Config in `.cc-dev.yaml`.
  - **`/loop-deploy`** — production verify loop: deploy → watch → verify (health + smoke + error-rate) → fix→redeploy until healthy; after `max_redeploys` it runs `rollback` and escalates, so an exhausted loop never leaves prod broken. Prod deploy + DB migrations are hard Approve/Deny gates. Config in `.cc-deploy.yaml`.
  - `harness-init` now scaffolds `.cc-dev.yaml` / `.cc-deploy.yaml` and git-ignores the new loop state files.

## [harness 1.0.0] — earlier

### Added
- **`harness` plugin** — tiered autonomy (explore / build / ship / escape) + the `/loop-build` build-test-fix loop with a `Stop`-hook verify gate and circuit breaker.
- **`security` `security-scan` skill** — supply-chain scan via `ecc-agentshield`.

## [marketplace 1.0.0] — 2026-04-08

### Added
- Initial release: 13 plugins (`shared`, `architect`, `ui-designer`, `ux-researcher`, `backend-dev`, `frontend-dev`, `data-engineer`, `test-builder`, `qa`, `security`, `devops`, `tech-writer`, `pm`) — 39 skills, 5 sub-agents, 4 stack profiles.
