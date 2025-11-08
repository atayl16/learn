# Deployment Strategies

## What It Is
Deployment strategies are systematic approaches to releasing new versions of your Rails application to production with minimal risk and downtime. Blue-green deployment maintains two identical production environments and switches traffic between them. Canary releases gradually roll out changes to a small subset of users before full deployment. Rolling deployments incrementally replace old instances with new ones. Each strategy balances risk, complexity, and downtime differently. The goal is zero-downtime deployments where users experience no service interruption during releases.

## Why It Matters
Deploying to production is high-stakes. A bad deployment can bring down your entire application, costing revenue and customer trust. Traditional "stop-the-world" deployments require maintenance windows and angry users. Modern deployment strategies eliminate downtime, enable rapid rollbacks, and reduce blast radius when bugs slip through. Choosing the wrong strategy can mean unnecessary infrastructure costs (blue-green doubles resources temporarily) or increased complexity (canary requires sophisticated traffic routing). Rails apps have specific concerns: database migrations must be backward compatible, asset compilation happens before deployment, and background jobs need graceful shutdown.

## When to Use
- **Blue-green deployment:** When you need instant rollback capability and can afford 2x infrastructure during cutover
- **Canary releases:** When testing new features with real traffic before full rollout, especially for high-risk changes
- **Rolling deployments:** For cost-efficient gradual updates when you can tolerate brief mixed-version states
- **Feature flags with deployment:** When deploying code that's not yet ready for all users
- **Database migrations:** When schema changes require careful coordination with code deployments
- **High-traffic applications:** When even 1 second of downtime costs thousands in lost revenue

## Three Common Pitfalls
1. **Database migration incompatibility:** Deploying code that requires new columns before running migrations breaks the old version. Fix: Make migrations backward-compatible. Add columns as nullable first, backfill data, then deploy code that uses them.
2. **Session store incompatibility:** Blue-green switches instantly, but user sessions may have old data structures. Fix: Use database-backed sessions or ensure session data is backward compatible across versions.
3. **Health checks that lie:** A health check that returns 200 before the app is fully ready (database connections, caches warmed) causes traffic to hit broken instances. Fix: Implement deep health checks that verify all critical dependencies.

---

## Core Deployment Strategies

### Blue-Green Deployment

**Concept:** Maintain two identical production environments ("blue" and "green"). Deploy new version to the inactive environment, test it, then switch all traffic at once.

**How it works:**
1. Blue environment serves production traffic
2. Deploy new version to green environment
3. Run smoke tests against green
4. Switch load balancer to point at green
5. Blue becomes the standby for instant rollback

```ruby
# config/routes.rb - Health check endpoint for load balancer
Rails.application.routes.draw do
  get '/health', to: 'health#check'
end

# app/controllers/health_controller.rb
class HealthController < ApplicationController
  def check
    # Deep health check verifying all dependencies
    checks = {
      database: check_database,
      redis: check_redis,
      migrations: check_migrations
    }

    if checks.values.all?
      render json: { status: 'healthy', version: ENV['APP_VERSION'], checks: checks }, status: :ok
    else
      render json: { status: 'unhealthy', checks: checks }, status: :service_unavailable
    end
  end

  private

  def check_database
    ActiveRecord::Base.connection.execute('SELECT 1')
    true
  rescue => e
    { error: e.message }
  end

  def check_redis
    Redis.current.ping == 'PONG'
  rescue => e
    { error: e.message }
  end

  def check_migrations
    ActiveRecord::Migration.check_pending!
    true
  rescue ActiveRecord::PendingMigrationError => e
    { error: 'Pending migrations' }
  end
end
```

**Trade-offs:**
- **Pros:** Instant cutover, instant rollback, full testing in production-like environment
- **Cons:** 2x infrastructure cost during deployment, requires load balancer configuration

### Canary Releases

**Concept:** Deploy new version to a small percentage of servers/users first. Monitor metrics. Gradually increase traffic if healthy.

