# Exercise: ADRs & Lightweight Documentation

## Objective

Write an Architecture Decision Record using the MADR template for a real project decision.

## Task

Your team is deciding whether to adopt GraphQL for the public API or stick with REST. Write an ADR documenting this decision:

1. Create `docs/adr/` directory in your Rails project
2. Write `0001-use-graphql-for-public-api.md` using the MADR template
3. Include context: mobile clients need data from 8+ REST endpoints per screen, causing latency
4. Document alternatives: REST (current), GraphQL, gRPC
5. Capture consequences (positive: reduced round trips, better mobile performance; negative: learning curve, query complexity monitoring)
6. Commit the ADR to version control
7. After 3 months (simulated), the team decides to revert to REST because query complexity caused performance issues. Write `0002-revert-to-rest-api.md` and mark ADR-0001 as superseded

## Acceptance Criteria

- [ ] `docs/adr/` directory exists in the project root
- [ ] `0001-use-graphql-for-public-api.md` includes all MADR sections (Status, Context, Decision, Alternatives, Consequences)
- [ ] Alternatives section explains why REST and gRPC were rejected
- [ ] Consequences section lists both positive and negative outcomes
- [ ] `0002-revert-to-rest-api.md` supersedes ADR-0001 with a link
- [ ] ADR-0001's Status is updated to "Superseded by ADR-0002"

## Verification Steps

1. Run `ls docs/adr/` and confirm two ADR files exist
2. Open `0001-use-graphql-for-public-api.md` and verify all sections are filled
3. Check `git log docs/adr/` and confirm ADRs are committed with descriptive messages
4. Verify ADR-0001 status reads "Superseded by ADR-0002"

## Stretch (Optional)

Add a script that generates ADR templates with sequential numbering: `./bin/new_adr "Use Redis for Caching"` creates `000N-use-redis-for-caching.md`.

## Time Estimate

19 minutes
