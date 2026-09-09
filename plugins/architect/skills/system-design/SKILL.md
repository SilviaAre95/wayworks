---
name: system-design
description: "Design system architecture for a feature or service — produces component diagrams, data flow, and tech decisions"
user-invocable: true
argument-hint: "<feature-or-system> [constraints]"
---

# System Design

Design the architecture for: **$ARGUMENTS**

## Steps

1. **Clarify scope** — Identify what's being built, who uses it, and at what scale. If the input is vague, state your assumptions explicitly before proceeding.

2. **Identify components** — Break the system into discrete services, modules, or layers. For each:
   - Name and responsibility (single-purpose)
   - Technology choice with rationale
   - Interfaces (APIs, events, shared state)

3. **Data flow** — Map how data moves through the system:
   - Entry points (user actions, webhooks, cron)
   - Processing steps
   - Storage (database, cache, file system)
   - Output (API responses, notifications, side effects)

4. **Define boundaries** — Identify:
   - What's synchronous vs async
   - What needs strong consistency vs eventual consistency
   - Where failures are tolerated vs critical

5. **Infrastructure** — Recommend:
   - Hosting (Railway, Vercel, GCP, AWS — match the team's stack)
   - Database (Postgres/Prisma preferred unless there's a reason not to)
   - Caching strategy if needed
   - CI/CD pipeline shape

## Output Format

```markdown
## System Design: <name>

### Overview
<2-3 sentence summary>

### Components
| Component | Responsibility | Tech | Interfaces |
|-----------|---------------|------|------------|
| ...       | ...           | ...  | ...        |

### Data Flow
<Numbered steps or ASCII diagram>

### Key Decisions
- <Decision 1>: <choice> because <reason>
- <Decision 2>: <choice> because <reason>

### Risks & Mitigations
- <Risk>: <mitigation>

### Open Questions
- <Things that need team input>
```

## Critique before handing over

Write the design in the format above **first**, then dispatch one `architect:design-reviewer` subagent and **paste the full design text into its prompt** — it has no other way to see it, since nothing has been written to a file. It attacks what you built: attack surface and auth boundaries, what breaks first at 10× load, zero-downtime deploy and rollback, race conditions and partial failure, runaway cost. Fold its Critical items into the design and list its Warnings under Risks. A design nobody argued with is a draft.

## Constraints

- Prefer the team's existing stack over introducing new tech
- Default to Postgres + Prisma unless the use case demands otherwise
- Don't design for hypothetical scale — design for current needs with clear scaling paths
- Flag security concerns explicitly
