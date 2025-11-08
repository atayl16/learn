# Exercise: Report Generation Strategies

## Objective

Build a streaming CSV report generator with background job processing, query caching, and memory-efficient exports for large datasets.

## Task

Create a Rails app that exports order data to CSV using three approaches:

1. Basic streaming CSV for immediate download
2. Background job for large exports with email notification
3. Cached analytical report with aggregated data

## Setup

### Step 1: Create Rails App & Models

```bash
rails new report_generator --skip-javascript
cd report_generator
bin/rails generate model Order customer_name:string amount:decimal status:string created_at:datetime
bin/rails db:migrate
```

### Step 2: Install Dependencies

```bash
bundle add sidekiq
```

### Step 3: Seed Data

```bash
bin/rails console
```

In console:

```ruby
# Generate 50,000 sample orders
statuses = ['pending', 'completed', 'cancelled']
50_000.times do |i|
  Order.create(
    customer_name: "Customer #{i}",
    amount: rand(10.0..500.0).round(2),
    status: statuses.sample,
    created_at: rand(90.days.ago..Time.current)
  )
end

puts "Created #{Order.count} orders"
```

### Step 4: Configure Sidekiq

`config/application.rb`:

```ruby
config.active_job.queue_adapter = :sidekiq
```

## Part 1: Streaming CSV Export (8 minutes)

**Task 1.1:** Create a streaming CSV controller

Create `app/controllers/reports_controller.rb`:

```ruby
class ReportsController < ApplicationController
  def orders_csv
    headers['Content-Type'] = 'text/csv'
    headers['Content-Disposition'] = 'attachment; filename=orders.csv'

    # Stream response without buffering
    self.response_body = csv_enumerator
  end

  private

  def csv_enumerator
    Enumerator.new do |stream|
      # TODO: Stream CSV header
      # TODO: Stream rows using find_each to batch queries
    end
  end
end
```

Add route in `config/routes.rb`:

```ruby
get 'reports/orders_csv', to: 'reports#orders_csv'
```

**Acceptance criteria:**
- [ ] CSV header includes: ID, Customer Name, Amount, Status, Created At
- [ ] Uses `find_each` to batch database queries (default 1000 records)
- [ ] Generates each CSV row with `CSV.generate_line`
- [ ] Memory usage stays constant (~50MB) regardless of dataset size

**Verification:**

```bash
bin/rails server
# Visit http://localhost:3000/reports/orders_csv
# Download should start immediately and complete in ~5 seconds
```

Check logs for batched queries:

```
Order Load (5.2ms)  SELECT "orders".* FROM "orders" ORDER BY "orders"."id" ASC LIMIT 1000
Order Load (3.8ms)  SELECT "orders".* FROM "orders" WHERE "orders"."id" > 1000 ORDER BY "orders"."id" ASC LIMIT 1000
# ... continues in batches
```

## Part 2: Background Job Export (10 minutes)

**Task 2.1:** Create background job for large exports

Generate job:

```bash
bin/rails generate job ReportExport
```

Edit `app/jobs/report_export_job.rb`:

```ruby
class ReportExportJob < ApplicationJob
  queue_as :reports

  def perform(user_email, filters = {})
    # TODO: Generate CSV file in tmp/
    # TODO: Store user_email for notification
    # TODO: Send email with download instructions
    # TODO: Clean up temp file
  end
end
```

Create mailer:

```bash
bin/rails generate mailer ReportMailer export_ready
```

Edit `app/mailers/report_mailer.rb`:

```ruby
class ReportMailer < ApplicationMailer
  def export_ready(email, filename)
    @filename = filename
    mail(to: email, subject: "Your report is ready")
  end
end
```

Add controller action:

```ruby
# app/controllers/reports_controller.rb
def queue_export
  ReportExportJob.perform_later(params[:email])
  flash[:notice] = "Report queued. You'll receive an email when ready."
  redirect_to root_path
end
```

**Acceptance criteria:**
- [ ] Job generates CSV file in `tmp/` directory
- [ ] Email sent with download instructions after completion
- [ ] Temp file cleaned up after email sent
- [ ] Job runs in background (controller returns immediately)

**Verification:**

Start Sidekiq:

```bash
bundle exec sidekiq
```

In another terminal:

```bash
bin/rails console
ReportExportJob.perform_later("test@example.com")
```

Check Sidekiq logs for job execution and email delivery.

## Part 3: Cached Analytical Report (7 minutes)

**Task 3.1:** Create cached aggregated report

Add controller action:

```ruby
# app/controllers/reports_controller.rb
def daily_revenue
  @report = Rails.cache.fetch(cache_key, expires_in: 1.hour) do
    # TODO: Execute expensive SQL query with GROUP BY
    # TODO: Return JSON with daily revenue sums
  end

  render json: @report
end

private

def cache_key
  "daily_revenue_#{Date.current}"
end
```

Write SQL query that aggregates daily revenue:

```sql
SELECT
  DATE(created_at) as date,
  COUNT(*) as order_count,
  SUM(amount) as total_revenue,
  AVG(amount) as avg_order_value
FROM orders
WHERE status = 'completed'
  AND created_at >= DATE_TRUNC('month', CURRENT_DATE)
GROUP BY DATE(created_at)
ORDER BY date
```

**Acceptance criteria:**
- [ ] First request executes SQL query (check logs for query time)
- [ ] Subsequent requests serve from cache (response time <10ms)
- [ ] Cache key includes current date for auto-expiration
- [ ] Returns JSON array of daily revenue data

**Verification:**

```bash
# First request - executes query
curl http://localhost:3000/reports/daily_revenue

# Check logs for query execution time
# Completed 200 OK in 234ms (ActiveRecord: 220ms)

# Second request - from cache
curl http://localhost:3000/reports/daily_revenue

# Check logs for cache hit
# Completed 200 OK in 8ms (ActiveRecord: 0ms)
```

## Stretch Goals

1. **Add filtering parameters:**

```ruby
def csv_enumerator
  Order.where(status: params[:status]).find_each do |order|
    # ...
  end
end
```

2. **Track export progress:**

Use Redis to store job progress percentage and poll from frontend.

3. **S3 upload for background exports:**

Instead of email, upload to S3 and send presigned URL:

```ruby
# Requires aws-sdk-s3 gem
s3 = Aws::S3::Resource.new
obj = s3.bucket('reports').object("exports/#{filename}")
obj.upload_file(filepath)
presigned_url = obj.presigned_url(:get, expires_in: 7.days.to_i)
```

4. **Memory profiling:**

Add memory_profiler gem and measure before/after memory usage:

```ruby
require 'memory_profiler'

report = MemoryProfiler.report do
  # Run export
end

report.pretty_print
```

## Solution Notes

**Common gotchas:**

1. **Forgetting `find_each` batch size:** Default 1000 is good for most cases. Increase to 5000 for simple queries, decrease to 100 for complex associations.

2. **Not setting CSV headers:** Browser won't recognize as downloadable file without proper `Content-Disposition` header.

3. **Cache key collisions:** Always include date/time component in cache key to prevent stale data.

4. **Temp file cleanup:** Use `ensure` block or `File.unlink` to prevent disk space leaks.

5. **Streaming in development:** Some web servers (WEBrick) buffer responses. Test with Puma for accurate streaming behavior.

**Expected timings:**
- 50,000 rows streamed: 3-5 seconds
- Background job: 8-12 seconds (includes email sending)
- Cached query: <10ms (after first hit)

## Time Estimate

25 minutes
