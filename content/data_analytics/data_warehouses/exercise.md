# Exercise: Working with Data Warehouses

## Objective
Connect a Rails application to BigQuery and implement an incremental data sync job that exports order data to the warehouse for analytics.

## Task
Your e-commerce Rails app needs to sync order data to BigQuery for business intelligence reporting. Build a sync job that exports only new/updated orders since the last sync, then query BigQuery from Rails to generate a revenue report.

**Setup:**

```bash
# Install BigQuery gem
bundle add google-cloud-bigquery

# Set environment variables
export GCP_PROJECT_ID="your-project-id"
export GCP_CREDENTIALS_PATH="/path/to/service-account.json"
```

**Assume this schema:**

```ruby
create_table :orders do |t|
  t.references :user, null: false
  t.decimal :amount, precision: 10, scale: 2
  t.string :status  # 'pending', 'completed', 'refunded'
  t.timestamps
end

create_table :sync_logs do |t|
  t.string :table_name
  t.datetime :last_sync_at
  t.timestamps
end
```

**BigQuery table schema:**

```sql
CREATE TABLE dataset.orders (
  id INT64,
  user_id INT64,
  amount NUMERIC,
  status STRING,
  created_at TIMESTAMP,
  updated_at TIMESTAMP
);
```

## Acceptance Criteria

### Part 1: Configure BigQuery Connection (5 minutes)

- [ ] Create `config/initializers/bigquery.rb` with authenticated BigQuery client
- [ ] Add environment variables for project ID and credentials path
- [ ] Verify connection: query `SELECT 1` successfully returns result

### Part 2: Build Incremental Sync Job (15 minutes)

- [ ] Create `app/jobs/sync_orders_to_bigquery_job.rb`
- [ ] Implement incremental sync logic:
  - Query `SyncLog` for last sync timestamp for 'orders' table
  - Select orders where `updated_at > last_sync_timestamp`
  - Insert/update rows in BigQuery using `insert` or streaming API
  - Record new sync timestamp in `SyncLog`
- [ ] Handle edge case: first run when `SyncLog` is empty (sync all orders or last 30 days)
- [ ] Add error handling and logging for failed syncs

**Starter code:**

```ruby
class SyncOrdersToBigqueryJob < ApplicationJob
  def perform
    last_sync = SyncLog.find_by(table_name: 'orders')&.last_sync_at || 30.days.ago
    current_sync = Time.current

    orders = Order.where('updated_at > ?', last_sync)
                  .select(:id, :user_id, :amount, :status, :created_at, :updated_at)

    # TODO: Insert orders into BigQuery
    # TODO: Handle errors
    # TODO: Update SyncLog
  end
end
```

### Part 3: Query BigQuery for Revenue Report (10 minutes)

- [ ] Create `app/services/bigquery_revenue_report.rb`
- [ ] Write method `daily_revenue(start_date, end_date)` that queries BigQuery for completed orders grouped by day
- [ ] Return results as array of hashes: `[{date: '2024-01-01', revenue: 1250.00}, ...]`
- [ ] Add caching layer using Rails.cache to avoid re-querying BigQuery for same date ranges

**SQL query:**

```sql
SELECT
  DATE(created_at) as date,
  SUM(amount) as revenue
FROM `project.dataset.orders`
WHERE status = 'completed'
  AND created_at BETWEEN @start_date AND @end_date
GROUP BY date
ORDER BY date;
```

### Part 4: Testing & Verification (5 minutes)

- [ ] Create 100 test orders with varying timestamps
- [ ] Run sync job and verify orders appear in BigQuery
- [ ] Update 10 orders and run sync again; verify only 10 rows are synced
- [ ] Query revenue report and verify totals match Rails database

**Verification commands:**

```bash
# Rails console
rails c

# Create test data
100.times { |i| Order.create!(user_id: 1, amount: rand(10..100), status: 'completed', created_at: i.days.ago) }

# Run sync
SyncOrdersToBigqueryJob.perform_now

# Check SyncLog
SyncLog.find_by(table_name: 'orders').last_sync_at

# Query BigQuery
BigqueryRevenueReport.daily_revenue(30.days.ago.to_date, Date.today)
```

**BigQuery verification:**

```sql
-- Count rows
SELECT COUNT(*) FROM `project.dataset.orders`;

-- Check recent syncs
SELECT id, updated_at FROM `project.dataset.orders` ORDER BY updated_at DESC LIMIT 10;
```

## Stretch Goals

- [ ] Add data validation: skip orders with invalid amounts (NULL, negative)
- [ ] Implement batch processing: sync in chunks of 1000 rows to avoid memory issues
- [ ] Add a `SyncOrdersController` that triggers sync and displays sync status
- [ ] Mask PII: hash email addresses before syncing users table
- [ ] Implement retry logic for transient BigQuery API errors using exponential backoff

## Solution Notes

**Common gotchas:**
- BigQuery insert API has quotas (10,000 rows/sec); batch large syncs
- Timestamps must be formatted as ISO 8601 strings or Unix timestamps
- BigQuery schema requires exact column name matches; use `select` to project columns
- First sync can timeout on large tables; run as background job with progress tracking
- Upsert logic: BigQuery doesn't support `ON CONFLICT`; use `MERGE` statements or delete + insert pattern

**Performance tips:**
- Use streaming inserts for low-latency syncs; batch inserts for high-volume syncs
- Partition BigQuery tables by date for faster queries on time-series data
- Index Rails `updated_at` column to speed up incremental queries

## Time Estimate
35 minutes
