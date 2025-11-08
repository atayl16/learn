# Job Scheduling & Deduplication

## What It Is
Job scheduling runs tasks at specific times or intervals using cron-like syntax (sidekiq-cron) or one-time delays (perform_in/perform_at). Deduplication prevents multiple instances of the same job from queuing or executing simultaneously using sidekiq-unique-jobs. Safe context passing means serializing primitives (IDs, strings, numbers) instead of ActiveRecord objects.

## Why It Matters
Production systems need recurring tasks: cache warming, report generation, subscription renewals, cleanup jobs. Without scheduling, you rely on external cron or manual triggers. Without deduplication, rapid user clicks or automated systems queue thousands of duplicate jobs, wasting resources and causing race conditions. Passing objects instead of IDs leads to stale data and serialization errors.

## When to Use
- Recurring tasks: daily reports, hourly cache refreshes, nightly database cleanup
- Delayed actions: send email 24 hours after signup, cancel unpaid orders after 15 minutes
- Prevent duplicates: user spamming "generate report" button, webhooks firing multiple times
- Time-based campaigns: schedule promotional emails for specific dates
- Rate limiting: ensure only one instance of a job runs at a time

## Three Common Pitfalls
1. **Passing ActiveRecord objects to jobs:** Objects serialize their attributes at enqueue time. If the record changes or gets deleted before the job runs, you process stale or missing data. Pass IDs, fetch fresh records in `perform`.
2. **No uniqueness checks on user-triggered jobs:** Users double-click submit buttons or retry failed requests. Without deduplication, you queue 50 "export CSV" jobs for the same dataset. Use `unique: :until_executing` to allow only one instance.
3. **Cron schedules without timezone awareness:** `0 9 * * *` means 9 AM UTC, not user's local time. Users in PST get reports at 1 AM. Use `ActiveSupport::TimeZone` or sidekiq-cron's `cron` with `class: MyWorker, args: {}, cron: "0 9 * * * America/Los_Angeles"`.

---

## Delayed Jobs (One-Time Scheduling)

Schedule a job to run at a specific time:

```ruby
# Sidekiq native syntax
ReportWorker.perform_in(1.hour, user.id)
ReportWorker.perform_at(Time.now + 2.days, user.id)

# ActiveJob syntax
ReportJob.set(wait: 1.hour).perform_later(user.id)
ReportJob.set(wait_until: Date.tomorrow.noon).perform_later(user.id)
```

**Use cases:**
- Send reminder email 24 hours after signup
- Cancel unpaid orders after 15 minutes
- Retry failed API calls with exponential backoff

**Time zones:** Times are stored as UTC in Redis. Use `Time.zone.now` for timezone-aware scheduling:

```ruby
# Send at 9 AM in user's timezone
send_time = Time.zone.parse("#{user.timezone} 9:00 AM tomorrow")
NotificationJob.set(wait_until: send_time).perform_later(user.id)
```

---

## Recurring Jobs with sidekiq-cron

Install sidekiq-cron:

```ruby
# Gemfile
gem 'sidekiq-cron'
```

Configure recurring jobs in `config/initializers/sidekiq.rb`:

```ruby
require 'sidekiq/cron/web'

schedule = {
  'cache_warmer' => {
    'cron' => '0 */6 * * *',  # Every 6 hours
    'class' => 'CacheWarmerWorker',
    'queue' => 'maintenance'
  },
  'daily_report' => {
    'cron' => '0 9 * * *',  # Every day at 9 AM UTC
    'class' => 'DailyReportWorker',
    'args' => ['summary']
  },
  'weekly_cleanup' => {
    'cron' => '0 2 * * 0',  # Sundays at 2 AM UTC
    'class' => 'WeeklyCleanupWorker'
  }
}

Sidekiq::Cron::Job.load_from_hash(schedule)
```

**Cron syntax quick reference:**
```
* * * * *
| | | | |
| | | | └─ Day of week (0-6, 0=Sunday)
| | | └─── Month (1-12)
| | └───── Day of month (1-31)
| └─────── Hour (0-23)
└───────── Minute (0-59)
```

**Examples:**
- `*/15 * * * *` — Every 15 minutes
- `0 0 * * *` — Daily at midnight UTC
- `30 14 * * 1-5` — Weekdays at 2:30 PM UTC

---

## Unique Jobs (Deduplication)

Install sidekiq-unique-jobs:

```ruby
# Gemfile
gem 'sidekiq-unique-jobs'
```

Configure in `config/initializers/sidekiq.rb`:

```ruby
require 'sidekiq-unique-jobs/web'

SidekiqUniqueJobs.configure do |config|
  config.enabled = true
end
```

