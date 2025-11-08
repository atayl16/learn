# Exercise: Idempotency Patterns & Retries

## Objective
Implement idempotency keys to prevent duplicate processing, configure custom retry strategies, and handle dead jobs in the DLQ.

## Task
Create a payment processing job that:

1. Uses Redis-based idempotency keys to prevent duplicate charges
2. Simulates API failures and retries with exponential backoff
3. Handles permanently failed jobs with a callback
4. Provides DLQ inspection and recovery commands

## Acceptance Criteria
- [ ] `ChargePaymentJob` checks Redis idempotency key before processing
- [ ] Job skips processing if idempotency key exists
- [ ] Custom retry logic: 3 attempts with 30-second delays for `ApiError`
- [ ] `sidekiq_retries_exhausted` callback logs failures
- [ ] Database unique constraint prevents duplicate payment records
- [ ] Dead jobs appear in DLQ after max retries
- [ ] Console commands provided to inspect and retry dead jobs

## Verification Steps

1. Enqueue the same payment twice rapidly:
```ruby
payment = Payment.create!(amount: 100, status: 'pending')
2.times { ChargePaymentJob.perform_later(payment.id) }
```

2. Check logs - second job should skip with "already processed" message

3. Simulate failure and watch retries:
```ruby
# Set environment to trigger failures
ENV['SIMULATE_FAILURE'] = 'true'
ChargePaymentJob.perform_later(payment.id)
```

4. After 3 retries, check DLQ:
```ruby
Sidekiq::DeadSet.new.size  # => 1
dead_job = Sidekiq::DeadSet.new.first
dead_job.item['error_message']  # Shows ApiError
```

## Setup Code

### Step 1: Create Payment Model

```bash
bin/rails generate model Payment amount:decimal status:string stripe_charge_id:string
```

Edit migration to add unique constraint:
```ruby
class CreatePayments < ActiveRecord::Migration[7.0]
  def change
    create_table :payments do |t|
      t.decimal :amount, precision: 10, scale: 2
      t.string :status
      t.string :stripe_charge_id
      t.timestamps
    end

    add_index :payments, :stripe_charge_id, unique: true
  end
end
```

Run migration:
```bash
bin/rails db:migrate
```

### Step 2: Create Payment Job with Idempotency

```bash
bin/rails generate job ChargePayment
```

Edit `app/jobs/charge_payment_job.rb`:
```ruby
class ChargePaymentJob < ApplicationJob
  queue_as :payments

  retry_on StandardError, wait: :exponentially_longer, attempts: 3
  discard_on ActiveRecord::RecordNotFound

  def perform(payment_id)
    payment = Payment.find(payment_id)
    idempotency_key = "payment:charge:#{payment.id}:#{payment.updated_at.to_i}"

    # Check if already processed
    if redis.exists?(idempotency_key)
      Rails.logger.info "Payment #{payment.id} already charged (idempotency), skipping"
      return
    end

    # Simulate API call
    if ENV['SIMULATE_FAILURE'] == 'true'
      raise ApiError, "Simulated API failure for testing"
    end

    charge_id = simulate_stripe_charge(payment.amount)

    # Update payment and set idempotency key atomically
    ActiveRecord::Base.transaction do
      payment.update!(status: 'completed', stripe_charge_id: charge_id)
      redis.setex(idempotency_key, 7.days.to_i, charge_id)
    end

    Rails.logger.info "Payment #{payment.id} charged successfully: #{charge_id}"
  end

  private

  def redis
    @redis ||= Redis.new(url: ENV.fetch('REDIS_URL', 'redis://localhost:6379/1'))
  end

  def simulate_stripe_charge(amount)
    sleep 1
    "ch_#{SecureRandom.hex(12)}"  # Fake Stripe charge ID
  end

  class ApiError < StandardError; end
end
```

### Step 3: Create Sidekiq Worker with Custom Retry

