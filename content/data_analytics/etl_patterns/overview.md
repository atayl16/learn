# ETL Patterns in Rails

## What It Is
ETL (Extract, Transform, Load) is a data pipeline pattern for moving data between systems. Extract reads data from sources (CSV files, APIs, databases). Transform validates, cleans, and normalizes the data. Load inserts or updates records in the target database. Idempotency ensures pipelines can re-run without duplicating data. Incremental refresh processes only changed records; full refresh replaces all data.

## Why It Matters
Production applications regularly import customer data, sync third-party APIs, migrate legacy systems, or aggregate analytics. Without proper ETL patterns, you risk data corruption, duplicate records, memory exhaustion, or failed imports that leave partial data. Rails developers must handle CSV files with millions of rows, validate data before insertion, recover from errors mid-import, and ensure imports are idempotent for safe retries.

## When to Use
- Import customer data from CSV files uploaded by users or partners
- Sync inventory, pricing, or product catalogs from third-party APIs
- Migrate data from legacy systems during platform transitions
- Aggregate event logs or metrics for analytics dashboards
- Reconcile data between microservices or external data warehouses

## Three Common Pitfalls
1. **Loading entire CSV into memory:** Reading a 500MB CSV file with `CSV.read()` causes out-of-memory crashes. Stream rows with `CSV.foreach()` to process one row at a time, keeping memory constant.
2. **No validation before insert:** Invalid data (null emails, negative prices, malformed dates) causes database errors mid-import, leaving partial data. Validate each row; collect errors; rollback or skip invalid rows.
3. **Non-idempotent imports without tracking:** Re-running an ETL job creates duplicate records. Use unique constraints, upsert operations (`INSERT ON CONFLICT`), or track processed file checksums to safely re-run jobs.

---

## Extract Patterns

### CSV Extraction

Stream large files row-by-row to avoid memory issues:

```ruby
class CsvExtractor
  def self.extract(file_path)
    CSV.foreach(file_path, headers: true, header_converters: :symbol) do |row|
      yield row.to_h
    end
  end
end

# Usage
CsvExtractor.extract('customers.csv') do |row|
  puts row # => { name: "John", email: "john@example.com" }
end
```

**Options:**
- `headers: true`: first row becomes column names
- `header_converters: :symbol`: convert headers to symbols
- `encoding: 'UTF-8'`: handle character encoding issues

### API Extraction

Paginate through API responses to handle large datasets:

```ruby
class ApiExtractor
  def self.extract(endpoint)
    page = 1
    loop do
      response = HTTParty.get(endpoint, query: { page: page, per_page: 100 })
      data = JSON.parse(response.body)

      break if data.empty?

      data.each { |record| yield record }
      page += 1
    end
  end
end
```

Handle rate limits with exponential backoff:

```ruby
response = HTTParty.get(endpoint)
if response.code == 429
  retry_after = response.headers['Retry-After'].to_i
  sleep(retry_after)
  retry
end
```

---

## Transform Patterns

### Data Validation

Validate rows before loading to catch errors early:

```ruby
class CustomerTransformer
  def self.transform(row)
    errors = []

    errors << "Missing email" if row[:email].blank?
    errors << "Invalid email format" unless row[:email]&.match?(URI::MailTo::EMAIL_REGEXP)
    errors << "Negative age" if row[:age].to_i < 0

    return { valid: false, errors: errors } if errors.any?

    {
      valid: true,
      data: {
        name: row[:name]&.strip&.titleize,
        email: row[:email]&.downcase,
        age: row[:age].to_i,
        created_at: Time.current
      }
    }
  end
end
```

### Data Normalization

Clean and standardize data:

```ruby
def normalize_phone(phone)
  phone.to_s.gsub(/\D/, '').last(10)  # Extract 10 digits
end

def parse_date(date_string)
  Date.parse(date_string)
rescue ArgumentError
  nil
end

def sanitize_amount(amount)
  amount.to_s.gsub(/[$,]/, '').to_f
end
```

---

## Load Patterns

### Batch Inserts

Insert records in batches for performance:

```ruby
class CustomerLoader
  BATCH_SIZE = 1000

  def self.load(records)
    records.each_slice(BATCH_SIZE) do |batch|
      Customer.insert_all(
        batch,
        returning: false,
        record_timestamps: true
      )
    end
  end
end
```

`insert_all` is 10-100x faster than individual `create` calls.

### Upsert Pattern

Update existing records or insert new ones:

```ruby
class ProductLoader
  def self.load(records)
    Product.upsert_all(
      records,
      unique_by: :sku,  # Unique constraint column
      update_only: [:name, :price, :updated_at]  # Don't update SKU
    )
  end
end
```

Requires a unique index:

```ruby
add_index :products, :sku, unique: true
```

---

## Incremental vs Full Refresh

### Full Refresh

Replace all data (useful for small datasets):

