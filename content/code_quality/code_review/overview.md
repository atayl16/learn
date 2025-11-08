# Code Review Techniques

## What It Is

Code review is the practice of having teammates examine proposed code changes before merging them. Effective reviews balance three goals: catching bugs and design flaws, teaching patterns and standards, and maintaining team velocity. Reviews use blocking comments for critical issues (security holes, broken logic) and non-blocking comments for style preferences and learning opportunities. A review checklist ensures consistency: verify tests pass, check for edge cases, assess readability, and confirm alignment with architecture.

## Why It Matters

Code merged without review accumulates technical debt faster than teams can address it. A reviewer catches the bug you missed after three hours of debugging. Reviews also scale knowledge: juniors learn patterns from seniors, seniors learn domain context from juniors. Poor reviews slow teams down with nitpicking (arguing over variable names) or rubber-stamping (approving without reading). Senior developers know when to block ("this leaks user emails") versus when to suggest ("consider extracting a service object here").

## When to Use

- Block merges for security vulnerabilities, data integrity bugs, or broken business logic
- Non-blocking comments for style preferences, performance optimizations, or refactoring suggestions
- Review checklists for complex domains (payments, authentication) to ensure critical checks happen
- Async reviews for non-urgent changes; pair programming or sync calls for architectural decisions
- Automated linting and CI checks to catch formatting and test failures before human review

## Three Common Pitfalls

1. **Nitpicking style in reviews:** Arguing over indentation or method names wastes time. Use automated linters (RuboCop, StandardRB) to enforce style, and reserve review comments for logic and design. If your team debates style in reviews, you need better tooling, not more opinions.

2. **Blocking on non-critical issues:** Marking a PR as "Request Changes" because a variable could be renamed or a method could be extracted slows delivery. Use non-blocking comments ("nit:" or "optional:") for suggestions that don't affect correctness. Block only for bugs, security issues, or violations of agreed-upon architecture.

3. **Skipping context in feedback:** Comments like "this is wrong" or "refactor this" frustrate authors and don't teach patterns. Explain why: "This query will N+1 on production data—consider `includes(:comments)`" or "Inline SQL bypasses our audit log—use the `AuditableUpdate` service instead."

---

## Giving Constructive Feedback

Effective feedback separates observation from judgment and explains the "why."

**Avoid:**

```
This code is messy. Fix it.
```

**Better:**

```
This method does three things: validates input, calls an API, and updates the database.
Consider extracting the API call into a service object so we can test it independently
and retry on failures. (non-blocking)
```

**Structure:**
1. State what you observed: "This controller action has 50 lines"
2. Explain the impact: "Long actions are hard to test and debug"
3. Suggest an approach: "Consider moving business logic to a service object"
4. Label priority: "blocking" for must-fix, "nit" for optional

Use questions to invite discussion: "Could this cause an N+1 if the user has 1000 posts?" frames the concern as a question, not an accusation.

---

## Critical vs Style Issues

Not all feedback deserves equal weight. Distinguish bugs from preferences.

**Critical (blocking):**
- Security: Exposing sensitive data, SQL injection, missing authorization
- Correctness: Off-by-one errors, race conditions, incorrect business logic
- Data integrity: Missing validations, unsafe migrations, transaction violations
- Performance: N+1 queries on large datasets, missing indexes, unbounded loops

**Style (non-blocking):**
- Variable naming: `user` vs `current_user`
- Method extraction: "This could be a private method"
- Pattern suggestions: "Have you considered the Strategy pattern here?"
- Documentation: "Add a comment explaining why we skip validation here"

**Example blocking comment:**

```ruby
# PR code
def charge_card(amount)
  Stripe::Charge.create(amount: amount, currency: "usd", source: params[:token])
end
```

**Review:**

```
BLOCKING: This reads the Stripe token directly from params without validation.
An attacker could pass arbitrary data. Use strong parameters and validate the
token format before passing it to Stripe.
```

**Example non-blocking comment:**

```ruby
# PR code
orders.each { |o| o.update(status: "shipped") }
```

**Review:**

```
nit: This triggers N UPDATE queries. Consider `Order.where(id: order_ids).update_all(status: "shipped")`
for better performance. Not blocking since this only runs on admin actions with <10 orders.
```

---

## Review Checklists

