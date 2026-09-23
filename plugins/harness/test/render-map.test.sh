#!/usr/bin/env bash
# Tests for render-map.sh. The page renders design.md itself, so what must be
# proven is (a) nothing in the design is dropped — every section is a tab, every
# Mermaid block and decision line is present — and (b) nothing in the design can
# execute: the embedded data cannot close its <script> element, and the page
# sanitizes before it touches the DOM. The browser-side half of (b) is checked by
# hand in Task 10; this file asserts the parts a shell can see.
set -uo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
SCRIPT=$ROOT/scripts/render-map.sh
TEMPLATE=$ROOT/templates/map.html
fail=0
ok()  { echo "ok   - $*"; }
bad() { echo "FAIL - $*"; fail=1; }
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT

D="$TMP/docs/designs/offline-stamp"; mkdir -p "$D"
cat > "$D/design.md" <<'EOF'
---
slug: offline-stamp
status: draft
stage: map
discovery: [docs/discovery/offline-qr.md]
---
# Offline stamp

## Discovery
Frozen: shops lose signal behind the counter.

## Scope
| In | Out |
|---|---|
| stamp offline | multi-device |

<script>console.log("xss-script")</script>
<img src=x onerror="console.log('xss-img')">
</script><script>console.log("xss-breakout")</script>

## Flow & what-ifs
```mermaid
flowchart LR
  scan[QR scanned offline] --> queue[(local queue)]
```

## Components
```mermaid
flowchart TB
  app --> syncworker
```

```text
## not a tab
```

## Scope board
| Item | State |
|---|---|
| queue | in |

## Decisions
- [x] W3 · high · QR scanned offline → queue locally, sync on reconnect · decided-by: you
- [~] A9 · low · second device for same shop · deferred: single-device shops only in v1
- [ ] Q4 · med · reward expiry? · open
EOF

OUT_DIR="$TMP/out"
out=$(bash "$SCRIPT" "$D" "$OUT_DIR" 2>&1); rc=$?
html="$OUT_DIR/offline-stamp.html"
{ [ "$rc" = "0" ] && [ -f "$html" ] && [ "$out" = "$html" ]; } \
  && ok "renders to <out>/<slug>.html and prints the path" || bad "render (rc=$rc: $out)"

for t in "Discovery" "Scope" "Flow & what-ifs" "Components" "Scope board" "Decisions"; do
  grep -qF "\"title\":\"$t\"" "$html" && ok "section '$t' is a tab" || bad "section '$t' missing"
done
[ "$(grep -o '```mermaid' "$html" | wc -l | tr -d ' ')" = "2" ] \
  && ok "both mermaid blocks embedded" || bad "mermaid block count"
grep -qF 'scan[QR scanned offline] --> queue[(local queue)]' "$html" && grep -qF 'app --> syncworker' "$html" \
  && ok "mermaid bodies embedded verbatim" || bad "mermaid bodies"
for l in '- [x] W3 · high · QR scanned offline → queue locally, sync on reconnect · decided-by: you' \
         '- [~] A9 · low · second device for same shop · deferred: single-device shops only in v1' \
         '- [ ] Q4 · med · reward expiry? · open'; do
  grep -qF -- "$l" "$html" && ok "decision line kept: ${l:0:14}" || bad "decision line lost: $l"
done

# --- nothing from the design can execute or break out ------------------------
grep -qF '<script>console.log' "$html" && bad "raw <script> from design survived" || ok "raw <script> from design is escaped"
grep -qF '<img src=x' "$html" && bad "raw <img onerror> survived" || ok "raw <img onerror> is escaped"
[ "$(grep -o '</script>' "$html" | wc -l)" = "$(grep -o '</script>' "$TEMPLATE" | wc -l)" ] \
  && ok "no extra </script> — data cannot close its element" || bad "design injected a </script>"
grep -q 'DOMPurify.sanitize(marked.parse' "$TEMPLATE" && ok "markdown is sanitized before the DOM" || bad "template must sanitize marked output"
grep -q "securityLevel: 'strict'" "$TEMPLATE" && ok "mermaid runs in strict mode" || bad "mermaid securityLevel must be strict"
urls=$(grep -oE 'https://cdn\.jsdelivr\.net/npm/[^"]+' "$TEMPLATE")
[ "$(printf '%s\n' "$urls" | grep -c .)" = "3" ] && ok "three CDN libraries" || bad "expected 3 CDN urls: $urls"
printf '%s\n' "$urls" | grep -vqE '@[0-9]+\.[0-9]+\.[0-9]+/' && bad "unpinned CDN url: $urls" || ok "every CDN url pins x.y.z"
# Pinning a version does not pin the bytes a CDN serves; SRI does. A script
# tag without integrity runs whatever jsdelivr returns, with the design in scope.
tags=$(grep -E '<script src="https://' "$TEMPLATE")
[ "$(printf '%s\n' "$tags" | grep -cE 'integrity="sha384-[A-Za-z0-9+/=]{64}" crossorigin="anonymous"')" = "3" ] \
  && ok "every CDN script carries a sha384 integrity + crossorigin" || bad "CDN scripts need SRI: $tags"

