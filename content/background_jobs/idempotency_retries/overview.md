# Idempotency Patterns & Retries

## What It Is
Idempotency means a job can run multiple times without causing duplicate effects. Idempotency keys are unique identifiers stored per job to detect and skip already-processed work. Retry strategies define how Sidekiq re-runs failed jobs, including backoff timing. The dead letter queue (DLQ) holds jobs that exceeded maximum retry attempts.

## Why It Matters
Network failures, server restarts, and timeouts cause jobs to run multiple times. Without idempotency, you charge customers twice, send duplicate emails, or corrupt data. Production systems rely on retries to handle transient errors (API rate limits, database locks), but unbounded retries can amplify problems. DLQs prevent broken jobs from blocking queues indefinitely.

## When to Use
- Payment processing, billing, or financial transactions
- Email/SMS sending where duplicates annoy users
- Third-party API calls with rate limits or intermittent failures
- Database operations that must complete exactly once
- Jobs triggering webhooks or external side effects

## Three Common Pitfalls
1. **Non-idempotent operations without protection:** Incrementing counters, appending to arrays, or creating records without uniqueness checks cause duplicates on retry. Use database constraints, idempotency keys, or `find_or_create_by`.
2. **Retrying permanently failed jobs forever:** Expired API keys, deleted records, or bad data never succeed. Set `retry: 5` or `retry: false` to move failed jobs to the DLQ after reasonable attempts.
3. **Ignoring the dead letter queue:** Dead jobs silently accumulate until you run out of Redis memory or discover missing invoices. Monitor DLQ size and alert when it grows; investigate root causes, not just retry blindly.

---

## Idempotency Keys Pattern

Store a unique key per operation to detect repeats:

```ruby
class ChargeCustomerJob < ApplicationJob
  def perform(payment_id)
    payment = Payment.find(payment_id)
    idempotency_key = "charge:#{payment.id}:#{payment.updated_at.to_i}"

    # Check if already processed
    if Redis.current.exists?(idempotency_key)
      Rails.logger.info "Payment #{payment.id} already charged, skipping"
      return
    end

    # Process payment
    result = StripeService.charge(payment.amount, payment.customer_id)

    # Mark as processed (expire after 7 days)
    Redis.current.setex(idempotency_key, 7.days.to_i, result.id)
  end
end

```

**Key composition:** Include record ID + timestamp or version to allow re-processing if the record changes.

---

## Database-Level Idempotency

Use unique constraints to prevent duplicates:

```ruby
# Migration
class CreateInvoices < ActiveRecord::Migration[7.0]
  def change
    create_table :invoices do |t|
      t.references :order, null: false
      t.decimal :amount
      t.string :stripe_charge_id
      t.timestamps
    end

    add_index :invoices, [:order_id, :stripe_charge_id], unique: true
  end
end

# Job
class CreateInvoiceJob < ApplicationJob
  def perform(order_id)
    order = Order.find(order_id)
    charge = StripeService.charge(order.total)

    # Unique index prevents duplicate invoices if job retries
    Invoice.create!(
      order_id: order.id,
      amount: order.total,
      stripe_charge_id: charge.id
    )
  rescue ActiveRecord::RecordNotUnique
    Rails.logger.info "Invoice already exists for order #{order_id}"
  end
end

```

Database constraints are more reliable than application-level checks (no race conditions).

---

## Retry Configuration

Sidekiq retries failed jobs with exponential backoff by default:

```ruby
class EmailWorker
  include Sidekiq::Worker
  sidekiq_options retry: 5  # Max 5 attempts (default: 25)

  def perform(user_id)
    user = User.find(user_id)
    UserMailer.welcome_email(user).deliver_now
  end
end

```

**Default backoff schedule (in seconds):**
- Attempt 1: immediate
- Attempt 2: 15s delay
- Attempt 3: 2 minutes
- Attempt 4: 10 minutes
- Attempt 5: 50 minutes
- ...exponential growth up to 25 attempts

