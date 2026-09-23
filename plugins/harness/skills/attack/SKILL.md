---
name: attack
description: "Adversarial review of a written design artifact — scope (ambiguity, missing actors, feature-bank conflicts, cheapest cut) or plan (connectivity, races, auth expiry, partial failure, data limits, abuse); scaled panel, top 15 to triage"
user-invocable: true
argument-hint: "--target scope|plan <design-dir>"
---

# Attack

Adversarial review of a design artifact's scope or plan, run by `/harness:shape` to pressure-test it before it locks. Findings are pressure, not patches — attackers report, `harness:triage` decides.

## Steps

1. **Parse `$ARGUMENTS`.** Expect `--target scope|plan <design-dir>`. `--target scope` reads `<design-dir>/design.md`; `--target plan` reads `<design-dir>/plan.md`. Both also read `docs/features/` when it exists, so a finding can cite an existing feature's acceptance criteria or non_goals instead of restating them.

2. **Pick the lenses** and read `references/lenses.md` for what each one looks for before attacking:
   - `--target scope` lenses (on `design.md`): ambiguity, missing actors, feature-bank conflicts, cheapest cut.
   - `--target plan` lenses (on `plan.md`): connectivity, concurrency/races, auth/session expiry, partial failure, data limits, abuse.

3. **Scale the panel.**
   - Small scope — one user flow, no new data store or actor — one attacker covers every lens.
   - Larger scope — one attacker per lens, in parallel, as fresh subagents that did not write the artifact.
   - Attackers never edit the artifact they attack — findings only, handed back as text.

4. **Merge.** Dedupe overlapping findings across attackers, then rank by severity, and cap the ranked list at the top 15; the rest land as `[~]` deferred with a one-line reason and can be pulled back into a later round.

5. **Number and hand off.** Prefix findings `A` for scope, `W` for plan, continuing numbering from the highest existing ID in `design.md`. Give each finding a severity (`high|med|low`) and a proposed decision, then hand the ranked list to `harness:triage`.

## Output Format

Numbered list, one line per finding — the shape `harness:triage` expects (ID, severity, text, proposal). One target per run, so every ID shares its prefix; this `--target scope` example continues from an existing `A11`:

```
1. A12 · high · reward tier is never named — which tier stamps? · propose: default to the shop's base tier
2. A13 · med · shop staff stamp cards but are not an actor · propose: add staff, stamp-only
...
15. A26 · low · second device for same shop · propose: out of scope, single-device v1
```

Overflow, shown for the record, not counted into the 15:

```
[~] A27 · low · loyalty for chains of shops · deferred: single-shop owners only in v1
```

## Constraints

- Never patch the artifact — attack only reports; `harness:triage` owns the decision.
- One finding per line; don't bundle two lenses' issues into one item.
- Say so when a lens has nothing to check (no actors discovered yet, no feature bank present) rather than skipping it silently.
- A lens with nothing wrong stays silent — don't invent filler findings to reach 15.