Create `app/workers/payment_processor.rb`:
```ruby
class PaymentProcessor
  include Sidekiq::Worker
  sidekiq_options retry: 3, queue: :payments

  def perform(payment_id)
    payment = Payment.find(payment_id)

    if ENV['SIMULATE_FAILURE'] == 'true'
      raise ApiError, "Temporary API failure"
    end

    charge_id = "ch_#{SecureRandom.hex(12)}"
    payment.update!(status: 'completed', stripe_charge_id: charge_id)
  end

  sidekiq_retry_in do |count, exception|
    case exception
    when ApiError
      30  # Wait 30 seconds between retries
    else
      (count ** 4) + 15  # Exponential backoff
    end
  end

  sidekiq_retries_exhausted do |job, exception|
    payment_id = job['args'].first
    Rails.logger.error "Payment #{payment_id} failed permanently: #{exception.message}"

    # Notify monitoring system
    # Bugsnag.notify(exception, payment_id: payment_id)

    # Mark payment as failed
    Payment.find(payment_id).update(status: 'failed')
  end

  class ApiError < StandardError; end
end
```

### Step 4: DLQ Inspection Commands

Add to `lib/tasks/sidekiq.rake`:
```ruby
namespace :sidekiq do
  desc "Show dead jobs"
  task dead_jobs: :environment do
    dead_set = Sidekiq::DeadSet.new
    puts "Dead jobs: #{dead_set.size}"

    dead_set.each do |job|
      puts "\n---"
      puts "Class: #{job.klass}"
      puts "Args: #{job.args}"
      puts "Error: #{job.item['error_message']}"
      puts "Failed at: #{job.item['failed_at']}"
    end
  end

  desc "Retry all dead jobs"
  task retry_dead: :environment do
    count = Sidekiq::DeadSet.new.size
    Sidekiq::DeadSet.new.retry_all
    puts "Retried #{count} dead jobs"
  end

  desc "Clear dead jobs"
  task clear_dead: :environment do
    count = Sidekiq::DeadSet.new.size
    Sidekiq::DeadSet.new.clear
    puts "Cleared #{count} dead jobs"
  end
end
```

### Step 5: Test Idempotency

In Rails console:
```ruby
# Create payment
payment = Payment.create!(amount: 150.00, status: 'pending')

# Enqueue twice
ChargePaymentJob.perform_later(payment.id)
ChargePaymentJob.perform_later(payment.id)

# Watch Sidekiq logs - second job should skip
# Check Redis
redis = Redis.new(url: 'redis://localhost:6379/1')
redis.keys("payment:charge:*")  # Should show idempotency key

# Verify only one charge
Payment.where(status: 'completed').count  # => 1
```

### Step 6: Test Retries and DLQ

```ruby
# Enable failure simulation
ENV['SIMULATE_FAILURE'] = 'true'

# Enqueue job
payment2 = Payment.create!(amount: 200.00, status: 'pending')
PaymentProcessor.perform_async(payment2.id)

# Watch Sidekiq logs - should retry 3 times then move to DLQ
# Wait ~2 minutes for retries to complete

# Check DLQ
Sidekiq::DeadSet.new.size  # => 1

# Inspect dead job
rake sidekiq:dead_jobs

# Disable simulation and retry
ENV['SIMULATE_FAILURE'] = 'false'
rake sidekiq:retry_dead
```

## Stretch (Optional)

Implement a circuit breaker pattern that disables retries after consecutive failures:

```ruby
class CircuitBreaker
  def self.open?(key)
    failures = Redis.current.get("circuit:#{key}").to_i
    failures > 10
  end

  def self.record_failure(key)
    Redis.current.incr("circuit:#{key}")
    Redis.current.expire("circuit:#{key}", 5.minutes.to_i)
  end

  def self.reset(key)
    Redis.current.del("circuit:#{key}")
  end
end

# In job:
def perform(payment_id)
  if CircuitBreaker.open?('stripe')
    Rails.logger.error "Circuit breaker open, skipping payment"
    return
  end

  # ... process payment
rescue ApiError => e
  CircuitBreaker.record_failure('stripe')
  raise
end
```

## Time Estimate
20 minutes
