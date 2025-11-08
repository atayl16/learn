# Exercise: Job Instrumentation & Backoff

## Objective
Implement comprehensive job instrumentation with structured logging, track metrics using middleware, configure custom exponential backoff, and monitor job lifecycle events.

## Task
Build an instrumented API integration job that:

1. Logs execution with structured tags (job class, user ID, request ID)
2. Tracks success/failure metrics and job duration
3. Implements custom backoff: exponential for timeouts, longer delays for rate limits
4. Uses middleware to measure queue latency
5. Alerts when jobs exhaust retries

## Acceptance Criteria
- [ ] `ApiCallWorker` logs with structured tags including user_id and job_id
- [ ] Sidekiq middleware tracks metrics (success count, failure count, duration)
- [ ] Custom `sidekiq_retry_in` implements different backoff for timeout vs rate limit errors
- [ ] `sidekiq_retries_exhausted` callback logs and increments alert counter
- [ ] Queue latency middleware measures time from enqueue to execution
- [ ] Logs show job start, success/failure, duration, and retry count
- [ ] Simulated failures trigger appropriate backoff delays

## Verification Steps

1. Start Sidekiq and enqueue a successful job:

```ruby
ApiCallWorker.perform_async(123, 'https://api.example.com/data')

```

Check logs for:

```
[ApiCallWorker] [user:123] [jid:abc123] Starting API call
[ApiCallWorker] [user:123] [jid:abc123] Completed successfully in 1.23s
Metric: background_job.success job:ApiCallWorker

```

2. Simulate timeout error:

```ruby
ENV['SIMULATE_TIMEOUT'] = 'true'
ApiCallWorker.perform_async(456, 'https://slow-api.example.com')

```

Verify exponential backoff in retry schedule.

3. Check middleware metrics in logs:

```
Queue latency: default - 0.05s
Job duration: ApiCallWorker - 1234ms

```

## Setup Code

### Step 1: Create Metrics Helper

Create `lib/metrics.rb`:

```ruby
module Metrics
  def self.increment(metric_name, tags: [])
    tag_str = tags.join(' ')
    Rails.logger.info "Metric: #{metric_name} #{tag_str}"

    # In production, send to actual metrics service:
    # StatsD.increment(metric_name, tags: tags)
  end

  def self.histogram(metric_name, value, tags: [])
    tag_str = tags.join(' ')
    Rails.logger.info "Metric: #{metric_name}=#{value} #{tag_str}"

    # In production:
    # StatsD.histogram(metric_name, value, tags: tags)
  end

  def self.gauge(metric_name, value, tags: [])
    tag_str = tags.join(' ')
    Rails.logger.info "Metric: #{metric_name}=#{value} #{tag_str}"

    # In production:
    # StatsD.gauge(metric_name, value, tags: tags)
  end
end

```

### Step 2: Create Instrumentation Middleware

Create `app/middleware/job_instrumentation_middleware.rb`:

```ruby
class JobInstrumentationMiddleware
  def call(worker, job, queue)
    job_class = job['class']
    job_id = job['jid']
    enqueued_at = job['enqueued_at'] || job['created_at']

    # Measure queue latency
    queue_latency = Time.now.to_f - enqueued_at.to_f
    Metrics.histogram('sidekiq.queue.latency', queue_latency, tags: ["queue:#{queue}"])

    Rails.logger.info "Queue latency: #{queue} - #{queue_latency.round(2)}s"

    start_time = Time.current

    yield  # Execute job

    # Success path
    duration = (Time.current - start_time) * 1000  # milliseconds
    Rails.logger.info "Job succeeded: #{job_class} [#{job_id}] in #{duration.round(0)}ms"

    Metrics.increment('background_job.success', tags: ["job:#{job_class}"])
    Metrics.histogram('background_job.duration', duration, tags: ["job:#{job_class}"])

  rescue StandardError => e
    duration = (Time.current - start_time) * 1000
    error_class = e.class.name

    Rails.logger.error "Job failed: #{job_class} [#{job_id}] after #{duration.round(0)}ms - #{error_class}: #{e.message}"

    Metrics.increment('background_job.failure', tags: ["job:#{job_class}", "error:#{error_class}"])
    Metrics.histogram('background_job.duration', duration, tags: ["job:#{job_class}", "status:failure"])

    raise  # Re-raise for retry
  end
end

```

