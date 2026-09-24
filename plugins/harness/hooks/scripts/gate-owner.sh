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
# unverified) leaves the loop ungated for the session that armed it, so a
# foreign skip is never silent: it prints a non-blocking systemMessage naming
# the owner. A skip is not a stand-down and is not logged; a re-arm that takes
# a loop from another session is (loop-arm.sh).
#
# Call it twice: before gate_lock, so a bystander never contends the lock, and
# again after the verify command returns, before any state is touched — a
# re-arm by another session during a long verify must not have its counter,
# sentinel or rollback driven by this run.
#
# Usage:  gate_foreign "$SENTINEL" "$INPUT" && exit 0
gate_foreign() {
  local owner sid
  owner=$(head -1 "$1" 2>/dev/null | tr -d '[:space:]')
  sid=$(printf '%s' "$2" | jq -r '.session_id // empty' 2>/dev/null)
  [ -n "$owner" ] && [ -n "$sid" ] && [ "$owner" != "$sid" ] || return 1
  jq -n --arg s "$(basename "$1")" --arg o "$owner" \
    '{systemMessage:("harness: " + $s + " is armed by another Claude Code session (" + $o + "), so this stop was not gated. If this session armed it (e.g. before /clear), re-arm the loop to gate it.")}'
}
