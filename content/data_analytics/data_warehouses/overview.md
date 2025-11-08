# Working with Data Warehouses

## What It Is
Data warehouses are specialized databases optimized for analytical queries (OLAP) rather than transactional operations (OLTP). Services like Snowflake and BigQuery store historical data aggregated from multiple sources. Rails applications sync data to warehouses via scheduled jobs, then query aggregated results for dashboards, reports, and business intelligence. Warehouses handle complex analytical queries (e.g., multi-year trends, cohort analysis) that would cripple production databases.

## Why It Matters
Production databases are optimized for fast writes and small reads (e.g., loading a user's profile). Running analytics queries like "calculate revenue by region for 3 years" locks tables and starves application traffic. Seniors separate concerns: transactional data stays in Postgres, analytical data lives in the warehouse. This architecture prevents slow reports from taking down production while enabling analysts to query terabytes of data without Rails developers writing custom code.

## When to Use
- **Business intelligence dashboards:** Aggregate metrics across millions of rows (revenue, retention, churn)
- **Historical trend analysis:** Multi-year comparisons that require scanning entire tables
- **Data science workflows:** Export cleaned datasets for ML model training
- **Cross-system analytics:** Join data from Rails, CRM, payment processors, and third-party APIs
- **Compliance and auditing:** Immutable event logs required for SOC2, GDPR, or financial regulations

## Three Common Pitfalls
1. **Syncing sensitive data without masking:** Warehouses often have looser access controls than production. Sync PII (emails, addresses) hashed or redacted to prevent data leaks.
2. **Full syncs on large tables:** Re-exporting 10 million rows nightly wastes bandwidth and warehouse storage. Use incremental syncs with `updated_at` filters and upsert logic.
3. **Querying warehouses in request/response cycles:** Warehouse queries take seconds to minutes. Cache results in Redis or run queries in background jobs, never in controllers.

---

## OLAP vs OLTP

**OLTP (Online Transaction Processing):** Optimized for many small, fast reads/writes. Rails apps use Postgres/MySQL for OLTP.

**OLAP (Online Analytical Processing):** Optimized for complex aggregations across large datasets. Warehouses use columnar storage and distributed execution.

**Example:**

```ruby
# OLTP: Fast single-row lookup
User.find(5)  # 2ms

# OLAP: Aggregate millions of rows
# SELECT date_trunc('month', created_at), COUNT(*)
# FROM users
# GROUP BY 1
# ORDER BY 1;
# (10+ seconds on production DB, <1s on warehouse)
```

**Why separate systems?**
- OLTP indexes optimize for point lookups; OLAP scans entire columns
- OLTP locks rows during writes; OLAP is read-only or append-only
- OLTP stores current state; OLAP stores historical snapshots

---

## Connecting Rails to BigQuery

BigQuery uses service account JSON credentials and the `google-cloud-bigquery` gem.

**Setup:**

```ruby
# Gemfile
gem 'google-cloud-bigquery'

# config/initializers/bigquery.rb
require 'google/cloud/bigquery'

BIGQUERY = Google::Cloud::Bigquery.new(
  project_id: ENV['GCP_PROJECT_ID'],
  credentials: ENV['GCP_CREDENTIALS_PATH']
)
```

**Query example:**

```ruby
# app/services/revenue_report.rb
class RevenueReport
  def self.monthly_revenue(year)
    query = <<~SQL
      SELECT
        DATE_TRUNC(created_at, MONTH) as month,
        SUM(amount) as revenue
      FROM `project.dataset.orders`
      WHERE EXTRACT(YEAR FROM created_at) = @year
      GROUP BY month
      ORDER BY month
    SQL

    BIGQUERY.query(query, params: { year: year }).to_a
  end
end
```

---

## Connecting Rails to Snowflake

Snowflake uses ODBC or REST API via the `snowflake-connector-ruby` gem or HTTP calls.

**Setup:**

```ruby
# Gemfile
gem 'snowflake-connector-ruby'

# config/initializers/snowflake.rb
require 'snowflake-connector-ruby'

SNOWFLAKE = SnowflakeConnector.new(
  account: ENV['SNOWFLAKE_ACCOUNT'],
  user: ENV['SNOWFLAKE_USER'],
  password: ENV['SNOWFLAKE_PASSWORD'],
  warehouse: ENV['SNOWFLAKE_WAREHOUSE'],
  database: ENV['SNOWFLAKE_DATABASE'],
  schema: 'PUBLIC'
)
```

**Query example:**

```ruby
result = SNOWFLAKE.execute("SELECT COUNT(*) FROM events WHERE user_id = ?", [user_id])
result.first['COUNT(*)']
```

---

## Data Sync Strategies

### Full Sync
Export entire table on every run. Simple but wasteful for large datasets.

```ruby
# app/jobs/user_sync_job.rb
class UserSyncJob < ApplicationJob
  def perform
    users = User.select(:id, :email, :created_at, :plan).map(&:attributes)
    BIGQUERY.insert('users', users)
  end
end
```

**Use when:** Table is small (<100k rows) or data changes unpredictably.

### Incremental Sync
Export only new/updated records since last sync.

```ruby
class IncrementalUserSyncJob < ApplicationJob
  def perform
    last_sync = SyncLog.last_sync_time('users')
    users = User.where('updated_at > ?', last_sync).select(:id, :email, :updated_at)

    BIGQUERY.insert('users', users.map(&:attributes))
    SyncLog.record_sync('users', Time.current)
  end
end
```

**Use when:** Table is large and has `updated_at` timestamp.

### Change Data Capture (CDC)
Stream database changes in real-time via tools like Debezium or AWS DMS.

**Use when:** Near real-time analytics required (e.g., fraud detection).

---

## Querying from Rails

**Anti-pattern: Synchronous queries**

```ruby
# DON'T: Blocks request for 30+ seconds
def dashboard
  @revenue = BIGQUERY.query("SELECT SUM(amount) FROM orders").first['total']
end
```

**Pattern 1: Background jobs + caching**

```ruby
class DashboardMetricsJob < ApplicationJob
  def perform
    revenue = BIGQUERY.query("SELECT SUM(amount) FROM orders").first['total']
    Rails.cache.write('dashboard:revenue', revenue, expires_in: 1.hour)
  end
end

# Controller
def dashboard
  @revenue = Rails.cache.fetch('dashboard:revenue') { 'Loading...' }
end
```

**Pattern 2: Materialize results in Postgres**

```ruby
# Sync aggregated results from warehouse to local table
class SyncDashboardMetricsJob < ApplicationJob
  def perform
    metrics = BIGQUERY.query("SELECT metric, value FROM dashboard_metrics").to_a
    metrics.each do |row|
      DashboardMetric.upsert({ metric: row['metric'], value: row['value'] })
    end
  end
end
```

---

## Trade-offs
- **Advantage:** Warehouses scale to petabytes and handle complex analytics without impacting production.
- **Cost:** Additional infrastructure ($100+/month), data sync complexity, eventual consistency (data lags behind production).
- **When to skip:** Small apps (<100k users), simple reporting needs met by Postgres views, budget constraints.

---

## One-Minute Recap
- Data warehouses (Snowflake, BigQuery) handle OLAP workloads; production databases handle OLTP
- Use incremental syncs for large tables to avoid re-exporting millions of rows
- Never query warehouses synchronously in controllers; use background jobs and caching
- Separate transactional data (Postgres) from analytical data (warehouse) to prevent analytics queries from degrading user experience
