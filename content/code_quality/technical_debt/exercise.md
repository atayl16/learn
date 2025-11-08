# Exercise: Technical Debt Assessment & Remediation Planning

**Estimated time:** 60-90 minutes

## Objective

Conduct a comprehensive technical debt assessment on a Rails e-commerce application. You'll analyze the codebase using the Technical Debt Quadrant, create an impact vs. effort matrix, perform churn analysis to identify hotspots, and deliver a stakeholder-ready remediation plan with business justification.

## Setup

You're inheriting "ShopNow," a 3-year-old Rails e-commerce platform experiencing significant velocity decline:

- 150,000 lines of Ruby code
- 45% test coverage
- 8 engineers (3 senior, 5 mid-level)
- 500K monthly active users, $5M annual revenue

**Recent Issues:**
- Checkout bugs: 12 incidents in past quarter
- Feature velocity down 40% over 6 months
- Onboarding takes 6 weeks vs. 2 weeks a year ago
- Production incidents up 60% year-over-year

```bash
# Clone sample repository (or use existing Rails app)
git clone git@github.com:company/shopnow.git
cd shopnow

# Run static analysis tools
bundle exec rubocop --format json > rubocop_report.json
bundle exec flog app/ lib/ > flog_scores.txt
bundle exec rails_best_practices .

# Analyze test coverage
COVERAGE=true bundle exec rspec
open coverage/index.html

# Perform churn analysis
git log --format=format: --name-only --since="6 months ago" | \
  grep "\.rb$" | sort | uniq -c | sort -rn | head -20
```

## Tasks

### Part 1: Debt Inventory & Classification (25 minutes)

**Task 1.1:** Create comprehensive debt inventory

Identify 10-15 specific technical debt items in the codebase. For each item, document:

```ruby
# Use this template
class DebtItem
  attr_accessor :id, :title, :description, :category,
                :quadrant, :impact_score, :effort_score,
                :affected_files, :business_impact

  def priority_score
    impact_score.to_f / effort_score
  end
end
```

**Example items to look for:**
- Missing test coverage in critical paths
- God objects (controllers/models >500 lines)
- Missing database indexes causing N+1 queries
- Hardcoded configuration values
- No monitoring/observability for background jobs
- Security vulnerabilities from Brakeman
- High-complexity methods (flog score >40)
- Fragile code with many production incidents

**Task 1.2:** Classify each item using Technical Debt Quadrant

For each debt item, determine:
1. **Was it deliberate?** Did team knowingly cut corners?
2. **Was it prudent?** Was it a reasonable decision at the time?

Assign to quadrant:
- **Reckless/Deliberate:** "We don't have time for design"
- **Reckless/Inadvertent:** "What's layering?"
- **Prudent/Deliberate:** "Ship now, refactor later"
- **Prudent/Inadvertent:** "Now we know how we should've done it"

**Acceptance criteria:**
- [ ] 10-15 specific debt items cataloged
- [ ] Each item has clear description and affected files
- [ ] Each item classified in debt quadrant
- [ ] Items cover multiple categories (testing, architecture, performance, security)

### Part 2: Impact vs. Effort Assessment (20 minutes)

**Task 2.1:** Score each debt item

Assign impact score (1-10) based on:
- Frequency of changes to this code
- Bug rate / production incidents
- Number of engineers blocked
- Customer-facing impact

Assign effort score (1-10) based on:
- Lines of code to change
- Test coverage (harder without tests)
- Number of dependent systems
- Team knowledge of area

**Task 2.2:** Calculate priority scores

```ruby
# Create debt_assessment.rb
debt_items = [
  { title: "Missing indexes on orders", impact: 8, effort: 2 },
  { title: "Zero test coverage - payments", impact: 10, effort: 7 },
  # ... add all items
]

sorted_items = debt_items.map do |item|
  item.merge(priority: item[:impact].to_f / item[:effort])
end.sort_by { |item| -item[:priority] }

puts "Priority Rankings:"
sorted_items.each_with_index do |item, i|
  puts "#{i + 1}. #{item[:title]} (#{item[:priority].round(2)})"
end
```

**Task 2.3:** Create impact vs. effort matrix

