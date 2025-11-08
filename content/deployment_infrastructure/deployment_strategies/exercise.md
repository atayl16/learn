# Exercise: Blue-Green Deployment with Load Balancer Switching

## Objective
Implement a complete blue-green deployment workflow using Docker containers and HAProxy as a load balancer. You'll deploy two versions of a Rails application, configure health checks, and practice switching traffic between environments with zero downtime.

## Task
Build a blue-green deployment system that:

1. Runs two identical Rails applications (blue and green environments)
2. Uses HAProxy to route traffic between environments
3. Implements health checks for both environments
4. Enables instant traffic switching via load balancer reconfiguration
5. Demonstrates rollback capability by switching back to the previous version

## Acceptance Criteria
- [ ] Two Rails containers running different versions (blue v1.0, green v2.0)
- [ ] HAProxy load balancer routing traffic to active environment
- [ ] Health check endpoint returns environment version and status
- [ ] Traffic can be switched from blue to green with zero downtime
- [ ] Rollback capability verified by switching back to blue
- [ ] Health checks prevent traffic to unhealthy instances
- [ ] Deployment script automates the entire blue-green workflow

## Verification Steps

1. Verify both environments are healthy:

```bash
# Blue environment (running v1.0)
curl http://localhost:8001/health
# Should return: {"status":"healthy","version":"v1.0","environment":"blue"}

# Green environment (running v2.0)
curl http://localhost:8002/health
# Should return: {"status":"healthy","version":"v2.0","environment":"green"}
```

2. Verify load balancer routes to active environment:

```bash
# Load balancer endpoint
curl http://localhost:8080/
# Should return the active environment's response
```

3. Test zero-downtime switch:

```bash
# In one terminal, continuously ping the service
while true; do curl -s http://localhost:8080/ | grep version; sleep 1; done

# In another terminal, switch environments
./scripts/switch_environment.sh green

# The first terminal should show no request failures during switch
```

4. Verify rollback capability:

```bash
# Switch back to blue
./scripts/switch_environment.sh blue

# Confirm traffic is back on v1.0
curl http://localhost:8080/health
```

## Setup Code

### Step 1: Create Rails Application Structure

```bash
# Create project directory
mkdir blue_green_deployment
cd blue_green_deployment

# Create Rails app
rails new demo_app --skip-test --database=postgresql
cd demo_app
```

### Step 2: Implement Health Check Endpoint

Edit `config/routes.rb`:

```ruby
Rails.application.routes.draw do
  get '/health', to: 'health#check'
  root 'application#index'
end
```

Create `app/controllers/health_controller.rb`:

```ruby
class HealthController < ApplicationController
  def check
    version = ENV['APP_VERSION'] || 'unknown'
    environment = ENV['ENVIRONMENT'] || 'unknown'

    checks = {
      database: check_database,
      redis: check_redis
    }

    all_healthy = checks.values.all? { |v| v == true }

    if all_healthy
      render json: {
        status: 'healthy',
        version: version,
        environment: environment,
        checks: checks,
        timestamp: Time.current
      }, status: :ok
    else
      render json: {
        status: 'unhealthy',
        version: version,
        environment: environment,
        checks: checks
      }, status: :service_unavailable
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
    # Optional: if you have Redis configured
    true
  rescue => e
    { error: e.message }
  end
end
```

Create `app/controllers/application_controller.rb`:

```ruby
class ApplicationController < ActionController::Base
  def index
    version = ENV['APP_VERSION'] || 'unknown'
    environment = ENV['ENVIRONMENT'] || 'unknown'

    render json: {
      message: "Hello from #{environment} environment!",
      version: version,
      environment: environment,
      hostname: Socket.gethostname,
      timestamp: Time.current
    }
  end
end
```

### Step 3: Create Multi-Environment Dockerfile

Create `Dockerfile` in the Rails app root:

```dockerfile
# syntax=docker/dockerfile:1
FROM ruby:3.2.2-alpine AS builder

RUN apk add --no-cache build-base postgresql-dev nodejs tzdata

WORKDIR /app

COPY Gemfile Gemfile.lock ./
RUN bundle config set --local deployment 'true' && \
    bundle config set --local without 'development test' && \
    bundle install --jobs 4

COPY . .

# Runtime stage
FROM ruby:3.2.2-alpine

RUN apk add --no-cache postgresql-client tzdata curl

RUN addgroup -g 1000 rails && \
    adduser -D -u 1000 -G rails rails

WORKDIR /app

COPY --from=builder /usr/local/bundle /usr/local/bundle
COPY --from=builder --chown=rails:rails /app /app

USER rails

EXPOSE 3000

ENV RAILS_ENV=production \
    RAILS_LOG_TO_STDOUT=true \
    RAILS_SERVE_STATIC_FILES=true

HEALTHCHECK --interval=10s --timeout=3s --start-period=30s --retries=3 \
  CMD curl -f http://localhost:3000/health || exit 1

CMD ["bundle", "exec", "rails", "server", "-b", "0.0.0.0"]
```

