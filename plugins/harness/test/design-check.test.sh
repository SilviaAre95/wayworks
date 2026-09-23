#!/usr/bin/env bash
# Tests for design-check.sh. The gate exists so unsupervised code starts from a
# design with no open question, no unowned decision and no untested what-if. A
# gate that passes everything reads as confirmation, so each block condition is
# asserted to exit non-zero — same contract as scripts/check-skill-rules.test.sh.
set -uo pipefail
SCRIPT=$(cd "$(dirname "$0")/../scripts" && pwd)/design-check.sh
fail=0
ok()  { echo "ok   - $*"; }
bad() { echo "FAIL - $*"; fail=1; }

TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT

GOOD='- [x] W3 · high · QR scanned offline → queue locally · decided-by: you
- [x] B2 · byproduct · local stamp queue · ack · decided-by: accepted-default
- [~] A9 · low · second device for same shop · deferred: single-device shops only in v1
- [x] Q1 · med · reward expiry? → 90 days · decided-by: you'

# mk <name> <status>; decision lines on stdin. Plan mentions W3 only.
mk() {
  d="$TMP/$1"; rm -rf "$d"; mkdir -p "$d"
  { printf -- '---\nslug: %s\nstatus: %s\nstage: lock\n---\n# t\n\n## Decisions\n' "$1" "$2"; cat; } > "$d/design.md"
  printf '# Plan\n\n### Task 1: offline queue (W3)\nTest: a scan with no network queues the stamp (W3)\n' > "$d/plan.md"
  echo "$d"
}
run() { OUT=$(bash "$SCRIPT" "$@" 2>&1); RC=$?; }
expect_block() { # $1=label $2=grep pattern
  { [ "$RC" = "1" ] && grep -q -- "$2" <<<"$OUT"; } && ok "$1" || bad "$1 (rc=$RC: $OUT)"
}

# --- valid designs pass -----------------------------------------------------
d=$(mk good locked <<<"$GOOD"); run "$d" --require-locked
{ [ "$RC" = "0" ] && grep -q "DESIGN OK — 4 decision" <<<"$OUT"; } \
  && ok "valid locked design passes" || bad "valid locked design passes (rc=$RC: $OUT)"
d=$(mk gooddraft draft <<<"$GOOD"); run "$d"
[ "$RC" = "0" ] && ok "draft passes without --require-locked (shape's lock stage)" || bad "draft without flag (rc=$RC: $OUT)"

# --- rule 1: open items -----------------------------------------------------
d=$(mk open locked <<<"$GOOD
- [ ] Q4 · med · reward expiry? · open"); run "$d"
expect_block "open item blocks and is named" "BLOCK: Q4"

# --- rule 2: decided-by and ack ---------------------------------------------
d=$(mk noby locked <<<"$GOOD
- [x] Q5 · med · stamp limit → 10/day"); run "$d"
expect_block "decided item without decided-by blocks" "BLOCK: Q5"
d=$(mk badby locked <<<"$GOOD
- [x] Q6 · med · x → y · decided-by: someone"); run "$d"
expect_block "decided-by with an unknown value blocks" "BLOCK: Q6"
d=$(mk noack locked <<<"$GOOD
- [x] B7 · byproduct · retry cache · decided-by: you"); run "$d"
expect_block "byproduct without ack blocks" "BLOCK: B7"
d=$(mk nodefer locked <<<"$GOOD
- [~] A2 · low · kiosk mode"); run "$d"
expect_block "deferred item without a reason blocks" "BLOCK: A2"

# --- rule 3: every decided W appears in plan.md ------------------------------
d=$(mk wmissing locked <<<"$GOOD
- [x] W8 · high · token expires mid-scan → re-auth then retry · decided-by: you"); run "$d"
expect_block "decided what-if absent from plan blocks" "BLOCK: W8"
d=$(mk wboundary locked <<<"$GOOD")
printf '### Task 1 (W30)\n' > "$d/plan.md"; run "$d"
expect_block "W3 is not satisfied by W30 (word boundary)" "BLOCK: W3"
d=$(mk wdeferred locked <<<"$GOOD
- [~] W9 · low · clock skew · deferred: server time only"); run "$d"
[ "$RC" = "0" ] && ok "deferred what-if need not appear in plan" || bad "deferred W should not need a task (rc=$RC: $OUT)"
d=$(mk noplan locked <<<"$GOOD"); rm "$d/plan.md"; run "$d"
expect_block "missing plan.md blocks" "plan.md"

# --- rule 4: status --------------------------------------------------------
d=$(mk draft draft <<<"$GOOD"); run "$d" --require-locked
expect_block "draft with --require-locked blocks" "not locked"
d=$(mk shipped shipped <<<"$GOOD"); run "$d" --require-locked
expect_block "shipped with --require-locked blocks (shipped designs are immutable)" "not locked"
d=$(mk badstatus done <<<"$GOOD"); run "$d"
expect_block "unknown status blocks" "draft|locked|shipped"
d="$TMP/nofm"; mkdir -p "$d"; printf '## Decisions\n%s\n' "$GOOD" > "$d/design.md"; cp "$TMP/good/plan.md" "$d/"; run "$d"
expect_block "missing frontmatter blocks" "frontmatter"

# --- malformed lines -------------------------------------------------------
d=$(mk dash locked <<<"$GOOD
- [x] W4 - high - hyphens instead of middle dots - decided-by: you"); run "$d"
expect_block "wrong separator is malformed" "malformed"
d=$(mk prefix locked <<<"$GOOD
- [x] X1 · high · unknown prefix · decided-by: you"); run "$d"
expect_block "unknown ID prefix is malformed" "malformed"
d=$(mk upper locked <<<"$GOOD
- [X] Q7 · med · capital X · decided-by: you"); run "$d"
expect_block "capital [X] is malformed" "malformed"

# --- empty and fenced ------------------------------------------------------
d=$(mk empty locked </dev/null); run "$d"
expect_block "a design with no decisions blocks (asserts nothing)" "no decision"
d=$(mk fenced locked <<<"$GOOD
\`\`\`
- [ ] Q9 · med · example inside a code fence · open
\`\`\`"); run "$d"
[ "$RC" = "0" ] && ok "checklist lines inside a code fence are ignored" || bad "fenced lines ignored (rc=$RC: $OUT)"

# --- invocation ------------------------------------------------------------
run "$TMP/does-not-exist"
expect_block "missing design dir blocks" "design.md"
run
[ "$RC" = "2" ] && ok "no arguments is a usage error (exit 2)" || bad "usage error (rc=$RC)"
run "$TMP/good" --bogus
[ "$RC" = "2" ] && ok "unknown flag is a usage error (exit 2)" || bad "unknown flag (rc=$RC)"

exit $fail