Checklists ensure consistency, especially for junior reviewers or complex domains.

**General Rails PR Checklist:**
- [ ] Tests pass in CI (green build required)
- [ ] New code has test coverage (unit or request tests)
- [ ] Database migrations are reversible and safe for zero-downtime deploy
- [ ] No N+1 queries (check for `includes` or `preload` on associations)
- [ ] Authorization checks present for user-facing actions
- [ ] No sensitive data in logs (passwords, tokens, PII)
- [ ] Error handling covers edge cases (nil values, timeouts, API failures)
- [ ] New ENV variables documented in `.env.example`

**Domain-Specific (Payments):**
- [ ] Idempotency keys used for Stripe API calls
- [ ] Amounts validated before charging (positive, within limits)
- [ ] Failures logged and alerted (Sentry, Rollbar)
- [ ] Refunds and disputes handled

Checklists turn implicit knowledge into explicit steps. Review the checklist, then adapt it for your team's context.

---

## Building Review Culture

Healthy review culture values learning over gatekeeping.

**Team norms to establish:**
1. **Response time:** Aim for first review within 4 hours during work hours
2. **Review size:** PRs over 400 lines take exponentially longer to review—break them up
3. **Label conventions:** Use "blocking," "nit," "question," "praise" to set expectations
4. **Author responsibility:** Respond to every comment (fix, disagree, or acknowledge)
5. **Reviewer responsibility:** Approve after blocking issues are resolved; don't request changes on nits

**Encourage learning in both directions:**

```
# Senior reviewing junior
"Nice use of `pluck` here to avoid loading full ActiveRecord objects—this saves memory."

# Junior reviewing senior
"I didn't know `find_each` batches queries. Could you add a comment explaining why
we use it here? It'll help the next person."
```

Pair programming for high-risk changes (data migrations, payment flows) beats async review. Save reviews for standard feature work.

---

## Blocking vs Non-Blocking Comments

Blocking comments prevent merge until resolved. Non-blocking comments are suggestions.

**Use blocking for:**
- Bugs that will break production
- Security vulnerabilities
- Violations of team architecture decisions (e.g., "we agreed not to use inline SQL")

**Use non-blocking for:**
- Performance optimizations on low-traffic code
- Refactoring suggestions
- Documentation improvements
- "FYI" context or learning points

**Example labels:**

```
BLOCKING: This migration drops the `email` column without a deprecation period.
We need a two-step deploy: deprecate first, drop in the next release.

nit: Consider renaming `process` to `process_payment` for clarity.

optional: You could extract this into a concern, but it's fine as-is.

question: Does this handle the case where `user.subscription` is nil?

praise: Great test coverage on the edge cases!
```

Authors can merge once blocking comments are addressed. Non-blocking comments can be resolved with "acknowledged" or deferred to a follow-up PR.

---

## Trade-offs Box

- **Advantage:** Code reviews catch bugs before production, spread knowledge across the team, and enforce standards without heavy process.
- **Cost:** Reviews add latency (hours to days between PR open and merge) and can become bottlenecks if reviewers are overloaded or nitpick style.
- **When to skip:** Skip reviews for trivial changes (typo fixes, README updates) or in emergencies (production outages). Use automated checks and pair programming as alternatives.

---

## Debugging Checklist

When reviews slow down or become contentious, check:

1. PR size: Run `git diff --stat main` and aim for <400 lines
2. Review latency: Track time from PR open to first review—should be under 4 hours
3. Approval rate: If <80% of PRs are approved without "Request Changes," reviewers may be over-blocking
4. Linter failures: Automate style checks so reviews focus on logic
5. Checklist coverage: Compare your review comments to your checklist—are you forgetting critical checks or nitpicking outside them?
6. Author-reviewer relationship: If reviews feel adversarial, schedule a sync call to align on expectations

---

## One-Minute Recap

- Code reviews catch bugs, share knowledge, and enforce standards; use blocking comments for critical issues, non-blocking for suggestions
- Distinguish security bugs and data corruption (blocking) from style preferences and refactorings (non-blocking)
- Checklists ensure consistency: verify tests, check for N+1s, validate migrations, confirm authorization
- Build culture by setting response time norms, using clear labels, and valuing learning over gatekeeping
- Merge after blocking issues are resolved; defer non-blocking suggestions to follow-up PRs or acknowledge them
