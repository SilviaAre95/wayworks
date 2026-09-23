---
name: triage
description: "Batch-decide review items with the user — proposed decision per item, one reply like 'ok 1-7, 8: …, 9: ?', written to design.md as gate-parseable checklist lines"
user-invocable: false
---

# Triage

Batch-decision protocol shared by `/harness:shape`'s attack, question, what-if and byproduct stages. It turns a numbered list of review items into decision lines `design-check.sh` parses — the gate has no model in the loop, so the grammar below is the whole contract.

## Steps

1. **Present every item with a proposed decision** — ID, severity (or `byproduct`), text, and a proposal. Number them.
2. **Cap a round at 15 items**, ranked by severity. Anything past 15 goes straight to `- [~]` deferred with a one-line reason, and can be pulled back into a later round.
3. **Take one batch reply**, e.g. `ok 1-7, 8: reject and show retry, 9: ?` — not item-by-item.
4. **Discuss every `?` item one at a time**, before writing anything else. An item stays `[ ]` until its `?` resolves or the user drops it.
5. **Write each resolved item to `design.md`'s `## Decisions` section** — never only in chat. If the user abandons triage partway, unaddressed items stay `- [ ]` and the design stays `draft`.

## Output format

Grammar: `- [x|~| ] <A|Q|W|B><n> · <severity|byproduct> · <text> · <decided-by: you|accepted-default | ack · decided-by: … | deferred: <reason> | open>`

ID prefixes: `A` scope attack, `Q` feature question, `W` what-if, `B` byproduct. Separator is ` · ` (middle dot, spaced).

```
- [x] W3 · high · QR scanned offline → queue locally, sync on reconnect, shop sees "pending" · decided-by: you
- [x] B2 · byproduct · local stamp queue (new storage + sync code) · ack · decided-by: accepted-default
- [~] A9 · low · second device for same shop · deferred: single-device shops only in v1
- [ ] Q4 · med · reward expiry? · open
```

- `decided-by: accepted-default` — the proposal was accepted unchanged (e.g. it fell in `1-7`).
- `decided-by: you` — the user changed the outcome, or it was a discussed `?` item.
- `B` items carry `ack` before `decided-by:` — unrequested work needs explicit acknowledgment.

## Constraints

- Never write `decided-by: you` for an item the user did not address — that line is the audit of what was actually considered.
- Never invent a decision for an unanswered item; leave it `- [ ]`.
- Keep IDs stable across a resumed session — a pulled-back deferred item keeps its number.
- One batch reply per round; re-open discussion only for `?` items, never to relitigate accepted ones.
