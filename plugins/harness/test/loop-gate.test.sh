#!/usr/bin/env bash
# Decision-table tests for the loop-gate Stop hook. Uses a temp project dir and
# CC_GATE_CMD to fake pass/fail without a real build.
set -uo pipefail
HOOK="$(cd "$(dirname "$0")/../hooks/scripts" && pwd)/loop-gate.sh"
fail=0
decision() {
  # Empty/whitespace-only output means the hook exited without blocking = ALLOW.
  # jq 1.7.1-apple exits 0 with no output on empty stdin, so the || never fires;
  # we must guard explicitly to avoid returning "" instead of "ALLOW".
  local stripped
  stripped=$(printf '%s' "$1" | tr -d '[:space:]')
  [ -z "$stripped" ] && { echo ALLOW; return 0; }
  printf '%s' "$1" | jq -r '.decision // "ALLOW"' 2>/dev/null || echo PARSE_ERR
}

# helper: run hook in a fresh temp dir; args: armed(0/1) gatecmd stop_active
run() {
  local armed="$1" gate="$2" stopactive="$3"
  local dir; dir=$(mktemp -d)
  [ "$armed" = "1" ] && touch "$dir/.cc-loop-active"
  CLAUDE_PROJECT_DIR="$dir" CC_GATE_CMD="$gate" \
    printf '{"stop_hook_active":%s,"cwd":"%s"}' "$stopactive" "$dir" \
    | CLAUDE_PROJECT_DIR="$dir" CC_GATE_CMD="$gate" bash "$HOOK"
  echo "::$dir"  # emit dir on its own marker line for post-checks
}

check() { local name="$1" got="$2" want="$3"; if [ "$got" = "$want" ]; then echo "ok   - $name"; else echo "FAIL - $name (got '$got' want '$want')"; fail=1; fi; }

# 1. Not armed -> allow stop (no output)
out=$(run 0 "true" false); d=$(decision "$(printf '%s' "$out" | grep -v '^::')"); check "unarmed allows stop" "$d" "ALLOW"

# 2. stop_hook_active does NOT short-circuit iteration — counter controls the loop.
out=$(run 1 "false" true); d=$(decision "$(printf '%s' "$out" | grep -v '^::')")
check "stop_hook_active no longer short-circuits: still blocks when armed+fail" "$d" "block"

# 3. Armed + gate passes -> allow + sentinel removed
out=$(run 1 "true" false); dir=$(printf '%s' "$out" | sed -n 's/^:://p'); d=$(decision "$(printf '%s' "$out" | grep -v '^::')")
check "green allows stop" "$d" "ALLOW"
[ -f "$dir/.cc-loop-active" ] && { echo "FAIL - green removes sentinel"; fail=1; } || echo "ok   - green removes sentinel"

# 4. Armed + gate fails, attempt < MAX -> block
out=$(run 1 "false" false); d=$(decision "$(printf '%s' "$out" | grep -v '^::')")
check "fail under cap blocks stop" "$d" "block"

# 5. Armed + gate fails at MAX -> block once (summary) AND sentinel removed
dir=$(mktemp -d); touch "$dir/.cc-loop-active"; echo 4 > "$dir/.cc-loop-state"
out=$(CLAUDE_PROJECT_DIR="$dir" CC_GATE_CMD="false" printf '{"stop_hook_active":false,"cwd":"%s"}' "$dir" | CLAUDE_PROJECT_DIR="$dir" CC_GATE_CMD="false" bash "$HOOK")
d=$(decision "$out"); check "breaker still blocks once to summarize" "$d" "block"
[ -f "$dir/.cc-loop-active" ] && { echo "FAIL - breaker removes sentinel"; fail=1; } || echo "ok   - breaker removes sentinel"

# 6. Corrupted state file (leading digit) -> sanitized to 0, incremented to 1, still blocks
dir=$(mktemp -d); touch "$dir/.cc-loop-active"; printf '5x' > "$dir/.cc-loop-state"
out=$(CLAUDE_PROJECT_DIR="$dir" CC_GATE_CMD="false" printf '{"stop_hook_active":false,"cwd":"%s"}' "$dir" | CLAUDE_PROJECT_DIR="$dir" CC_GATE_CMD="false" bash "$HOOK")
d=$(decision "$out"); check "corrupted state still blocks" "$d" "block"
state_val=$(cat "$dir/.cc-loop-state" 2>/dev/null || echo "missing")
check "corrupted state sanitized to 1" "$state_val" "1"

