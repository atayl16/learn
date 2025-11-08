# Job Instrumentation & Backoff

## What It Is
Job instrumentation captures execution data—start time, duration, arguments, errors—through logging and metrics. Metrics track success rates, queue latency, and retry counts for monitoring dashboards (Datadog, Prometheus). Custom backoff strategies control retry timing based on error types or attempt count. Lifecycle hooks (middleware, callbacks) inject instrumentation at job start, success, failure, and retry events.

## Why It Matters
Production background jobs fail silently without instrumentation. You discover broken payment processing days later when customers complain. Metrics reveal queue backlogs before they cause outages. Custom backoff prevents retry storms: hitting rate-limited APIs every 15 seconds makes things worse; waiting 5 minutes gives systems time to recover. Structured logging enables searching for specific job failures across millions of log lines.

## When to Use
- Production monitoring: alert on job failure rates > 5%, queue depth > 1000
- Performance tracking: measure P95 job duration, identify slow jobs
- Debugging: trace specific job execution with request IDs and user context
- Rate limiting: implement exponential backoff for third-party API calls
- Business metrics: count successful payments, sent emails, generated reports

## Three Common Pitfalls
1. **Logging job arguments with sensitive data:** Job args appear in logs and Sidekiq web UI. Logging `charge_card(card_number, cvv)` exposes PINs. Log IDs only: `charge_card(payment_id)` and fetch details in the job.
2. **No metric differentiation by error type:** Grouping all failures together hides root causes. `ApiRateLimitError` needing backoff looks identical to `RecordNotFound` that won't fix itself. Tag metrics with error class.
3. **Fixed retry delays for rate-limited APIs:** Retrying every 15 seconds when you're rate-limited wastes retries and blocks other jobs. Use `sidekiq_retry_in` to wait 5-30 minutes based on error type and attempt count.

---

## Structured Logging

Add context to logs for filtering and searching:

```ruby
class ReportGeneratorWorker
  include Sidekiq::Worker

  def perform(user_id, report_type)
    Rails.logger.tagged("ReportGenerator", "user:#{user_id}", "type:#{report_type}") do
      Rails.logger.info "Starting report generation"

      user = User.find(user_id)
      report = generate_report(user, report_type)

      Rails.logger.info "Report generated successfully: #{report.id}"
    end
  rescue StandardError => e
    Rails.logger.error "Report generation failed: #{e.message}"
    raise
  end
end
```

**Log output:**
```
[ReportGenerator] [user:123] [type:monthly] Starting report generation
[ReportGenerator] [user:123] [type:monthly] Report generated successfully: 456
```

Search logs: `grep "user:123" log/sidekiq.log`

---

## Job Lifecycle Metrics

Track job execution with ActiveSupport::Notifications:

```ruby
# config/initializers/sidekiq_instrumentation.rb
ActiveSupport::Notifications.subscribe('perform.active_job') do |name, start, finish, id, payload|
  job_name = payload[:job].class.name
  duration = (finish - start) * 1000  # Convert to milliseconds

  if payload[:exception_object]
    # Job failed
    error_class = payload[:exception_object].class.name
    Rails.logger.error "Job failed: #{job_name} (#{duration}ms) - #{error_class}"

    # Send metric to monitoring service
    StatsD.increment('sidekiq.job.failed', tags: ["job:#{job_name}", "error:#{error_class}"])
  else
    # Job succeeded
    Rails.logger.info "Job succeeded: #{job_name} (#{duration}ms)"

    StatsD.increment('sidekiq.job.success', tags: ["job:#{job_name}"])
    StatsD.histogram('sidekiq.job.duration', duration, tags: ["job:#{job_name}"])
  end
end
```

Metrics exposed:
- `sidekiq.job.success` (count)
- `sidekiq.job.failed` (count) with error class tag
- `sidekiq.job.duration` (histogram) for P50/P95/P99

---

## Sidekiq Middleware

Middleware wraps every job execution:

```ruby
# app/middleware/job_metrics_middleware.rb
class JobMetricsMiddleware
  def call(worker, job, queue)
    start_time = Time.current
    job_class = job['class']

    Rails.logger.info "Job started: #{job_class} [#{job['jid']}]"

    yield  # Execute the job

    duration = Time.current - start_time
    Rails.logger.info "Job completed: #{job_class} in #{duration.round(2)}s"

    # Record success metric
    track_metric('success', job_class, duration)

  rescue StandardError => e
    duration = Time.current - start_time
    Rails.logger.error "Job failed: #{job_class} - #{e.class.name}: #{e.message}"

    # Record failure metric
    track_metric('failure', job_class, duration, e.class.name)

    raise  # Re-raise to trigger retry
  end

  private

  def track_metric(status, job_class, duration, error_class = nil)
    tags = ["job:#{job_class}", "status:#{status}"]
    tags << "error:#{error_class}" if error_class

    # Assuming Datadog statsd client
    StatsD.increment('background_job.executed', tags: tags)
    StatsD.histogram('background_job.duration', duration, tags: tags)
  end
end

# config/initializers/sidekiq.rb
Sidekiq.configure_server do |config|
  config.server_middleware do |chain|
    chain.add JobMetricsMiddleware
  end
end
```

