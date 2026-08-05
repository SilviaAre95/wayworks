---
name: code-audit
description: "Security audit of application code — OWASP Top 10, injection vectors, auth flaws, data exposure"
user-invocable: true
argument-hint: "<file-or-directory> [focus: auth|injection|data|all] [--no-verify]"
---

# Security Code Audit

Audit: **$ARGUMENTS** (focus defaults to all)

## Steps

### 1. Injection Vulnerabilities
- **SQL Injection**: raw SQL with string concatenation/interpolation? (Prisma's parameterized queries are safe; raw queries are not)
- **XSS**: user input rendered as HTML without sanitization? `dangerouslySetInnerHTML`?
- **Command Injection**: user input passed to `exec`, `spawn`, `eval`?
- **Path Traversal**: user input in file paths without sanitization? (`../../../etc/passwd`)
- **SSRF**: user-controlled URLs in server-side fetch/requests?

### 2. Authentication & Authorization
- Are all protected routes checking auth?
- Is session management secure (httpOnly, secure, sameSite cookies)?
- Are passwords hashed with bcrypt/argon2 (not MD5/SHA)?
- Is there rate limiting on login endpoints?
- Are JWTs validated properly (algorithm, expiry, issuer)?
- Is there proper RBAC — not just "is authenticated" but "has permission"?

### 3. Data Exposure
- Are API responses leaking sensitive fields (password hash, internal IDs, PII)?
- Are error messages exposing internal details (stack traces, SQL queries)?
- Are logs capturing sensitive data (passwords, tokens, credit cards)?
- Is PII encrypted at rest?
- Are database queries returning `SELECT *` instead of specific fields?

### 4. Configuration & Secrets
- Are secrets in environment variables (not hardcoded)?
- Is `.env` in `.gitignore`?
- Are there any API keys, tokens, or passwords in the codebase?
- Is CORS configured restrictively (not `*`)?
- Are security headers set (CSP, X-Frame-Options, HSTS)?

### 5. Dependencies
- Are there known vulnerable dependencies? (`npm audit`)
- Are dependencies pinned to specific versions?
- Are there unnecessary dependencies with broad system access?

### 6. Verification pass (Critical and High only)

The checklist is a single pass and inherits that pass's false-positive rate. Before reporting, dispatch one `security:finding-verifier` subagent per **Critical** and **High** finding — all in one concurrent batch — to try to disprove it.

Give each verifier only the claim, its severity, and its `file:line` — **not your reasoning.** A verifier shown the argument that produced a finding tends to agree with it; the point is a fresh read of the code. Medium and Low skip this; the cost outweighs their blast radius.

Apply the verdicts: `stands` → report as normal, applying any `CORRECTION`. `refuted` → move to **Refuted** with the verifier's reason; **never delete it**, since a verifier can be wrong and a silently dropped finding is unreviewable.

Skip this step when invoked with `--no-verify`.

## Output Format

```markdown
## Security Audit: <target>

### Risk Summary
- **Critical**: X (exploit possible)
- **High**: Y (vulnerability exists, exploit requires effort)
- **Medium**: Z (defense-in-depth gap)
- **Low**: W (hardening opportunity)

### Critical Findings
1. **<vulnerability type>** — <file:line>
   - **Risk**: <what an attacker can do>
   - **Fix**: <specific code change>
   - **Verify**: <how to test the fix>

### High Findings
...

### Refuted
<Critical/High candidates a verifier disproved — omit this section if none>
1. **<vulnerability type>** — <file:line>
   - **Why it does not hold**: <verifier's reason + evidence>

### Hardening Recommendations
1. <recommendation>
```

State in the Risk Summary how many Critical/High candidates were verified and how many were refuted, so the reader can see the filter ran.

## Constraints

- Prioritize by exploitability, not theoretical severity
- Provide specific fixes with code, not just "sanitize input"
- Check the actual data flow, not just pattern matching
- Don't flag framework-handled security (e.g., Prisma's SQL parameterization)
- If you find a critical vulnerability, flag it clearly at the top
- A finding survives unless a verifier **disproves** it — uncertainty is not refutation, and exploit difficulty is a severity question, not an existence one