Configure in `config/initializers/sidekiq.rb`:

```ruby
Sidekiq.configure_server do |config|
  config.redis = { url: ENV.fetch('REDIS_URL', 'redis://localhost:6379/1') }

  config.server_middleware do |chain|
    chain.add JobInstrumentationMiddleware
  end
end

Sidekiq.configure_client do |config|
  config.redis = { url: ENV.fetch('REDIS_URL', 'redis://localhost:6379/1') }
end

```

### Step 3: Create Worker with Custom Backoff

Create `app/workers/api_call_worker.rb`:

```ruby
class ApiCallWorker
  include Sidekiq::Worker
  sidekiq_options queue: :api_calls, retry: 8

  def perform(user_id, endpoint)
    Rails.logger.tagged('ApiCallWorker', "user:#{user_id}", "jid:#{jid}") do
      Rails.logger.info "Starting API call to #{endpoint}"

      response = make_api_call(endpoint)

      Rails.logger.info "Completed successfully: #{response.code}"
    end
  end

  sidekiq_retry_in do |count, exception|
    Rails.logger.warn "Retry attempt #{count} due to #{exception.class.name}"

    case exception
    when Net::ReadTimeout, Net::OpenTimeout, Timeout::Error
      # Exponential backoff: 60s, 240s, 540s, 960s...
      delay = (count ** 2) * 60
      Rails.logger.info "Timeout error, retrying in #{delay}s"
      delay

    when RateLimitError
      # Longer backoff for rate limits: 5min, 10min, 20min, 40min...
      delay = (2 ** count) * 5.minutes.to_i
      Rails.logger.info "Rate limit error, retrying in #{delay}s"
      delay

    when ApiServerError
      # Medium backoff: 2min, 4min, 8min...
      delay = (2 ** count) * 2.minutes.to_i
      Rails.logger.info "Server error, retrying in #{delay}s"
      delay

    else
      # Use default Sidekiq backoff
      nil
    end
  end

  sidekiq_retries_exhausted do |job, exception|
    user_id = job['args'].first
    endpoint = job['args'].last

    Rails.logger.error "ALERT: ApiCallWorker exhausted retries for user #{user_id}, endpoint #{endpoint}"
    Rails.logger.error "Final error: #{exception.class.name} - #{exception.message}"

    # Increment alert metric
    Metrics.increment('background_job.exhausted', tags: ["job:ApiCallWorker", "error:#{exception.class.name}"])

    # In production, trigger PagerDuty or Slack alert
    # AlertService.notify(
    #   title: 'Background job failed permanently',
    #   details: { job: job, error: exception.message }
    # )
  end

  private

  def make_api_call(endpoint)
    # Simulate different error scenarios
    if ENV['SIMULATE_TIMEOUT'] == 'true'
      sleep 2
      raise Net::ReadTimeout, 'Request timeout after 2s'
    end

    if ENV['SIMULATE_RATE_LIMIT'] == 'true'
      raise RateLimitError, 'Rate limit exceeded: 429 Too Many Requests'
    end

    if ENV['SIMULATE_SERVER_ERROR'] == 'true'
      raise ApiServerError, '500 Internal Server Error'
    end

    # Successful response
    OpenStruct.new(code: 200, body: '{"status": "ok"}')
  end

  class RateLimitError < StandardError; end
  class ApiServerError < StandardError; end
end

```

### Step 4: Create Model for Context

```bash
bin/rails generate model User email:string
bin/rails db:migrate

```

In Rails console:

```ruby
User.create!(email: 'test@example.com')

```

### Step 5: Test Successful Job

```ruby
# Clear environment variables
ENV.delete('SIMULATE_TIMEOUT')
ENV.delete('SIMULATE_RATE_LIMIT')
ENV.delete('SIMULATE_SERVER_ERROR')

# Enqueue job
user = User.first
ApiCallWorker.perform_async(user.id, 'https://api.example.com/data')

```

