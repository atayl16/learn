# ActiveJob vs Sidekiq Fundamentals

## What It Is
Sidekiq is a Ruby background job processor using Redis for queue storage and multi-threaded workers for job execution. ActiveJob is Rails' abstraction layer that provides a common interface across multiple backend adapters (Sidekiq, Resque, DelayedJob), allowing you to switch queue systems without changing job code.

## Why It Matters
Background jobs move slow operations (email sending, API calls, report generation) out of the request-response cycle, keeping web responses fast. Understanding the trade-offs between ActiveJob's portability and Sidekiq's native features determines when to use abstraction versus direct integration. Redis configuration and worker concurrency directly impact throughput and memory usage in production.

## When to Use
- Move email delivery, file uploads, or external API calls outside HTTP requests
- Process large datasets or reports asynchronously
- Schedule recurring tasks like cache warming or data cleanup
- Implement retry logic for unreliable third-party integrations
- Distribute workload across multiple worker processes

## Three Common Pitfalls
1. **Passing ActiveRecord objects to jobs:** Serializes the object state, not the ID. If the record changes before the job runs, you process stale data. Pass IDs instead and fetch fresh records in the job.
2. **Underestimating Redis memory needs:** Each queued job consumes Redis memory. A million jobs at 1KB each = 1GB. Monitor Redis memory and set maxmemory policies to prevent OOM crashes.
3. **Ignoring queue priority and concurrency:** All jobs in the default queue share worker threads. Slow jobs (report generation) block fast ones (password resets). Use separate queues with dedicated workers.

---

## ActiveJob Abstraction Layer

ActiveJob provides a backend-agnostic API:

```ruby
# app/jobs/email_notification_job.rb
class EmailNotificationJob < ApplicationJob
  queue_as :default

  def perform(user_id)
    user = User.find(user_id)
    UserMailer.welcome_email(user).deliver_now
  end
end

# Enqueue from anywhere
EmailNotificationJob.perform_later(user.id)
```

Configure the adapter in `config/application.rb`:

```ruby
config.active_job.queue_adapter = :sidekiq
```

Switching to Resque or DelayedJob requires changing one line. Jobs remain unchanged.

---

## Sidekiq Direct Usage

Use Sidekiq's native API for advanced features (batches, scheduled sets, unique jobs):

```ruby
# app/workers/report_generator.rb
class ReportGenerator
  include Sidekiq::Worker
  sidekiq_options queue: :reports, retry: 5

  def perform(report_id)
    report = Report.find(report_id)
    report.generate_pdf
    report.update(status: 'completed')
  end
end

# Enqueue
ReportGenerator.perform_async(report.id)

# Schedule for later
ReportGenerator.perform_in(1.hour, report.id)
ReportGenerator.perform_at(Time.now + 2.hours, report.id)
```

Direct usage unlocks Sidekiq-specific options: batch processing, unique jobs, pro features.

---

## Redis Configuration

Sidekiq stores queues and job data in Redis:

```ruby
# config/initializers/sidekiq.rb
Sidekiq.configure_server do |config|
  config.redis = { url: ENV['REDIS_URL'] || 'redis://localhost:6379/0' }
end

Sidekiq.configure_client do |config|
  config.redis = { url: ENV['REDIS_URL'] || 'redis://localhost:6379/0' }
end
```

**Client vs Server:**
- Client: Rails app enqueueing jobs (needs connection pool)
- Server: Sidekiq process running workers (needs larger pool)

**Connection pool sizing:**
```ruby
# Server: pool size = concurrency + 5 (default: 10)
config.redis = { url: 'redis://localhost:6379/0', size: 15 }
```

---

## Queues and Priorities

Route jobs to specific queues:

```ruby
class EmailNotificationJob < ApplicationJob
  queue_as :mailers
end

class ReportGeneratorJob < ApplicationJob
  queue_as :reports
end
```

Start workers with queue priorities:

```bash
# Process :critical 4x more than :default, 8x more than :low
bundle exec sidekiq -q critical,4 -q default,2 -q low,1
```

Or use dedicated worker processes:

```bash
# Terminal 1: Fast jobs only
bundle exec sidekiq -q mailers -q critical -c 10

# Terminal 2: Slow jobs with limited concurrency
bundle exec sidekiq -q reports -c 2
```

---

## Worker Concurrency

Sidekiq runs jobs in threads within a process:

```bash
# Default: 10 threads
bundle exec sidekiq

# High throughput: 25 threads (requires more memory)
bundle exec sidekiq -c 25

# Low memory: 5 threads
bundle exec sidekiq -c 5
```

**Thread safety requirement:** Jobs must be thread-safe. Avoid shared mutable state, use connection pools for databases/Redis.

**Memory calculation:**
- Base Sidekiq process: ~50MB
- Each thread: +10-50MB (depends on job complexity)
- 25 threads: ~300-500MB per worker process

---

## Trade-offs Box
- **Advantage:** ActiveJob lets you switch queue backends (Sidekiq to Resque) without changing job code; Sidekiq's native API exposes advanced features like batches and unique jobs.
- **Cost:** ActiveJob adds abstraction overhead and hides Sidekiq-specific features; direct Sidekiq usage locks you into one backend.
- **When to skip:** For simple apps with <100 jobs/day, consider DelayedJob (no Redis dependency) or inline processing (no background jobs).

---

## Debugging Checklist

When jobs aren't processing:

1. Check Redis connection: `redis-cli ping` returns `PONG`
2. Verify Sidekiq process is running: `ps aux | grep sidekiq`
3. Check queue names match: `Sidekiq::Queue.all.map(&:name)` in Rails console
4. Inspect queued jobs: `Sidekiq::Queue.new('default').size`
5. Review Sidekiq logs: `tail -f log/sidekiq.log`
6. Check Redis memory: `redis-cli info memory | grep used_memory_human`
7. Verify worker concurrency setting: `-c` flag matches workload
8. Inspect dead jobs: `Sidekiq::DeadSet.new.size`

---

## One-Minute Recap
- ActiveJob abstracts queue backends; Sidekiq provides the fastest, most feature-rich implementation
- Pass record IDs to jobs, not ActiveRecord objects
- Configure Redis connection pools: client for Rails app, server for Sidekiq workers
- Route jobs to queues, assign priorities, and tune concurrency per queue
- Sidekiq uses threads (not processes), requiring thread-safe code
