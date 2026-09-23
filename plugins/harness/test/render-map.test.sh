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

# --- bad input fails ---------------------------------------------------------
bash "$SCRIPT" >/dev/null 2>&1; [ "$?" = "2" ] && ok "no args is a usage error" || bad "no args should exit 2"
bash "$SCRIPT" "$TMP/nope" "$OUT_DIR" >/dev/null 2>&1; [ "$?" = "1" ] && ok "missing design.md fails" || bad "missing design should exit 1"
E="$TMP/docs/designs/evil"; mkdir -p "$E"
printf -- '---\nslug: ../../escape\nstatus: draft\n---\n## Decisions\n' > "$E/design.md"
bash "$SCRIPT" "$E" "$OUT_DIR" >/dev/null 2>&1; rc=$?
{ [ "$rc" = "1" ] && [ ! -e "$TMP/escape.html" ]; } && ok "path-traversal slug is refused" || bad "unsafe slug accepted (rc=$rc)"
N="$TMP/docs/designs/from-dir"; mkdir -p "$N"
printf -- '---\nstatus: draft\n---\n## Decisions\n' > "$N/design.md"
bash "$SCRIPT" "$N" "$OUT_DIR" >/dev/null 2>&1 && [ -f "$OUT_DIR/from-dir.html" ] \
  && ok "missing slug falls back to directory name" || bad "slug fallback"

exit $fail
