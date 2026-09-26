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
# way the renderers do (CommonMark 0.31.2, and marked for the map page). Three
# rounds of review showed that a line loop modelling block structure —
# paragraphs, list items, quotes, tabs — never converges: every round found a
# structure it read differently (XARI-151, XARI-160). So the dialect is judged
# one line at a time, with no structure to model, and anything outside it
# blocks. Outside fences:
# - checkboxes live only in the record: outside `## Decisions` any `[ ]`,
#   `[x]`, `[X]` or `[~]` blocks, whatever the list marker, nesting or heading
#   above it, and read as a reader sees it — through escapes, code and
#   emphasis markers — with entities limited to &lt; &gt; &amp; &quot; &#39;.
#   Unicode shapes (☐) and Mermaid node text are not checked. Guessing which headings a reader takes as "the record"
#   (translations, look-alikes, "Decision log", sub-sections) never converged,
#   so an open item may appear only where the gate reads;
# - the record: every non-blank line under `## Decisions` is a decision line,
#   with no raw HTML (not even <br>), &entity;, link, `~` after its marker
#   (marked strikes through single tildes) or code fence, and no second
#   checkbox in its text — each can show a reader
#   something other than what the gate reads;
# - headings are ATX at column 0 and plain text: a `#` run anywhere else on a
#   line (indented, after a list marker) blocks, as does inline markup in a
#   heading (code, emphasis, strikethrough, links, escapes, raw HTML,
#   entities). A second heading whose ASCII letters are exactly "Decision" or
#   "Decisions" blocks — letters alone, so no invisible character splits the
#   word — though with checkboxes confined to the record it can hold nothing
#   open; a second `## Decisions…` blocks, since which is the record
#   would be a guess;
# - no setext headings: a line of only `-`, `=`, `*`, `_` and spaces must not
#   sit directly under text (a blank line, heading or fence closer comes first);
# - no blockquotes, no link reference definitions (`]:` — marked lets their
#   titles span lines), and no raw HTML anywhere: `<` then a letter, `/`, `!`
#   or `?` blocks, code spans included, except an autolink and a mid-line <br>
#   (a line that opens with <br> starts an HTML block that swallows what
#   follows). The map page keeps tags like <h2>, <ul> and <input>, so inline
#   HTML can draw a record. `]:` blocks outside a [[wikilink]];
# - no tab, vertical tab, form feed, non-ASCII space or common invisible
#   format character: renderers treat them as indentation or heading
#   separators. (Headings do not rely on this list — see above.)
# - frontmatter holds only the keys /harness:shape writes (slug, status, stage,
#   discovery, discovery-status) and `- value` list items whose value is one
#   path or [[wikilink]]: a plain CommonMark renderer shows it as body text.
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
re_items='^ *(([-*+]|[0-9]{1,9}[.)])( +|$))*'   # leading list markers, stripped to find content
re_atx='^#{1,6}( (.*))?$'
re_rule='^[-=*_ ]*[-=*_][-=*_ ]*$'
re_fm_key='^(slug|status|stage|discovery|discovery-status):( .*)?$'
# One path or [[wikilink]]; quoted, anything but the quote (a leading quote
# cannot open a block, and rawhtml still runs on the line).
fm_val='(\[\[[^][]*\]\]|[A-Za-z0-9._/~-]+)'
re_fm_item="^ *- ($fm_val|\"[^\"]+\"|'[^']+') *\$"
# An autolink starts with a letter or digit: `<!`, `<?` and `</` always open HTML.
re_autolink='^<([A-Za-z][A-Za-z0-9+.-]{1,31}:[^<>[:space:]]*|[A-Za-z0-9][^<>@[:space:]]*@[A-Za-z0-9.-]+)>'
re_br='^<[Bb][Rr] */?>'
re_entity='&(#[0-9]{1,7}|#[xX][0-9a-fA-F]{1,6}|[A-Za-z][A-Za-z0-9]{1,31});'
re_markup='[][`*_~\\<]'
re_dec_word='^[Dd][Ee][Cc][Ii][Ss][Ii][Oo][Nn][Ss]?$'   # the whole heading, letters only
re_check='\[( +| *[xX~] *)\]'   # a checkbox, or text that reads as one
re_ok_entity='^&(lt|gt|amp|quot|#39);'   # the only entities outside the record
# checktext <line>: sets k, the line as a reader sees its brackets — [[wikilinks]]
# removed (they show double brackets), and the escapes, code and emphasis
# markers that can spell "[ ]" without those bytes dropped.
checktext() {
  k="$1"
  while [[ "$k" =~ ^(.*)\[\[[^][]*\]\](.*)$ ]]; do k="${BASH_REMATCH[1]}${BASH_REMATCH[2]}"; done
  k="${k//\\/}"; k="${k//\`/}"; k="${k//\*/}"; k="${k//_/}"
}
# oddentity <text>: true if the text holds an entity other than &lt; &gt; &amp; &quot; &#39;.
oddentity() {
  local s="$1"
  while [[ "$s" == *'&'* ]]; do
    s="${s#*&}"
    [[ "&$s" =~ ^$re_entity ]] || continue
    [[ "&$s" =~ $re_ok_entity ]] || return 0
  done
  return 1
}
# Whitespace a renderer reads as indentation or a heading separator: tab, VT,
# FF, and the non-ASCII spaces JavaScript's \s matches; and invisible format
# characters — soft hyphen U+00AD, U+034F, U+180E, U+200B–U+200F,
# U+202A–U+202E, U+2060–U+2064 — as UTF-8 bytes.
odd_spaces=($'\t' $'\v' $'\f' $'\xc2\x85' $'\xc2\xa0' $'\xe1\x9a\x80' $'\xe2\x80\xa8' $'\xe2\x80\xa9' \
  $'\xe2\x80\xaf' $'\xe2\x81\x9f' $'\xe3\x80\x80' $'\xef\xbb\xbf' $'\xc2\xad' $'\xcd\x8f' $'\xe1\xa0\x8e')