Plot items on 2x2 matrix:
```
HIGH IMPACT
    │  Quick Wins        │  Big Bets
    │  (Do First)        │  (Plan)
    ├─────────────────────────────
    │  Low Value         │  Time Sinks
    │  (Skip)            │  (Avoid)
                    LOW EFFORT → HIGH EFFORT
```

**Acceptance criteria:**
- [ ] Impact score (1-10) assigned to each item with justification
- [ ] Effort score (1-10) assigned to each item with justification
- [ ] Priority scores calculated (impact/effort ratio)
- [ ] Items sorted by priority score
- [ ] Visual matrix created showing all items

### Part 3: Churn Analysis & Hotspots (15 minutes)

**Task 3.1:** Identify high-change files

```bash
# Find most-changed files in last 6 months
git log --format=format: --name-only --since="6 months ago" | \
  grep "\.rb$" | sort | uniq -c | sort -rn | head -20

# Check complexity of top files
bundle exec flog app/controllers/orders_controller.rb
```

**Task 3.2:** Cross-reference with quality metrics

For top 5 most-changed files, document:
- Change frequency (# commits)
- Complexity score (flog)
- Test coverage (%)
- Lines of code
- Production incidents traced to this file

**Task 3.3:** Identify 3-5 critical hotspots

A hotspot is: **high churn + low quality**

Example:
```markdown
## 🔥 CRITICAL: orders_controller.rb
- Churn: 127 changes in 6 months (HIGHEST)
- Complexity: 450.2 flog score (VERY HIGH)
- Coverage: 25% (LOW)
- LOC: 2,500 (GOD OBJECT)
- Priority: URGENT
```

**Acceptance criteria:**
- [ ] Churn analysis completed for past 6 months
- [ ] Top 10 most-changed files identified
- [ ] Complexity/coverage checked for high-churn files
- [ ] 3-5 critical hotspots documented
- [ ] Hotspots prioritized by impact on velocity

### Part 4: Remediation Roadmap (20 minutes)

**Task 4.1:** Create phased remediation plan

Break work into 3 phases:

**Phase 1: Quick Wins (1-2 weeks)**
- High impact, low effort items
- Deliver immediate ROI
- Build momentum

**Phase 2: Critical Risk Reduction (4-8 weeks)**
- High impact, high effort items
- Address biggest velocity bottlenecks
- Reduce production risk

**Phase 3: Long-term Improvements (8+ weeks)**
- Establish sustainable practices
- Prevent future debt
- Improve developer experience

**Task 4.2:** Define success metrics

For each phase, specify:
- Velocity improvement target
- Quality metrics (coverage, incidents, complexity)
- Business metrics (feature throughput, bug rate)

**Acceptance criteria:**
- [ ] Roadmap with 3 phases and timelines
- [ ] Each phase has specific deliverables
- [ ] Week-by-week breakdown for Phase 1 & 2
- [ ] Success metrics defined for each phase
- [ ] Total investment estimated (engineer-weeks)
- [ ] Expected ROI calculated

### Part 5: Stakeholder Communication (10 minutes)

**Task 5.1:** Write executive summary

Create non-technical document explaining:
1. The problem in business terms
2. Current business impact (quantified)
3. Proposed solution (3 phases)
4. Investment required
5. Expected returns (velocity, quality, revenue)
6. Break-even timeline
7. Clear recommendation

**Bad:** "We need to refactor service layer for separation of concerns"

**Good:** "Our checkout code causes 12 bugs/quarter costing $50K revenue. 3 weeks refactoring will reduce bugs 75% and unblock payment integrations."

**Task 5.2:** Create debt backlog document

```markdown
# Q1 2024 Technical Debt Priorities

## Critical (Blocking Business Goals)
### 1. Add Test Coverage to Payment Processing
- Impact: 15 incidents in 6 months, $50K lost revenue
- Business Cost: Blocks Stripe Connect integration
- Effort: 3 weeks
- ROI: Break-even in 2 months

[Continue for top 5 items...]
```

**Acceptance criteria:**
- [ ] Executive summary written in non-technical language
- [ ] Business impact quantified in dollars/time
- [ ] ROI calculation included
- [ ] Clear recommendation stated
- [ ] Debt backlog document with top 5 items prioritized

## Verification Steps

Your final deliverable should include:

1. **Debt Inventory Spreadsheet**
   - 10-15 rows with: Title, Category, Quadrant, Impact, Effort, Priority, Files, Business Impact

2. **Impact vs. Effort Matrix**
   - Visual 2x2 grid with items plotted
   - Color-coded by quadrant

3. **Churn Analysis Report**
   - Top 10 most-changed files
   - Cross-reference with quality metrics
   - 3-5 hotspots identified and prioritized

4. **Remediation Roadmap**
   - 3 phases with timelines
   - Week-by-week breakdown
   - Success metrics
   - Investment estimate

5. **Stakeholder Communication Document**
   - Executive summary (1 page)
   - Debt backlog (top 5 items)
   - ROI justification
   - Clear recommendation

6. **Prevention Strategy**
   - Code review standards
   - CI quality gates
   - Capacity allocation (e.g., 20% on debt)

## Stretch Goals

- [ ] **Automated analysis script:** Ruby script that runs analysis tools and generates debt report
- [ ] **Debt dashboard:** Rails admin page showing current debt metrics with charts
- [ ] **Cost calculator:** Tool that estimates dollar cost of velocity decline
- [ ] **Prevention checklist:** Pre-commit hooks and CI checks to prevent new debt
- [ ] **Quarterly review template:** Agenda for stakeholder debt review meetings
- [ ] **Velocity tracking:** Before/after metrics for debt remediation efforts

## Solution Notes

**Common Assessment Mistakes:**

1. **Scoring everything as high impact:** Be ruthless. Not all debt matters equally. Focus on business impact.

2. **Underestimating effort:** Refactoring untested code takes 3x longer than you think. Account for writing tests first.

3. **Forgetting churn:** A messy file changed once/year < moderately messy file changed daily.

4. **Technical jargon:** Stakeholders care about shipping faster, not "separation of concerns."

**Assessment Strategy:**

Start with automated tools:
```bash
# Static analysis
bundle exec rubocop
bundle exec flog app/ lib/
bundle exec brakeman

# Coverage
COVERAGE=true bundle exec rspec

# Churn
git log --format=format: --name-only --since="6 months ago" | \
  grep "\.rb$" | sort | uniq -c | sort -rn
```

Then interview engineers:
- "What part of codebase frustrates you most?"
- "Where do bugs come from repeatedly?"
- "What blocks you from shipping quickly?"

Review incident reports:
- Which code caused production issues?
- Are there patterns?

**Prioritization Philosophy:**

Goal is NOT zero debt. It's strategic management:
- Fix debt blocking velocity NOW
- Accept debt that doesn't hurt (yet)
- Prevent reckless debt via code review
- Time-box prudent/deliberate debt

**Real-World Tips:**

1. **Quick wins first:** Build credibility with stakeholders by delivering fast ROI
2. **Track before/after:** Measure velocity improvement to justify continued investment
3. **Make debt visible:** Public backlog, quarterly reviews, dashboard
4. **Allocate capacity:** Reserve 15-25% of every sprint for debt
5. **Prevent new debt:** Code review standards, linting, quality gates

**Example Priority Calculation:**

```ruby
# High priority: Quick win
{
  title: "Add indexes to orders table",
  impact: 8,   # Slow checkout, customer complaints
  effort: 2,   # 1 hour to add
  priority: 4.0  # DO THIS FIRST
}

# Medium priority: Big bet
{
  title: "Refactor OrdersController",
  impact: 9,   # Blocks all checkout features
  effort: 8,   # 2 weeks to refactor safely
  priority: 1.125  # Plan carefully, high value
}

# Low priority: Skip it
{
  title: "Rename variables in AdminController",
  impact: 2,   # Cosmetic, rarely touched
  effort: 5,   # Tedious, many files
  priority: 0.4  # NOT WORTH IT
}
```

**Stakeholder Communication Template:**

```markdown
## The Problem
[State in business terms: slow features, lost revenue, bugs]

## Business Impact
[Quantify: $X lost, Y% slower, Z incidents]

## Solution
[3 phases with timelines]

## Investment & Return
- Investment: X engineer-weeks
- Return: +Y% velocity, -Z% incidents
- Break-even: N months

## Recommendation
[Clear ask: approve 16-week program]
```

## Time Estimate

60-90 minutes for complete assessment and deliverables
