#!/usr/bin/env bash
# Deterministic gate over a design: <dir>/design.md + <dir>/plan.md.
#
# Why this exists: /harness:shape moves human supervision to before code, so a
# coding loop can run unattended. That only holds if the design it builds from
# has no open question, every decision says who made it, every byproduct was
# acknowledged, and every what-if became a task with a test. Those are grep-able
# facts, so they are checked here rather than trusted to a model.
#
# Usage: design-check.sh <design-dir> [--require-locked]
#   --require-locked  also require frontmatter status: locked (loop-dev passes it;
#                     shape's lock stage does not, since it locks after this passes)
# Exit 0 = pass, 1 = blocked, 2 = usage error. BLOCK lines go to stdout.
set -uo pipefail
usage() { echo "usage: design-check.sh <design-dir> [--require-locked]" >&2; exit 2; }
[ $# -ge 1 ] || usage
DIR="$1"; shift
REQUIRE_LOCKED=0
for a in "$@"; do
  case "$a" in --require-locked) REQUIRE_LOCKED=1 ;; *) usage ;; esac
done
DESIGN="$DIR/design.md"; PLAN="$DIR/plan.md"

fail=0
block() { echo "BLOCK: $*"; fail=1; }
# Author text echoed into a block message: first 80 bytes, control and
# non-ASCII bytes shown as '?', so a design cannot write escapes into the output.
shown() { printf '%s' "${1:0:80}" | tr -c '[:print:]' '?'; }
finish() {
  [ "$fail" -eq 0 ] && echo "DESIGN OK — $n decision(s) checked" || echo "DESIGN BLOCKED"
  exit $fail
}
n=0
[ -f "$DESIGN" ] || { block "design.md: $DESIGN does not exist"; finish; }

# --- bytes -----------------------------------------------------------------
# The loop below splits lines on \n only. CommonMark and marked also break a
# line at a lone \r, bash drops NUL bytes the renderers keep, and invalid
# UTF-8 made the regexes locale-dependent — each let a crafted design hide an
# open item from the gate while the rendered page showed it. So those bytes
# block, and the regexes run byte-wise (LC_ALL=C) where iconv is missing.
export LC_ALL=C
grep -aq $'\r.' "$DESIGN" && block "design.md: a carriage return not followed by a newline (renderers break the line there) — save it with LF or CRLF line endings"
[ "$(tr -d '\000' < "$DESIGN" | wc -c)" -eq "$(wc -c < "$DESIGN")" ] || block "design.md: contains a NUL byte — remove it"
if command -v iconv >/dev/null 2>&1; then
  iconv -f UTF-8 -t UTF-8 "$DESIGN" >/dev/null 2>&1 || block "design.md: not valid UTF-8 — re-save it as UTF-8"
fi

# --- frontmatter -----------------------------------------------------------
fm=$(awk '{ sub(/\r$/, "") } NR==1 && $0!="---"{exit} NR>1 && $0=="---"{exit} NR>1{print}' "$DESIGN")
if [ -z "$fm" ]; then
  block "design.md: no frontmatter (expected slug, status, stage between --- lines)"
fi
status=$(printf '%s\n' "$fm" | sed -nE 's/^status:[[:space:]]*([A-Za-z]+).*/\1/p' | head -1)
case "$status" in
  draft|locked|shipped) ;;
  *) block "design.md: status '${status:-<missing>}' is not draft|locked|shipped" ;;
esac
if [ "$REQUIRE_LOCKED" -eq 1 ] && [ "$status" != "locked" ]; then
  block "design.md: status is '${status:-<missing>}', not locked — finish it with /harness:shape"
fi

