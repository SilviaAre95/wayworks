# Session ownership for the harness Stop gates. Sourced, not executed.
#
# Sentinels live in the project directory, so every Claude Code session open
# in the same checkout used to share one armed loop. A bystander session's
# stop then drove the owner's gate — ran `verify`, spent the retry budget,
# and for loop-deploy could reach `rollback` against prod (XARI-159).
#
# loop-arm.sh writes the arming session's CLAUDE_CODE_SESSION_ID into the
# sentinel; the Stop hook input carries the same value as `session_id`.
# gate_foreign is true only when BOTH are present and they differ. Either one
# missing (a sentinel armed before this change, or a harness that does not
# supply an id) falls back to the old shared behaviour rather than silently
# disabling the gate — loop-arm warns when it arms without an owner.
#
# --resume keeps the session id (verified on 2.1.282), so a resumed session
# still owns its loop. Anything that starts a new id (/clear is expected to;
# unverified) leaves the loop ungated for the session that armed it — re-arm.
#
# Usage:  gate_foreign "$SENTINEL" "$INPUT" && exit 0
gate_foreign() {
  local owner sid
  owner=$(head -1 "$1" 2>/dev/null | tr -d '[:space:]')
  sid=$(printf '%s' "$2" | jq -r '.session_id // empty' 2>/dev/null)
  [ -n "$owner" ] && [ -n "$sid" ] && [ "$owner" != "$sid" ]
}
