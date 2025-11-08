# Rails Seniority Coach — Mastery Rubric

## Depth Levels Defined

The curriculum uses **four depth targets** to guide learning outcomes. Each topic specifies its target; use this rubric to self-assess.

---

## 1. Exposure

**Can define the term; knows when it might apply.**

### Knowledge
- Recall the concept name and basic definition
- Identify contexts where it's relevant
- Name 1-2 use cases

### Skills
- Recognize the pattern in existing code
- Follow a tutorial to implement a simple example
- Ask informed questions when encountering it

### Example Self-Test
> "I can explain what a CTE is in one sentence and name one scenario where I'd consider using it instead of a JOIN."

### Typical for:
- Advanced/niche topics outside daily work
- Patterns you'll encounter but not own
- Foundations for future deep dives

---

## 2. Working

**Can implement with notes; can debug common issues.**

### Knowledge
- Explain how it works with a diagram or example
- List 3-5 common use cases
- Identify 2-3 pitfalls and how to avoid them

### Skills
- Implement from scratch using documentation
- Debug typical errors (e.g., N+1, missing index, wrong scope)
- Refactor existing code to apply the pattern
- Write basic tests

### Example Self-Test
> "I can add eager loading to fix an N+1 query, verify it with logs, and write a test that catches future regressions."

