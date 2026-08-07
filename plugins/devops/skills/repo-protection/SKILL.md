---
name: repo-protection
description: "Generate or review GitHub repository protection — branch rulesets, secret scanning, Dependabot, and Actions token hardening"
user-invocable: true
argument-hint: "<owner/repo> [preset: oss|private] [--review]"
---

# Repository Protection

Audit or apply baseline protection per: **$ARGUMENTS** (preset inferred from repo visibility when omitted; `--review` reports without changing anything)

## Steps

1. **Audit what exists.** Never propose from assumption — read the live state:
   ```bash
   gh api repos/<owner>/<repo> --jq '{private, default_branch, security_and_analysis}'
   gh api repos/<owner>/<repo>/rulesets --jq '.[] | {id, name, enforcement}'
   gh api repos/<owner>/<repo>/actions/permissions/workflow
   gh api repos/<owner>/<repo>/vulnerability-alerts --silent && echo alerts-on
   ```

2. **Find the real CI contexts.** A required status check is matched by *exact name*, and a required context nothing produces sits at "Expected — waiting for status to be reported" forever, blocking every PR. Derive them from what actually ran, not from the workflow file:
   ```bash
   gh api repos/<owner>/<repo>/commits/<default-branch-sha>/check-runs --jq '.check_runs[].name'
   ```
   A job with no `name:` reports under its job id. **Renaming a CI job silently strands the required context** — say so when you apply this.

3. **Pick the preset.** `templates/ruleset-oss.json` for public repos; `templates/ruleset-private.json` for private or solo ones, which drops the review requirement (an approval only you can give is ceremony you bypass every time, and a rule routinely bypassed trains you to ignore it). Substitute the real contexts from step 2.

4. **Keep a bypass actor.** `{"actor_id": 5, "actor_type": "RepositoryRole", "bypass_mode": "always"}` is the repository-admin role. An empty `bypass_actors` on a solo repo locks you out of merging your own work.

5. **Apply**, ruleset then settings — order matters, each depends on the one before:
   ```bash
   gh api -X POST repos/<owner>/<repo>/rulesets --input ruleset.json
   gh api -X PUT repos/<owner>/<repo>/vulnerability-alerts        # before Dependabot
   gh api -X PUT repos/<owner>/<repo>/automated-security-fixes
   gh api -X PATCH repos/<owner>/<repo> -f 'security_and_analysis[secret_scanning][status]=enabled'
   gh api -X PATCH repos/<owner>/<repo> -f 'security_and_analysis[secret_scanning_push_protection][status]=enabled'
   ```
   Secret scanning and push protection are free on public repos; private repos need GitHub Advanced Security — report that rather than failing.

6. **Verify by re-reading**, never by assuming the write worked.

## Output Format

```markdown
## Repository Protection: <owner/repo> (<public|private>)

| Control | Before | After |
|---------|--------|-------|
| Branch ruleset | none | Baseline (active) |
| Force-push / deletion | allowed | blocked |
| Required checks | — | <contexts> |
| Secret scanning + push protection | disabled | enabled |
| Vulnerability alerts + Dependabot | disabled | enabled |

**Bypass**: <who, and what they can bypass>
**Watch out**: <renamed CI jobs strand required contexts; existing secret alerts; Dependabot will open PRs>
```

## Constraints

- Show the plan and get approval before writing — this can lock a maintainer out of their own repository
- Required contexts come from observed check runs, never guessed from workflow YAML
- Never propose an empty `bypass_actors` unless a second maintainer can merge
- `PUT /rulesets/<id>` replaces the whole rules array — read the existing ruleset and merge, never blind-write
- Enabling secret scanning surfaces pre-existing secrets in history; push protection only blocks future pushes
- Actions hardening (`default_workflow_permissions: read`, workflows cannot approve PRs) is separate from rulesets — check it, and flag `pull_request_target` workflows to `ci-pipeline`