Use in workers:

```ruby
class ExportReportWorker
  include Sidekiq::Worker
  sidekiq_options queue: :exports,
                  lock: :until_executed,
                  on_conflict: :log

  def perform(user_id, report_type)
    user = User.find(user_id)
    # Generate and send report
  end
end
```

**Lock strategies:**
- `until_executing`: Prevent duplicate enqueuing, allow re-enqueue once job starts
- `until_executed`: Prevent duplicates until job completes successfully
- `until_and_while_executing`: Prevent duplicates during and after execution
- `while_executing`: Allow queuing duplicates, but only one executes at a time

**Conflict resolution:**
- `reject`: Silently drop duplicate (default)
- `log`: Log duplicate and drop
- `replace`: Replace queued job with new one
- `reschedule`: Push duplicate's scheduled time later

---

## Passing Safe Arguments

**Bad: Passing objects**

```ruby
# DON'T DO THIS
user = User.find(123)
EmailJob.perform_later(user)  # Serializes entire User object
```

**Problems:**
- If user's email changes after enqueue, job sends to old address
- If user is deleted, job crashes with deserialization error
- Larger payload = more Redis memory

**Good: Passing IDs**

```ruby
# DO THIS
EmailJob.perform_later(user.id)

# In job
def perform(user_id)
  user = User.find(user_id)
  UserMailer.welcome_email(user).deliver_now
rescue ActiveRecord::RecordNotFound
  Rails.logger.warn "User #{user_id} not found, skipping email"
end
```

**Serializable types:**
- Primitives: `Integer`, `String`, `Float`, `Boolean`, `nil`
- Collections: `Array`, `Hash` (with serializable values)
- Avoid: ActiveRecord models, custom objects

**Passing multiple arguments:**

```ruby
ReportJob.perform_later(user_id, report_type, start_date.iso8601, end_date.iso8601)

def perform(user_id, report_type, start_date_str, end_date_str)
  start_date = Date.parse(start_date_str)
  end_date = Date.parse(end_date_str)
  # ...
end
```

---

## Combining Scheduling and Uniqueness

Prevent duplicate delayed jobs:

```ruby
class TrialExpirationWorker
  include Sidekiq::Worker
  sidekiq_options queue: :notifications,
                  lock: :until_executed,
                  lock_args_method: :lock_args

  def perform(user_id, trial_end_date)
    user = User.find(user_id)
    return if user.subscription.active?

    TrialMailer.expiration_warning(user).deliver_now
  end

  def self.lock_args(args)
    # Only user_id matters for uniqueness (ignore date changes)
    [args.first]
  end
end

# Schedule 7 days before trial ends
user.trial_end_date = 14.days.from_now
TrialExpirationWorker.perform_at(user.trial_end_date - 7.days, user.id, user.trial_end_date)

# If user extends trial, old job is replaced
user.trial_end_date = 30.days.from_now
TrialExpirationWorker.perform_at(user.trial_end_date - 7.days, user.id, user.trial_end_date)
```

---

## Trade-offs Box
- **Advantage:** sidekiq-cron eliminates external cron configuration; unique jobs prevent duplicate work; delayed jobs enable time-based workflows.
- **Cost:** sidekiq-cron polls Redis every 30 seconds adding minimal latency; unique jobs add Redis lookups for lock checks; scheduled jobs remain in Redis until execution time.
- **When to skip:** For simple apps, system cron + rake tasks work fine; if duplicates don't matter (idempotent analytics), skip uniqueness overhead.

---

## Debugging Checklist

When scheduled or unique jobs misbehave:

1. Check scheduled jobs: `Sidekiq::ScheduledSet.new.each { |job| puts job.display_class }`
2. Verify cron jobs loaded: `Sidekiq::Cron::Job.all.map(&:name)`
3. Check next cron run time: `Sidekiq::Cron::Job.find('job_name').last_enqueue_time`
4. Inspect unique locks: `SidekiqUniqueJobs::Digests.all`
5. Check timezone: `Time.zone.name` in Rails console
6. Review lock conflicts: search logs for "Duplicate"
7. Verify job arguments are serializable: avoid ActiveRecord objects
8. Check Redis scheduled set size: `Sidekiq::ScheduledSet.new.size`

---

## One-Minute Recap
- Use `perform_in` / `perform_at` for one-time delayed jobs; sidekiq-cron for recurring schedules
- Pass IDs and primitives to jobs, never ActiveRecord objects
- sidekiq-unique-jobs prevents duplicate enqueueing or execution
- Lock strategies: `until_executed` (no duplicates until done), `while_executing` (one at a time)
- Cron syntax uses UTC unless explicitly configured with timezone