# --- a '## ' line inside a code fence is content, not a tab ------------------
grep -qF '"title":"not a tab"' "$html" && bad "a fenced '## ' line became a tab" || ok "a fenced '## ' line is not a tab boundary"
data_json=$(awk '/<script id="design-data"/{f=1;next} f&&/<\/script>/{exit} f' "$html")
printf '%s' "$data_json" | jq -e '.[] | select(.title=="Components") | .md | contains("## not a tab")' >/dev/null 2>&1 \
  && ok "fenced content stays in its section" || bad "fenced '## ' content left the Components section"

# --- bad input fails ---------------------------------------------------------
bash "$SCRIPT" >/dev/null 2>&1; [ "$?" = "2" ] && ok "no args is a usage error" || bad "no args should exit 2"
bash "$SCRIPT" "$TMP/nope" "$OUT_DIR" >/dev/null 2>&1; [ "$?" = "1" ] && ok "missing design.md fails" || bad "missing design should exit 1"
E="$TMP/docs/designs/evil"; mkdir -p "$E"
printf -- '---\nslug: ../../escape\nstatus: draft\n---\n## Decisions\n' > "$E/design.md"
bash "$SCRIPT" "$E" "$OUT_DIR" >/dev/null 2>&1; rc=$?
{ [ "$rc" = "1" ] && [ ! -e "$TMP/escape.html" ]; } && ok "path-traversal slug is refused" || bad "unsafe slug accepted (rc=$rc)"
# --- never write through a symlink -------------------------------------------
# .wayworks/maps is a predictable path; a pre-planted symlink there would turn a
# render into an overwrite of whatever file it points at.
L="$TMP/linkout"; mkdir -p "$L"; echo "original" > "$TMP/victim.txt"
ln -s "$TMP/victim.txt" "$L/offline-stamp.html"
bash "$SCRIPT" "$D" "$L" >/dev/null 2>&1; rc=$?
{ [ "$rc" = "1" ] && [ "$(cat "$TMP/victim.txt")" = "original" ]; } \
  && ok "an output path that is a symlink is refused, target untouched" || bad "wrote through a symlink (rc=$rc)"

# --- --open ------------------------------------------------------------------
# Stubs stand in for the viewer so no test ever launches one.
STUB="$TMP/stub"; mkdir -p "$STUB"
for v in open xdg-open; do printf '#!/bin/sh\necho "$1" > "%s/opened"\n' "$TMP" > "$STUB/$v"; chmod +x "$STUB/$v"; done
out=$(PATH="$STUB:$PATH" bash "$SCRIPT" --open "$D" "$OUT_DIR" 2>&1); rc=$?
{ [ "$rc" = "0" ] && [ "$out" = "$html" ] && [ "$(cat "$TMP/opened" 2>/dev/null)" = "$html" ]; } \
  && ok "--open prints the path and opens it" || bad "--open (rc=$rc: $out)"
PATH="$STUB:$PATH" bash "$SCRIPT" --open "$TMP/nope" "$OUT_DIR" >/dev/null 2>&1; [ "$?" = "1" ] \
  && ok "--open with a missing design fails" || bad "--open missing design should exit 1"
PATH="$STUB:$PATH" bash "$SCRIPT" --bogus "$D" "$OUT_DIR" >/dev/null 2>&1; [ "$?" = "2" ] \
  && ok "an unknown flag is a usage error" || bad "unknown flag should exit 2"

N="$TMP/docs/designs/from-dir"; mkdir -p "$N"
printf -- '---\nstatus: draft\n---\n## Decisions\n' > "$N/design.md"
bash "$SCRIPT" "$N" "$OUT_DIR" >/dev/null 2>&1 && [ -f "$OUT_DIR/from-dir.html" ] \
  && ok "missing slug falls back to directory name" || bad "slug fallback"

exit $fail
