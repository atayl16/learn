# Exercise: Job Scheduling & Deduplication

## Objective
Configure recurring jobs with sidekiq-cron, implement delayed one-time jobs, prevent duplicates with sidekiq-unique-jobs, and pass safe arguments.

## Task
Build a subscription management system that:

1. Schedules recurring daily cleanup of expired trials (sidekiq-cron)
2. Sends trial expiration reminders 3 days before end date (delayed job)
3. Prevents duplicate reminder jobs using sidekiq-unique-jobs
4. Demonstrates safe argument passing (IDs, not objects)

## Acceptance Criteria
- [ ] sidekiq-cron configured with a daily cleanup job running at 3 AM UTC
- [ ] `TrialReminderWorker` schedules delayed job 3 days before trial ends
- [ ] Duplicate reminder jobs are rejected (same user_id = same lock)
- [ ] Worker accepts only `user_id` (integer), fetches User in `perform`
- [ ] Cron job list visible in Sidekiq web UI at `/sidekiq/cron`
- [ ] Scheduled jobs appear in Sidekiq scheduled set
- [ ] Logs show unique job conflicts when duplicates are attempted

## Verification Steps

1. Check cron jobs loaded:
```ruby
Sidekiq::Cron::Job.all.each { |job| puts "#{job.name}: #{job.cron}" }
# Should show: cleanup_expired_trials: 0 3 * * *
```

2. Schedule a reminder and verify it's unique:
```ruby
user = User.create!(email: 'test@example.com', trial_end_date: 5.days.from_now)

# Enqueue once
TrialReminderWorker.perform_at(user.trial_end_date - 3.days, user.id)

# Try to enqueue duplicate
TrialReminderWorker.perform_at(user.trial_end_date - 3.days, user.id)

# Check scheduled set - should only have 1 job
Sidekiq::ScheduledSet.new.select { |j| j.klass == 'TrialReminderWorker' }.size  # => 1
```

3. Check logs for uniqueness conflict message

## Setup Code

### Step 1: Install Gems

```ruby
# Gemfile
gem 'sidekiq-cron'
gem 'sidekiq-unique-jobs'
```

Run:
```bash
bundle install
```

### Step 2: Configure Sidekiq

Edit `config/initializers/sidekiq.rb`:
```ruby
require 'sidekiq/cron/web'
require 'sidekiq-unique-jobs/web'

Sidekiq.configure_server do |config|
  config.redis = { url: ENV.fetch('REDIS_URL', 'redis://localhost:6379/1') }

  # Load cron schedule
  schedule_file = 'config/schedule.yml'
  if File.exist?(schedule_file)
    schedule = YAML.load_file(schedule_file)
    Sidekiq::Cron::Job.load_from_hash(schedule)
  end
end

Sidekiq.configure_client do |config|
  config.redis = { url: ENV.fetch('REDIS_URL', 'redis://localhost:6379/1') }
end

SidekiqUniqueJobs.configure do |config|
  config.enabled = true
end
```

### Step 3: Create Schedule Configuration

Create `config/schedule.yml`:
```yaml
cleanup_expired_trials:
  cron: "0 3 * * *"  # Daily at 3 AM UTC
  class: "CleanupExpiredTrialsWorker"
  queue: maintenance
  description: "Remove expired trial users and send final notifications"

cache_warmer:
  cron: "*/30 * * * *"  # Every 30 minutes
  class: "CacheWarmerWorker"
  queue: maintenance
  description: "Warm frequently accessed caches"
```

### Step 4: Create User Model

```bash
bin/rails generate model User email:string trial_end_date:datetime subscription_active:boolean
```

Edit migration to add defaults:
```ruby
class CreateUsers < ActiveRecord::Migration[7.0]
  def change
    create_table :users do |t|
      t.string :email, null: false
      t.datetime :trial_end_date
      t.boolean :subscription_active, default: false
      t.timestamps
    end

    add_index :users, :email, unique: true
    add_index :users, :trial_end_date
  end
end
```

Run:
```bash
bin/rails db:migrate
```

### Step 5: Create Recurring Cleanup Worker

