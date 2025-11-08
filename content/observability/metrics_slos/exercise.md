# Exercise: Metrics and SLO Thinking

## Objective
Instrument a Rails application to track RED metrics, define SLOs for error rate and latency, and create a simple dashboard showing SLO compliance.

## Task
In a Rails application:

1. Install statsd-instrument gem
2. Configure StatsD middleware to track requests
3. Create a controller that reports metrics
4. Define SLOs for error rate and P99 latency
5. Build a simple dashboard endpoint showing SLO status

## Acceptance Criteria
- [ ] statsd-instrument gem installed and configured
- [ ] Middleware tracks request rate, errors, and duration
- [ ] Dashboard shows current error rate and P99 latency
- [ ] SLO thresholds defined (error rate < 1%, P99 < 500ms)
- [ ] Dashboard indicates SLO compliance (pass/fail)
- [ ] Test endpoints demonstrate metrics collection

## Verification Steps

### Step 1: Install statsd-instrument

```bash
# Add to Gemfile
bundle add statsd-instrument

bundle install

```

### Step 2: Configure StatsD

Create `config/initializers/statsd.rb`:

```ruby
# For development, we'll use logger backend to see metrics in console
# In production, use UDP backend pointing to real StatsD server
if Rails.env.production?
  StatsD.backend = StatsD::Instrument::Backends::UDPBackend.new(
    ENV.fetch('STATSD_ADDR', 'localhost:8125')
  )
else
  # Development: log metrics to console
  StatsD.backend = StatsD::Instrument::Backends::LoggerBackend.new(Rails.logger)
end

StatsD.prefix = 'myapp'
StatsD.default_sample_rate = 1.0

```

### Step 3: Add Metrics Middleware

Edit `config/application.rb`:

```ruby
module YourApp
  class Application < Rails::Application
    # ... existing config ...

    # Track RED metrics for all requests
    config.middleware.insert_before(
      Rails::Rack::Logger,
      StatsD::Instrument::Middleware,
      StatsD.backend
    )
  end
end

```

### Step 4: Create Metrics Store

Create `app/services/metrics_store.rb`:

```ruby
class MetricsStore
  WINDOW_SIZE = 60 # Track last 60 seconds

  def self.record_request(status, duration_ms)
    @requests ||= []
    @requests << {
      status: status,
      duration_ms: duration_ms,
      timestamp: Time.current
    }

    # Clean old entries
    cutoff = Time.current - WINDOW_SIZE.seconds
    @requests.reject! { |r| r[:timestamp] < cutoff }
  end

  def self.stats
    @requests ||= []
    return default_stats if @requests.empty?

    total = @requests.size
    errors = @requests.count { |r| r[:status] >= 500 }
    error_rate = (errors.to_f / total * 100).round(2)

    durations = @requests.map { |r| r[:duration_ms] }.sort
    p99_index = [(durations.size * 0.99).ceil - 1, 0].max
    p99_latency = durations[p99_index]&.round(2) || 0

    {
      total_requests: total,
      error_count: errors,
      error_rate_percent: error_rate,
      p99_latency_ms: p99_latency,
      window_seconds: WINDOW_SIZE
    }
  end

  def self.default_stats
    {
      total_requests: 0,
      error_count: 0,
      error_rate_percent: 0.0,
      p99_latency_ms: 0.0,
      window_seconds: WINDOW_SIZE
    }
  end

  def self.reset!
    @requests = []
  end
end

```

### Step 5: Track Metrics in ApplicationController

Edit `app/controllers/application_controller.rb`:

```ruby
class ApplicationController < ActionController::Base
  around_action :track_metrics

  private

  def track_metrics
    start = Time.current
    yield
    duration_ms = (Time.current - start) * 1000

    MetricsStore.record_request(response.status, duration_ms)

    # Send to StatsD
    StatsD.increment('requests.count')
    StatsD.increment("requests.status.#{response.status}")
    StatsD.measure('requests.duration', duration_ms)

    if response.status >= 500
      StatsD.increment('requests.errors')
    end
  end
end

```

### Step 6: Create Dashboard Controller

Generate controller:

```bash
bin/rails generate controller Dashboard index

```

Edit `app/controllers/dashboard_controller.rb`:

```ruby
class DashboardController < ApplicationController
  # Define SLOs
  SLO_ERROR_RATE_PERCENT = 1.0
  SLO_P99_LATENCY_MS = 500.0

  def index
    @stats = MetricsStore.stats
    @slos = slo_status(@stats)
  end

  private

  def slo_status(stats)
    error_rate_met = stats[:error_rate_percent] <= SLO_ERROR_RATE_PERCENT
    latency_met = stats[:p99_latency_ms] <= SLO_P99_LATENCY_MS
    all_met = error_rate_met && latency_met

    {
      error_rate: {
        current: stats[:error_rate_percent],
        target: SLO_ERROR_RATE_PERCENT,
        met: error_rate_met
      },
      p99_latency: {
        current: stats[:p99_latency_ms],
        target: SLO_P99_LATENCY_MS,
        met: latency_met
      },
      all_slos_met: all_met
    }
  end
end

```

### Step 7: Create Dashboard View

