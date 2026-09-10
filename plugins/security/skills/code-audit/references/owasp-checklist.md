# OWASP audit checklist

The pass-one checklist: injection, auth/authz, data exposure, configuration and secrets, dependencies. Work through it against the target, then return to SKILL.md for the verification pass — a finding that has not been through that pass is not reportable.

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

