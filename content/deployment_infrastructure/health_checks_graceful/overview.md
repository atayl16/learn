# Health Checks & Graceful Shutdowns

## What It Is

Health checks are HTTP endpoints that tell orchestrators (Kubernetes, ECS, load balancers) whether your app is ready to serve traffic. **Liveness probes** detect if the app is frozen or deadlocked (restart it). **Readiness probes** detect if it's ready to handle requests (remove from load balancer until ready). Rails 7.1 introduced the `/up` endpoint (`Rails::HealthController`) for basic health checks. Graceful shutdown means handling **SIGTERM** signals to drain connections and finish in-flight requests before terminating—critical for zero-downtime deployments where old pods/containers must exit cleanly as new ones spin up.

## Why It Matters

Without health checks, orchestrators send traffic to unhealthy instances, causing 502 errors and user-facing outages. In Kubernetes, pods without readiness checks receive traffic before booting completes—users hit "database not ready" errors during deploys. Graceful shutdown prevents dropped requests during rolling updates: when a pod receives SIGTERM, it has 10-30 seconds to finish active requests before being killed. Poorly configured shutdown handlers can leak database connections, orphan background jobs, or corrupt data mid-transaction. Senior Rails developers architect systems where deployments are invisible to users—no error spikes, no timeouts.

## When to Use

- **Kubernetes deployments:** Readiness probes prevent traffic to unready pods; liveness probes restart frozen processes
- **Load balancers (ALB/NLB):** Health checks remove unhealthy targets from rotation automatically
- **Rolling deployments:** Graceful shutdown drains connections during blue-green or canary deploys
- **Database migrations:** Custom readiness checks ensure migrations complete before serving traffic
- **Background workers (Sidekiq):** Trap SIGTERM to finish jobs before shutdown, prevent job loss
- **Monitoring/alerting:** Health endpoints feed uptime monitors (Datadog, New Relic)

## Three Common Pitfalls

1. **Using liveness checks for slow startup:** If liveness probes fail during slow boot (asset compilation, cache warming), Kubernetes kills and restarts the pod in a crash loop. Fix: Use readiness checks for startup; liveness only for detecting deadlocks.
2. **Ignoring SIGTERM in production:** Default Rails servers (Puma) handle SIGTERM, but custom scripts or workers might not. If your container ignores SIGTERM, Kubernetes sends SIGKILL after `terminationGracePeriodSeconds` (default 30s), killing mid-request. Fix: Register signal handlers.
3. **Health checks that trigger expensive operations:** Querying every database table or calling external APIs in `/up` adds latency and load. Probes run every 5-10 seconds; expensive checks can DoS your own app. Fix: Keep checks lightweight—verify critical dependencies only.

---

## Readiness vs Liveness Probes

### Readiness Probe

**Purpose:** Is the app ready to serve traffic right now?

**When it fails:** Remove from load balancer, but keep pod running.

**Use cases:**
- App is booting (loading Rails, connecting to DB)
- Database migrations in progress
- Cache warming incomplete
- External dependency (Redis, Elasticsearch) unreachable

**Example:** `/up` endpoint returns 200 only after DB connection succeeds.

```yaml
# Kubernetes config
readinessProbe:
  httpGet:
    path: /up
    port: 3000
  initialDelaySeconds: 10
  periodSeconds: 5
  failureThreshold: 3
```

### Liveness Probe

**Purpose:** Is the app alive or deadlocked?

**When it fails:** Restart the pod.

**Use cases:**
- Thread deadlock (all Puma workers stuck)
- Memory leak causing OOM (out of memory)
- Infinite loop in application code
- Unrecoverable errors (corrupted cache)

**Example:** Lightweight endpoint that just returns 200.

```yaml
# Kubernetes config
livenessProbe:
  httpGet:
    path: /up
    port: 3000
  initialDelaySeconds: 30
  periodSeconds: 10
  failureThreshold: 5
```