Edit `app/views/dashboard/index.html.erb`:

```erb
<h1>Service Health Dashboard</h1>

<div style="padding: 20px; border: 2px solid <%= @slos[:all_slos_met] ? 'green' : 'red' %>; margin: 20px 0;">
  <h2>
    Overall Status:
    <%= @slos[:all_slos_met] ? '✓ All SLOs Met' : '✗ SLO Violation' %>
  </h2>
</div>

<h2>RED Metrics (Last <%= @stats[:window_seconds] %> seconds)</h2>

<table border="1" cellpadding="10" style="border-collapse: collapse; width: 100%;">
  <tr>
    <th>Metric</th>
    <th>Current Value</th>
    <th>SLO Target</th>
    <th>Status</th>
  </tr>

  <tr>
    <td><strong>Rate</strong></td>
    <td><%= @stats[:total_requests] %> requests</td>
    <td>-</td>
    <td>ℹ️ Info only</td>
  </tr>

  <tr style="background-color: <%= @slos[:error_rate][:met] ? '#d4edda' : '#f8d7da' %>">
    <td><strong>Errors</strong></td>
    <td>
      <%= @stats[:error_rate_percent] %>%
      (<%= @stats[:error_count] %> / <%= @stats[:total_requests] %> requests)
    </td>
    <td>&lt; <%= @slos[:error_rate][:target] %>%</td>
    <td><%= @slos[:error_rate][:met] ? '✓ Pass' : '✗ Fail' %></td>
  </tr>

  <tr style="background-color: <%= @slos[:p99_latency][:met] ? '#d4edda' : '#f8d7da' %>">
    <td><strong>Duration (P99)</strong></td>
    <td><%= @stats[:p99_latency_ms] %> ms</td>
    <td>&lt; <%= @slos[:p99_latency][:target] %> ms</td>
    <td><%= @slos[:p99_latency][:met] ? '✓ Pass' : '✗ Fail' %></td>
  </tr>
</table>

<hr>

<h3>Test Endpoints</h3>
<ul>
  <li><%= link_to 'Fast endpoint (50ms)', fast_test_path %></li>
  <li><%= link_to 'Slow endpoint (600ms)', slow_test_path %></li>
  <li><%= link_to 'Error endpoint (500)', error_test_path %></li>
  <li><%= link_to 'Reset metrics', reset_metrics_path, method: :post %></li>
</ul>

```

### Step 8: Create Test Endpoints

Edit `app/controllers/dashboard_controller.rb` (add actions):

```ruby
def fast_test
  sleep 0.05
  render plain: 'Fast response (50ms)'
end

def slow_test
  sleep 0.6
  render plain: 'Slow response (600ms)'
end

def error_test
  raise StandardError, 'Intentional error for testing'
end

def reset_metrics
  MetricsStore.reset!
  redirect_to dashboard_index_path, notice: 'Metrics reset'
end

```

Update `config/routes.rb`:

```ruby
Rails.application.routes.draw do
  get 'dashboard', to: 'dashboard#index', as: :dashboard_index
  get 'dashboard/fast', to: 'dashboard#fast_test', as: :fast_test
  get 'dashboard/slow', to: 'dashboard#slow_test', as: :slow_test
  get 'dashboard/error', to: 'dashboard#error_test', as: :error_test
  post 'dashboard/reset', to: 'dashboard#reset_metrics', as: :reset_metrics
end

```

### Step 9: Test the Dashboard

Start Rails server:

```bash
bin/rails server

```

1. Visit http://localhost:3000/dashboard
2. Should show "All SLOs Met" (no requests yet)
3. Click "Fast endpoint" 10 times
4. Return to dashboard - should still pass SLOs
5. Click "Slow endpoint" 5 times
6. Dashboard should show P99 SLO violation (>500ms)
7. Click "Error endpoint" 2 times
8. Dashboard may show error rate violation
9. Click "Reset metrics" to start over

### Step 10: Observe StatsD Logs

Check `log/development.log` for StatsD metrics:

```
[StatsD] myapp.requests.count:1|c
[StatsD] myapp.requests.status.200:1|c
[StatsD] myapp.requests.duration:52.3|ms

```

In production, these would be sent to actual StatsD server.

## Stretch (Optional)

1. Add error budget calculation:

```ruby
# In dashboard_controller.rb
def error_budget
  slo_uptime = 0.999  # 99.9%
  allowed_error_rate = 1 - slo_uptime  # 0.1%
  current_error_rate = @stats[:error_rate_percent] / 100
  budget_used = (current_error_rate / allowed_error_rate * 100).round(2)

  {
    allowed_error_rate_percent: allowed_error_rate * 100,
    budget_used_percent: budget_used,
    budget_remaining_percent: 100 - budget_used
  }
end

```

2. Add request rate (requests/sec):

```ruby
def stats
  # ... existing code ...
  rate_per_second = (total.to_f / WINDOW_SIZE).round(2)
  { rate_per_second: rate_per_second, ... }
end

```

3. Track per-endpoint metrics:

```ruby
StatsD.increment("requests.endpoint.#{controller_name}.#{action_name}")

```

## Time Estimate
15 minutes
