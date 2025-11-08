# ADRs & Lightweight Documentation

## What It Is

Architecture Decision Records (ADRs) document significant technical decisions: why you chose Sidekiq over Resque, Postgres over MySQL, or microservices over a monolith. ADRs live in `docs/adr/` as numbered markdown files. The MADR (Markdown Any Decision Records) format provides a lightweight template. Each ADR captures context, options considered, decision, and consequences.

## Why It Matters

Six months later, nobody remembers why the team chose Elasticsearch over Postgres full-text search. New engineers reverse decisions that were carefully evaluated, reintroducing old problems. ADRs preserve the "why" behind choices, prevent relitigating settled questions, and onboard new team members by explaining trade-offs at decision time.

## When to Use

- Database or framework choices (Postgres vs MySQL, Rails vs Sinatra)
- Architecture patterns (monolith vs microservices, REST vs GraphQL)
- Major library additions (background job system, feature flag library)
- Infrastructure changes (Heroku to AWS, Docker to Kubernetes)
- Reversing a previous decision (migrating away from a pattern)

## Three Common Pitfalls

1. **Writing ADRs after the fact:** ADRs written post-decision miss the context and alternatives considered. Write the ADR when making the decision, not months later when details are forgotten.

2. **Making ADRs too heavyweight:** Requiring 10-page documents discourages writing them. Use a lightweight template (MADR) that takes 15 minutes. Focus on context, options, and trade-offs, not exhaustive research.

3. **Not updating superseded ADRs:** When reversing a decision, mark the old ADR as superseded and link to the new one. Don't delete old ADRs; they explain historical context and why earlier approaches failed.

---

## ADR File Structure

ADRs live in `docs/adr/` numbered sequentially.

```
docs/
  adr/
    0001-use-postgres-for-primary-database.md
    0002-use-sidekiq-for-background-jobs.md
    0003-switch-to-graphql-api.md
    0004-supersede-rest-api-with-graphql.md

```

Sequential numbering prevents merge conflicts. Files are immutable once committed; new decisions supersede old ones.

## MADR Template

MADR provides a consistent structure for ADRs.

```markdown
# ADR-0001: Use Postgres for Primary Database

## Status
Accepted

## Context
We need a relational database for storing users, orders, and products.
Requirements: ACID transactions, JSON support, robust full-text search,
strong Rails ecosystem support.

## Decision
Use Postgres 14 as the primary database.

## Alternatives Considered
- MySQL: Lacks JSON operators and full-text search quality
- MongoDB: No ACID transactions, harder to enforce schema
- SQLite: Not suitable for production multi-user workloads

## Consequences
### Positive
- Strong JSON support via jsonb columns
- Built-in full-text search without external dependencies
- Excellent Rails integration via pg gem and ActiveRecord
- Wide operational tooling (pgAdmin, Heroku Postgres)

### Negative
- Slightly higher memory usage than MySQL
- Requires learning Postgres-specific syntax (JSONB operators, CTEs)
- Heroku Postgres pricing higher than competitors for equivalent resources

## Notes
Migration from SQLite in development took 2 hours. Added pg gem and
updated database.yml. No code changes required.

```

Each section is concise. The template takes 10-20 minutes to fill out.

## Writing the Context Section

Context explains the problem and constraints at decision time.

**Bad:**
> We chose Sidekiq.

**Good:**
> We need background job processing for email delivery and report generation.
> Requirements: 10K jobs/hour peak, retries on failure, job priority, monitoring UI.
> Team has Redis experience but not RabbitMQ.

Context includes requirements, constraints (budget, team skills), and the environment that shaped the decision.

## Documenting Alternatives

List options considered and why they were rejected.

**Bad:**
> Considered Resque. Chose Sidekiq.

**Good:**
> - Sidekiq: Multithreaded, lower memory, built-in web UI
> - Resque: Mature, simple, but higher memory due to forking
> - DelayedJob: No Redis required, but DB polling adds load

Explaining why alternatives were rejected prevents future debates.

## Capturing Consequences

List positive and negative outcomes to set expectations.

```markdown
## Consequences
### Positive
- Sidekiq's multithreading reduces server costs by 40%
- Web UI provides visibility into queues and failures
- Active community and frequent updates

### Negative
- Thread safety required in job code (no class variables)
- Redis dependency adds operational complexity
- Requires paid Sidekiq Pro for advanced features (batching)

```

Honest assessment of trade-offs prevents surprises.

## Marking ADRs as Superseded

When reversing a decision, update the old ADR and link to the new one.

```markdown
# ADR-0002: Use REST API for Public Endpoints

## Status
Superseded by ADR-0003

(original content remains)

```

In ADR-0003:

```markdown
# ADR-0003: Use GraphQL API for Public Endpoints

## Context
ADR-0002 chose REST, but mobile clients now require 10+ endpoints
per screen, causing latency. GraphQL reduces round trips.

## Decision
Migrate public API to GraphQL...

```

Never delete old ADRs. They explain why earlier decisions didn't work.

## Lightweight vs Heavyweight Docs

ADRs are lightweight: 1-2 pages, 15 minutes to write. Heavyweight docs (architecture diagrams, RFC-style proposals) are for complex cross-team initiatives.

**Lightweight (ADR):** "We chose Sidekiq over Resque for background jobs."
**Heavyweight (Design Doc):** "Microservices decomposition plan with service boundaries, API contracts, migration phases, and rollback strategy."

Use ADRs for 80% of decisions. Reserve heavyweight docs for migrations affecting multiple teams.

---

## Trade-offs Box

- **Advantage:** Preserves decision context, prevents relitigating settled questions, onboards new engineers faster.
- **Cost:** Requires discipline to write during decision time; templates can feel like busywork for trivial choices.
- **When to skip:** Skip ADRs for reversible, low-impact decisions (CSS framework choice, test library) that don't affect architecture.

---

## Debugging Checklist

When an architectural decision is questioned, check:

1. ADR existence: Search `docs/adr/` for keywords related to the decision
2. Status field: Confirm if the ADR is Accepted, Superseded, or Deprecated
3. Consequences section: Check if negative outcomes match current complaints
4. Alternatives section: Verify if the proposed alternative was already considered
5. Superseding ADRs: Look for newer ADRs that updated the decision
6. Commit history: Use `git log docs/adr/0001-*.md` to see when it was written and by whom

---

## One-Minute Recap

- ADRs document the "why" behind significant technical decisions using a lightweight template
- Store ADRs in `docs/adr/` as numbered markdown files committed to version control
- MADR template includes context, decision, alternatives, and consequences in 1-2 pages
- Mark superseded ADRs but never delete them; link to new ADRs that reverse decisions
- Reserve ADRs for architecture-impacting choices; skip for trivial or reversible decisions