### Typical for:
- Observability tools (metrics, APM)
- Secondary frontend stack (React when you're a Hotwire shop)
- Supporting patterns (e.g., feature flags, basic auth)

---

## 3. Strong

**Can design, debug in production, and teach others.**

### Knowledge
- Explain the concept **without notes** to a peer
- Compare 2-3 alternative approaches and their trade-offs
- Cite official docs or canonical sources
- Anticipate edge cases and failure modes

### Skills
- Design a solution from requirements
- Debug production issues using logs, metrics, traces
- Optimize performance (e.g., index tuning, cache invalidation)
- Review PRs and suggest improvements
- Mentor juniors through implementation

### Example Self-Test
> "I can design a caching strategy for a high-traffic API endpoint, handle cache invalidation on updates, and debug stale-cache issues in production using logs and metrics."

### Typical for:
- **Core Rails** (request lifecycle, Active Record, routing)
- **SQL/Postgres** (queries, indexes, migrations)
- **API design** (REST, pagination, errors, auth)
- **Background jobs** (Sidekiq, idempotency, retries)
- **Performance** (N+1, caching, memory)

---

## 4. Expert

**Can choose trade-offs, optimize, and extend patterns safely.**

### Knowledge
- Explain nuances that aren't in the official docs
- Predict performance/scaling implications
- Design solutions for edge cases (high concurrency, data volume)
- Contribute to or extend the framework/library

### Skills
- Architect systems balancing correctness, performance, maintainability
- Tune low-level parameters (e.g., Postgres configs, GC settings)
- Write custom middleware, plugins, or database extensions
- Lead architecture reviews and set team standards
- Teach at conferences or write authoritative blog posts

### Example Self-Test
> "I can design a zero-downtime migration for a 100M-row table with custom backfill logic, tune Postgres autovacuum settings, and write a detailed ADR explaining the approach."

### Typical for:
- Specialized deep dives (not required for seniority)
- Niche domains (e.g., low-latency systems, distributed transactions)
- **Not a curriculum goal** — self-directed after mastering Strong

---

## Track-Level Depth Targets

Each track has an overall depth goal:

| Track | Depth Target | Rationale |
|-------|--------------|-----------|
| **Rails Internals** | Strong | Core of daily work; needed for debugging production Rails apps |
| **SQL/Postgres** | Strong | Database is the bottleneck; must design schemas and tune queries |
| **Background Jobs** | Strong | Async processing is critical; idempotency/retries prevent bugs |
| **Caching/Performance** | Strong | Production apps need fast responses; caching/N+1 are daily concerns |
| **Observability** | Working→Strong | Must use tools (logs, metrics, traces) but not necessarily tune them |
| **API/Security** | Strong | APIs are the interface; security bugs are high-impact |
| **Frontend (Hotwire)** | Strong | Primary frontend stack; must design and optimize |
| **Frontend (React)** | Working | Secondary stack; enough to integrate and review PRs |
| **Architecture/Design** | Strong | Seniors design systems and mentor; need strong patterns |

---

## Self-Assessment Questions

Use these to gauge your current level for any topic:

### Exposure → Working
- Can I implement this **without** a step-by-step tutorial?
- Can I debug a common error message?
- Can I explain it to a junior in 2 minutes?

### Working → Strong
- Can I design a solution from scratch **without** docs?
- Can I debug this in production using logs/metrics?
- Can I review a PR and suggest 2-3 improvements?
- Can I mentor someone through their first implementation?

### Strong → Expert
- Can I write a detailed blog post or give a conference talk?
- Can I optimize for edge cases (scale, concurrency, correctness)?
- Can I extend the framework or contribute a patch?

---

## Progression Pathways

### Typical Mid-Level Starting Point
- **Rails Internals:** Working (can add features, needs docs for debugging)
- **SQL/Postgres:** Working (writes queries, no index tuning)
- **Jobs/Caching:** Exposure–Working (uses basics, no optimization)
- **Observability:** Exposure (reads logs, doesn't design dashboards)
- **API/Security:** Working (implements endpoints, basic auth)
- **Frontend:** Working (one stack, mostly following patterns)
- **Architecture:** Exposure (reads code, doesn't design systems)

### Senior Target (After This Curriculum)
- **Rails Internals:** Strong
- **SQL/Postgres:** Strong
- **Jobs/Caching:** Strong
- **Observability:** Working→Strong
- **API/Security:** Strong
- **Frontend (primary):** Strong
- **Frontend (secondary):** Working
- **Architecture:** Strong

### Estimated Timeline
- **12-week standard:** 3 topics/week, 3-4 hours/week
- **6-week fast track:** 5 topics/week, 6-8 hours/week
- **10-week weekends:** 2 topics/week, 4-5 hours/weekend

---

## Verification Methods

### Exposure
- ✅ Pass the checkpoint quiz (60%+ correct)
- ✅ Define the concept in writing (2-3 sentences)

### Working
- ✅ Complete the exercise with all acceptance criteria
- ✅ Pass the checkpoint quiz (70%+ correct)
- ✅ Debug a provided broken example

### Strong
- ✅ Complete the exercise + stretch goal
- ✅ Pass the checkpoint quiz (80%+ correct)
- ✅ Review a PR and suggest 3 improvements
- ✅ Explain the concept to a peer and answer 2 follow-up questions

### Expert
- ✅ Design a solution for a novel scenario (not in the curriculum)
- ✅ Write a 500-word blog post or 10-minute talk outline
- ✅ Contribute a patch or extension to an open-source project

---

## When to Move On

**Don't aim for perfection.** Move to the next topic when you can:
1. **Explain** the concept without notes (2 minutes, to yourself or a peer)
2. **Implement** the core pattern from memory
3. **Debug** a common error using the debugging checklist
4. **Pass** the checkpoint quiz at your target depth level

**Return later** if you encounter gaps in real work. Spaced repetition beats cramming.

---

## Red Flags (You're Not Ready)

- ❌ Can't explain the concept without reading the overview
- ❌ Can't complete the exercise without copy-pasting from notes
- ❌ Checkpoint quiz score < 60%
- ❌ Don't understand the "why" behind trade-offs

**Action:** Re-read the overview, try the exercise again, review references.

---

## Green Flags (You're Ready)

- ✅ Can explain the concept and one trade-off from memory
- ✅ Completed the exercise without referring to the overview
- ✅ Checkpoint quiz score ≥ 70% (Working) or ≥ 80% (Strong)
- ✅ Can debug a realistic error using the checklist

**Action:** Move to the next topic. Add this one to your spaced-repetition schedule (review in 1 week, 1 month).

---

## Depth Target Recommendations by Role

| Role | Rails | SQL | Jobs | Cache | Obs | API | FE-1 | FE-2 | Arch |
|------|-------|-----|------|-------|-----|-----|------|------|------|
| **Mid-Level** | Work | Work | Exp | Exp | Exp | Work | Work | Exp | Exp |
| **Senior (IC)** | Strong | Strong | Strong | Strong | Work | Strong | Strong | Work | Strong |
| **Senior (Lead)** | Strong | Strong | Strong | Strong | Strong | Strong | Strong | Work | Strong |
| **Staff** | Expert | Expert | Strong | Strong | Strong | Expert | Strong | Work | Expert |

Use these as a guideline, not a rule. Adjust based on your team's stack and your career goals.

---

## Final Note

**Strong is the target.** Expert is earned through years of production experience and deep specialization. This curriculum gets you to **Strong** across all core areas — enough to:

- Design and ship production features independently
- Debug production issues without senior help
- Review PRs and mentor juniors
- Lead architecture discussions
- Interview successfully for senior IC roles

**Expert comes later**, through focused practice, teaching, and contribution.
