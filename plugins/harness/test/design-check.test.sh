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

# --- section scoping: only ## Decisions is parsed ---------------------------
# mkdoc <name>; the whole body (after frontmatter) on stdin.
mkdoc() {
  d="$TMP/$1"; rm -rf "$d"; mkdir -p "$d"
  { printf -- '---\nslug: %s\nstatus: locked\nstage: lock\n---\n# t\n\n' "$1"; cat; } > "$d/design.md"
  cp "$TMP/good/plan.md" "$d/plan.md"
  echo "$d"
}
d=$(mkdoc othersections <<EOF
## Discovery
- [[kaffecard]] is the prior art
- [pilot notes](notes/pilot.md)
- [ ] verify with shop owners

## Decisions
$GOOD

## Scope
- [ ] verify with shop owners
EOF
); run "$d"
[ "$RC" = "0" ] && ok "checkbox-looking lines outside ## Decisions are ignored" \
  || bad "lines outside Decisions ignored (rc=$RC: $OUT)"
d=$(mkdoc nodecisions <<<"## Discovery
$GOOD"); run "$d"
expect_block "a design with no ## Decisions section blocks" "Decisions"
for variant in '  - [ ] Q9 · med · indented' '* [ ] Q9 · med · star' '+ [ ] Q9 · med · plus' \
               '1. [ ] Q9 · med · ordered' '1) [ ] Q9 · med · paren'; do
  d=$(mk variant locked <<<"$GOOD
$variant"); run "$d"
  expect_block "non-canonical checkbox inside Decisions is malformed: '$variant'" "malformed"
done
# A blockquoted checkbox renders as a to-do, so skipping it would hide an open
# (or unowned) item exactly like an indented one.
for variant in '> - [ ] Q9 · med · quoted' '> - [x] Q9 · med · quoted · decided-by: you' '>- [ ] Q9 · med · tight quote'; do
  d=$(mk variant locked <<<"$GOOD
$variant"); run "$d"
  expect_block "blockquoted checkbox inside Decisions is malformed: '$variant'" "malformed"
done
# Two Decisions sections make it ambiguous which one is the record; reading
# only the exact heading let decisions under '## Decisions (cont.)' go unseen.
d=$(mkdoc twodecisions <<EOF
## Decisions
$GOOD

## Decisions
- [ ] Q9 · med · second section · open
EOF
); run "$d"
expect_block "a second '## Decisions' heading blocks" "more than one '## Decisions'"
d=$(mkdoc decisionscont <<EOF
## Decisions
$GOOD

## Decisions (cont.)
- [ ] Q9 · med · hidden in a continuation section · open
EOF
); run "$d"
expect_block "a '## Decisions (cont.)' heading alongside '## Decisions' blocks" "more than one '## Decisions'"
d=$(mk fakefence locked <<<"$GOOD
\`\`\` \`x\`
- [ ] Q9 · med · hidden behind a fake fence · open
\`\`\`"); run "$d"
expect_block "a fake fence (backtick in info string) does not hide an open item" "BLOCK: Q9"
d=$(mk tildefence locked <<<"$GOOD
~~~ text
- [ ] Q9 · med · example inside a tilde fence · open
~~~"); run "$d"
[ "$RC" = "0" ] && ok "checklist lines inside a ~~~ fence are ignored" || bad "tilde fence ignored (rc=$RC: $OUT)"
# A fence closes only on its own marker: inside a ``` block a ~~~ line is
# content. Toggling on any marker let the ~~~ close the block and the real ```
# closer open a new one, hiding the open item after it from the gate.
d=$(mk mixedfence locked <<<"$GOOD
\`\`\`
~~~
\`\`\`
- [ ] Q9 · med · after a mixed-marker fence · open
~~~"); run "$d"
expect_block "a ~~~ line does not close a \`\`\` fence (open item after it is seen)" "BLOCK: Q9"
d=$(mk mixedfence2 locked <<<"$GOOD
~~~
\`\`\`
~~~
- [ ] Q9 · med · after a mixed-marker fence · open
\`\`\`"); run "$d"
expect_block "a \`\`\` line does not close a ~~~ fence (open item after it is seen)" "BLOCK: Q9"
d=$(mk unclosed locked <<<"$GOOD
\`\`\`
- [ ] Q9 · med · everything after an unclosed fence is hidden · open"); run "$d"
expect_block "an unclosed fence blocks" "fence"

# CommonMark fences (XARI-151): an opener or closer may be indented 0–3
# spaces; a closer is the opener's character, at least as long, with no info
# string. A column-0-only rule let an indented closer end the block in the
# rendered doc but not in the gate, hiding every decision until the next fence.
d=$(mk indentclose locked <<EOF
$GOOD
\`\`\`
example
   \`\`\`
- [ ] Q9 · med · after an indented closer · open
\`\`\`
later example
   \`\`\`
EOF
); run "$d"
expect_block "an indented closer ends the fence (open item after it is seen)" "BLOCK: Q9"
# Openers stay column-0: an indented fence may belong to a list item, which
# CommonMark ends with the item, and bash cannot track containers — so the
# gate reads through an indented fence (fail closed) rather than trust it.
d=$(mk indentopen locked <<EOF
$GOOD
  \`\`\`
- [ ] Q9 · med · inside an indented fence the gate does not trust · open
  \`\`\`
EOF
); run "$d"
expect_block "an indented opener is not trusted: lines inside it are still checked" "BLOCK: Q9"
d=$(mk listfence locked <<EOF
- [x] A1 · a · decided-by: you
  \`\`\`
- [ ] Q1 · med · after a list item fence that ends with the item · open
  \`\`\`
EOF
); run "$d"
expect_block "a fence inside a list item does not hide the next decision" "BLOCK: Q1"
d=$(mk listfence4 locked <<EOF
- [x] A1 · a · decided-by: you
  \`\`\`
  code
    \`\`\`
- [ ] Q1 · med · after a list item fence · open
\`\`\`
EOF
); run "$d"
expect_block "a list item's fence with a deeper closer does not hide the next decision" "BLOCK: Q1"
d=$(mk listsec locked <<EOF
$GOOD
- [x] A2 · a · decided-by: you
  \`\`\`
## Decisions
- [ ] Q1 · med · in a second Decisions section · open
  \`\`\`
EOF
); run "$d"
expect_block "a list item's fence does not hide a second Decisions heading" "more than one '## Decisions'"
d=$(mk fourspace locked <<EOF
$GOOD
    \`\`\`
- [ ] Q9 · med · after a 4-space-indented fence-looking line · open
    \`\`\`
EOF
); run "$d"
expect_block "a 4-space-indented line is not a fence (open item is seen)" "BLOCK: Q9"
d=$(mk fourclose locked <<EOF
$GOOD
\`\`\`
    \`\`\`
\`\`\`
- [ ] Q9 · med · after a fence with a 4-space line inside · open
EOF
); run "$d"
expect_block "a 4-space-indented line does not close a fence" "BLOCK: Q9"
d=$(mk longfence locked <<EOF
$GOOD
\`\`\`\`
\`\`\`
- [ ] Q9 · med · example inside a 4-backtick fence · open
\`\`\`\`
EOF
); run "$d"
[ "$RC" = "0" ] && ok "a shorter run does not close a longer fence" || bad "shorter closer (rc=$RC: $OUT)"
d=$(mk infoclose locked <<EOF
$GOOD
\`\`\`
\`\`\` js
\`\`\`
- [ ] Q9 · med · after a fence whose inner line had an info string · open
\`\`\`
x
\`\`\`
EOF
); run "$d"
expect_block "a line with an info string does not close a fence" "BLOCK: Q9"

d=$(mk crlf locked <<EOF
$GOOD
\`\`\`
example
\`\`\`
- [ ] Q9 · med · after a CRLF fence · open
EOF
); perl -pi -e 's/\n/\r\n/' "$d/design.md"; run "$d"
expect_block "a CRLF closer ends the fence (open item after it is seen)" "BLOCK: Q9"

# --- anchored markers and bounded echo --------------------------------------
d=$(mk undecided locked <<<"$GOOD
- [x] Q8 · med · x → y · undecided-by: you"); run "$d"
expect_block "'undecided-by: you' does not count as decided-by" "BLOCK: Q8"
d=$(mk undeferred locked <<<"$GOOD
- [~] A8 · low · x · undeferred: later"); run "$d"
expect_block "'undeferred:' does not count as a deferral reason" "BLOCK: A8"
long=$(printf 'z%.0s' $(seq 1 300))
d=$(mk longline locked <<<"$GOOD
- [x] X1 · $long"); run "$d"
{ [ "$RC" = "1" ] && ! grep -q "zzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzz" <<<"$OUT"; } \
  && ok "a malformed line is echoed truncated to 80 chars" || bad "malformed echo truncated (rc=$RC: $OUT)"

# --- invocation ------------------------------------------------------------
run "$TMP/does-not-exist"
expect_block "missing design dir blocks" "design.md"
run
[ "$RC" = "2" ] && ok "no arguments is a usage error (exit 2)" || bad "usage error (rc=$RC)"
run "$TMP/good" --bogus
[ "$RC" = "2" ] && ok "unknown flag is a usage error (exit 2)" || bad "unknown flag (rc=$RC)"

exit $fail
