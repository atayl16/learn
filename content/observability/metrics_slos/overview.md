# Metrics and SLO Thinking

## What It Is
RED metrics (Rate, Errors, Duration) measure web service health by tracking request rate (requests/second), error rate (percentage of failed requests), and response duration (latency percentiles). Service Level Indicators (SLIs) are specific measurements (P99 latency, error rate); Service Level Objectives (SLOs) are target thresholds (P99 < 500ms, errors < 0.1%); Service Level Agreements (SLAs) are contractual commitments with penalties for violations.

## Why It Matters
Monitoring individual errors or slow requests creates noise without revealing system health. RED metrics provide a unified view: a spike in error rate signals a problem even if individual errors seem unrelated. SLOs convert monitoring into business objectives, answering "is our service reliable enough?" with data. Setting realistic SLOs (99% instead of 100%) creates error budgets that balance reliability with development velocity.

## When to Use
- Defining service health for dashboards and alerts
- Comparing reliability across services or deployments
- Setting alert thresholds that reflect user impact
- Communicating service quality to stakeholders
- Deciding whether to prioritize reliability work or new features

## Three Common Pitfalls
1. **Targeting 100% uptime:** Perfect reliability is impossible and expensive. Aiming for 100% blocks deployments and experiments. Calculate realistic SLOs (99%-99.9%) based on user expectations and error budgets.
2. **Alerting on every blip:** A single slow request or brief error spike doesn't indicate system failure. Alert when SLOs are violated over windows (5+ minutes) to reduce false positives and on-call fatigue.
3. **Measuring vanity metrics:** Tracking "total users" or "requests per day" doesn't reveal service health. Focus on actionable metrics (error rate, latency) that indicate problems requiring immediate action.

---

## RED Metrics Explained

**Rate:** Requests per second (throughput)

```ruby
# Track with StatsD or Prometheus
StatsD.increment('requests.count')

```

**Errors:** Percentage of requests returning 5xx status

```ruby
# Track error rate
if response.status >= 500
  StatsD.increment('requests.errors')
end

# Calculate: errors / total_requests * 100

```

**Duration:** Request latency (P50, P95, P99)

```ruby
# Track response time
start = Time.current
process_request
duration_ms = (Time.current - start) * 1000
StatsD.measure('requests.duration', duration_ms)

```

These three metrics reveal most service problems.

---

## SLI vs SLO vs SLA

**SLI (Service Level Indicator):** What you measure
- P99 latency: 450ms
- Error rate: 0.05%
- Availability: 99.95%

**SLO (Service Level Objective):** Your internal target
- P99 latency < 500ms
- Error rate < 0.1%
- Availability > 99.9%

**SLA (Service Level Agreement):** External commitment with consequences
- P99 latency < 1000ms (credits if violated)
- Availability > 99.5% (refund if violated)

**Hierarchy:** SLA ≤ SLO ≤ current SLI

Set SLOs stricter than SLAs to catch problems before violating contracts.

---

## Setting Realistic SLOs

Compare uptime targets:

| SLO | Downtime/Year | Downtime/Month | Use Case |
|-----|---------------|----------------|----------|
| 99% | 3.65 days | 7.2 hours | Internal tools |
| 99.9% | 8.76 hours | 43 minutes | Most web apps |
| 99.95% | 4.38 hours | 21 minutes | Critical services |
| 99.99% | 52 minutes | 4 minutes | Payment processing |

**Higher SLOs cost more:**
- 99.9% → 99.99% = 10x cost (redundancy, chaos engineering, on-call)

Calculate based on user impact:
- Can users tolerate 40 minutes downtime/month? → 99.9%
- Must users have <5 minutes downtime/month? → 99.99%

---

## Error Budgets

Error budget = allowed failures based on SLO

**Example:** 99.9% uptime SLO
- Target: 99.9% of requests succeed
- Error budget: 0.1% can fail
- At 1M requests/month: 1,000 errors allowed

**Using error budget:**
- Budget remaining → ship new features aggressively
- Budget exhausted → freeze feature work, fix reliability
- Budget overspent → miss SLO, investigate incident

Error budgets balance innovation with stability.

---

## Dashboard Design

Effective dashboards answer: "Is the service healthy?"

**Layout:**

```
┌─────────────────────────────────────┐
│ Service Health: ✓ All SLOs Met     │
├─────────────────────────────────────┤
│ Rate:     1,240 req/s  (normal)    │
│ Errors:   0.03%        (SLO: <0.1%)│
│ Duration: P99 = 380ms  (SLO: <500ms)│
├─────────────────────────────────────┤
│ Error Budget: 67% remaining        │
└─────────────────────────────────────┘

```

**Design principles:**
- RED metrics on every dashboard
- Show current value vs SLO threshold
- Graph last 24 hours (spot trends)
- Include error budget status

---

## Alerting Thresholds

Alert when SLO violation is imminent:

```ruby
# Good: Alert on sustained SLO violation
if error_rate > 0.1% for 5.minutes
  page_oncall("Error rate SLO violated")
end

if p99_latency > 500.ms for 10.minutes
  page_oncall("Latency SLO violated")
end

```

**Bad alerts:**

```ruby
# Don't alert on single errors
if single_request.status == 500
  page_oncall  # TOO NOISY
end

# Don't alert on arbitrary thresholds
if error_rate > 1%  # Why 1%? Is it tied to user impact?
  page_oncall
end

```

Every alert should answer: "Does this require immediate human action?"

---

## Instrumenting Rails for RED Metrics

Send metrics to StatsD/Prometheus:

```ruby
# Gemfile
gem 'statsd-instrument'

# config/initializers/statsd.rb
StatsD.backend = StatsD::Instrument::Backends::UDPBackend.new(
  ENV.fetch('STATSD_ADDR', 'localhost:8125')
)

# config/application.rb
config.middleware.use(StatsD::Instrument::Middleware)

```

Metrics sent automatically:
- Request rate: `requests.count`
- Error rate: `requests.status.5xx`
- Duration: `requests.duration`

Build Grafana/Datadog dashboards from these metrics.

---

## Trade-offs Box
- **Advantage:** RED metrics and SLOs convert chaotic monitoring into clear health signals; error budgets justify reliability investments with data.
- **Cost:** Requires metrics infrastructure (StatsD, Prometheus, Datadog); setting SLOs demands understanding user expectations and cost trade-offs.
- **When to skip:** For prototype apps or internal tools with <10 users, manual testing suffices; adopt SLOs when scaling to 1000+ users or building customer-facing SaaS.

---

## Debugging Checklist

When SLO violations occur:

1. Check RED metrics: Which metric violated SLO? (rate, errors, duration)
2. Identify time window: When did violation start? Correlate with deploys
3. Review error logs: What exceptions or status codes increased?
4. Check dependencies: Did external API or database slow down?
5. Compare percentiles: Is P99 slow but P50 normal? (tail latency)
6. Inspect dashboards: Are all endpoints affected or just one?
7. Review recent changes: Code deploys, config changes, traffic spikes
8. Calculate error budget: How much budget remains this month?

---

## One-Minute Recap
- RED metrics (Rate, Errors, Duration) provide unified service health view
- SLIs are measurements; SLOs are targets; SLAs are external contracts
- Set realistic SLOs (99%-99.9%) based on user impact, not perfection
- Error budgets balance feature velocity with reliability work
- Alert on sustained SLO violations over time windows, not single events