**Implementation with feature flags:**

```ruby
# Gemfile
gem 'flipper'
gem 'flipper-active_record'

# config/initializers/flipper.rb
Flipper.configure do |config|
  config.default do
    adapter = Flipper::Adapters::ActiveRecord.new
    Flipper.new(adapter)
  end
end

# app/controllers/api/v2/users_controller.rb
class Api::V2::UsersController < ApplicationController
  def index
    # Canary: Show new optimized query to 10% of users
    if Flipper.enabled?(:optimized_user_query, current_user)
      @users = User.optimized_query.limit(100)
    else
      @users = User.legacy_query.limit(100)
    end

    render json: @users
  end
end

# Enable for 10% of users
Flipper.enable_percentage_of_actors(:optimized_user_query, 10)

# Monitor error rates, increase gradually
Flipper.enable_percentage_of_actors(:optimized_user_query, 50)
Flipper.enable_percentage_of_actors(:optimized_user_query, 100)
```

**Trade-offs:**
- **Pros:** Lower risk, real user feedback, gradual rollout
- **Cons:** Requires feature flag infrastructure, more complex monitoring, users get inconsistent experiences

### Rolling Deployment

**Concept:** Update instances one-by-one or in small batches. Always maintain minimum healthy capacity.

**Kubernetes example:**

```yaml
# deployment.yml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: rails-app
spec:
  replicas: 6
  strategy:
    type: RollingUpdate
    rollingUpdate:
      maxSurge: 2        # Can create 2 extra pods during update
      maxUnavailable: 1  # Maximum 1 pod can be down at a time
  template:
    metadata:
      labels:
        app: rails-app
        version: v2.5.0
    spec:
      containers:
      - name: rails
        image: myapp:v2.5.0
        readinessProbe:
          httpGet:
            path: /health
            port: 3000
          initialDelaySeconds: 10
          periodSeconds: 5
        livenessProbe:
          httpGet:
            path: /health
            port: 3000
          initialDelaySeconds: 30
          periodSeconds: 10
```

**How Kubernetes rolling update works:**
1. Creates 2 new pods (maxSurge)
2. Waits for readiness probe to pass
3. Terminates 1 old pod
4. Repeats until all pods updated

**Trade-offs:**
- **Pros:** Efficient resource usage, no extra infrastructure needed
- **Cons:** Mixed versions run simultaneously, slower rollout, harder to rollback mid-deployment

---

## Zero-Downtime Deployments

### Critical Requirements

**1. Graceful Shutdown**

```ruby
# config/puma.rb
workers ENV.fetch("WEB_CONCURRENCY") { 2 }
threads_count = ENV.fetch("RAILS_MAX_THREADS") { 5 }
threads threads_count, threads_count

preload_app!

# Handle SIGTERM gracefully
on_worker_shutdown do
  puts "Worker shutting down - finishing in-flight requests"
  # Puma automatically waits for requests to complete
  # But you can clean up resources here
  ActiveRecord::Base.connection_pool.disconnect!
end

# Signal readiness to load balancer
on_worker_boot do
  ActiveRecord::Base.establish_connection
end
```

**2. Health Check Endpoints**

Separate liveness (is process alive?) from readiness (can it handle traffic?):

```ruby
# config/routes.rb
get '/health/live', to: 'health#live'
get '/health/ready', to: 'health#ready'

# app/controllers/health_controller.rb
class HealthController < ApplicationController
  def live
    # Simple: is the process running?
    render json: { status: 'alive' }, status: :ok
  end

  def ready
    # Deep check: can we serve traffic?
    ActiveRecord::Base.connection.execute('SELECT 1')
    Redis.current.ping
    render json: { status: 'ready' }, status: :ok
  rescue => e
    render json: { status: 'not ready', error: e.message }, status: :service_unavailable
  end
end
```

**3. Backward-Compatible Migrations**