Disable retries for jobs that should never retry:

```ruby
sidekiq_options retry: false

```

---

## Custom Backoff Strategies

Override retry logic for specific error types:

```ruby
class ApiWorker
  include Sidekiq::Worker
  sidekiq_options retry: 10

  def perform(endpoint)
    response = HTTParty.get(endpoint)
    # Process response
  end

  sidekiq_retries_exhausted do |job, exception|
    Rails.logger.error "Job #{job['jid']} failed permanently: #{exception.message}"
    Bugsnag.notify(exception, job: job)
  end

  sidekiq_retry_in do |count, exception|
    case exception
    when RateLimitError
      30.minutes.to_i  # Wait longer for rate limits
    when Net::ReadTimeout
      60 * (count ** 2)  # Exponential backoff for timeouts
    else
      nil  # Use default backoff
    end
  end
end

```

**Callbacks:**
- `sidekiq_retry_in`: set custom delay before next retry
- `sidekiq_retries_exhausted`: run code when job moves to DLQ

---

## Dead Letter Queue

Failed jobs after max retries go to the DLQ:

```ruby
# Check DLQ size
Sidekiq::DeadSet.new.size

# Inspect dead jobs
dead_set = Sidekiq::DeadSet.new
dead_set.each do |job|
  puts "Job: #{job.klass}, Args: #{job.args}, Error: #{job.item['error_message']}"
end

# Retry a specific dead job
dead_job = dead_set.first
dead_job.retry

# Retry all dead jobs (dangerous!)
Sidekiq::DeadSet.new.retry_all

# Clear DLQ (permanent deletion)
Sidekiq::DeadSet.new.clear

```

**DLQ monitoring:** Alert when `Sidekiq::DeadSet.new.size > threshold`. Investigate patterns: same error, same job class, or data quality issues.

---

## Conditional Retries

Skip retries for certain errors:

```ruby
class ProcessOrderJob < ApplicationJob
  retry_on StandardError, wait: :exponentially_longer, attempts: 5
  discard_on ActiveJob::DeserializationError  # Record deleted, don't retry
  discard_on PaymentDeclinedError  # User error, not transient

  def perform(order_id)
    order = Order.find(order_id)
    PaymentService.charge(order)
  end
end

```

ActiveJob provides `retry_on` and `discard_on` for declarative retry policies.

---

## Trade-offs Box
- **Advantage:** Idempotency keys prevent duplicate charges/emails; retries handle transient failures (network glitches, rate limits); DLQ isolates broken jobs.
- **Cost:** Idempotency checks add Redis lookups or database queries; aggressive retries amplify load during outages; DLQ requires manual investigation.
- **When to skip:** Single-attempt jobs (analytics, logging) don't need retries; read-only jobs (cache warming) are naturally idempotent.

---

## Debugging Checklist

When jobs fail repeatedly or cause duplicates:

1. Check retry count: `Sidekiq::Queue.new('default').first.item['retry_count']`
2. Inspect error messages: `Sidekiq::RetrySet.new.first.item['error_message']`
3. Review idempotency key logic: ensure keys include version or timestamp
4. Search logs for duplicate keys: `grep "already processed" log/sidekiq.log`
5. Check DLQ size: `Sidekiq::DeadSet.new.size`
6. Examine dead job errors: group by `error_class` to find patterns
7. Verify database constraints: `UNIQUE` indexes prevent duplicate records
8. Monitor retry backoff: ensure exponential delays don't block urgent work

---

## One-Minute Recap
- Idempotency ensures jobs run safely multiple times; use Redis keys or database constraints
- Pass record IDs, not objects; fetch fresh data in the job
- Sidekiq retries 25 times by default with exponential backoff; tune per job
- Dead letter queue holds permanently failed jobs; monitor and investigate
- Use `discard_on` for non-retryable errors; `retry_on` for transient failures
