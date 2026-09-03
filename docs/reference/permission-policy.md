# Harness Permission Policy (canonical)

A plugin cannot grant permissions — these go in `settings.json`. Precedence: `deny` > `ask` > `allow`.

## Universal floor — `~/.claude/settings.json` → `permissions.deny`
Applies in every tier, including `bypassPermissions`.

```json
"deny": [
  "Bash(sudo *)",
  "Bash(rm -rf *)",
  "Bash(rm -rf /*)",
  "Bash(rm -rf ~/*)",
  "Edit(.git/**)",
  "Edit(.env)",
  "Edit(.env.*)"
]
```

> **Why `Edit`, not `Write`.** Claude Code's file-permission checks only match
> `Edit(path)` rules — and `Edit` rules cover *all* file-editing tools, Write
> included. A `Write(.env)` deny is silently inert; Claude Code says so at
> startup: *"Permission deny rule: Write(.env) is not matched by file
> permission checks — only Edit(path) rules are."* This policy shipped the
> inert form for months and every downstream repo copied it, so the rules
> meant to protect `.env` and `.git` protected nothing. If you copied an
> earlier version of this block, change `Write(` to `Edit(` in your
> settings.
>
> **Unverified, worth testing:** the `Bash(sudo *)` space-glob form above
> predates this fix. The documented pattern form is `Bash(cmd:*)`. Claude
> Code emitted no warning for these, but absence of a warning is not proof
> they match — verify before relying on them as the only floor.

## Hard gates — `permissions.ask` (always prompt, even in build/bypass)

```json
"ask": [
  "Bash(railway up*)",
  "Bash(vercel*--prod*)",
  "Bash(vercel --prod*)",
  "Read(.env)",
  "Read(.env.*)",
  "Bash(railway variables set*)"
]
```
External-send MCP tools (email/comment posting) are gated by omission from `allow`: in the `ship`/`default` tier they prompt naturally.

## Generous allow — project `.claude/settings.json` → `permissions.allow`

```json
"allow": [
  "Bash(npm run *)", "Bash(npm install*)", "Bash(npm test*)",
  "Bash(git add *)", "Bash(git commit *)", "Bash(git status*)",
  "Bash(git diff*)", "Bash(git log*)", "Bash(git push *)",
  "Bash(railway status*)", "Bash(railway logs*)", "Bash(railway variables)",
  "Bash(vercel ls*)", "Bash(vercel inspect*)",
  "Read(*)", "Grep(*)", "Glob(*)"
]
```