Expected log output:

```
Queue latency: api_calls - 0.05s
[ApiCallWorker] [user:1] [jid:abc123] Starting API call to https://api.example.com/data
[ApiCallWorker] [user:1] [jid:abc123] Completed successfully: 200
Job succeeded: ApiCallWorker [abc123] in 45ms
Metric: background_job.success job:ApiCallWorker
Metric: background_job.duration=45 job:ApiCallWorker

```

### Step 6: Test Timeout Error with Backoff

```ruby
ENV['SIMULATE_TIMEOUT'] = 'true'
ApiCallWorker.perform_async(user.id, 'https://slow-api.example.com')

```

Watch logs for retry scheduling:

```
Job failed: ApiCallWorker [xyz789] after 2005ms - Net::ReadTimeout: Request timeout
Retry attempt 0 due to Net::ReadTimeout
Timeout error, retrying in 60s

```

Check retry set:

```ruby
retry_job = Sidekiq::RetrySet.new.first
retry_job['retry_count']  # => 0, 1, 2...
retry_job['error_class']   # => "Net::ReadTimeout"
Time.at(retry_job['at'])   # Next retry time

```

### Step 7: Test Rate Limit Error

```ruby
ENV.delete('SIMULATE_TIMEOUT')
ENV['SIMULATE_RATE_LIMIT'] = 'true'
ApiCallWorker.perform_async(user.id, 'https://api.example.com/limited')

```

Verify longer backoff in logs:

```
Retry attempt 0 due to RateLimitError
Rate limit error, retrying in 300s  # 5 minutes

```

### Step 8: Force Exhaustion (Optional)

Set low retry count for testing:

```ruby
# Temporarily in worker
sidekiq_options retry: 2

ENV['SIMULATE_SERVER_ERROR'] = 'true'
ApiCallWorker.perform_async(user.id, 'https://broken-api.example.com')

# Wait for retries to exhaust, check logs
# Should see: ALERT: ApiCallWorker exhausted retries
# Metric: background_job.exhausted job:ApiCallWorker error:ApiServerError

```

### Step 9: Monitor Queue Depth

Create monitoring task `lib/tasks/sidekiq_monitor.rake`:

```ruby
namespace :sidekiq do
  desc "Report queue statistics"
  task stats: :environment do
    queues = Sidekiq::Queue.all

    puts "\n=== Queue Statistics ==="
    queues.each do |queue|
      puts "#{queue.name}: #{queue.size} jobs"
      Metrics.gauge('sidekiq.queue.depth', queue.size, tags: ["queue:#{queue.name}"])
    end

    retry_count = Sidekiq::RetrySet.new.size
    puts "Retrying: #{retry_count} jobs"
    Metrics.gauge('sidekiq.retrying', retry_count)

    dead_count = Sidekiq::DeadSet.new.size
    puts "Dead: #{dead_count} jobs"
    Metrics.gauge('sidekiq.dead', dead_count)
  end
end

```

Run: `bundle exec rake sidekiq:stats`

## Stretch (Optional)

1. Add request ID tracking from Rails controller:

```ruby
# In controller
request_id = request.request_id
ApiCallWorker.perform_async(user.id, endpoint, request_id)

# In worker
def perform(user_id, endpoint, request_id = nil)
  RequestStore.store[:request_id] = request_id
  Rails.logger.tagged("request:#{request_id}") do
    # ... existing code
  end
end

```

2. Implement circuit breaker that stops enqueueing after 10 consecutive failures

3. Create a Rake task that analyzes dead jobs by error class:

```ruby
task dead_analysis: :environment do
  dead_set = Sidekiq::DeadSet.new
  errors = Hash.new(0)

  dead_set.each do |job|
    errors[job.item['error_class']] += 1
  end

  puts "\n=== Dead Job Analysis ==="
  errors.sort_by { |_, count| -count }.each do |error_class, count|
    puts "#{error_class}: #{count} jobs"
  end
end

```

## Time Estimate
25 minutes
