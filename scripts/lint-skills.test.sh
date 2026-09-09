#!/usr/bin/env bash
# Tests for lint-skills.sh. A linter whose field extractor silently returns
# empty would report every file clean, so each violation class is asserted to
# actually fail — and each legitimate exception asserted to actually pass.
set -uo pipefail
LINT=$(cd "$(dirname "$0")" && pwd)/lint-skills.sh
fail=0
ok()  { echo "ok   - $*"; }
bad() { echo "FAIL - $*"; fail=1; }

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

# Build a fixture skill. $1=path under plugins, $2=frontmatter+body
mkskill() {
  mkdir -p "$TMP/$(dirname "$1")"
  printf '%s\n' "$2" > "$TMP/$1"
}

reset() { rm -rf "$TMP/plugins"; mkdir -p "$TMP/plugins"; }

# Run linter against the fixture tree, setting RC and OUT in the caller.
run() { OUT=$(LINT_ROOT="$TMP" bash "$LINT" 2>&1); RC=$?; }

CLEAN='---
name: good-skill
description: "Does a thing"
user-invocable: true
argument-hint: "<target>"
---

# Good'

# --- baseline: a conforming skill passes ---
reset; mkskill plugins/p/skills/good-skill/SKILL.md "$CLEAN"
run; [ "$RC" = "0" ] && ok "clean skill passes" || bad "clean skill passes (out: $OUT)"

# --- missing name ---
reset; mkskill plugins/p/skills/x/SKILL.md '---
description: "d"
user-invocable: true
argument-hint: "<a>"
---'
run; [ "$RC" = "1" ] && ok "missing name fails" || bad "missing name fails"

# --- name does not match directory ---
reset; mkskill plugins/p/skills/x/SKILL.md '---
name: not-x
description: "d"
user-invocable: true
argument-hint: "<a>"
---'
run; { [ "$RC" = "1" ] && echo "$OUT" | grep -q "does not match"; } \
  && ok "name/dir mismatch fails" || bad "name/dir mismatch fails"

# --- missing description ---
reset; mkskill plugins/p/skills/x/SKILL.md '---
name: x
user-invocable: true
argument-hint: "<a>"
---'
run; [ "$RC" = "1" ] && ok "missing description fails" || bad "missing description fails"

# --- unquoted description ---
reset; mkskill plugins/p/skills/x/SKILL.md '---
name: x
description: bare unquoted
user-invocable: true
argument-hint: "<a>"
---'
run; { [ "$RC" = "1" ] && echo "$OUT" | grep -q "must be quoted"; } \
  && ok "unquoted description fails" || bad "unquoted description fails"

# --- single quotes and block scalars are acceptable ---
reset; mkskill plugins/p/skills/x/SKILL.md "---
name: x
description: 'single quoted'
user-invocable: true
argument-hint: \"<a>\"
---"
run; [ "$RC" = "0" ] && ok "single-quoted description passes" || bad "single-quoted description passes (out: $OUT)"

# --- missing user-invocable ---
reset; mkskill plugins/p/skills/x/SKILL.md '---
name: x
description: "d"
argument-hint: "<a>"
---'
run; [ "$RC" = "1" ] && ok "missing user-invocable fails" || bad "missing user-invocable fails"

# --- consumes $ARGUMENTS but declares no hint => error ---
reset; mkskill plugins/p/skills/x/SKILL.md '---
name: x
description: "d"
user-invocable: true
---

Operate on $ARGUMENTS.'
run; { [ "$RC" = "1" ] && echo "$OUT" | grep -q "declares no"; } \
  && ok "args-without-hint fails" || bad "args-without-hint fails"

# --- invocable, takes no arguments, no hint => fine (feature-bank's shape) ---
reset; mkskill plugins/p/skills/x/SKILL.md '---
name: x
description: "d"
user-invocable: true
---

Runs a fixed flow with no user input.'
run; [ "$RC" = "0" ] && ok "argument-less invocable skill needs no hint" || bad "argument-less invocable skill needs no hint (out: $OUT)"

# --- declares a hint but never reads $ARGUMENTS => warn, do not fail ---
reset; mkskill plugins/p/skills/x/SKILL.md '---
name: x
description: "d"
user-invocable: true
argument-hint: "[--flag]"
---

Body that never reads the argument string.'
run; { [ "$RC" = "0" ] && echo "$OUT" | grep -q "typed arguments are ignored"; } \
  && ok "unfulfilled argument-hint warns" || bad "unfulfilled argument-hint warns (rc=$RC out: $OUT)"

# --- user-invocable: false without argument-hint is CORRECT (stack profiles) ---
reset; mkskill plugins/p/skills/x/SKILL.md '---
name: x
description: "d"
user-invocable: false
---'
run; [ "$RC" = "0" ] && ok "non-invocable skill needs no argument-hint" || bad "non-invocable skill needs no argument-hint (out: $OUT)"