### Step 4: Create HAProxy Configuration

Create `haproxy/haproxy.cfg` in project root:

```conf
global
    log stdout format raw local0
    maxconn 4096

defaults
    log     global
    mode    http
    option  httplog
    option  dontlognull
    timeout connect 5000ms
    timeout client  50000ms
    timeout server  50000ms

# Stats page for monitoring
listen stats
    bind *:8404
    stats enable
    stats uri /stats
    stats refresh 10s
    stats admin if TRUE

# Frontend - receives traffic
frontend http_front
    bind *:80
    default_backend active_env

# Backend pools
backend blue_env
    option httpchk GET /health
    http-check expect status 200
    server blue blue:3000 check inter 5s fall 3 rise 2

backend green_env
    option httpchk GET /health
    http-check expect status 200
    server green green:3000 check inter 5s fall 3 rise 2

# Active backend (will be modified during switches)
backend active_env
    option httpchk GET /health
    http-check expect status 200
    server blue blue:3000 check inter 5s fall 3 rise 2
```

### Step 5: Create Docker Compose Configuration

Create `docker-compose.yml`:

```yaml
version: '3.8'

services:
  db:
    image: postgres:15-alpine
    environment:
      POSTGRES_USER: postgres
      POSTGRES_PASSWORD: postgres
      POSTGRES_DB: demo_production
    volumes:
      - postgres_data:/var/lib/postgresql/data
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U postgres"]
      interval: 10s
      timeout: 5s
      retries: 5

  # Blue environment (v1.0)
  blue:
    build:
      context: ./demo_app
      dockerfile: Dockerfile
    environment:
      DATABASE_URL: postgresql://postgres:postgres@db:5432/demo_production
      RAILS_ENV: production
      SECRET_KEY_BASE: insecure_secret_for_demo_only_change_in_production
      APP_VERSION: v1.0
      ENVIRONMENT: blue
    depends_on:
      db:
        condition: service_healthy
    ports:
      - "8001:3000"
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:3000/health"]
      interval: 10s
      timeout: 3s
      retries: 3
      start_period: 30s

  # Green environment (v2.0)
  green:
    build:
      context: ./demo_app
      dockerfile: Dockerfile
    environment:
      DATABASE_URL: postgresql://postgres:postgres@db:5432/demo_production
      RAILS_ENV: production
      SECRET_KEY_BASE: insecure_secret_for_demo_only_change_in_production
      APP_VERSION: v2.0
      ENVIRONMENT: green
    depends_on:
      db:
        condition: service_healthy
    ports:
      - "8002:3000"
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:3000/health"]
      interval: 10s
      timeout: 3s
      retries: 3
      start_period: 30s

  # HAProxy load balancer
  haproxy:
    image: haproxy:2.8-alpine
    ports:
      - "8080:80"     # Main traffic
      - "8404:8404"   # Stats page
    volumes:
      - ./haproxy:/usr/local/etc/haproxy:ro
      - haproxy_config:/etc/haproxy
    depends_on:
      - blue
      - green
    command: haproxy -f /usr/local/etc/haproxy/haproxy.cfg

volumes:
  postgres_data:
  haproxy_config:
```

### Step 6: Create Deployment Scripts

Create `scripts/switch_environment.sh`:

```bash
#!/bin/bash
set -e

TARGET_ENV=$1

if [ -z "$TARGET_ENV" ]; then
  echo "Usage: $0 [blue|green]"
  exit 1
fi

if [ "$TARGET_ENV" != "blue" ] && [ "$TARGET_ENV" != "green" ]; then
  echo "Error: Environment must be 'blue' or 'green'"
  exit 1
fi

echo "Switching to $TARGET_ENV environment..."

# Health check before switch
echo "Checking $TARGET_ENV environment health..."
HEALTH_STATUS=$(curl -s http://localhost:800$([ "$TARGET_ENV" = "blue" ] && echo "1" || echo "2")/health | grep -o '"status":"[^"]*"' | cut -d'"' -f4)

if [ "$HEALTH_STATUS" != "healthy" ]; then
  echo "Error: $TARGET_ENV environment is not healthy!"
  echo "Status: $HEALTH_STATUS"
  exit 1
fi

echo "$TARGET_ENV is healthy. Proceeding with switch..."

# Create new HAProxy config
cat > haproxy/haproxy.cfg << EOF
global
    log stdout format raw local0
    maxconn 4096

defaults
    log     global
    mode    http
    option  httplog
    option  dontlognull
    timeout connect 5000ms
    timeout client  50000ms
    timeout server  50000ms

listen stats
    bind *:8404
    stats enable
    stats uri /stats
    stats refresh 10s
    stats admin if TRUE

frontend http_front
    bind *:80
    default_backend active_env

backend blue_env
    option httpchk GET /health
    http-check expect status 200
    server blue blue:3000 check inter 5s fall 3 rise 2

backend green_env
    option httpchk GET /health
    http-check expect status 200
    server green green:3000 check inter 5s fall 3 rise 2

backend active_env
    option httpchk GET /health
    http-check expect status 200
    server $TARGET_ENV $TARGET_ENV:3000 check inter 5s fall 3 rise 2
EOF

# Reload HAProxy
echo "Reloading HAProxy configuration..."
docker-compose exec haproxy haproxy -f /usr/local/etc/haproxy/haproxy.cfg -sf $(docker-compose exec haproxy pidof haproxy)

echo "Successfully switched to $TARGET_ENV!"
echo "Verify with: curl http://localhost:8080/health"
```

