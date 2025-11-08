# Exercise: Health Checks & Graceful Shutdowns

## Objective

Implement production-ready health check endpoints and graceful shutdown handlers for a Rails application, including readiness/liveness probes and SIGTERM handling.

## Task

Build a comprehensive health monitoring system:

1. Create custom health check endpoints with database and dependency verification
2. Configure Puma for graceful shutdown with connection draining
3. Implement a signal handler for background workers
4. Test health checks under various failure scenarios
5. Verify graceful shutdown prevents dropped requests

## Acceptance Criteria

- [ ] Custom `/health` endpoint checks database, Redis, and returns appropriate status codes
- [ ] Lightweight `/up` endpoint exists for basic liveness checks
- [ ] Puma configured with graceful shutdown settings
- [ ] Signal handler traps SIGTERM and SIGINT for background workers
- [ ] Health endpoint returns 503 when dependencies are unavailable
- [ ] Graceful shutdown waits for in-flight requests before terminating
- [ ] Connection draining tested: no 502/504 errors during shutdown
- [ ] Health check response includes status details in JSON format

## Setup Code

### Step 1: Create Rails Application

```bash
# Create new Rails app
rails new health_demo --database=postgresql
cd health_demo

# Add Redis gem for dependency checking
bundle add redis

# Generate a simple controller
bin/rails generate controller Pages index

```

Edit `config/routes.rb`:

```ruby
Rails.application.routes.draw do
  root 'pages#index'
end

```

Edit `app/views/pages/index.html.erb`:

```erb
<h1>Health Check Demo</h1>
<p>Time: <%= Time.current %></p>
<p>This app demonstrates health checks and graceful shutdown.</p>

```

### Step 2: Create Custom Health Controller

Create `app/controllers/health_controller.rb`:

```ruby
class HealthController < ApplicationController
  skip_before_action :verify_authenticity_token

  def show
    checks = perform_health_checks

    if checks[:status] == "healthy"
      render json: checks, status: :ok
    else
      render json: checks, status: :service_unavailable
    end
  end

  def liveness
    # Simple liveness check - just verify app is running
    render json: { status: "ok" }, status: :ok
  end

  private

  def perform_health_checks
    results = {
      status: "healthy",
      timestamp: Time.current.iso8601,
      checks: {}
    }

    # Check database
    results[:checks][:database] = check_database

    # Check Redis
    results[:checks][:redis] = check_redis

    # Check disk space
    results[:checks][:disk] = check_disk_space

    # Overall status
    unhealthy = results[:checks].values.any? { |check| check[:status] != "ok" }
    results[:status] = unhealthy ? "unhealthy" : "healthy"

    results
  end

  def check_database
    start = Time.current
    ActiveRecord::Base.connection.execute("SELECT 1")
    duration = ((Time.current - start) * 1000).round(2)

    {
      status: "ok",
      response_time_ms: duration
    }
  rescue => e
    {
      status: "error",
      error: e.message
    }
  end

  def check_redis
    return { status: "skipped", message: "Redis not configured" } unless defined?(Redis)

    start = Time.current
    redis = Redis.new
    redis.ping
    duration = ((Time.current - start) * 1000).round(2)

    {
      status: "ok",
      response_time_ms: duration
    }
  rescue => e
    {
      status: "error",
      error: e.message
    }
  ensure
    redis&.quit
  end

  def check_disk_space
    stat = Sys::Filesystem.stat("/")
    percent_used = ((stat.blocks - stat.blocks_available).to_f / stat.blocks * 100).round(2)

    if percent_used > 90
      {
        status: "warning",
        percent_used: percent_used,
        message: "Disk usage above 90%"
      }
    else
      {
        status: "ok",
        percent_used: percent_used
      }
    end
  rescue => e
    {
      status: "error",
      error: e.message
    }
  end
end

```

Add routes in `config/routes.rb`:

```ruby
Rails.application.routes.draw do
  root 'pages#index'

  # Health check endpoints
  get 'health' => 'health#show'      # Readiness probe
  get 'up' => 'health#liveness'      # Liveness probe
end

```

### Step 3: Configure Puma for Graceful Shutdown

Edit `config/puma.rb`:

```ruby
# Puma configuration for graceful shutdown

max_threads_count = ENV.fetch("RAILS_MAX_THREADS") { 5 }
min_threads_count = ENV.fetch("RAILS_MIN_THREADS") { max_threads_count }
threads min_threads_count, max_threads_count

# Workers for production
workers ENV.fetch("WEB_CONCURRENCY") { 2 }

# Preload application for better performance
preload_app!

# Port
port ENV.fetch("PORT") { 3000 }

# Environment
environment ENV.fetch("RAILS_ENV") { "development" }

# PID file
pidfile ENV.fetch("PIDFILE") { "tmp/pids/server.pid" }

# Graceful shutdown settings
worker_timeout 30               # Give workers 30 seconds to finish requests
worker_shutdown_timeout 20      # Force shutdown after 20 seconds if still running

# Restart command for phased-restart
plugin :tmp_restart

# Lifecycle hooks
on_worker_boot do
  # Re-establish database connections for each worker
  ActiveRecord::Base.establish_connection if defined?(ActiveRecord)
end

on_worker_shutdown do
  # Clean up resources when worker shuts down
  puts "Worker #{Process.pid} shutting down gracefully..."
  ActiveRecord::Base.connection_pool.disconnect! if defined?(ActiveRecord)
end

before_fork do
  # Close database connections before forking workers
  ActiveRecord::Base.connection_pool.disconnect! if defined?(ActiveRecord)
end

# Gracefully handle SIGTERM
on_restart do
  puts "Puma master process restarting..."
end

```

### Step 4: Create Graceful Shutdown Handler for Workers

Create `lib/graceful_shutdown.rb`:

```ruby
module GracefulShutdown
  class Handler
    attr_reader :shutting_down, :active_tasks

    def initialize
      @shutting_down = false
      @active_tasks = 0
      @mutex = Mutex.new
    end

    def trap_signals
      %w[TERM INT].each do |signal|
        Signal.trap(signal) do
          handle_shutdown(signal)
        end
      end
    end

    def start_task
      @mutex.synchronize { @active_tasks += 1 }
    end

    def finish_task
      @mutex.synchronize { @active_tasks -= 1 }
    end

    def active_tasks?
      @mutex.synchronize { @active_tasks > 0 }
    end

    private

    def handle_shutdown(signal)
      return if @shutting_down

      @shutting_down = true
      puts "\n[#{Time.current}] Received #{signal}, initiating graceful shutdown..."
      puts "[#{Time.current}] Active tasks: #{@active_tasks}"

      # Stop accepting new work
      stop_accepting_work

      # Wait for active tasks to complete
      wait_for_active_tasks

      # Clean up resources
      cleanup_resources

      puts "[#{Time.current}] Graceful shutdown complete"
      exit 0
    end

    def stop_accepting_work
      puts "[#{Time.current}] Stopped accepting new work"
      # Mark that we're shutting down so new tasks are rejected
    end

    def wait_for_active_tasks
      timeout = 30
      start_time = Time.current
      last_count = -1

      while active_tasks? && (Time.current - start_time) < timeout
        current_count = @active_tasks
        if current_count != last_count
          puts "[#{Time.current}] Waiting for #{current_count} active tasks..."
          last_count = current_count
        end
        sleep 0.5
      end

      if active_tasks?
        puts "[#{Time.current}] WARNING: Timeout reached, #{@active_tasks} tasks still active"
      else
        puts "[#{Time.current}] All tasks completed"
      end
    end

    def cleanup_resources
      puts "[#{Time.current}] Cleaning up resources..."

      # Close database connections
      if defined?(ActiveRecord::Base)
        ActiveRecord::Base.connection_pool.disconnect!
        puts "[#{Time.current}] Database connections closed"
      end

      # Close Redis connections
      if defined?(Redis) && Redis.current
        Redis.current.quit
        puts "[#{Time.current}] Redis connection closed"
      end
    end
  end

  def self.handler
    @handler ||= Handler.new
  end

  def self.trap_signals
    handler.trap_signals
  end
end

```

### Step 5: Create Background Worker Script

Create `bin/worker`:

```ruby
#!/usr/bin/env ruby
require_relative '../config/environment'
require_relative '../lib/graceful_shutdown'

# Set up graceful shutdown
GracefulShutdown.trap_signals

puts "Worker started (PID: #{Process.pid})"
puts "Press Ctrl+C or send SIGTERM to test graceful shutdown"

# Simulate background processing
loop do
  break if GracefulShutdown.handler.shutting_down

  GracefulShutdown.handler.start_task

  begin
    # Simulate work (e.g., processing a job)
    puts "[#{Time.current}] Processing task..."
    sleep 5  # Simulate 5-second task

    puts "[#{Time.current}] Task completed"
  ensure
    GracefulShutdown.handler.finish_task
  end

  # Wait before next task
  sleep 2 unless GracefulShutdown.handler.shutting_down
end

puts "Worker exiting"

```

Make it executable:

```bash
chmod +x bin/worker

```

### Step 6: Create Test Script for Health Checks