# 7. Multi-turn regression: stop_hook_active=true on every call, persistent state.
#    Counter — not the flag — must bound the loop: block calls 1-5, allow call 6.
mt_dir=$(mktemp -d); touch "$mt_dir/.cc-loop-active"
for i in 1 2 3 4 5; do
  mt_out=$(printf '{"stop_hook_active":true,"cwd":"%s"}' "$mt_dir" \
    | CLAUDE_PROJECT_DIR="$mt_dir" CC_GATE_CMD="false" bash "$HOOK")
  mt_d=$(decision "$mt_out")
  check "multi-turn call $i blocks (stop_hook_active=true, gate=fail)" "$mt_d" "block"
done
# After 5 failures sentinel must be gone.
[ -f "$mt_dir/.cc-loop-active" ] && { echo "FAIL - multi-turn: sentinel should be removed after breaker"; fail=1; } \
  || echo "ok   - multi-turn: sentinel removed after 5 attempts"
# 6th call: sentinel gone -> hook exits 0 (ALLOW) with no output.
mt_out6=$(printf '{"stop_hook_active":true,"cwd":"%s"}' "$mt_dir" \
  | CLAUDE_PROJECT_DIR="$mt_dir" CC_GATE_CMD="false" bash "$HOOK")
mt_d6=$(decision "$mt_out6")
check "multi-turn call 6 allows (sentinel gone)" "$mt_d6" "ALLOW"

# 8. Live lock held by another process -> block WITHOUT running the gate:
#    no attempt counted, sentinel kept, lock not stolen.
lk_dir=$(mktemp -d); touch "$lk_dir/.cc-loop-active"
mkdir "$lk_dir/.cc-loop-gate.lock"; echo $$ > "$lk_dir/.cc-loop-gate.lock/pid"
lk_out=$(printf '{"stop_hook_active":false,"cwd":"%s"}' "$lk_dir" \
  | CLAUDE_PROJECT_DIR="$lk_dir" CC_GATE_CMD="false" bash "$HOOK")
lk_d=$(decision "$lk_out"); check "live lock blocks stop" "$lk_d" "block"
[ -f "$lk_dir/.cc-loop-state" ] && { echo "FAIL - lock contention must not count an attempt"; fail=1; } \
  || echo "ok   - lock contention counts no attempt"
[ -f "$lk_dir/.cc-loop-active" ] && echo "ok   - lock contention keeps sentinel" \
  || { echo "FAIL - lock contention keeps sentinel"; fail=1; }
[ -d "$lk_dir/.cc-loop-gate.lock" ] && echo "ok   - live lock not stolen" \
  || { echo "FAIL - live lock not stolen"; fail=1; }

# 9. Stale lock (dead holder pid) -> stolen, gate runs, lock released on exit.
sl_dir=$(mktemp -d); touch "$sl_dir/.cc-loop-active"
mkdir "$sl_dir/.cc-loop-gate.lock"; sl_dead=$(bash -c 'echo $$'); echo "$sl_dead" > "$sl_dir/.cc-loop-gate.lock/pid"
sl_out=$(printf '{"stop_hook_active":false,"cwd":"%s"}' "$sl_dir" \
  | CLAUDE_PROJECT_DIR="$sl_dir" CC_GATE_CMD="true" bash "$HOOK")
sl_d=$(decision "$sl_out"); check "stale lock stolen: green allows" "$sl_d" "ALLOW"
[ -d "$sl_dir/.cc-loop-gate.lock" ] && { echo "FAIL - stale lock released after run"; fail=1; } \
  || echo "ok   - stale lock released after run"

# 10. Stand-down audit trail: a breaker trip appends one durable line naming
#     the loop and breaker; a clean green run writes nothing.
sd_dir=$(mktemp -d); touch "$sd_dir/.cc-loop-active"; echo 4 > "$sd_dir/.cc-loop-state"
printf '{"stop_hook_active":false,"cwd":"%s"}' "$sd_dir" | CLAUDE_PROJECT_DIR="$sd_dir" CC_GATE_CMD="false" bash "$HOOK" >/dev/null
sd_line=$(tail -1 "$sd_dir/.cc-loop-standdowns.log" 2>/dev/null || echo "missing")
case "$sd_line" in *"loop verify-breaker"*) echo "ok   - breaker logs stand-down" ;; *) echo "FAIL - breaker logs stand-down (got '$sd_line')"; fail=1 ;; esac
case "$sd_line" in *"attempts=5"*) echo "ok   - stand-down line records attempts" ;; *) echo "FAIL - stand-down line records attempts (got '$sd_line')"; fail=1 ;; esac
sd_dir2=$(mktemp -d); touch "$sd_dir2/.cc-loop-active"
printf '{"stop_hook_active":false,"cwd":"%s"}' "$sd_dir2" | CLAUDE_PROJECT_DIR="$sd_dir2" CC_GATE_CMD="true" bash "$HOOK" >/dev/null
[ -f "$sd_dir2/.cc-loop-standdowns.log" ] && { echo "FAIL - green run writes no stand-down"; fail=1; } || echo "ok   - green run writes no stand-down"

exit $fail