Make it executable:

```bash
chmod +x scripts/switch_environment.sh
```

Create `scripts/deploy.sh`:

```bash
#!/bin/bash
set -e

NEW_VERSION=$1
TARGET_ENV=$2

if [ -z "$NEW_VERSION" ] || [ -z "$TARGET_ENV" ]; then
  echo "Usage: $0 <version> [blue|green]"
  echo "Example: $0 v2.1 green"
  exit 1
fi

echo "Deploying $NEW_VERSION to $TARGET_ENV environment..."

# Update environment variable in docker-compose
export NEW_APP_VERSION=$NEW_VERSION

# Rebuild and restart target environment
echo "Building new image..."
docker-compose build $TARGET_ENV

echo "Stopping $TARGET_ENV..."
docker-compose stop $TARGET_ENV

echo "Starting $TARGET_ENV with version $NEW_VERSION..."
docker-compose up -d $TARGET_ENV

# Wait for health check
echo "Waiting for $TARGET_ENV to be healthy..."
RETRY_COUNT=0
MAX_RETRIES=30

while [ $RETRY_COUNT -lt $MAX_RETRIES ]; do
  HEALTH_CHECK=$(curl -s http://localhost:800$([ "$TARGET_ENV" = "blue" ] && echo "1" || echo "2")/health || echo "unhealthy")

  if echo "$HEALTH_CHECK" | grep -q '"status":"healthy"'; then
    echo "$TARGET_ENV is healthy!"
    break
  fi

  echo "Waiting for $TARGET_ENV... ($RETRY_COUNT/$MAX_RETRIES)"
  sleep 2
  RETRY_COUNT=$((RETRY_COUNT + 1))
done

if [ $RETRY_COUNT -eq $MAX_RETRIES ]; then
  echo "Error: $TARGET_ENV failed to become healthy"
  exit 1
fi

echo "Deployment complete!"
echo "To switch traffic: ./scripts/switch_environment.sh $TARGET_ENV"
```

Make it executable:

```bash
chmod +x scripts/deploy.sh
```

### Step 7: Initial Setup and Database Migration

```bash
# Start all services
docker-compose up -d

# Create database
docker-compose exec blue bundle exec rails db:create
docker-compose exec blue bundle exec rails db:migrate

# Verify both environments are running
curl http://localhost:8001/health  # Blue
curl http://localhost:8002/health  # Green
```

### Step 8: Test Blue-Green Deployment Workflow

**Test 1: Initial traffic to blue**

```bash
# Check active environment
curl http://localhost:8080/ | jq

# Output should show blue environment, v1.0
```

**Test 2: Deploy new version to green (inactive)**

```bash
# Simulate deploying v2.1 to green
./scripts/deploy.sh v2.1 green

# Verify green is running new version but not receiving traffic
curl http://localhost:8002/health | jq
```

**Test 3: Zero-downtime switch to green**

```bash
# In terminal 1: Monitor traffic continuously
while true; do
  curl -s http://localhost:8080/ | jq -r '.version + " - " + .environment'
  sleep 1
done

# In terminal 2: Switch to green
./scripts/switch_environment.sh green

# Terminal 1 should show no errors, seamless switch from v1.0 to v2.0
```

**Test 4: Rollback to blue**

```bash
# Switch back to blue
./scripts/switch_environment.sh blue

# Verify traffic is on v1.0 again
curl http://localhost:8080/ | jq
```

**Test 5: Simulate unhealthy environment**

```bash
# Stop green to make it unhealthy
docker-compose stop green

# Try to switch (should fail)
./scripts/switch_environment.sh green
# Output: "Error: green environment is not healthy!"
```