Create `bin/test_health`:

```bash
#!/bin/bash

echo "Testing Health Check Endpoints"
echo "================================"
echo

echo "1. Testing Liveness Endpoint (/up)"
echo "-----------------------------------"
curl -s -w "\nHTTP Status: %{http_code}\n" http://localhost:3000/up | jq .
echo

echo "2. Testing Readiness Endpoint (/health)"
echo "---------------------------------------"
curl -s -w "\nHTTP Status: %{http_code}\n" http://localhost:3000/health | jq .
echo

echo "3. Testing with Database Down"
echo "-----------------------------"
echo "Stop your database and run: curl http://localhost:3000/health"
echo "Expected: HTTP 503 with error details"
echo

```

Make it executable:

```bash
chmod +x bin/test_health

```

## Verification Steps

### 1. Test Health Endpoints

```bash
# Start Rails server
bin/rails server

# In another terminal, test liveness endpoint
curl http://localhost:3000/up
# Should return: {"status":"ok"}

# Test readiness endpoint
curl http://localhost:3000/health | jq .
# Should return detailed health check with all dependencies

```

Expected output:

```json
{
  "status": "healthy",
  "timestamp": "2024-01-15T10:30:00Z",
  "checks": {
    "database": {
      "status": "ok",
      "response_time_ms": 2.34
    },
    "redis": {
      "status": "skipped",
      "message": "Redis not configured"
    },
    "disk": {
      "status": "ok",
      "percent_used": 45.67
    }
  }
}

```

### 2. Test Failed Health Check

```bash
# Stop PostgreSQL
sudo systemctl stop postgresql
# or on macOS: brew services stop postgresql

# Test health endpoint
curl -w "\nStatus: %{http_code}\n" http://localhost:3000/health | jq .

# Should return HTTP 503 with error details

```

### 3. Test Graceful Shutdown

```bash
# Start Rails server in foreground
bin/rails server

# In another terminal, send requests in a loop
while true; do
  curl -s http://localhost:3000 > /dev/null && echo "Success" || echo "Failed"
  sleep 0.5
done

# In another terminal, gracefully stop server
kill -TERM $(cat tmp/pids/server.pid)

# Watch the server logs - should see:
# - "Puma master process shutting down"
# - "Worker shutting down gracefully"
# - No request failures during shutdown

```

### 4. Test Background Worker Graceful Shutdown

```bash
# Start worker
bin/worker

# In another terminal, send SIGTERM
kill -TERM $(pgrep -f "bin/worker")

# Should see:
# - "Received TERM, initiating graceful shutdown"
# - "Waiting for active tasks..."
# - "All tasks completed"
# - "Graceful shutdown complete"

```

### 5. Simulate Kubernetes-style Rolling Update

Create `bin/rolling_update_test`:

```bash
#!/bin/bash

echo "Simulating Kubernetes Rolling Update"
echo "====================================="
echo

# Start server
bin/rails server -p 3000 &
SERVER_PID=$!
sleep 5

echo "Server started (PID: $SERVER_PID)"
echo

# Send continuous traffic
echo "Starting traffic simulation..."
(
  for i in {1..30}; do
    response=$(curl -s -o /dev/null -w "%{http_code}" http://localhost:3000/)
    if [ "$response" = "200" ]; then
      echo "[$i] Success"
    else
      echo "[$i] Failed (HTTP $response)"
    fi
    sleep 1
  done
) &
TRAFFIC_PID=$!

# Wait 5 seconds, then send SIGTERM
sleep 5
echo
echo "Sending SIGTERM to server..."
kill -TERM $SERVER_PID

# Wait for both to complete
wait $TRAFFIC_PID
wait $SERVER_PID

echo
echo "Test complete - check for any failed requests above"

```

Make it executable and run:

```bash
chmod +x bin/rolling_update_test
bin/rolling_update_test

```

## Stretch (Optional)

1. **Add Circuit Breaker Pattern:**

Create `lib/health_check/circuit_breaker.rb`:

```ruby
module HealthCheck
  class CircuitBreaker
    STATES = [:closed, :open, :half_open]

    def initialize(failure_threshold: 5, timeout: 60)
      @failure_threshold = failure_threshold
      @timeout = timeout
      @failures = 0
      @state = :closed
      @opened_at = nil
    end

    def call
      case @state
      when :open
        return open_state_result if should_remain_open?
        @state = :half_open
      end

      begin
        result = yield
        on_success
        result
      rescue => e
        on_failure
        raise e
      end
    end

    private

    def should_remain_open?
      Time.current - @opened_at < @timeout
    end

    def on_success
      @failures = 0
      @state = :closed
    end

    def on_failure
      @failures += 1
      if @failures >= @failure_threshold
        @state = :open
        @opened_at = Time.current
      end
    end

    def open_state_result
      raise "Circuit breaker open - service unavailable"
    end
  end
end

```