```ruby
# Bad: breaks old code immediately
class AddEmailToUsers < ActiveRecord::Migration[7.0]
  def change
    add_column :users, :email, :string, null: false
  end
end

# Good: allow old code to work without email
class AddEmailToUsers < ActiveRecord::Migration[7.0]
  def change
    add_column :users, :email, :string, null: true  # nullable first
  end
end

# Deploy 1: Add nullable column, deploy new code
# Deploy 2: Backfill data
# Deploy 3: Add NOT NULL constraint
```

---

## Rollback Strategies

### Fast Rollback Options

**1. Load Balancer Switch (Blue-Green)**

```bash
# AWS ALB example
aws elbv2 modify-listener --listener-arn $LISTENER_ARN \
  --default-actions Type=forward,TargetGroupArn=$BLUE_TARGET_GROUP

# Instant rollback to blue environment
# Takes ~5 seconds for all traffic to switch
```

**2. Container Tag Revert (Kubernetes)**

```bash
# Rollback to previous revision
kubectl rollout undo deployment/rails-app

# Or specific revision
kubectl rollout undo deployment/rails-app --to-revision=3

# Check rollout status
kubectl rollout status deployment/rails-app
```

**3. Feature Flag Disable**

```ruby
# Instant disable of problematic feature
Flipper.disable(:new_checkout_flow)

# Or for specific users
Flipper.disable_actor(:new_checkout_flow, user)
```

### Database Rollback Challenges

**Problem:** Can't rollback deployed code if migration is irreversible.

**Solution:** Three-phase deployment for breaking changes:

```ruby
# Phase 1: Add new column (backward compatible)
class AddPreferencesToUsers < ActiveRecord::Migration[7.0]
  def change
    add_column :users, :preferences_json, :jsonb
  end
end
# Deploy code that writes to BOTH old and new columns

# Phase 2: Backfill data
# Run rake task to copy data

# Phase 3: Remove old column (breaking change)
class RemoveOldPreferences < ActiveRecord::Migration[7.0]
  def change
    remove_column :users, :old_preferences
  end
end
# Deploy code that only uses new column
```

---

## Best Practices

- **Always use health checks:** Implement deep health checks that verify database, cache, and critical dependencies before routing traffic
- **Make migrations backward compatible:** New code should work with old schema; old code should tolerate new schema
- **Monitor deployment metrics:** Track error rates, latency, throughput during and after deployments
- **Automate rollback decisions:** Set thresholds (error rate >1%, latency >500ms) that trigger automatic rollbacks
- **Test rollback procedures:** Practice rollbacks regularly; if rollback is painful, you'll avoid deploying
- **Use canaries for risky changes:** Algorithm changes, payment flows, and critical paths deserve gradual rollout
- **Decouple deployment from release:** Deploy dark-launched code behind feature flags, release by enabling flags
- **Document rollback steps:** Playbooks for database rollbacks, cache invalidation, and service restarts

---

## Key Terms

- **Blue-green deployment** - Two identical environments; switch traffic between them
- **Canary release** - Gradual rollout to subset of users/servers
- **Rolling deployment** - Incremental replacement of old instances with new
- **Zero-downtime deployment** - Release without service interruption
- **Graceful shutdown** - Finish in-flight requests before terminating process
- **Health check** - Endpoint that verifies application readiness
- **Rollback** - Reverting to previous version after failed deployment
- **Feature flag** - Runtime toggle to enable/disable features without deploying

---

## Summary

Deployment strategies eliminate downtime and reduce risk when releasing Rails applications. Blue-green deployments enable instant rollback but cost 2x infrastructure. Canary releases provide gradual validation with real traffic. Rolling deployments balance efficiency and safety. All strategies require health checks, graceful shutdowns, and backward-compatible database migrations. The best strategy depends on your risk tolerance, infrastructure budget, and rollback requirements. Master these patterns to deploy confidently and recover quickly.

**Next steps:** Complete the exercise to implement blue-green deployment with load balancer switching.