**Critical difference:** Liveness failures restart the pod; readiness failures just stop traffic. Use conservative `failureThreshold` for liveness (5+) to avoid restart loops.

---

## Rails 7.1 `/up` Endpoint

Rails 7.1 added `Rails::HealthController` with a `/up` route by default:

```ruby
# config/routes.rb (automatically added)
Rails.application.routes.draw do
  get "up" => "rails/health#show", as: :rails_health_check
end
```

**What it does:**
- Returns `200 OK` if the app is running
- Does **not** check database, Redis, or external services by default
- Intended for basic liveness checks

**Accessing it:**

```bash
curl http://localhost:3000/up
# => 200 OK (body: empty)
```

### Customizing Health Checks

For readiness checks, create a custom controller that verifies critical dependencies:

```ruby
# app/controllers/health_controller.rb
class HealthController < ApplicationController
  skip_before_action :verify_authenticity_token

  def show
    # Check database connection
    ActiveRecord::Base.connection.execute("SELECT 1")

    # Check Redis (if using)
    Redis.current.ping if defined?(Redis)

    # Check critical external service
    # HTTParty.get("https://api.example.com/health", timeout: 2)

    render json: { status: "ok" }, status: :ok
  rescue => e
    Rails.logger.error("Health check failed: #{e.message}")
    render json: { status: "error", message: e.message }, status: :service_unavailable
  end
end
```

```ruby
# config/routes.rb
get "health" => "health#show"
```

**When to use custom checks:**
- Readiness probes (ensure DB/Redis ready)
- Advanced monitoring (report metrics to APM)
- Post-migration verification (ensure schema up to date)

**When to use `/up`:**
- Liveness probes (simple "is the process alive?")
- Load balancer health checks (lightweight)

---

## Graceful Shutdown with SIGTERM

### How Shutdown Works

1. Orchestrator (Kubernetes) sends **SIGTERM** to pod
2. Pod has `terminationGracePeriodSeconds` (default 30s) to exit cleanly
3. During grace period:
   - Stop accepting new connections
   - Finish in-flight requests
   - Close database connections
   - Flush logs
4. If pod doesn't exit in time, **SIGKILL** force-kills it

### Puma Graceful Shutdown

Puma (Rails default) handles SIGTERM gracefully:

```ruby
# config/puma.rb
workers ENV.fetch("WEB_CONCURRENCY") { 2 }
threads_count = ENV.fetch("RAILS_MAX_THREADS") { 5 }
threads threads_count, threads_count

preload_app!

# Graceful shutdown configuration
worker_timeout 30  # Time to wait for workers to finish
worker_shutdown_timeout 15  # Force shutdown after this

on_worker_boot do
  ActiveRecord::Base.establish_connection
end

# Handle SIGTERM
on_worker_shutdown do
  ActiveRecord::Base.connection_pool.disconnect!
end
```

**What happens on SIGTERM:**
1. Puma stops accepting new connections
2. Waits for active requests to complete (up to `worker_timeout`)
3. Closes worker threads gracefully
4. Exits with status 0

### Custom Signal Handlers

For background workers or custom scripts:

```ruby
# lib/graceful_shutdown.rb
class GracefulShutdown
  def self.trap_signals
    %w[TERM INT].each do |signal|
      Signal.trap(signal) do
        puts "Received #{signal}, shutting down gracefully..."

        # Stop accepting new work
        @shutting_down = true

        # Finish current work
        finish_in_flight_requests

        # Cleanup
        ActiveRecord::Base.connection_pool.disconnect!
        Redis.current.quit if defined?(Redis)

        exit 0
      end
    end
  end

  def self.finish_in_flight_requests
    timeout = 30
    start_time = Time.current

    while active_requests? && (Time.current - start_time) < timeout
      sleep 0.5
    end
  end

  def self.active_requests?
    # Check if any requests are still being processed
    # Implementation depends on your architecture
    false
  end
end

# In initializer or at top of script
GracefulShutdown.trap_signals
```

