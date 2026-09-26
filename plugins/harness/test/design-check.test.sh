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
# mkdoc <name>; the whole body (after frontmatter) on stdin.
mkdoc() {
  d="$TMP/$1"; rm -rf "$d"; mkdir -p "$d"
  { printf -- '---\nslug: %s\nstatus: locked\nstage: lock\n---\n# t\n\n' "$1"; cat; } > "$d/design.md"
  cp "$TMP/good/plan.md" "$d/plan.md"
  echo "$d"
}
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
d=$(mkdoc fenced <<EOF
## Scope
\`\`\`
- [ ] Q9 · med · example inside a code fence · open
\`\`\`

## Decisions
$GOOD
EOF
); run "$d"
[ "$RC" = "0" ] && ok "checklist lines inside a code fence are ignored" || bad "fenced lines ignored (rc=$RC: $OUT)"
d=$(mk recfence locked <<<"$GOOD
~~~
- [ ] Q9 · med · shown as code in the record · open
~~~"); run "$d"
expect_block "a code fence in the record blocks" "code fence in the record"

# --- section scoping: only ## Decisions is parsed ---------------------------
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
expect_block "a to-do checkbox outside ## Decisions blocks (checkboxes live only in the record)" "checkbox outside"
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
d=$(mkdoc tildefence <<EOF
## Scope
~~~ text
- [ ] Q9 · med · example inside a tilde fence · open
~~~

## Decisions
$GOOD
EOF
); run "$d"
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
grep -q "ambiguous" <<<"$OUT" && bad "an indented closer ends the fence is not flagged ambiguous ($OUT)" || ok "an indented closer ends the fence is not flagged ambiguous"
# An indented fence opener blocks: at top level it is a fence, inside a list
# item it ends with the item, and a line-based loop cannot tell which. Trusting
# it and reading through it both let an open decision pass. It blocks exactly
# once, then its content is skipped (the design is already blocked).
IND="code fence indented under a list"
once() { [ "$(grep -c "$IND" <<<"$OUT")" = "1" ] && ok "$1" || bad "$1 (rc=$RC: $OUT)"; }
d=$(mk indentopen locked <<EOF
$GOOD
  \`\`\`
- [ ] Q9 · med · inside an indented fence the gate does not trust · open
  \`\`\`
EOF
); run "$d"
expect_block "an indented opener blocks" "$IND"; once "...exactly once (its closer is not re-flagged)"
d=$(mk listfence locked <<EOF
- [x] A1 · a · decided-by: you
  \`\`\`
- [ ] Q1 · med · after a list item fence that ends with the item · open
  \`\`\`
EOF
); run "$d"
expect_block "a fence inside a list item blocks instead of hiding the next decision" "$IND"
d=$(mk listfence4 locked <<EOF
- [x] A1 · a · decided-by: you
  \`\`\`
  code
    \`\`\`
- [ ] Q1 · med · after a list item fence · open
\`\`\`
EOF
); run "$d"
expect_block "a list item's fence with a deeper closer blocks" "$IND"; once "...exactly once, with no spurious unclosed-fence block"
d=$(mk listsec locked <<EOF
$GOOD
- [x] A2 · a · decided-by: you
  \`\`\`
## Decisions
- [ ] Q1 · med · in a second Decisions section · open
  \`\`\`
EOF
); run "$d"
expect_block "a list item's fence cannot hide a second Decisions heading" "$IND"
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
d=$(mkdoc longfence <<EOF
## Scope
\`\`\`\`
\`\`\`
- [ ] Q9 · med · example inside a 4-backtick fence · open
\`\`\`\`

## Decisions
$GOOD
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
grep -q "ambiguous" <<<"$OUT" && bad "a CRLF closer ends the fence is not flagged ambiguous ($OUT)" || ok "a CRLF closer ends the fence is not flagged ambiguous"

# Ambiguous fence lines block instead of being read either way: an indented
# opener (a fence at top level, but it ends with its list item inside one),
# and a near-miss closer that CommonMark and marked disagree on.
d=$(mk indenttop locked <<EOF
$GOOD
  \`\`\`
~~~
  \`\`\`
- [ ] Q9 · med · visible after an indented top-level fence · open
~~~
EOF
); run "$d"
expect_block "an indented top-level fence blocks as ambiguous" "$IND"
d=$(mk indentthen locked <<EOF
$GOOD
   \`\`\`
example
\`\`\`
- [ ] Q1 · med · reward expiry · open
\`\`\`
EOF
); run "$d"
expect_block "an indented fence before a later fence pair blocks" "$IND"
for tail in "\t" "\`" "\f"; do
  d=$(mk "nearclose$RANDOM" locked <<EOF
$GOOD
~~~
x
EOF
); printf '~~~%b\n- [ ] Q9 · med · after a near-miss closer · open\n~~~\n' "$tail" >> "$d/design.md"; run "$d"
  expect_block "a closer followed by '$tail' blocks as ambiguous" "ambiguous fence closer"
done
d=$(mkdoc spaceclose <<EOF
## Scope
~~~
- [ ] Q9 · med · example inside a fence · open
~~~   

## Decisions
$GOOD
EOF
); run "$d"
[ "$RC" = "0" ] && ok "a closer followed by spaces closes cleanly" || bad "space-trailed closer (rc=$RC: $OUT)"

# Bytes the renderers and the gate split differently block before parsing: a
# lone CR is a line break to CommonMark and marked but not to `read`, bash
# drops NULs the renderers keep, and invalid UTF-8 makes the regexes
# locale-dependent. Each let a crafted design hide an open item.
d=$(mk lonecr locked <<<"$GOOD"); printf '\140\140\140\n\140\140\140\r- [ ] Q2 · med · after a lone CR · open\n\140\140\140\n' >> "$d/design.md"; run "$d"
expect_block "a lone CR blocks (renderers break the line there)" "carriage return"
d=$(mk nul locked <<<"$GOOD"); printf '\140\140\140\n\140\140\140\000\n\140\140\140\n- [ ] Q2 · med · after a NUL · open\n\140\140\140\n' >> "$d/design.md"; run "$d"
expect_block "a NUL byte blocks" "NUL"
d=$(mk badutf8 locked <<<"$GOOD"); printf '\140\140\140\377\n\140\140\140\n- [ ] Q2 · med · after invalid UTF-8 · open\n\140\140\140\n' >> "$d/design.md"; run "$d"
expect_block "invalid UTF-8 blocks" "UTF-8"
d=$(mk utf8ok locked <<<"$GOOD
- [x] Q7 · med · año, café, 日本 → ok · decided-by: you"); run "$d"
[ "$RC" = "0" ] && ok "valid non-ASCII UTF-8 passes" || bad "valid UTF-8 (rc=$RC: $OUT)"

# An indented backtick run with a backtick in its info string is inline code
# to every renderer, not a fence.
d=$(mk indentinline locked <<<"$GOOD
  \`\`\` \`x\` inline code"); run "$d"
grep -q "$IND" <<<"$OUT" && bad "indented inline code is not a fence ($OUT)" || ok "indented inline code is not a fence"
# Only '## Decisions' at column 0 opens the record: any other heading shown as
# 'Decisions' would be a second record the gate never reads.
for h in " ## Decisions" "##  Decisions" "##	Decisions" "### Decisions" "## decisions"; do
  d=$(mk "dechead$RANDOM" locked <<<"$GOOD
$h
- [ ] Q2 · med · in a disguised second record · open"); run "$d"
  expect_block "heading '$h' blocks" "heading"
done
d=$(mk dechsetext locked <<<"$GOOD

Decisions
---------
- [ ] Q2 · med · under a setext Decisions heading · open"); run "$d"
expect_block "a setext 'Decisions' heading blocks" "right under text"
d=$(mk dechcont locked <<<"$GOOD
Discussion of the decisions
---------"); run "$d"
grep -q "not written as" <<<"$OUT" && bad "a setext heading about decisions is fine ($OUT)" || ok "a setext heading that is not 'Decisions' is fine"

# --- the design dialect is an allowlist (XARI-160) ---------------------------
# A line gate cannot track every Markdown construct a renderer does, and each
# blocklist round found a new one. So a design may use only the constructs the
# gate reads the same way the renderers do; anything else blocks.
pass() { [ "$RC" = "0" ] && ok "$1" || bad "$1 (rc=$RC: $OUT)"; }
# What /harness:shape writes: frozen discovery claims, tables, Mermaid fences.
d=$(mkdoc shaped <<EOF
## Discovery
[brief](docs/discovery/offline-stamps.md)
- Shops lose signal in basements, so scans must work offline
- Stamps are idempotent by card+timestamp, see <https://example.com/spec>
- p95 sync stays <200ms on 3G

## Scope

| In | Out |
|---|---|
| offline queue | multi-device<br>shops |

## Flow & what-ifs

\`\`\`mermaid
flowchart LR
  A[Scan QR<br>offline] --> B[Queue locally]
  B -.-> C{Online?}
\`\`\`

## Components

\`\`\`mermaid
graph TD
  app --> queue
\`\`\`

## Scope board

| Item | Scope | Decision |
|---|---|---|
| stamp_count rename | in | Q1 |

## Decisions
$GOOD
EOF
); run "$d" --require-locked
pass "a design shaped like /harness:shape output passes"
# The shipped template itself (frontmatter, empty tables, '## Decisions' last).
d="$TMP/template"; mkdir -p "$d"; cp "$TMP/good/plan.md" "$d/"
{ sed -e 's/__SLUG__/template/' -e 's/__TITLE__/Offline stamps/' "$(dirname "$SCRIPT")/../templates/design.md"; printf '%s\n' "$GOOD"; } > "$d/design.md"
run "$d"
pass "the /harness:shape template with decisions appended passes"

# Inside the record every non-blank line must be a decision line: an escaped
# marker, a table row or a lazy continuation renders an open item as text.
for variant in '\- [ ] Q2 · med · escaped marker · open' '| [ ] Q2 | open |' \
               '[ ] Q2 · med · lazy continuation of the line above · open' \
               '### Notes' 'Some note about the decisions'; do
  d=$(mk "rec$RANDOM" locked <<<"$GOOD
$variant"); run "$d"
  expect_block "a non-decision line in the record blocks: '$variant'" "malformed"
done
d=$(mk reccomment locked <<EOF
$GOOD
<!--
\`\`\`
-->
- [ ] Q2 · med · shown by the renderers after the comment · open
\`\`\`
EOF
); run "$d"
expect_block "an HTML comment hiding a fence opener in the record blocks" "HTML"

# Raw HTML blocks anywhere: a fence opener inside <!-- … --> is HTML to the
# renderers, so the gate's fence would swallow the rendered record.
d=$(mkdoc htmlscope <<EOF
## Scope
<!--
\`\`\`
-->

## Decisions
- [ ] Q2 · med · open in the rendered record · open

\`\`\`
## Decisions
$GOOD
EOF
); run "$d"
expect_block "an HTML comment hiding a fence opener outside the record blocks" "HTML"
for h in '<h2>Decisions</h2>' '<details>' '  <div>' '- <!-- note -->' '> </div>' '<?php x ?>' '<!DOCTYPE html>'; do
  d=$(mkdoc "html$RANDOM" <<EOF
## Scope
$h

## Decisions
$GOOD
EOF
); run "$d"
  expect_block "a raw HTML block line blocks: '$h'" "HTML"
done
d=$(mkdoc autolink <<EOF
## Scope
<https://example.com/a>
<ops@example.com>
<= 5 shops, < 3 devices

## Decisions
$GOOD
EOF
); run "$d"
pass "autolinks and a bare '<' are not HTML"

# Headings: nested ones and ones spelled with inline markup block, so any
# heading that renders as 'Decisions' is caught by a plain text comparison.
for q in '> ## Decisions' '>> ### Notes' '> shops only' '- > ## Decisions' '1. > # Decisions'; do
  d=$(mkdoc "quote$RANDOM" <<EOF
$q
- [ ] Q2 · med · in a second rendered record · open

## Decisions
$GOOD
EOF
); run "$d"
  expect_block "a blockquote blocks: '$q'" "blockquote"
done
for h in '- ## Decisions' '1. # Title' '  ## Decisions' '    ## Decisions' \
         '## *Decisions*' '## Decision&#115;' '## Decision&#x73;' '## &#68;ecisions' '## De&#99;isions' '## [Decisions](x)' \
         '## De`cis`ions' '## \Decisions' '## _Decisions_' '## Deci<span>sions</span>'; do
  d=$(mkdoc "head$RANDOM" <<EOF
$h
- [ ] Q2 · med · in a second rendered record · open

## Decisions
$GOOD
EOF
); run "$d"
  expect_block "heading '$h' blocks" "heading"
done
d=$(mkdoc plainheads <<EOF
## Flow & what-ifs
### Rename stamp_count to stamps_total
## Scope board ##

## Decisions
$GOOD
EOF
); run "$d"
pass "plain headings with '&', intraword '_' and closing hashes pass"

# Setext: the heading text is the whole paragraph the underline closes.
d=$(mkdoc setextmulti <<EOF
## Scope
The team reviewed these
Decisions
---

## Decisions
$GOOD
EOF
); run "$d"
expect_block "no setext: a rule-like line right under text blocks (multi-line paragraph)" "right under text"
d=$(mkdoc setextlazy <<EOF
## Scope
- shops only
Decisions
---

## Decisions
$GOOD
EOF
); run "$d"
expect_block "no setext: a rule-like line right under text blocks (lazy)" "right under text"
d=$(mkdoc setextquote <<EOF
## Scope
> shops only
Decisions
---

## Decisions
$GOOD
EOF
); run "$d"
expect_block "a blockquote's lazy continuation blocks (no blockquotes)" "blockquote"
d=$(mkdoc setextlist <<EOF
## Scope
- Decisions
---

## Decisions
$GOOD
EOF
); run "$d"
expect_block "no setext: a rule-like line right under text blocks (list)" "right under text"
for body in '- Decisions\n  ---' '## Scope\nDecisions\n=========' \
            '*Decisions*\n---' 'Deci<!--\n-->sions\n---' 'Deci<!--\n2. x -->sions\n---'; do
  d=$(mkdoc "setext$RANDOM" < <(printf -- "$body"'\n- [ ] Q2 · med · open · open\n\n## Decisions\n%s\n' "$GOOD")); run "$d"
  expect_block "setext heading blocks: '$body'" "heading"
done

# Review of PR #80: each of these printed DESIGN OK while commonmark 0.31.2 and
# marked 15 showed an open Q2 under a "Decisions" heading.
# body <printf-format> — a design whose body (after frontmatter) is the format,
# followed by the valid record.
body() { mkdoc "$1" < <(printf -- "$2"'\n\n## Decisions\n%s\n' "$GOOD"); }
# An autolink starts with a letter or digit: <!, <? and </ always open HTML.
for h in '<!--x@a.b>' '<?x@a.b>' '<![CDATA[x@a.b>'; do
  d=$(body "auto$RANDOM" "## Scope\n$h\n\140\140\140\n-->\n\n## Decisions\n- [ ] Q2 · med · open · open\n\n\140\140\140"); run "$d"
  expect_block "'$h' is HTML, not an autolink" "raw HTML"
done
# A tab after '>' or a list marker is a container, as a space is.
for b in '>\t## Decisions\n>\t- [ ] Q2 · open' '-\t## Decisions\n\n\t- [ ] Q2 · open' \
         '- \t## Decisions' '1.\t## Decisions' '>\t- ## Decisions' '>\tDecisions\n>\t---' \
         '- foo\n\n\tDecisions\n\t---'; do
  d=$(body "tab$RANDOM" "$b"); run "$d"
  expect_block "a tab-separated container is read: '$b'" "heading"
done
d=$(body tabhtml '-\t<h2>Decisions</h2>'); run "$d"
expect_block "HTML after a tab-separated list marker blocks" "raw HTML"
# A heading on a list continuation line indented 4+ spaces is still a heading.
d=$(body contind '- a\n\n    ## Decisions\n\n    - [ ] Q2 · open'); run "$d"
expect_block "a heading on an indented list continuation line blocks" "heading inside"
# Inline HTML draws a record too: the map keeps <h2>, <ul> and <input>.
d=$(body inlinehtml '## Scope\nSee <h2>Decisions</h2><ul><li><input type="checkbox"> Q2 · open</li></ul>'); run "$d"
expect_block "inline HTML in prose blocks" "raw HTML"
d=$(body brok '## Scope\n| a | b |\n|---|---|\n| multi<br>line | `stamp_count` &lt;div&gt; |'); run "$d"
pass "<br>, inline code without '<', and &lt; pass"
# Code spans are not exempt: renderers pair backticks across escapes, lines and
# table cells differently from any line rule.
for b in '## Scope\nEmbed it with `<div class="w">`' \
         '## Scope\n\\`<input type="checkbox" disabled>\\` Q9 open' \
         '## Scope\nNote `a\nb` <h2>Decisions</h2> `c' \
         '| a | b |\n|---|---|\n| `x | <h2>Decisions</h2> | y` |'; do
  d=$(body "span$RANDOM" "$b"); run "$d"
  expect_block "HTML in or around a code span blocks: '$b'" "raw HTML"
done
d=$(mk recspan locked <<<"$GOOD
- [x] A1 · fine · decided-by: you \\\`</li><li><input type=\"checkbox\" disabled> Q2 · open\`"); run "$d"
expect_block "an escaped backtick cannot hide HTML in a decision line" "a decision line holds"
d=$(mk recbr locked <<<"$GOOD
- [x] Q3 · med · a<br>- [ ] Q2 · open · decided-by: you"); run "$d"
expect_block "<br> inside a decision line blocks" "a decision line holds"
d=$(mk reccmt locked <<<"$GOOD
- [x] Q5 · med · still open, nobody decided <!-- · decided-by: you -->"); run "$d"
expect_block "a comment hiding the owner in a decision line blocks" "a decision line holds"
d=$(mk recent locked <<<"$GOOD
- [x] Q5 · med · a &#91; &#93; Q2 · open · decided-by: you"); run "$d"
expect_block "an entity in a decision line blocks" "a decision line holds"
# CRLF frontmatter is skipped by the gate, so render-map skips it too; a
# heading written inside it never reaches a reader.
d=$(mk crlffm locked <<<"$GOOD"); perl -pi -e 's/\n/\r\n/' "$d/design.md"; run "$d" --require-locked
pass "CRLF frontmatter is skipped"
# Any heading that starts with "Decision" is the record's word.
for h in '### Decisions:' '### Decisions.' '### Decision' '## Decision' \
         '### Decisions/2' '## Decisions ##'; do
  d=$(body "word$RANDOM" "$h\n- [ ] Q2 · open"); run "$d"
  expect_block "heading '$h' blocks" "reads as the Decisions record"
done
# Round 2: an item marker that cannot interrupt a paragraph is an underline
# or text; a rule or underline indented past the paragraph's window is text.
for b in 'Decisions\n-\n\n- [ ] Q1 · open' 'Decisions\n*\n===' 'Decisions\n+\n===' 'Decisions\n1.\n===' \
         'Decisions\n    ***\n===' 'Decisions\n\t***\n===' '- - a\n\n    Decisions\n    ---'; do
  d=$(body "und$RANDOM" "$b"); run "$d"
  expect_block "setext heading read as the renderers read it: '$b'" "heading"
done
d=$(body deepunder '## Scope\nDecisions pending review\n    ---'); run "$d"
expect_block "no setext: a rule-like line right under text blocks (deep)" "right under text"
# Round 3: structure the old paragraph model misread. The dialect now has no
# setext headings, no blockquotes and no odd whitespace, so none need modelling.
for b in '    x\nDecisions\n ---\n\n- [ ] Q1 · open' '- Decisions\n===' '2. Decisions\n===' '- a\n  ---' \
         '1. Decisions\n  ---'; do
  d=$(body "r3u$RANDOM" "$b"); run "$d"
  expect_block "a rule-like line under text blocks: '$b'" "right under text"
done
for b in '+ > Decisions\n  > ===' '> x\n2. Decisions\n   ---'; do
  d=$(body "r3q$RANDOM" "$b"); run "$d"
  expect_block "a quote inside or before a list blocks: '$b'" "blockquote"
done
for b in '##\302\240Decisions' '#\vDecisions' '#\fDecisions' '##\342\200\203Decisions' '##\343\200\200Decisions' \
         '## \302\240Decisions' '-\t>\t## Decisions'; do
  d=$(body "r3s$RANDOM" "$b\n- [ ] Q1 · open"); run "$d"
  expect_block "odd whitespace blocks: '$b'" "non-ASCII space"
done
for b in '## Scope\n[a\\]b]: /u "\n\140\140\140\n"' '## Scope\n[a\nb]: /u "\n\140\140\140\n"'; do
  d=$(body "r3l$RANDOM" "$b"); run "$d"
  expect_block "a link definition with an escaped or split label blocks: '$b'" "link reference definition"
done
d=$(body strike '## ~~Decisions~~\n- [ ] Q9 · high · open · open'); run "$d"
expect_block "a strikethrough heading blocks" "inline markup"
d=$(body rules 'intro\n## Scope\n---\n\ntext\n\n***\n\n## Flow & what-ifs\n\n---\n\ntext\n~~~\ncode\n~~~\n---'); run "$d"
pass "a rule after a heading, a blank line or a fence closer passes"
d="$TMP/fmcol0"; mkdir -p "$d"; cp "$TMP/good/plan.md" "$d/"
printf -- '---\nslug: fmcol0\nstatus: draft\ndiscovery:\n- docs/discovery/a.md\n  - "docs/discovery/b.md"\n  - "[[brief]]"\n  - [[other brief]]\n---\n## Decisions\n%s\n' "$GOOD" > "$d/design.md"; run "$d"
pass "frontmatter list items at column 0, quoted or as a wikilink pass"
# Round 4: a line opening with <br> starts an HTML block (CommonMark type 7)
# that swallows the next fence line, so the gate's fence and the renderers'
# disagree; invisible characters hide inside a heading that reads "Decisions".
for b in '## Scope\n\n<br>\n\140\140\140\n\n## Decisions\n\n- [ ] Q1 · ship without auth?\n\n\140\140\140' \
         '### Notes\n<BR />\n~~~\n\n## Decisions\n\n- [ ] Q1 · open\n\n~~~' '- <br>' '   <br/>'; do
  d=$(body "br$RANDOM" "$b"); run "$d"
  expect_block "a line opening with <br> blocks: '$b'" "opening with <br>"
done
for b in '## \342\200\213Decisions' '## \302\255Decisions' '## \342\200\214Decisions' '## \342\200\216Decisions' \
         '## \342\201\240Decisions' '## Deci\342\200\213sions'; do
  d=$(body "zw$RANDOM" "$b\n\n- [ ] Q1 · open"); run "$d"
  expect_block "an invisible character blocks: '$b'" "invisible character"
done
# Round 5: a list of invisible characters is never complete, so the heading
# test reads ASCII letters only — any other byte inside "Decisions" is ignored.
for b in '## \342\201\246Decisions' '## Dec\342\201\251isions' '## \330\234Decisions' '## Deci\357\270\217sions' \
         '## \343\205\244Decisions' '## \363\240\200\201Decisions' '## \001Decisions'; do
  d=$(body "inv$RANDOM" "$b\n\n- [ ] Q1 · open"); run "$d"
  expect_block "a heading whose letters read 'Decision…' blocks: '$b'" "reads as the Decisions record"
done
# Only a heading that reads as the record blocks: its letters are "Decision",
# or start with "Decisions". A feature titled "Decision…" still locks.
d=$(body decwords '## Scope\n### Decision criteria\n## 1. Decision log\n## 42 Decisiones pendientes'); run "$d"
pass "headings that only start with the word 'Decision' pass"
d="$TMP/dectitle"; mkdir -p "$d"; cp "$TMP/good/plan.md" "$d/"
{ sed -e 's/__SLUG__/dectitle/' -e 's/__TITLE__/Decision tree editor/' "$(dirname "$SCRIPT")/../templates/design.md"; printf '%s\n' "$GOOD"; } > "$d/design.md"
run "$d"; pass "a design titled 'Decision tree editor' passes"
# A frontmatter list item is one path or [[wikilink]]: a plain renderer shows
# frontmatter as body text, where a nested list can hold a heading.
for b in '- - ## Decisions\n- - [ ] Q1 · open' '- 1. ## Decisions' '- - # Decision log' '- docs/a.md and more'; do
  d="$TMP/fmn$RANDOM"; mkdir -p "$d"; cp "$TMP/good/plan.md" "$d/"
  printf -- "---\nslug: fmn\nstatus: draft\ndiscovery:\n$b\n---\n## Decisions\n%s\n" "$GOOD" > "$d/design.md"; run "$d"
  expect_block "a frontmatter item that is not one path blocks: '$b'" "frontmatter holds only"
done
# Round 7: an empty heading ends the record for the gate but shows nothing;
# a checkbox under any heading that starts like "Decision" blocks, so titles
# like "Decision support tool" still lock.
for b in '## \n- [ ] Q9 · open' '## ##\n- [ ] Q9 · open' '### \342\201\246\n- [ ] Q9 · open'; do
  d=$(mk "empty$RANDOM" locked < <(printf -- "$GOOD\n$b\n")); run "$d"
  expect_block "an item after an empty heading blocks: '$b'" "BLOCK"
done
for h in '## 1. Decision log' '## Decision record' '## Decision (open)' '### Decisions—open' '## Decision support' '# Decision tree editor'; do
  d=$(body "lead$RANDOM" "$h\n\n- [ ] Q1 · open"); run "$d"
  expect_block "a checkbox under '$h' blocks" "checkbox outside"
  d=$(body "leadok$RANDOM" "$h\n\n- plain notes, no checkbox"); run "$d"
  pass "'$h' with no checkbox under it passes"
done
# A second heading that reads exactly "Decisions" misleads a reviewer even
# with nothing checkable under it.
for h in '### Decisions' '## Decision' '## \342\201\246Decisions' '## Dec\342\201\251isions:'; do
  d=$(body "exact$RANDOM" "$h\n\nplain text, no checkbox"); run "$d"
  expect_block "a heading reading exactly 'Decision(s)' blocks: '$h'" "reads as the Decisions record but is not"
done
d=$(body leadreset '## Decision scope\n\n## Scope\n- [ ] verify with shop owners'); run "$d"
expect_block "a to-do checkbox under any heading outside the record blocks" "checkbox outside"
d="$TMP/fmspace"; mkdir -p "$d"; cp "$TMP/good/plan.md" "$d/"
printf -- '---\nslug: fmspace\nstatus: draft\ndiscovery:\n  - "02-Projects/homa-os/Product Brief v1.0.md"\n  - '"'"'docs/my file.md'"'"'\n---\n## Decisions\n%s\n' "$GOOD" > "$d/design.md"; run "$d"
pass "a quoted frontmatter path with spaces passes"
# Checkboxes live only in the record, so no heading needs to be recognised:
# translations, enumerators, sub-sections, nesting and text forms all block.
for b in '## Decisión\n\n- [ ] Q99 · nunca decidido · open' '## Décision\n\n- [ ] Q1 · open' \
         '## II. Decisions\n- [ ] Q1 · open' '## A. Decision log\n- [ ] Q1 · open' \
         '## Decision log\n\n- - [ ] Q1 · open' '## Decision log\n\n1. - [ ] Q1 · open' \
         '## Decision log\n\n### Pending\n\n- [ ] Q1 · open' '## Decisi0ns\n- [ ] Q1 · open' \
         '## 2\n- [ ] Q1 · open' '[ ] Q1 · open' '\\- [ ] Q1 · open' '- \\[ ] Q1 · open' \
         '- notes\n[ ] Q1 · open' '| - [ ] Q1 | open |\n|---|---|' '[x] A9 · chosen' \
         '### Decision criteria\n- [ ] must work offline'; do
  d=$(body "cb$RANDOM" "$b"); run "$d"
  expect_block "a checkbox outside the record blocks: '$b'" "checkbox outside"
done
d=$(body critok '### Decision criteria\n- must work offline\n- see [ADR 3](docs/adr/3.md) and [[offline-sync]]'); run "$d"
pass "plain bullets and links under a 'Decision…' heading pass"
d=$(body cjk '## 决定\n\n## 🎉 launch\n\nnotes'); run "$d"
pass "non-ASCII headings pass"
# A decision line may not hide its owner or a second item from the page.
for l in '- [x] Q5 · high · pick db [why](u "· decided-by: you ")' \
         '- [x] B5 · byproduct · cache ![n](u "· ack · decided-by: you ")' \
         '- [x] Q5 · med · ~~a · decided-by: you b~~' \
         '- [x] A5 · ok · decided-by: you · [ ] Q9 · ship without auth?'; do
  d=$(mk "rl$RANDOM" locked <<<"$GOOD
$l"); run "$d"
  expect_block "a decision line cannot hide an owner or an item: '$l'" "a decision line holds"
done
d="$TMP/fmcb"; mkdir -p "$d"; cp "$TMP/good/plan.md" "$d/"
printf -- '---\nslug: fmcb\nstatus: draft\ndiscovery:\n  - "- [ ] Q1 · open"\n---\n## Decisions\n%s\n' "$GOOD" > "$d/design.md"; run "$d"
expect_block "a checkbox in a quoted frontmatter value blocks" "checkbox in frontmatter"
d=$(body brlike '- <bridge-status>up</bridge-status>'); run "$d"
{ [ "$RC" = "1" ] && grep -q "raw HTML" <<<"$OUT" && ! grep -q "opening with <br>" <<<"$OUT"; } \
  && ok "a tag that only starts with 'br' is raw HTML, not a <br> opener" || bad "br-like tag (rc=$RC: $OUT)"
d=$(body wikicolon '## Discovery\n- [[kaffecard]]: prior art for idempotent stamping\n- see [[a]] and [[b]]: both'); run "$d"
pass "a wikilink followed by a colon is not a link definition"
d=$(body linkdef "## Context\n\n[r]: /u '\n\140\140\140\n'\n\n## Decisions\n\n- [ ] Q1 · open\n\n[s]: /v '\n\140\140\140\n'"); run "$d"
expect_block "a link reference definition blocks" "link reference definition"
# Frontmatter is body text to a plain renderer, so it holds only shape's keys.
d="$TMP/fmhide"; mkdir -p "$d"; cp "$TMP/good/plan.md" "$d/"
printf -- '---\nslug: fmhide\nstatus: draft\n## Decisions\n- [ ] Q1 · open question\n---\n## Decisions\n%s\n' "$GOOD" > "$d/design.md"; run "$d"
expect_block "a heading and an open item inside frontmatter block" "frontmatter holds only"
d="$TMP/fmhtml"; mkdir -p "$d"; cp "$TMP/good/plan.md" "$d/"
printf -- '---\nslug: fmhtml\nstatus: draft <h2>Decisions</h2>\n---\n## Decisions\n%s\n' "$GOOD" > "$d/design.md"; run "$d"
expect_block "HTML inside frontmatter blocks" "raw HTML in frontmatter"
d="$TMP/fmlist"; mkdir -p "$d"; cp "$TMP/good/plan.md" "$d/"
printf -- '---\nslug: fmlist\nstatus: locked\nstage: lock\ndiscovery:\n  - docs/discovery/offline-qr.md\ndiscovery-status: partial\n---\n## Decisions\n%s\n' "$GOOD" > "$d/design.md"; run "$d" --require-locked
pass "frontmatter with shape's keys and a discovery list passes"
# CRLF: a valid design saved with CRLF line endings passes.
d=$(mk crlfok locked <<<"$GOOD"); perl -pi -e 's/\n/\r\n/' "$d/design.md"; run "$d" --require-locked
[ "$RC" = "0" ] && ok "a valid CRLF design passes" || bad "valid CRLF design (rc=$RC: $OUT)"
# Author text is echoed with control bytes replaced, so a design cannot write
# terminal escapes into the hook output.
d=$(mk ctrlecho locked <<<"$GOOD"); printf '  - [ ] Q5 \033[31mred\033[0m\n' >> "$d/design.md"; run "$d"
{ [ "$RC" = "1" ] && ! grep -q $'\033' <<<"$OUT"; } && ok "echoed author text carries no escape bytes" || bad "escape bytes echoed ($OUT)"

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