```ruby
class FullRefreshLoader
  def self.load(records)
    Product.transaction do
      Product.delete_all
      Product.insert_all(records)
    end
  end
end
```

**Risk:** If import fails mid-process, you lose all data. Use transaction and keep backup.

### Incremental Refresh

Process only changed records since last run:

```ruby
class IncrementalLoader
  def self.load(records)
    last_sync = EtlRun.last&.completed_at || 1.year.ago

    records.each do |record|
      next if record[:updated_at] <= last_sync

      Product.upsert(record, unique_by: :external_id)
    end

    EtlRun.create!(completed_at: Time.current)
  end
end
```

Track last successful run to avoid reprocessing unchanged data.

---

## Idempotency in ETL

### File Checksum Tracking

Prevent re-importing the same file:

```ruby
class IdempotentImporter
  def self.import(file_path)
    checksum = Digest::MD5.file(file_path).hexdigest

    if ImportLog.exists?(file_checksum: checksum)
      Rails.logger.info "File already imported: #{file_path}"
      return
    end

    # Run import
    perform_import(file_path)

    ImportLog.create!(
      file_name: File.basename(file_path),
      file_checksum: checksum,
      imported_at: Time.current
    )
  end
end
```

### Idempotent Upserts

Use unique constraints and upsert to safely re-run:

```ruby
# Migration
add_index :customers, :external_id, unique: true

# Import (safe to run multiple times)
Customer.upsert_all(records, unique_by: :external_id)
```

---

## Error Recovery

### Collect Errors Without Stopping

```ruby
class ResilientImporter
  def self.import(file_path)
    successful = 0
    failed = []

    CsvExtractor.extract(file_path) do |row|
      result = CustomerTransformer.transform(row)

      if result[:valid]
        Customer.create!(result[:data])
        successful += 1
      else
        failed << { row: row, errors: result[:errors] }
      end
    rescue => e
      failed << { row: row, errors: [e.message] }
    end

    {
      successful: successful,
      failed: failed.count,
      error_details: failed
    }
  end
end
```

### Dead Letter Queue for Failed Rows

Store failed rows for manual review:

```ruby
class FailedImport < ApplicationRecord
  # has columns: row_data (jsonb), error_message, source_file, created_at
end

# In import job
rescue => e
  FailedImport.create!(
    row_data: row,
    error_message: e.message,
    source_file: file_path
  )
end
```

---

## Sidekiq for ETL Pipelines

Run imports asynchronously to avoid HTTP timeouts:

```ruby
class CsvImportJob
  include Sidekiq::Worker
  sidekiq_options queue: :etl, retry: 3

  def perform(file_path)
    results = { successful: 0, failed: 0, errors: [] }

    CsvExtractor.extract(file_path) do |row|
      result = CustomerTransformer.transform(row)

      if result[:valid]
        Customer.upsert(result[:data], unique_by: :email)
        results[:successful] += 1
      else
        results[:failed] += 1
        results[:errors] << { row: row, errors: result[:errors] }
      end
    end

    Rails.logger.info "Import complete: #{results}"
    UserMailer.import_summary(results).deliver_now
  end

  sidekiq_retries_exhausted do |job, exception|
    UserMailer.import_failed(job['args'].first, exception).deliver_now
  end
end

# Enqueue
CsvImportJob.perform_async('uploads/customers.csv')
```

---

## Trade-offs Box
- **Advantage:** Streaming CSV reads handle files larger than memory; batch inserts are 10-100x faster than individual creates; upserts provide idempotency.
- **Cost:** Error handling adds complexity; incremental refresh requires tracking state; background jobs delay feedback to users.
- **When to skip:** For <1000 records, inline processing is simpler; for real-time sync, consider webhooks instead of batch ETL.

---

## Debugging Checklist

When ETL jobs fail or produce incorrect data:

1. Check file encoding: `file -I data.csv` (look for UTF-8 vs ISO-8859-1)
2. Validate CSV structure: `head -20 data.csv | cat -A` (check delimiters, line endings)
3. Test transformation logic in console with sample row
4. Check database constraints: failed inserts often indicate missing unique indexes
5. Review Sidekiq logs for memory errors: `tail -f log/sidekiq.log`
6. Monitor Redis memory: large ETL jobs can fill Redis queues
7. Check for partial imports: count records before/after, verify transaction rollback
8. Inspect failed imports table: `FailedImport.pluck(:error_message).tally`

---

## One-Minute Recap
- ETL = Extract (read data), Transform (validate/clean), Load (insert/update)
- Stream large files with `CSV.foreach`, not `CSV.read`, to avoid memory issues
- Validate rows before loading; collect errors; use transactions for consistency
- Use `insert_all` for batch performance, `upsert_all` for idempotency
- Track file checksums or use unique constraints to prevent duplicate imports
- Run ETL jobs in Sidekiq; send email summaries; store failed rows for review