2. **Add Metrics Export:**

```ruby
# In HealthController
def metrics
  checks = perform_health_checks

  # Prometheus-style metrics
  metrics = []
  metrics << "health_status{status=\"#{checks[:status]}\"} 1"

  checks[:checks].each do |name, check|
    status_value = check[:status] == "ok" ? 1 : 0
    metrics << "health_check_status{check=\"#{name}\"} #{status_value}"

    if check[:response_time_ms]
      metrics << "health_check_duration_ms{check=\"#{name}\"} #{check[:response_time_ms]}"
    end
  end

  render plain: metrics.join("\n"), content_type: 'text/plain'
end

```

3. **Add Startup Probe:**

```ruby
# In HealthController
def startup
  # Check if app has completed initialization
  if Rails.application.initialized?
    render json: { status: "ready" }, status: :ok
  else
    render json: { status: "initializing" }, status: :service_unavailable
  end
end

```

4. **Add Load Shedding:**

```ruby
# config/initializers/load_shedding.rb
class LoadShedding
  def self.shedding?
    # Shed load if queue depth too high
    queue_depth = ActiveRecord::Base.connection_pool.stat[:busy]
    max_queue = ENV.fetch("MAX_QUEUE_DEPTH", 10).to_i

    queue_depth > max_queue
  end
end

# In ApplicationController
before_action :check_load_shedding

def check_load_shedding
  if LoadShedding.shedding?
    render json: { error: "Service temporarily unavailable" },
           status: :service_unavailable
  end
end

```

5. **Kubernetes Deployment Configuration:**

Create `k8s/deployment.yml`:

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: rails-app
spec:
  replicas: 3
  strategy:
    type: RollingUpdate
    rollingUpdate:
      maxSurge: 1
      maxUnavailable: 0
  selector:
    matchLabels:
      app: rails-app
  template:
    metadata:
      labels:
        app: rails-app
    spec:
      terminationGracePeriodSeconds: 60
      containers:
      - name: rails
        image: rails-app:latest
        ports:
        - containerPort: 3000

        # Startup probe - check if app has finished booting
        startupProbe:
          httpGet:
            path: /up
            port: 3000
          initialDelaySeconds: 0
          periodSeconds: 5
          failureThreshold: 12  # 60 seconds max (12 * 5s)

        # Readiness probe - check if app is ready for traffic
        readinessProbe:
          httpGet:
            path: /health
            port: 3000
          initialDelaySeconds: 10
          periodSeconds: 5
          failureThreshold: 3
          successThreshold: 1
          timeoutSeconds: 3

        # Liveness probe - check if app is alive
        livenessProbe:
          httpGet:
            path: /up
            port: 3000
          initialDelaySeconds: 30
          periodSeconds: 10
          failureThreshold: 5
          timeoutSeconds: 3

        # PreStop hook for connection draining
        lifecycle:
          preStop:
            exec:
              command: ["/bin/sh", "-c", "sleep 15"]

        resources:
          requests:
            memory: "256Mi"
            cpu: "100m"
          limits:
            memory: "512Mi"
            cpu: "500m"

```

## Solution Notes

**Common Gotchas:**

1. **Health check too expensive:** If health checks query large datasets or call slow external APIs, they can become a bottleneck. Keep checks lightweight - just verify connectivity, not functionality.

2. **Liveness probe too aggressive:** If `failureThreshold` is too low or `initialDelaySeconds` too short, pods restart in a loop during slow boots. Use conservative values.

3. **No connection draining:** Without a preStop hook, Kubernetes sends traffic during shutdown, causing 502 errors. Always implement preStop sleep.

4. **Ignoring SIGTERM in workers:** Custom background scripts must trap SIGTERM explicitly. Ruby doesn't handle it by default.

5. **Database connection leaks:** Always disconnect connections in shutdown handlers to avoid "too many connections" errors.

**Testing Checklist:**

- [ ] Health endpoint returns 200 when all dependencies healthy
- [ ] Health endpoint returns 503 when database down
- [ ] Liveness endpoint always returns 200 (unless app deadlocked)
- [ ] Graceful shutdown logs "shutting down gracefully"
- [ ] No request failures during `kill -TERM`
- [ ] Worker completes active tasks before exiting
- [ ] Database connections closed cleanly
- [ ] Kubernetes rolling update has 0 downtime

## Time Estimate

25 minutes
