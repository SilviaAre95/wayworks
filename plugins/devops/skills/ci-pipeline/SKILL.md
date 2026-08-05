---
name: ci-pipeline
description: "Generate or review CI/CD pipeline configs — GitHub Actions, Railway, Vercel, or generic CI"
user-invocable: true
argument-hint: "<platform: github-actions|railway|vercel|gitlab> [type: build|deploy|full]"
---

# CI Pipeline

Generate or review a CI pipeline per: **$ARGUMENTS** (platform defaults to github-actions, pipeline type defaults to full)

## Steps

1. **Analyze the project** — Determine:
   - Build tool (npm, pnpm, turborepo)
   - Test framework (vitest, jest, playwright)
   - Lint tool (eslint, biome)
   - Deploy target (Vercel, Railway, Docker)
   - Monorepo? (turbo.json present)

2. **Generate pipeline config**:

### GitHub Actions (full pipeline)

```yaml
name: CI

on:
  push:
    branches: [main, develop]
  pull_request:
    branches: [main]

concurrency:
  group: ${{ github.workflow }}-${{ github.ref }}
  cancel-in-progress: true

jobs:
  lint:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-node@v4
        with:
          node-version: 20
          cache: npm
      - run: npm ci
      - run: npm run lint

  test:
    runs-on: ubuntu-latest
    needs: lint
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-node@v4
        with:
          node-version: 20
          cache: npm
      - run: npm ci
      - run: npm test

  build:
    runs-on: ubuntu-latest
    needs: test
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-node@v4
        with:
          node-version: 20
          cache: npm
      - run: npm ci
      - run: npm run build

  deploy:
    runs-on: ubuntu-latest
    needs: build
    if: github.ref == 'refs/heads/main'
    steps:
      - uses: actions/checkout@v4
      # Deploy step depends on target platform
```

3. **Add quality gates**:
   - PR checks: lint + test must pass before merge
   - Branch protection: require status checks
   - Deploy only from main (or release branches)

4. **Optimize**:
   - Cache `node_modules` and build outputs
   - Use `concurrency` to cancel stale runs
   - Run lint and test in parallel when possible
   - Use `turbo` for monorepo builds

5. **If reviewing an existing config — check for "pwn request" first.** `pull_request_target` and `workflow_run` run with the *base* repo's write-scoped `GITHUB_TOKEN` and secrets. Flag it as high severity when such a workflow also checks out fork-controlled code — a `ref:` resolving to `github.event.pull_request.head.*` followed by any step that executes what was checked out (`npm ci` lifecycle scripts, `make`, a build, a test run). Recommend one of:
   - Switch to `pull_request`, so the fork's code runs unprivileged — usually what was actually intended.
   - Split into two jobs: privileged metadata work (labels, comments) separate from anything running fork code.
   - If it must stay privileged: check out the *base* ref only, plus a least-privilege `permissions:` block.

   `actions/checkout` blocks this fetch by default as of 2026-07-20 (backported to all supported majors), so an affected workflow may now be *failing* rather than merely unsafe — say which one you're looking at.

## Output Format

Produce the CI config file(s):
- `.github/workflows/ci.yml` for GitHub Actions
- `railway.json` for Railway
- `vercel.json` for Vercel
- `.gitlab-ci.yml` for GitLab

Include comments explaining each section.

## Constraints

- Never put secrets directly in CI config — use environment variables/secrets
- Pin action versions to specific commits or tags, not `@main`
- Keep pipeline under 10 minutes for PRs
- Only deploy from protected branches
- Include `concurrency` to prevent parallel deploys
- Never use `pull_request_target`/`workflow_run` to check out a fork's ref (see step 5)
