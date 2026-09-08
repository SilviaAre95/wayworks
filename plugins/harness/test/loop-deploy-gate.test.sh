#!/usr/bin/env bash
# Tests for loop-deploy-gate.sh — the prod-verify loop gate.
set -uo pipefail
GATE="$(cd "$(dirname "$0")/.." && pwd)/hooks/scripts/loop-deploy-gate.sh"
pass=0; fail=0
# CLAUDE_PROJECT_DIR pinned to the temp dir: under a Stop hook the env leaks
# the real project dir and the gate would resolve DIR to it instead.
run() { printf '{"cwd":"%s"}' "$1" | CLAUDE_PROJECT_DIR="$1" bash "$GATE"; }
has() { if printf '%s' "$2" | grep -q "$3"; then echo "ok: $1"; pass=$((pass+1)); else echo "FAIL: $1 (want '$3' in: $2)"; fail=$((fail+1)); fi; }
empty() { if [ -z "$2" ]; then echo "ok: $1"; pass=$((pass+1)); else echo "FAIL: $1 (want empty, got: $2)"; fail=$((fail+1)); fi; }
eq() { if [ "$2" = "$3" ]; then echo "ok: $1"; pass=$((pass+1)); else echo "FAIL: $1 (want '$3' got '$2')"; fail=$((fail+1)); fi; }

# 1. Not armed -> allow
d=$(mktemp -d); empty "not-armed allows" "$(run "$d")"; rm -rf "$d"

# 2. Armed + verify PASS -> allow (empty), state cleaned
d=$(mktemp -d); touch "$d/.cc-deploy-active"
out=$(CC_DEPLOY_VERIFY_CMD="true" run "$d")
empty "verify-pass allows" "$out"
eq "verify-pass disarms" "$([ -f "$d/.cc-deploy-active" ] && echo present || echo gone)" "gone"
rm -rf "$d"

# 3. Armed + verify FAIL (under cap) -> block, counter=1
d=$(mktemp -d); touch "$d/.cc-deploy-active"
out=$(CC_DEPLOY_VERIFY_CMD="false" run "$d")
has "verify-fail blocks" "$out" '"decision": *"block"'
has "verify-fail feedback" "$out" "attempt 1/3"
eq "verify-fail counts" "$(cat "$d/.cc-deploy-state")" "1"
eq "verify-fail keeps sentinel" "$([ -f "$d/.cc-deploy-active" ] && echo present)" "present"
rm -rf "$d"

# 4. Armed + verify FAIL at cap -> rollback runs, disarm, escalate message
d=$(mktemp -d); touch "$d/.cc-deploy-active"; echo 2 > "$d/.cc-deploy-state"
out=$(CC_DEPLOY_VERIFY_CMD="false" CC_DEPLOY_ROLLBACK_CMD="touch $d/ROLLED_BACK" run "$d")
has "cap triggers escalate" "$out" "escalate"
eq "rollback command ran" "$([ -f "$d/ROLLED_BACK" ] && echo yes || echo no)" "yes"
eq "cap disarms" "$([ -f "$d/.cc-deploy-active" ] && echo present || echo gone)" "gone"
rm -rf "$d"

# 5. max_redeploys read from .cc-deploy.yaml (with comment) -> cap honored at 2
d=$(mktemp -d); touch "$d/.cc-deploy-active"; echo 1 > "$d/.cc-deploy-state"
printf 'max_redeploys: 2   # keep it tight\n' > "$d/.cc-deploy.yaml"
out=$(CC_DEPLOY_VERIFY_CMD="false" CC_DEPLOY_ROLLBACK_CMD="true" run "$d")
has "cfg cap honored" "$out" "escalate"
rm -rf "$d"

# 6. Config-file verify/rollback at cap (no env override) -> quotes + inline comment parsed correctly
d=$(mktemp -d); touch "$d/.cc-deploy-active"; echo 1 > "$d/.cc-deploy-state"
printf 'max_redeploys: 2\nverify: "false"\nrollback: "touch ROLLED_CFG"   # inline comment\n' > "$d/.cc-deploy.yaml"
out=$(run "$d")
has "cfg-driven cap triggers escalate" "$out" "escalate"
eq "cfg-driven rollback ran" "$([ -f "$d/ROLLED_CFG" ] && echo yes || echo no)" "yes"
rm -rf "$d"

# 7. No verify configured (no .cc-deploy.yaml, no env override) -> block + disarm
d=$(mktemp -d); touch "$d/.cc-deploy-active"
out=$(run "$d")
has "no-verify blocks" "$out" 'no `verify:` command'
eq "no-verify disarms" "$([ -f "$d/.cc-deploy-active" ] && echo present || echo gone)" "gone"
rm -rf "$d"

# 8. Live lock held by another process -> block, no redeploy counted, sentinel kept
d=$(mktemp -d); touch "$d/.cc-deploy-active"
mkdir "$d/.cc-loop-gate.lock"; echo $$ > "$d/.cc-loop-gate.lock/pid"
out=$(CC_DEPLOY_VERIFY_CMD="false" run "$d")
has "live lock blocks" "$out" "already in progress"
eq "live lock counts no redeploy" "$([ -f "$d/.cc-deploy-state" ] && cat "$d/.cc-deploy-state" || echo none)" "none"
eq "live lock keeps sentinel" "$([ -f "$d/.cc-deploy-active" ] && echo present)" "present"
rm -rf "$d"

# 9. Stand-down audit trail: the redeploy breaker and the no-verify disarm each
#    append one durable line; a healthy verify writes nothing.
d=$(mktemp -d); touch "$d/.cc-deploy-active"; echo 2 > "$d/.cc-deploy-state"
CC_DEPLOY_VERIFY_CMD="false" CC_DEPLOY_ROLLBACK_CMD="true" run "$d" >/dev/null
has "redeploy breaker logs stand-down" "$(tail -1 "$d/.cc-loop-standdowns.log" 2>/dev/null)" "loop-deploy redeploy-breaker attempts=3 rollback=ok"
rm -rf "$d"
d=$(mktemp -d); touch "$d/.cc-deploy-active"; echo 2 > "$d/.cc-deploy-state"
CC_DEPLOY_VERIFY_CMD="false" CC_DEPLOY_ROLLBACK_CMD="false" run "$d" >/dev/null
has "failed rollback recorded" "$(tail -1 "$d/.cc-loop-standdowns.log" 2>/dev/null)" "rollback=FAILED"
rm -rf "$d"
d=$(mktemp -d); touch "$d/.cc-deploy-active"
run "$d" >/dev/null
has "no-verify disarm logs stand-down" "$(tail -1 "$d/.cc-loop-standdowns.log" 2>/dev/null)" "loop-deploy no-verify-command"
rm -rf "$d"
d=$(mktemp -d); touch "$d/.cc-deploy-active"
CC_DEPLOY_VERIFY_CMD="true" run "$d" >/dev/null
eq "healthy verify writes no stand-down" "$([ -f "$d/.cc-loop-standdowns.log" ] && echo present || echo gone)" "gone"
rm -rf "$d"

echo "---"; echo "pass=$pass fail=$fail"; [ "$fail" -eq 0 ]
