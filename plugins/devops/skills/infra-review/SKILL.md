---
name: infra-review
description: "Review infrastructure configs — Docker, CI/CD, deploy targets, env vars, and production readiness"
user-invocable: true
argument-hint: "<scope: docker|ci|deploy|env|all>"
---

# Infrastructure Review

Review scope: **$ARGUMENTS**

## Steps

1. **Docker review** (if applicable):
   - Is the Dockerfile multi-stage?
   - Is the production image minimal (alpine/distroless)?
   - Running as non-root?
   - No secrets baked in?
   - Layer caching optimized?
   - `.dockerignore` present and complete?

2. **CI/CD review**:
   - Are all quality gates in place (lint, test, build, type-check)?
   - Are deploys gated on test success?
   - Is there branch protection on main?
   - Are secrets managed properly (not in code, using CI secrets)?
   - Is there a rollback strategy?

3. **Deploy target review**:
   - Is the deploy config correct for the platform?
   - Are health checks configured?
   - Is auto-scaling configured (if applicable)?
   - Are deploy previews enabled for PRs?
   - Is there a staging environment?

4. **Environment variables review**:
   - Is there a `.env.example` with all required vars?
   - Are secrets in `.env` excluded from git (`.gitignore`)?
   - Are production secrets stored securely (not in repo)?
   - Are there env vars that differ between environments and is this documented?
   - Are there unused env vars?

5. **Production readiness checklist**:
   - [ ] Error monitoring (Sentry, etc.)
   - [ ] Logging (structured, not console.log)
   - [ ] Health check endpoint
   - [ ] Database migrations automated
   - [ ] SSL/TLS configured
   - [ ] CORS configured correctly
   - [ ] Rate limiting on public endpoints
   - [ ] Backup strategy for database
   - [ ] No pending/unapplied migrations on the deploy branch
   - [ ] No secrets committed — scan the diff, not just `.gitignore`

## Output Format

```markdown
## Infrastructure Review

### Summary
- **Critical**: X issues
- **Warnings**: Y issues
- **Production ready**: yes/no

### Critical Issues
1. **<area>**: <issue + fix>

### Warnings
1. **<area>**: <issue + recommendation>

### Production Readiness
| Check | Status | Notes |
|-------|--------|-------|
| Error monitoring | missing | Add Sentry |
| Health checks | present | /api/health |
| SSL | configured | via platform |
```

## Constraints

- Focus on security and reliability issues first
- Don't suggest changes that require different hosting (review what they have)
- Check `.env.example` exists — it's the team's documentation for env vars
- If Terraform/IaC exists, review that instead of manual infrastructure