# --- the design dialect ----------------------------------------------------
# The rendered design is what a human reviewed, so the gate must read it the
# way the renderers do (CommonMark 0.31.2, and marked for the map page). A line
# loop cannot model every Markdown construct, and each blocklist round found a
# new one that hid an open decision (XARI-151, XARI-160). So a design may use
# only a dialect the gate reads the same way, and anything outside it blocks:
# - the record: every non-blank line under `## Decisions` is a decision line
#   (or a fence). Discovery and Scope may hold wikilink bullets, links and
#   plain to-dos — only the record is parsed;
# - no raw HTML blocks: a line opening, after any quote or list markers, with
#   `<` then a letter, `/`, `!` or `?` (how every HTML block starts) blocks,
#   autolinks (`<https://…>`, `<a@b.c>`) excepted;
# - headings are top-level plain text: none inside a list or blockquote, and
#   none using inline markup (code, emphasis, links, escapes, raw HTML,
#   entities). Plain text renders as written, so "is this heading 'Decisions'"
#   is a text comparison, and only `## Decisions` at column 0 may say it. A
#   second `## Decisions…` heading blocks too: which is the record is a guess.
# - a setext heading's text is the whole paragraph its underline closes, as the
#   renderers read it — a lazy continuation or list item followed by a less
#   indented `---` is a rule, not a heading.
# Not modelled: Unicode lookalikes ("Dеcisions" with a Cyrillic е) — no text
# rule can see what a reader's eye does.
re_line='^- \[([ x~])\] ([AQWB][0-9]+) · (.+)$'
re_box='^[[:space:]]*(>[[:space:]]*)*([-*+]|[0-9]+[.)])[[:space:]]+\['
re_by='(^|· )decided-by: (you|accepted-default)( |$)'
re_ack='(^|· )ack( ·|$)'
re_defer='(^|· )deferred: [^[:space:]]'
# Fences. CommonMark (0.31.2 §4.5) and marked differ at the edges, and a
# line-based loop cannot track list items — so for fences the gate reads only
# the lines every reader agrees on, and BLOCKS on the rest rather than guess (a
# guess either way let an open decision through, XARI-151):
# - an opener is a run of 3+ backticks or tildes at column 0, then an info
#   string; a backtick info string holds no backtick ("``` `x`" is inline
#   code, not a fence). An opener indented 1–3 spaces is a fence at top level
#   but ends with its list item inside one — ambiguous, so it blocks;
# - a closer is 0–3 spaces, a run of the opener's character at least as long,
#   then only spaces (a CRLF line's \r is stripped first). A near-miss — the run followed by a tab,
#   the other fence character or any other whitespace — is read differently by
#   the two renderers, so it blocks too. A shorter run, the other character's
#   run, a line with an info string, or 4+ spaces of indent is plain content.
re_open='^(`{3,}|~{3,})(.*)$'
re_indented_open='^ {1,3}(`{3,}|~{3,})(.*)$'
re_close='^ {0,3}(`{3,}|~{3,}) *$'
re_near_close='^ {0,3}(`{3,}|~{3,})[`~[:space:]]*$'
re_quote='^ *> ?(.*)$'
re_marker='^( *)([-*+]|[0-9]{1,9}[.)])( +|$)(.*)$'
re_hr='^ *((-[ 	]*){3,}|(\*[ 	]*){3,}|(_[ 	]*){3,})$'
re_underline='^( *)(=+|-+)[ 	]*$'
re_atx='^ {0,3}#{1,6}([ 	](.*))?$'
re_html='^[[:space:]]*<[A-Za-z/!?]'
re_autolink='^[[:space:]]*<([A-Za-z][A-Za-z0-9+.-]{1,31}:[^<>[:space:]]*|[^<>@[:space:]]+@[A-Za-z0-9.-]+)>'
re_entity='&(#[0-9]{1,7}|#[xX][0-9a-fA-F]{1,6}|[A-Za-z][A-Za-z0-9]{1,31});'
re_markup='[][`*_\\<]'
re_dec_word='^[Dd][Ee][Cc][Ii][Ss][Ii][Oo][Nn][Ss]([[:space:]#]|$)'
# containers <line>: strip quote and list markers. Sets q (after quotes only),
# c (after all markers), depth (quote count), mark (1 if a list marker was
# stripped since the last quote), mcol (the column content starts at after it)
# and interrupts (whether that marker may start a list inside a paragraph).
containers() {
  q="$1"; depth=0
  while [[ "$q" =~ $re_quote ]]; do q="${BASH_REMATCH[1]}"; depth=$((depth + 1)); done
  c="$q"; mark=0; mcol=0; interrupts=1
  [[ "$q" =~ $re_hr ]] && return
  while [[ "$c" =~ $re_marker ]]; do
    mcol=$((mcol + ${#BASH_REMATCH[1]} + ${#BASH_REMATCH[2]} + ${#BASH_REMATCH[3]}))
    case "${BASH_REMATCH[2]}" in 1.|1\)|-|\*|+) ;; *) interrupts=0 ;; esac   # only bullets and "1." interrupt
    c="${BASH_REMATCH[4]}"; mark=1
  done
  [[ "$c" =~ ^[[:space:]]*$ ]] && interrupts=0   # an empty item cannot interrupt a paragraph
}
# heading <text> <nested 0|1> <canonical 0|1>: the allowlist for a heading.
heading() {
  local t="$1" p
  [[ "$t" =~ ^[[:space:]]*(.*[^[:space:]])?[[:space:]]*$ ]]; t="${BASH_REMATCH[1]}"
  if [[ "$t" =~ ^(.*)[[:space:]]#+$ ]]; then t="${BASH_REMATCH[1]}"; elif [[ "$t" =~ ^#+$ ]]; then t=""; fi
  if [ "$2" -eq 1 ]; then
    block "design.md:$ln: a heading inside a list or blockquote — design headings sit at the top level"; return
  fi
  p="$t"   # an underscore between letters or digits is never emphasis
  while [[ "$p" =~ ^(.*[[:alnum:]])_+([[:alnum:]].*)$ ]]; do p="${BASH_REMATCH[1]}${BASH_REMATCH[2]}"; done
  if [[ "$p" =~ $re_markup ]] || [[ "$p" =~ $re_entity ]]; then
    block "design.md:$ln: heading uses inline markup (\` * _ \\ [ < or an &entity;) — write headings as plain text"; return
  fi
  [[ "$t" =~ $re_dec_word ]] && [ "$3" -eq 0 ] && \
    block "design.md:$ln: a 'Decisions' heading not written as '## Decisions' at column 0 — the gate reads only that form"
}
fm_end=0
[ -n "$fm" ] && fm_end=$(awk '{ sub(/\r$/, "") } NR>1 && $0=="---"{ print NR; exit }' "$DESIGN")
fm_end="${fm_end:-0}"
decided_w=""
infence=0; fch=""; flen=0; insec=0; seen_sec=0; nsec=0; ln=0
popen=0; ptext=""; pdepth=0; pcol=0; pnest=0   # the open paragraph, for setext
while IFS= read -r line || [ -n "$line" ]; do
  ln=$((ln + 1))
  line="${line%$'\r'}"   # CRLF: one trailing \r (a lone \r mid-line blocked above)
  [ "$ln" -le "$fm_end" ] && continue
  if [ "$infence" -eq 1 ]; then
    if [[ "$line" =~ $re_near_close ]]; then
      run="${BASH_REMATCH[1]}"
      if [ "${run:0:1}" = "$fch" ] && [ "${#run}" -ge "$flen" ]; then
        if [[ "$line" =~ $re_close ]] && [ "${BASH_REMATCH[1]}" = "$run" ]; then infence=0
        else block "design.md:$ln: ambiguous fence closer (renderers disagree whether it closes) — end the line after the ${fch}${fch}${fch} run"; infence=0
        fi
      fi
    fi
    continue
  fi
  if [[ "$line" =~ $re_indented_open ]]; then
    run="${BASH_REMATCH[1]}"; info="${BASH_REMATCH[2]}"
    if ! { [ "${run:0:1}" = '`' ] && [[ "$info" == *'`'* ]]; }; then   # else inline code
      # Block once, then skip to its closer: the design is already blocked, so
      # skipping cannot let anything through, and its closer is not re-flagged.
      block "design.md:$ln: code fence indented under a list or paragraph — the gate cannot tell where it ends; move the code block out of the list, to column 0"
      infence=1; fch="${run:0:1}"; flen="${#run}"; popen=0; continue
    fi
  fi
  if [[ "$line" =~ $re_open ]]; then
    run="${BASH_REMATCH[1]}"; info="${BASH_REMATCH[2]}"
    if ! { [ "${run:0:1}" = '`' ] && [[ "$info" == *'`'* ]]; }; then
      infence=1; fch="${run:0:1}"; flen="${#run}"; popen=0; continue
    fi
  fi
  containers "$line"
  if [[ "$c" =~ $re_html ]] && ! [[ "$c" =~ $re_autolink ]]; then
    block "design.md:$ln: raw HTML block (renderers hide or reshape what follows it) — write it as Markdown or put it in a code fence"
  fi
  if [[ "$q" =~ ^[[:space:]]*$ ]]; then popen=0
  elif [ "$popen" -eq 1 ] && [ "$mark" -eq 0 ] && [ "$depth" -eq "$pdepth" ] \
       && [[ "$q" =~ $re_underline ]] && [ "${#BASH_REMATCH[1]}" -ge "$pcol" ]; then
    heading "$ptext" "$pnest" 0; popen=0
  elif [[ "$q" =~ $re_hr ]]; then popen=0
  elif [[ "$c" =~ $re_atx ]]; then
    nested=0; { [ "$depth" -gt 0 ] || [ "$mark" -eq 1 ]; } && nested=1
    canon=0; [[ "$line" == '## Decisions'* ]] && canon=1
    heading "${BASH_REMATCH[2]}" "$nested" "$canon"; popen=0
  elif [[ "$c" =~ ^[[:space:]]*$ ]]; then popen=0   # an empty list item
  elif [ "$popen" -eq 1 ] && [ "$depth" -le "$pdepth" ] && { [ "$mark" -eq 0 ] || [ "$interrupts" -eq 0 ]; }; then
    ptext="$ptext $c"   # continuation, or a lazy one
  else
    popen=1; ptext="$c"; pdepth="$depth"; pcol=0; pnest=0
    [ "$mark" -eq 1 ] && pcol="$mcol"
    { [ "$depth" -gt 0 ] || [ "$mark" -eq 1 ]; } && pnest=1
  fi
  case "$line" in
    '## '*)
      insec=0
      case "$line" in
        '## Decisions'*)
          nsec=$((nsec + 1))
          [ "$nsec" -eq 2 ] && block "design.md: more than one '## Decisions' heading — ambiguous which section is the record" ;;
      esac
      [[ "$line" =~ ^'## Decisions'[[:space:]]*$ ]] && { insec=1; seen_sec=1; }
      continue ;;
  esac
  [ "$insec" -eq 1 ] || continue
  [[ "$line" =~ ^[[:space:]]*$ ]] && continue
  case "$line" in
    '- ['*) ;;
    *) [[ "$line" =~ $re_box ]] && n=$((n + 1))
       block "malformed decision line (only '- [x|~| ] <A|Q|W|B><n> · …' lines belong under '## Decisions'): $(shown "$line")"
       continue ;;
  esac
  n=$((n + 1))
  if ! [[ "$line" =~ $re_line ]]; then
    block "malformed decision line (want '- [x|~| ] <A|Q|W|B><n> · …'): $(shown "$line")"; continue
  fi
  mark="${BASH_REMATCH[1]}"; id="${BASH_REMATCH[2]}"; rest="${BASH_REMATCH[3]}"
  case "$mark" in
    ' ') block "$id: still open — triage it" ;;
    '~') [[ "$rest" =~ $re_defer ]] || block "$id: deferred without 'deferred: <reason>'" ;;
    x)
      [[ "$rest" =~ $re_by ]] || block "$id: decided but no 'decided-by: you|accepted-default'"
      case "$id" in
        B*) [[ "$rest" =~ $re_ack ]] || block "$id: byproduct not acknowledged ('ack')" ;;
        W*) decided_w="$decided_w $id" ;;
      esac
      ;;
  esac
done < "$DESIGN"
[ "$infence" -eq 1 ] && block "design.md: unclosed code fence — everything after it is hidden from this check"
if [ "$seen_sec" -eq 0 ]; then
  block "design.md: no '## Decisions' section — decision lines are only read from there"
elif [ "$n" -eq 0 ]; then
  block "design.md: no decision lines — stages 3, 4, 6 and 7 never recorded anything, so this design asserts nothing"
fi

# --- plan cross-check ------------------------------------------------------
if [ ! -f "$PLAN" ]; then
  block "plan.md: $PLAN does not exist — stage 5 must write it"
else
  for id in $decided_w; do
    grep -qw -- "$id" "$PLAN" || block "$id: decided what-if never appears in plan.md — it needs a task with a test"
  done
fi
finish