### Step 9: Monitor HAProxy Stats

Visit http://localhost:8404/stats in your browser to see:
- Active backend servers
- Health check status
- Request rates
- Error rates

### Step 10: Cleanup

```bash
# Stop all services
docker-compose down

# Remove volumes
docker-compose down -v
```

## Stretch (Optional)

1. **Add automated rollback on error detection:**

Create `scripts/auto_rollback.sh`:

```bash
#!/bin/bash
# Monitor error rate and auto-rollback if > threshold

CURRENT_ENV=$1
PREVIOUS_ENV=$2
ERROR_THRESHOLD=5  # percentage

# Monitor for 60 seconds
for i in {1..12}; do
  # Simulate checking error rate (in real scenario, check APM/logs)
  ERROR_RATE=$(curl -s http://localhost:8080/health | jq -r '.error_rate // 0')

  if [ "$ERROR_RATE" -gt "$ERROR_THRESHOLD" ]; then
    echo "ERROR RATE EXCEEDED! Rolling back to $PREVIOUS_ENV"
    ./scripts/switch_environment.sh $PREVIOUS_ENV
    exit 1
  fi

  sleep 5
done

echo "Deployment stable. No rollback needed."
```

2. **Implement database migration coordination:**

Add migration check to health endpoint:

```ruby
def check_migrations
  ActiveRecord::Migration.check_pending!
  { status: 'current', version: ActiveRecord::Migrator.current_version }
rescue ActiveRecord::PendingMigrationError
  { status: 'pending', error: 'Migrations pending' }
end
```

3. **Add smoke tests before switching:**

Create `scripts/smoke_test.sh`:

```bash
#!/bin/bash
TARGET_ENV=$1
PORT=$([ "$TARGET_ENV" = "blue" ] && echo "8001" || echo "8002")

echo "Running smoke tests against $TARGET_ENV..."

# Test 1: Health check passes
curl -f http://localhost:$PORT/health || exit 1

# Test 2: Homepage loads
curl -f http://localhost:$PORT/ || exit 1

# Test 3: Response time < 500ms
RESPONSE_TIME=$(curl -o /dev/null -s -w '%{time_total}' http://localhost:$PORT/)
if (( $(echo "$RESPONSE_TIME > 0.5" | bc -l) )); then
  echo "Response time too slow: ${RESPONSE_TIME}s"
  exit 1
fi

echo "All smoke tests passed!"
```

4. **Implement canary deployment variation:**

Modify HAProxy config to send 10% traffic to new environment:

```conf
backend active_env
    balance roundrobin
    # 90% to blue
    server blue blue:3000 check weight 90
    # 10% to green (canary)
    server green green:3000 check weight 10
```

5. **Add metrics collection:**

Instrument application to track deployment metrics:

```ruby
# config/initializers/deployment_metrics.rb
ActiveSupport::Notifications.subscribe('process_action.action_controller') do |*args|
  event = ActiveSupport::Notifications::Event.new(*args)

  # Log metrics for monitoring
  Rails.logger.info({
    event: 'request',
    version: ENV['APP_VERSION'],
    environment: ENV['ENVIRONMENT'],
    duration: event.duration,
    status: event.payload[:status]
  }.to_json)
end
```

## Solution Notes

**Common Gotchas:**

1. **HAProxy config not reloading:** Use `haproxy -sf <pid>` to gracefully reload config without dropping connections.

2. **Health checks too aggressive:** If health checks mark healthy instances as down, increase `inter` interval or reduce `fall` threshold.

3. **Database connection conflicts:** Both environments share the same database. Ensure migrations are backward compatible.

4. **Port conflicts:** Blue uses 8001, green uses 8002, load balancer uses 8080. Ensure these ports are available.

5. **Container startup timing:** Health checks may fail if probed before Rails finishes booting. Use `start_period` to allow warmup time.

**Production Considerations:**

- Use separate databases for true isolation, or use feature flags for schema changes
- Implement automated smoke tests before switching
- Set up monitoring/alerting on error rates during deployments
- Keep old environment running for several hours after switch for quick rollback
- Use infrastructure-as-code (Terraform) to provision blue/green environments
- Implement connection draining to finish in-flight requests before shutdown

**Blue-Green vs Rolling Deployment:**

| Aspect | Blue-Green | Rolling |
|--------|------------|---------|
| Infrastructure cost | 2x during switch | 1x always |
| Rollback speed | Instant | Slow (reverse update) |
| Testing before switch | Full production testing | No pre-switch testing |
| Mixed versions | Never | Temporarily |
| Best for | Critical apps, instant rollback needed | Cost-sensitive, gradual updates |

## Time Estimate
25 minutes