# --- nested skills (stack-profiles live one level deeper) are still linted ---
reset; mkskill plugins/p/skills/group/nested/SKILL.md '---
name: WRONG
description: "d"
user-invocable: false
---'
run; [ "$RC" = "1" ] && ok "nested skill is linted" || bad "nested skill is linted"

# --- long description warns but does NOT fail ---
long=$(printf 'x%.0s' $(seq 1 300))
reset; mkskill plugins/p/skills/x/SKILL.md "---
name: x
description: \"$long\"
user-invocable: true
argument-hint: \"<a>\"
---"
run; { [ "$RC" = "0" ] && echo "$OUT" | grep -q "warning:"; } \
  && ok "long description warns without failing" || bad "long description warns without failing (rc=$RC)"

# --- positional arguments ---
reset; mkskill plugins/p/skills/x/SKILL.md '---
name: x
description: "d"
user-invocable: true
argument-hint: "<a>"
---

Use $1 as the target.'
run; [ "$RC" = "1" ] && ok "positional \$1 fails" || bad "positional \$1 fails"

# --- no frontmatter at all ---
reset; mkskill plugins/p/skills/x/SKILL.md '# Just a heading'
run; [ "$RC" = "1" ] && ok "missing frontmatter fails" || bad "missing frontmatter fails"

# --- body text that looks like frontmatter is not read as frontmatter ---
reset; mkskill plugins/p/skills/x/SKILL.md '---
name: x
description: "d"
user-invocable: true
argument-hint: "<a>"
---

Body mentioning name: something-else and user-invocable: false'
run; [ "$RC" = "0" ] && ok "body text is not parsed as frontmatter" || bad "body text is not parsed as frontmatter (out: $OUT)"

# --- commands: bare description is fine, no name required ---
reset
mkdir -p "$TMP/plugins/p/commands"
printf '%s\n' '---
description: Bare scalar is the command convention
allowed-tools: Read
---' > "$TMP/plugins/p/commands/c.md"
run; [ "$RC" = "0" ] && ok "command with bare description passes" || bad "command with bare description passes (out: $OUT)"

# --- commands: missing description fails ---
reset
mkdir -p "$TMP/plugins/p/commands"
printf '%s\n' '---
allowed-tools: Read
---' > "$TMP/plugins/p/commands/c.md"
run; [ "$RC" = "1" ] && ok "command without description fails" || bad "command without description fails"

# --- agents: allowed-tools is inert here and must be rejected ---
reset
mkdir -p "$TMP/plugins/p/agents"
printf '%s\n' '---
name: rev
description: "A reviewer"
allowed-tools: "Read Grep Glob"
---' > "$TMP/plugins/p/agents/rev.md"
run
[ "$RC" = "1" ] && ok "agent with allowed-tools fails" || bad "agent with allowed-tools fails (out: $OUT)"
printf '%s' "$OUT" | grep -q "silently ignored here" \
  && ok "agent allowed-tools error explains the consequence" \
  || bad "agent allowed-tools error explains the consequence (out: $OUT)"

# --- agents: comma-separated tools is the correct form ---
reset
mkdir -p "$TMP/plugins/p/agents"
printf '%s\n' '---
name: rev
description: "A reviewer"
tools: Read, Glob, Grep
model: sonnet
---' > "$TMP/plugins/p/agents/rev.md"
run; [ "$RC" = "0" ] && ok "agent with comma-separated tools passes" || bad "agent with comma-separated tools passes (out: $OUT)"

# --- agents: a space-separated list parses as one bogus tool name ---
reset
mkdir -p "$TMP/plugins/p/agents"
printf '%s\n' '---
name: rev
description: "A reviewer"
tools: Read Glob Grep
---' > "$TMP/plugins/p/agents/rev.md"
run; [ "$RC" = "1" ] && ok "agent with space-separated tools fails" || bad "agent with space-separated tools fails (out: $OUT)"

# --- agents: a single tool with no comma is legitimate ---
reset
mkdir -p "$TMP/plugins/p/agents"
printf '%s\n' '---
name: rev
description: "A reviewer"
tools: Read
---' > "$TMP/plugins/p/agents/rev.md"
run; [ "$RC" = "0" ] && ok "agent with a single tool passes" || bad "agent with a single tool passes (out: $OUT)"

# --- agents: name must match the filename ---
reset
mkdir -p "$TMP/plugins/p/agents"
printf '%s\n' '---
name: something-else
description: "A reviewer"
tools: Read
---' > "$TMP/plugins/p/agents/rev.md"
run; [ "$RC" = "1" ] && ok "agent name mismatching filename fails" || bad "agent name mismatching filename fails"

exit $fail
