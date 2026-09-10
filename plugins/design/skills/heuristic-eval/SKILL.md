---
name: heuristic-eval
description: "Evaluate a UI against Nielsen's 10 usability heuristics with severity ratings and fix recommendations"
user-invocable: true
argument-hint: "<page-or-flow> [heuristics: all|visibility|feedback|consistency|errors]"
---

# Heuristic Evaluation

Evaluate: **$ARGUMENTS** (heuristics focus defaults to all)

## The heuristics

Walk `references/nielsen-heuristics.md` — Nielsen's ten, from visibility of system status through help and documentation — against the target, noting where each is violated and on which screen or flow.

## Output Format

```markdown
## Heuristic Evaluation: <target>

### Summary
| Heuristic | Score (0-4) | Critical Issues |
|-----------|-------------|-----------------|
| 1. Visibility of System Status | 3 | loading states missing on 2 pages |
| 2. Match Real World | 4 | — |
| ... | ... | ... |

**Overall Score**: X/40

### Critical Issues (severity 3-4)
1. **H5 Error Prevention**: <file:line> — <issue + fix>

### Moderate Issues (severity 2)
1. **H3 User Control**: <issue + recommendation>

### Minor Issues (severity 0-1)
1. **H8 Minimalist Design**: <cosmetic suggestion>
```

**Severity scale**: 0 = not a problem, 1 = cosmetic, 2 = minor, 3 = major, 4 = catastrophic

## Constraints

- Evaluate based on the code/UI, not screenshots
- Provide actionable fixes, not just problem descriptions
- Be honest about severity — not everything is critical
- Consider the user context (admin tool vs consumer app have different standards)
