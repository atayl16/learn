# APM Basics and Flamegraphs

## What It Is
Application Performance Monitoring (APM) tools (New Relic, Scout, Skylight) trace request execution through your Rails app, breaking down time spent in controllers, views, database queries, and external API calls. Flamegraphs visualize these traces as horizontal bars representing method calls and their durations. Segments (also called spans) represent individual operations like SQL queries or HTTP requests within a trace.

## Why It Matters
Response time logs show total duration but hide where time is spent. APM reveals that a 2-second request spent 1.8 seconds in a single N+1 query or 500ms rendering a partial. Flamegraphs make bottlenecks visible at a glance: wide bars indicate slow operations. Detecting N+1 queries via APM prevents production performance degradation before customers complain.

## When to Use
- Identifying which controller actions are slowest in production
- Finding N+1 queries missed during development
- Pinpointing slow external API calls or database queries
- Comparing performance across deploys or code changes
- Profiling local development with rack-mini-profiler before shipping

## Three Common Pitfalls
1. **Ignoring percentiles:** Average response time (200ms) hides the worst cases. P95 or P99 (95th/99th percentile) reveals tail latency affecting real users. Always check high percentiles in APM dashboards.
2. **Over-instrumenting:** Adding custom segments to every method call increases overhead and costs. Instrument only slow operations (>50ms) like API calls or complex calculations.
3. **Fixing symptoms instead of root causes:** Caching a slow query treats the symptom. Use flamegraphs to find the root cause (missing index, N+1, inefficient algorithm) and fix it instead.

---

## Reading Flamegraphs

APM tools display traces as flamegraphs:

```
Controller: UsersController#show (145ms)
├─ SQL: SELECT * FROM users (5ms)
├─ View: users/show.html.erb (130ms)
│  ├─ Partial: _profile.html.erb (8ms)
│  └─ Partial: _posts.html.erb (120ms)
│     └─ SQL: SELECT * FROM posts WHERE user_id = ? (110ms) [N+1]
└─ External API: fetch_avatar (10ms)
```

**Reading top to bottom:**
- Top level = controller action (total time)
- Nested levels = operations within that action
- Width = time consumed (wider = slower)

**Key insight:** The `_posts.html.erb` partial took 120ms, with 110ms spent on one SQL query. This indicates an N+1 problem.

---

## APM Service Setup

Install Skylight (lightweight, Rails-focused APM):

```ruby
# Gemfile
gem 'skylight'

# Terminal
bundle install
bundle exec skylight setup
# Follow prompts to create account and get auth token

# config/application.rb
config.skylight.authentication = ENV['SKYLIGHT_AUTHENTICATION']
```

Deploy and visit Skylight dashboard to see traces.

Alternative APM tools:
- **Scout APM:** Similar to Skylight, includes memory profiling
- **New Relic:** Full-stack APM with infrastructure monitoring
- **Datadog APM:** Distributed tracing across microservices

---

## Segments and Spans

APM breaks requests into segments:

```ruby
# Automatic instrumentation (built-in)
User.where(active: true).includes(:posts)  # Auto-traced as SQL segment

# Custom instrumentation for slow operations
ActiveSupport::Notifications.instrument('process.payment') do
  PaymentGateway.charge(amount)
end
```

Skylight/Scout auto-instrument:
- ActiveRecord queries
- View rendering
- HTTP requests (via Net::HTTP)
- Background jobs

Custom segments appear in flamegraphs alongside built-in ones.

---

## Detecting N+1 Queries

APM highlights N+1 patterns:

```ruby
# Bad: N+1 query (1 + N queries)
@users = User.limit(10)
@users.each do |user|
  puts user.posts.count  # Triggers: SELECT COUNT(*) FROM posts WHERE user_id = ?
end
```

**APM flamegraph shows:**
- 1 query to fetch users (5ms)
- 10 identical COUNT queries (10 x 8ms = 80ms)

**Fix with counter cache:**

```ruby
# Good: single query with counter_cache
class User < ApplicationRecord
  has_many :posts
end

class Post < ApplicationRecord
  belongs_to :user, counter_cache: true
end

@users = User.limit(10)
@users.each { |user| puts user.posts_count }  # No extra queries
```

APM shows only the initial User query.

---

## Local Profiling with rack-mini-profiler

Install rack-mini-profiler for per-request profiling:

```ruby
# Gemfile (development group)
group :development do
  gem 'rack-mini-profiler'
  gem 'memory_profiler'
  gem 'stackprof'
end
```

Visit any page in development - see performance badge in top-left corner:

```
GET /users/123
Total: 245ms | SQL: 18ms (4 queries) | Views: 220ms
```

Click badge for detailed breakdown:
- SQL queries with durations
- View rendering times
- Flamegraph of Ruby method calls

---

## Profiling Specific Actions

Force profiling on specific requests:

```ruby
# In controller
def show
  Rack::MiniProfiler.step('Load user') do
    @user = User.find(params[:id])
  end

  Rack::MiniProfiler.step('Load posts with comments') do
    @posts = @user.posts.includes(:comments)
  end

  render :show
end
```

rack-mini-profiler shows each step's duration separately.

---

## Trade-offs Box
- **Advantage:** APM flamegraphs instantly reveal slow queries, N+1s, and rendering bottlenecks without manual instrumentation.
- **Cost:** APM services charge per-host or per-request; high-traffic apps may need sampling (trace 10% of requests) to control costs.
- **When to skip:** For internal tools with <100 daily users, rack-mini-profiler in development may suffice; invest in APM when optimizing user-facing production apps.

---

## Debugging Checklist

When APM shows unexpected slow traces:

1. Check percentiles: Is slowness P50 (common) or P99 (rare)?
2. Identify widest segment: Which operation consumed most time?
3. Look for N+1 patterns: Multiple identical queries in sequence
4. Verify indexes: Run EXPLAIN on slow queries in Rails console
5. Check external APIs: Are third-party calls timing out?
6. Compare across deploys: Did recent code change introduce regression?
7. Profile locally: Use rack-mini-profiler to reproduce issue
8. Review sampling rate: APM may not trace all requests

---

## One-Minute Recap
- APM tools trace requests through Rails, showing time spent in controllers, views, SQL, and external APIs
- Flamegraphs visualize traces with wide bars indicating slow operations
- Segments (spans) represent individual operations like queries or HTTP calls
- N+1 queries appear as multiple identical segments in flamegraphs
- rack-mini-profiler provides local profiling without shipping to external APM service