Middleware runs for every job, providing centralized instrumentation.

---

## Custom Backoff Strategies

Implement exponential backoff with jitter:

```ruby
class ApiWorker
  include Sidekiq::Worker
  sidekiq_options retry: 10

  def perform(endpoint)
    response = HTTParty.get(endpoint, timeout: 10)
    # Process response
  end

  sidekiq_retry_in do |count, exception|
    case exception
    when Net::ReadTimeout, Net::OpenTimeout
      # Exponential: 1min, 4min, 9min, 16min...
      (count ** 2) * 60
    when RateLimitError
      # Longer backoff for rate limits: 5, 10, 20, 40 minutes
      (2 ** count) * 5.minutes.to_i
    when Errno::ECONNREFUSED
      # Fixed delay for connection refused
      2.minutes.to_i
    else
      # Default Sidekiq backoff
      nil
    end
  end

  sidekiq_retries_exhausted do |job, exception|
    Rails.logger.error "ApiWorker exhausted retries: #{job['args']} - #{exception.message}"

    # Alert on-call engineer
    PagerDuty.trigger(
      service_key: ENV['PAGERDUTY_KEY'],
      description: "ApiWorker failed permanently for #{job['args']}",
      details: { job: job, error: exception.message }
    )
  end

  class RateLimitError < StandardError; end
end
```

**Backoff patterns:**
- **Linear:** `count * 60` (1min, 2min, 3min...)
- **Exponential:** `(count ** 2) * 60` (1min, 4min, 9min, 16min...)
- **Exponential with base:** `(2 ** count) * 60` (1min, 2min, 4min, 8min, 16min...)
- **Jitter:** Add randomness to prevent thundering herd: `((count ** 2) * 60) + rand(30)`

---

## Queue Latency Monitoring

Track how long jobs wait before execution:

```ruby
# app/middleware/queue_latency_middleware.rb
class QueueLatencyMiddleware
  def call(worker, job, queue)
    enqueued_at = job['enqueued_at'] || job['created_at']
    latency = Time.now.to_f - enqueued_at.to_f

    StatsD.histogram('sidekiq.queue.latency', latency, tags: ["queue:#{queue}"])

    if latency > 300  # 5 minutes
      Rails.logger.warn "High queue latency: #{queue} - #{latency.round(2)}s"
    end

    yield
  end
end

Sidekiq.configure_server do |config|
  config.server_middleware do |chain|
    chain.add QueueLatencyMiddleware
  end
end
```

Alert when latency exceeds thresholds (queue backlog).

---

## Success/Failure Rate Dashboards

Track job health with cumulative metrics:

```ruby
# app/workers/monitored_worker.rb
module MonitoredWorker
  extend ActiveSupport::Concern

  included do
    after_perform :track_success
  end

  def track_success
    StatsD.increment("#{self.class.name.underscore}.success")
  end

  def self.track_failure(exception, job)
    job_class = job['class'].underscore
    error_class = exception.class.name

    StatsD.increment("#{job_class}.failure", tags: ["error:#{error_class}"])
  end
end

# Usage
class EmailWorker
  include Sidekiq::Worker
  include MonitoredWorker

  def perform(user_id)
    # Send email
  end
end
```

Dashboard queries (Datadog example):
- Success rate: `sum(email_worker.success) / (sum(email_worker.success) + sum(email_worker.failure))`
- Failure count by error: `sum(*.failure) by error`

---

## Trade-offs Box
- **Advantage:** Instrumentation reveals silent failures; metrics enable proactive alerts; custom backoff prevents retry storms and API bans.
- **Cost:** Logging adds 1-5ms per job; metrics require external services (Datadog, StatsD); complex backoff logic increases debugging difficulty.
- **When to skip:** For low-stakes jobs (cache warming, analytics), basic logging suffices; skip metrics if job volume < 1000/day.

---

## Debugging Checklist

When jobs fail without clear cause:

1. Check job logs: `grep "job_class" log/sidekiq.log | grep ERROR`
2. Review retry count: `Sidekiq::RetrySet.new.first['retry_count']`
3. Inspect error message: `Sidekiq::RetrySet.new.first['error_message']`
4. Verify backoff timing: check `sidekiq_retry_in` logic for edge cases
5. Check queue latency: compare `enqueued_at` to `started_at`
6. Review metrics dashboard: correlate failure spikes with deployments or outages
7. Search for similar failures: `grep "error_class" log/* | wc -l`
8. Validate instrumentation hooks: ensure middleware runs for all queues

---

## One-Minute Recap
- Structured logging with tags (user ID, job class) enables filtering and debugging
- Sidekiq middleware wraps every job for centralized metrics and instrumentation
- Custom backoff strategies (exponential, jitter) prevent retry storms for rate-limited APIs
- Track success/failure rates, queue latency, and duration in monitoring dashboards
- Use `sidekiq_retries_exhausted` to alert or log when jobs permanently fail
