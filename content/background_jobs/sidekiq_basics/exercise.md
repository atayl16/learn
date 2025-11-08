# Exercise: ActiveJob vs Sidekiq Fundamentals

## Objective
Configure Sidekiq with Redis, create jobs using both ActiveJob and Sidekiq's native API, and route them to different queues with priority settings.

## Task
In a Rails app with Redis running locally:

1. Install Sidekiq and configure Redis connection
2. Create an ActiveJob that sends a notification email
3. Create a native Sidekiq worker that generates a report
4. Configure queue priorities and start workers
5. Enqueue jobs and observe processing order

## Acceptance Criteria
- [ ] Redis connection configured in `config/initializers/sidekiq.rb`
- [ ] ActiveJob class `NotificationJob` queues to `:mailers`
- [ ] Sidekiq worker `ReportWorker` queues to `:reports` with 3 retry attempts
- [ ] Worker started with `:mailers` priority 2x higher than `:reports`
- [ ] Sidekiq web UI accessible at `/sidekiq` showing both queues
- [ ] Log output shows jobs processing in priority order

## Verification Steps

1. Start Redis:

```bash
redis-server

```

2. Check Redis is running:

```bash
redis-cli ping
# Should output: PONG

```

3. Start Sidekiq with queue priorities:

```bash
bundle exec sidekiq -q mailers,2 -q reports,1

```

4. In Rails console, enqueue jobs:

```ruby
# Enqueue 5 report jobs (slow queue)
5.times { |i| ReportWorker.perform_async(i) }

# Enqueue 3 notification jobs (fast queue)
3.times { |i| NotificationJob.perform_later(i) }

# Check queue sizes
Sidekiq::Queue.new('mailers').size  # => 3
Sidekiq::Queue.new('reports').size  # => 5

```

5. Watch Sidekiq logs - notification jobs should process first despite being enqueued second

## Setup Code

### Step 1: Install and Configure

```bash
# In Gemfile
bundle add sidekiq
bundle add redis

# Start Redis
redis-server

```

Create `config/initializers/sidekiq.rb`:

```ruby
Sidekiq.configure_server do |config|
  config.redis = { url: ENV.fetch('REDIS_URL', 'redis://localhost:6379/1') }
end

Sidekiq.configure_client do |config|
  config.redis = { url: ENV.fetch('REDIS_URL', 'redis://localhost:6379/1') }
end

```

Configure ActiveJob in `config/application.rb`:

```ruby
config.active_job.queue_adapter = :sidekiq

```

### Step 2: Create ActiveJob

```bash
bin/rails generate job Notification

```

Edit `app/jobs/notification_job.rb`:

```ruby
class NotificationJob < ApplicationJob
  queue_as :mailers

  def perform(user_id)
    Rails.logger.info "NotificationJob: Processing user #{user_id}"
    sleep 2  # Simulate email sending
    Rails.logger.info "NotificationJob: Completed user #{user_id}"
  end
end

```

### Step 3: Create Sidekiq Worker

Create `app/workers/report_worker.rb`:

```ruby
class ReportWorker
  include Sidekiq::Worker
  sidekiq_options queue: :reports, retry: 3

  def perform(report_id)
    Rails.logger.info "ReportWorker: Generating report #{report_id}"
    sleep 5  # Simulate slow report generation
    Rails.logger.info "ReportWorker: Completed report #{report_id}"
  end
end

```

### Step 4: Add Web UI (Optional)

In `config/routes.rb`:

```ruby
require 'sidekiq/web'

Rails.application.routes.draw do
  mount Sidekiq::Web => '/sidekiq'
end

```

Visit http://localhost:3000/sidekiq to see queues, jobs, and stats.

### Step 5: Test Different Enqueue Methods

In Rails console:

```ruby
# ActiveJob syntax
NotificationJob.perform_later(123)
NotificationJob.set(wait: 10.seconds).perform_later(456)

# Native Sidekiq syntax
ReportWorker.perform_async(789)
ReportWorker.perform_in(1.minute, 999)
ReportWorker.perform_at(Time.now + 5.minutes, 111)

```

## Stretch (Optional)

1. Add a third queue `:critical` with highest priority:

```ruby
class UrgentWorker
  include Sidekiq::Worker
  sidekiq_options queue: :critical, retry: 0

  def perform(alert_id)
    Rails.logger.info "URGENT: Processing alert #{alert_id}"
  end
end

```

Start worker: `bundle exec sidekiq -q critical,4 -q mailers,2 -q reports,1`

2. Monitor Redis memory usage:

```bash
redis-cli info memory | grep used_memory_human

```

Enqueue 1000 jobs and check memory increase.

## Time Estimate
18 minutes