Create `app/workers/cleanup_expired_trials_worker.rb`:
```ruby
class CleanupExpiredTrialsWorker
  include Sidekiq::Worker
  sidekiq_options queue: :maintenance, retry: 3

  def perform
    Rails.logger.info "Starting trial cleanup at #{Time.current}"

    expired_count = 0
    User.where('trial_end_date < ?', Time.current)
        .where(subscription_active: false)
        .find_each do |user|
      Rails.logger.info "Cleaning up expired trial for user #{user.id}"
      user.destroy
      expired_count += 1
    end

    Rails.logger.info "Cleaned up #{expired_count} expired trials"
  end
end
```

### Step 6: Create Unique Delayed Worker

Create `app/workers/trial_reminder_worker.rb`:
```ruby
class TrialReminderWorker
  include Sidekiq::Worker
  sidekiq_options queue: :notifications,
                  lock: :until_executed,
                  on_conflict: :log

  def perform(user_id)
    user = User.find(user_id)

    # Skip if already subscribed
    if user.subscription_active
      Rails.logger.info "User #{user_id} already subscribed, skipping reminder"
      return
    end

    # Send reminder email
    Rails.logger.info "Sending trial reminder to #{user.email} (ends: #{user.trial_end_date})"
    # TrialMailer.expiration_reminder(user).deliver_now

  rescue ActiveRecord::RecordNotFound
    Rails.logger.warn "User #{user_id} not found, skipping reminder"
  end
end
```

### Step 7: Create Cache Warmer (Bonus Cron Job)

Create `app/workers/cache_warmer_worker.rb`:
```ruby
class CacheWarmerWorker
  include Sidekiq::Worker
  sidekiq_options queue: :maintenance, retry: 2

  def perform
    Rails.logger.info "Warming caches at #{Time.current}"

    # Warm popular queries
    Rails.cache.fetch('active_users_count', expires_in: 1.hour) do
      User.where(subscription_active: true).count
    end

    Rails.logger.info "Cache warming completed"
  end
end
```

### Step 8: Helper to Schedule Reminders

Add to `app/models/user.rb`:
```ruby
class User < ApplicationRecord
  after_create :schedule_trial_reminder

  private

  def schedule_trial_reminder
    return unless trial_end_date.present?
    return if subscription_active?

    reminder_time = trial_end_date - 3.days

    if reminder_time > Time.current
      TrialReminderWorker.perform_at(reminder_time, id)
      Rails.logger.info "Scheduled trial reminder for user #{id} at #{reminder_time}"
    end
  end
end
```

### Step 9: Test in Console

```ruby
# Create user with trial
user = User.create!(
  email: 'test@example.com',
  trial_end_date: 5.days.from_now
)

# Verify reminder scheduled
Sidekiq::ScheduledSet.new.each do |job|
  if job.klass == 'TrialReminderWorker'
    puts "Scheduled: #{job.display_class} at #{job.at}"
    puts "Args: #{job.args}"
  end
end

# Try to schedule duplicate (should be rejected)
TrialReminderWorker.perform_at(user.trial_end_date - 3.days, user.id)
# Check logs for "Duplicate" message

# Verify cron jobs
Sidekiq::Cron::Job.all.each do |job|
  puts "#{job.name}: next run at #{job.last_enqueue_time}"
end

# Manually trigger cron job for testing
CleanupExpiredTrialsWorker.perform_async
```

### Step 10: Access Web UI

Add to `config/routes.rb`:
```ruby
require 'sidekiq/web'
require 'sidekiq/cron/web'

Rails.application.routes.draw do
  mount Sidekiq::Web => '/sidekiq'
end
```

Visit:
- http://localhost:3000/sidekiq — Main dashboard
- http://localhost:3000/sidekiq/cron — Cron jobs list
- http://localhost:3000/sidekiq/scheduled — Scheduled (delayed) jobs

## Stretch (Optional)

1. Add timezone-aware scheduling:

```ruby
# Schedule at 9 AM in user's timezone
user_timezone = ActiveSupport::TimeZone['America/Los_Angeles']
send_time = user_timezone.parse('9:00 AM tomorrow')
NotificationWorker.perform_at(send_time, user.id)
```

2. Implement custom uniqueness key (ignore trial_end_date changes):

```ruby
class TrialReminderWorker
  # ...
  def self.lock_args(args)
    # Only user_id matters for lock (ignore other args)
    [args.first]
  end
end
```

## Time Estimate
22 minutes
