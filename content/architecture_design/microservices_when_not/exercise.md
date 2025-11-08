# Exercise: When NOT to Microservice

## Objective

Evaluate whether a scenario justifies microservices or a modular monolith.

## Task

You're consulting for three teams considering microservices. Evaluate each scenario and recommend either:
- **Microservices** (justify with specific organizational or scaling needs)
- **Modular Monolith** (explain why microservices add complexity without benefit)

**Scenario A:** 8-person team, 1-year-old Rails app, 50K users, deploys 3x per day, no deployment conflicts. Team wants to "prepare for scale."

**Scenario B:** 60-person engineering org, 3 product teams, shared User model causes deployment conflicts weekly. Checkout team needs to deploy payment changes without coordinating with other teams.

**Scenario C:** E-commerce app where Orders and Inventory are tightly coupled (every order checks inventory). Team extracted them into separate services. Now writes involve API calls between services, and failures require compensating transactions.

For each scenario:
1. Recommend microservices or modular monolith
2. Explain the primary reason for your recommendation
3. List the main trade-off your recommendation introduces

## Acceptance Criteria

- [ ] Scenario A recommendation includes team size and deployment frequency as factors
- [ ] Scenario B recommendation addresses organizational independence needs
- [ ] Scenario C recommendation discusses shared data and distributed transaction costs
- [ ] Each recommendation includes one concrete trade-off (what you gain vs what you lose)
- [ ] Recommendations reference specific signals (team size, deployment conflicts, shared data)

## Verification Steps

1. Confirm Scenario A recommendation explains why premature extraction adds complexity
2. Verify Scenario B recommendation identifies team independence as justification for services
3. Check Scenario C recommendation suggests recombining or using a modular monolith
4. Ensure each recommendation mentions a specific cost (debugging complexity, deployment overhead, refactoring difficulty)

## Stretch (Optional)

For Scenario C, design a modular monolith structure with Orders and Inventory modules that communicate via service objects, avoiding direct model access.

## Time Estimate

18 minutes