### Sidekiq Graceful Shutdown

Sidekiq automatically handles SIGTERM:

```yaml
# config/sidekiq.yml
:timeout: 25  # Time to finish jobs before forced shutdown
```

**Behavior:**
- Stops fetching new jobs from Redis
- Waits up to `timeout` seconds for active jobs to finish
- Re-queues unfinished jobs (if job didn't `acknowledge` completion)

**Best practice:** Set `timeout` < Kubernetes `terminationGracePeriodSeconds` to ensure Sidekiq exits before SIGKILL.

---

## Zero-Downtime Deployments

### Rolling Update Strategy

```yaml
# Kubernetes Deployment
spec:
  replicas: 3
  strategy:
    type: RollingUpdate
    rollingUpdate:
      maxSurge: 1        # Add 1 new pod before removing old
      maxUnavailable: 0  # Never have fewer than 3 pods
  template:
    spec:
      terminationGracePeriodSeconds: 60
      containers:
      - name: rails
        readinessProbe:
          httpGet:
            path: /up
            port: 3000
          initialDelaySeconds: 15
```

**Flow:**
1. New pod starts (replica 4/3)
2. Waits for readiness probe success (DB connected, app booted)
3. Adds new pod to service (receives traffic)
4. Old pod receives SIGTERM
5. Old pod drains connections (60s grace period)
6. Old pod exits
7. Repeat until all pods updated

### Connection Draining

**Problem:** Load balancer might send requests during SIGTERM grace period.

**Solution:** Use Kubernetes preStop hook to remove from service before SIGTERM:

```yaml
spec:
  containers:
  - name: rails
    lifecycle:
      preStop:
        exec:
          command: ["/bin/sh", "-c", "sleep 15"]
```

**What this does:**
1. Kubernetes removes pod from service endpoints
2. Sleeps 15 seconds (allows load balancer to propagate)
3. Then sends SIGTERM to app
4. App drains remaining connections

**Result:** No new requests arrive during shutdown; only in-flight requests finish.

---

## Best Practices

- Use **readiness probes** for startup/dependency checks; **liveness probes** for deadlock detection
- Keep liveness checks lightweight (just `/up`, no DB queries)
- Set `initialDelaySeconds` > app boot time to avoid restart loops
- Use conservative `failureThreshold` (3-5) to tolerate transient failures
- Configure `terminationGracePeriodSeconds` > longest request timeout
- Implement preStop hooks to drain connections before SIGTERM
- Log shutdown events for debugging ("Received SIGTERM, draining...")
- Test graceful shutdown: `kubectl delete pod <name>` should show 0 downtime
- Monitor health check failures in production (alert on sustained failures)
- Use custom health controllers for readiness; `/up` for liveness

---

## Key Terms

- **Liveness probe** - Detects if app is frozen; restarts on failure
- **Readiness probe** - Detects if app is ready for traffic; removes from load balancer on failure
- **SIGTERM** - Unix signal requesting graceful termination
- **SIGKILL** - Unix signal forcing immediate termination (unblockable)
- **Connection draining** - Finishing in-flight requests before shutdown
- **preStop hook** - Kubernetes lifecycle hook executed before SIGTERM
- **terminationGracePeriodSeconds** - Max time to shutdown before SIGKILL

---

## Summary

Health checks enable orchestrators to route traffic only to healthy instances. Readiness probes ensure apps are ready before receiving requests; liveness probes restart deadlocked processes. Rails 7.1's `/up` endpoint provides basic health checks; custom controllers verify databases and dependencies. Graceful shutdown handles SIGTERM by draining connections and finishing requests before exit—critical for zero-downtime deployments. Kubernetes rolling updates combine readiness checks, preStop hooks, and graceful shutdown to deploy without user impact.

**Next steps:** Complete the exercise to implement custom health checks and graceful shutdown handlers.
