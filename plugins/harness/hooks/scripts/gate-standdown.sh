# Durable audit trail for gate stand-downs. Sourced, not executed.
#
# Every circuit breaker disarms its loop and lets the stop through. That is
# the right behaviour — but the only record of WHY the loop ended was that
# turn's hook output, which the human merging the PR may never read. A stop
# reached by exhausting the breaker then looks identical to a clean green run.
#
# gate_standdown appends one line per trip to .cc-loop-standdowns.log. The
# file is append-only and no gate ever deletes it, so the distinction survives
# the session. It matches the .cc-loop-* gitignore glob; harness-init lists it
# explicitly for consumer projects.
#
# Usage: gate_standdown "$DIR" <loop> <breaker> [detail ...]
# Line:  <utc timestamp> <loop> <breaker> [detail ...] head=<short sha|nogit> diff=<hash of `git diff HEAD`|nogit>
# The diff hash is the same fingerprint shape loop-dev's review marker uses,
# so a later reader can tell whether the tree at stand-down is the tree that
# got merged.
gate_standdown() {
  local dir="$1" loop="$2" breaker="$3"; shift 3
  local head=nogit diff=nogit
  if git -C "$dir" rev-parse --git-dir >/dev/null 2>&1; then
    head=$(git -C "$dir" rev-parse --short HEAD 2>/dev/null || echo nohead)
    diff=$(git -C "$dir" diff HEAD 2>/dev/null | git -C "$dir" hash-object --stdin 2>/dev/null || echo nodiff)
  fi
  printf '%s %s %s%s head=%s diff=%s\n' \
    "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$loop" "$breaker" "${*:+ $*}" "$head" "$diff" \
    >> "$dir/.cc-loop-standdowns.log"
}
