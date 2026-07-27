#!/usr/bin/env bash
# PreToolUse hook: gate stray doc-file creation behind an explicit approve.
# New .md/.txt files outside the standard set (README/CLAUDE/AGENTS/etc,
# docs/, plugin content dirs) tend to be agent-generated summaries the repo
# never asked for; "ask" surfaces them instead of letting them accumulate.
# Editing an existing doc always defers to the normal permission flow.
set -uo pipefail
INPUT=$(cat)
TOOL=$(printf '%s' "$INPUT" | jq -r '.tool_name // ""')
FILE=$(printf '%s' "$INPUT" | jq -r '.tool_input.file_path // ""')
if [ "$TOOL" != "Write" ] || [ -z "$FILE" ]; then echo '{}'; exit 0; fi
case "$FILE" in
  *.md|*.MD|*.txt) ;;
  *) echo '{}'; exit 0 ;;
esac
if [ -e "$FILE" ]; then echo '{}'; exit 0; fi
case "$(basename "$FILE")" in
  README*|readme*|CLAUDE.md|AGENTS.md|AGENT.md|CONTRIBUTING*|CHANGELOG*|LICENSE*|SKILL.md)
    echo '{}'; exit 0 ;;
esac
case "$FILE" in
  */docs/*|docs/*|*/.claude/*|.claude/*|*/.github/*|.github/*|\
  */skills/*|skills/*|*/commands/*|commands/*|*/agents/*|agents/*|\
  */memory/*|memory/*|*/scratchpad/*)
    echo '{}'; exit 0 ;;
esac
jq -n --arg f "$FILE" '{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:"ask",permissionDecisionReason:("New doc file outside the standard set: " + $f + ". Consolidate into README or docs/ unless the user explicitly wants this file.")}}'
