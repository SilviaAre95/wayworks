---
name: code-audit
description: "Security audit of application code — OWASP Top 10, injection vectors, auth flaws, data exposure"
user-invocable: true
argument-hint: "<file-or-directory> [focus: auth|injection|data|all] [--no-verify]"
---

# Security Code Audit

Audit: **$ARGUMENTS** (focus defaults to all)

## Steps

### 1. Checklist pass

Work through `references/owasp-checklist.md` against the target: injection (SQL, XSS, command, path traversal, SSRF), authentication and authorization, data exposure, configuration and secrets, and dependencies. Honour the focus argument; `all` covers every section.

This pass is commodity — a capable model produces it on request, and first-party tools ship it free. It is a single pass and inherits that pass's false-positive rate, which is what step 2 exists to correct.

### 2. Verification pass (Critical and High only)

Before reporting, dispatch one `security:finding-verifier` subagent per **Critical** and **High** finding — all in one concurrent batch — to try to disprove it.

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