for i in 0 1 2 3 4 5 6 7 8 9 a b c d e f; do odd_spaces+=($'\xe2\x80'"$(printf "\\x8$i")"); done   # U+2000–U+200F
for i in a b c d e; do odd_spaces+=($'\xe2\x80'"$(printf "\\xa$i")"); done   # U+202A–U+202E
for i in 0 1 2 3 4 6 7 8 9; do odd_spaces+=($'\xe2\x81'"$(printf "\\xa$i")"); done   # U+2060–U+2064, U+2066–U+2069
odd_spaces+=($'\xd8\x9c')   # U+061C: with U+200E/F, U+202A–E and U+2066–9, every bidi control
oddspace() { local b; for b in "${odd_spaces[@]}"; do [[ "$1" == *"$b"* ]] && return 0; done; return 1; }
# rawhtml <text> <allow-br 0|1>: true if the text holds raw HTML.
rawhtml() {
  local s="$1"
  while [[ "$s" == *'<'* ]]; do
    s="${s#*<}"
    [[ "$s" =~ ^[A-Za-z/!?] ]] || continue
    [[ "<$s" =~ $re_autolink ]] && continue
    [ "$2" -eq 1 ] && [[ "<$s" =~ $re_br ]] && continue
    return 0
  done
  return 1
}
# heading <text> <canonical 0|1>: the allowlist for a column-0 ATX heading.
heading() {
  local t="$1" p
  [[ "$t" =~ ^[[:space:]]*(.*[^[:space:]])?[[:space:]]*$ ]]; t="${BASH_REMATCH[1]}"
  if [[ "$t" =~ ^(.*)[[:space:]]#+$ ]]; then t="${BASH_REMATCH[1]}"; elif [[ "$t" =~ ^#+$ ]]; then t=""; fi
  p="$t"   # an underscore between letters or digits is never emphasis
  while [[ "$p" =~ ^(.*[[:alnum:]])_+([[:alnum:]].*)$ ]]; do p="${BASH_REMATCH[1]}${BASH_REMATCH[2]}"; done
  if [[ "$p" =~ $re_markup ]] || [[ "$p" =~ $re_entity ]]; then
    block "design.md:$ln: heading uses inline markup (\` * _ ~ \\ [ < or an &entity;) — write headings as plain text"; return
  fi
  # Letters only: any invisible or non-ASCII byte inside "Decisions" would
  # otherwise dodge the test while the heading still reads "Decisions".
  [ "$2" -eq 1 ] && return
  [[ "${t//[^A-Za-z]/}" =~ $re_dec_word ]] && \
    block "design.md:$ln: a heading that reads as the Decisions record but is not '## Decisions' at column 0 — the gate reads only that form; reword it"
}
fm_end=0
[ -n "$fm" ] && fm_end=$(awk '{ sub(/\r$/, "") } NR>1 && $0=="---"{ print NR; exit }' "$DESIGN")
fm_end="${fm_end:-0}"
decided_w=""
infence=0; fch=""; flen=0; insec=0; seen_sec=0; nsec=0; ln=0
prev=""   # the previous line, when it is text a rule-like line would turn into a heading
while IFS= read -r line || [ -n "$line" ]; do
  ln=$((ln + 1))
  line="${line%$'\r'}"   # CRLF: one trailing \r (a lone \r mid-line blocked above)
  if [ "$ln" -le "$fm_end" ]; then
    if [ "$ln" -gt 1 ] && [ "$ln" -lt "$fm_end" ]; then
      { [[ "$line" =~ $re_fm_key ]] || [[ "$line" =~ $re_fm_item ]] || [ -z "$line" ]; } \
        || block "design.md:$ln: frontmatter holds only slug, status, stage, discovery and discovery-status — a plain renderer shows it as body text: $(shown "$line")"
      rawhtml "$line" 0 && block "design.md:$ln: raw HTML in frontmatter"
      checktext "$line"; [[ "$k" =~ $re_check ]] && block "design.md:$ln: a checkbox in frontmatter — open items live only in the record"
      oddentity "$line" && block "design.md:$ln: an entity in frontmatter — only &lt; &gt; &amp; &quot; &#39; are allowed"
      oddspace "$line" && block "design.md:$ln: a tab, non-ASCII space or invisible character in frontmatter — use plain spaces"
    fi
    continue
  fi
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
      infence=1; fch="${run:0:1}"; flen="${#run}"; prev=""; continue
    fi
  fi
  if [[ "$line" =~ $re_open ]]; then
    run="${BASH_REMATCH[1]}"; info="${BASH_REMATCH[2]}"
    if ! { [ "${run:0:1}" = '`' ] && [[ "$info" == *'`'* ]]; }; then
      [ "$insec" -eq 1 ] && block "design.md:$ln: a code fence in the record — '## Decisions' holds only decision lines"
      infence=1; fch="${run:0:1}"; flen="${#run}"; prev=""; continue
    fi
  fi
  oddspace "$line" && block "design.md:$ln: a tab, non-ASCII space or invisible character (renderers read it as indentation or a heading separator, or hide it) — use plain spaces"
  rawhtml "$line" 1 && block "design.md:$ln: raw HTML (renderers hide or reshape it) — write &lt; for a literal '<'; code goes in a fence at column 0"
  nowiki="$line"   # a [[wikilink]] holds no link label, so its "]]:" is not one
  while [[ "$nowiki" =~ ^(.*)\[\[[^][]*\]\](.*)$ ]]; do nowiki="${BASH_REMATCH[1]}${BASH_REMATCH[2]}"; done
  [[ "$nowiki" == *']:'* ]] && block "design.md:$ln: ']:' starts a link reference definition — write links inline, [text](url)"
  [[ "$line" =~ $re_items ]]; c="${line:${#BASH_REMATCH[0]}}"   # the line's content after list markers
  [[ "$c" =~ $re_br ]] && block "design.md:$ln: a line opening with <br> starts an HTML block that hides what follows — put <br> mid-line or drop it"
  [ "${c:0:1}" = '>' ] && block "design.md:$ln: a blockquote — outside the design dialect; quote as plain text or in a fence"
  if [ "$insec" -eq 0 ]; then
    checktext "$line"
    [[ "$k" =~ $re_check ]] && block "design.md:$ln: a checkbox outside '## Decisions' — open items live only in the record; write a plain bullet or move it there"
    oddentity "$line" && block "design.md:$ln: an entity other than &lt; &gt; &amp; &quot; &#39; — it can spell text the gate does not see; write the character"
  fi
  if [[ "$line" =~ $re_atx ]]; then
    htext="${BASH_REMATCH[2]-}"; canon=0
    [[ "$line" =~ ^'## Decisions'[[:space:]]*$ ]] && canon=1
    heading "$htext" "$canon"; prev=""
  elif [[ "$c" =~ $re_atx ]]; then
    block "design.md:$ln: a heading inside a list or indented — design headings sit at column 0; code goes in a fence at column 0"; prev=""
  elif [[ "$line" =~ $re_rule ]]; then
    [ -n "$prev" ] && block "design.md:$ln: a line of - = * or _ right under text makes that text a heading — add a blank line above it"
    prev=""
  elif [[ "$line" =~ ^[[:space:]]*$ ]]; then prev=""
  else prev="$line"
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
  checktext "${line:5}"
  { rawhtml "$line" 0 || [[ "$line" =~ $re_entity ]] || [[ "$line" == *']('* ]] || [[ "${line:5}" == *'~'* ]] \
    || [[ "$k" =~ $re_check ]]; } && \
    block "design.md:$ln: a decision line holds raw HTML, an &entity;, a link, strikethrough or a second checkbox — the renderers would show text other than what the gate reads"
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
