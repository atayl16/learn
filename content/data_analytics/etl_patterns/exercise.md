# Exercise: ETL Patterns in Rails

## Objective
Build a complete ETL pipeline to import product data from CSV files with validation, error handling, idempotency, and background job processing.

## Task
Create a product import system that:

1. Extracts data from CSV files using streaming
2. Validates and transforms each row
3. Loads data using batch upserts
4. Tracks import status and errors
5. Runs asynchronously via Sidekiq

## Acceptance Criteria
- [ ] CSV extraction streams rows (not loaded into memory)
- [ ] Validator checks required fields and data types
- [ ] Transformer normalizes prices, SKUs, and product names
- [ ] Loader uses `upsert_all` with unique constraint on SKU
- [ ] Import job runs in Sidekiq with error tracking
- [ ] Failed rows stored in `FailedImport` model for review
- [ ] Import summary logged with success/failure counts
- [ ] Re-running import with same file is idempotent (no duplicates)

## Verification Steps

1. Create sample CSV file:

```bash
cat > products.csv << 'EOF'
sku,name,price,category
PROD-001,Wireless Mouse,$29.99,Electronics
PROD-002,USB Cable,9.99,Electronics
PROD-003,Notebook,invalid_price,Office
,Missing SKU Product,19.99,Office
PROD-004,Mechanical Keyboard,$149.99,Electronics
EOF
```

2. Run import job:

```ruby
# In Rails console
ProductImportJob.perform_async('products.csv')
```

3. Check results:

```ruby
Product.count  # => 3 (valid products)
FailedImport.count  # => 2 (invalid rows)
FailedImport.pluck(:error_message)
# => ["Invalid price format", "Missing required field: sku"]
```

4. Re-run import (should be idempotent):

```ruby
ProductImportJob.perform_async('products.csv')
Product.count  # => Still 3 (no duplicates)
```

## Setup Code

### Step 1: Database Schema

Create models and migrations:

```bash
bin/rails generate model Product sku:string name:string price:decimal category:string
bin/rails generate model FailedImport row_data:jsonb error_message:text source_file:string
bin/rails generate model ImportLog file_name:string file_checksum:string row_count:integer successful_count:integer failed_count:integer
```

Edit migration to add unique constraint:

```ruby
# db/migrate/xxx_create_products.rb
class CreateProducts < ActiveRecord::Migration[7.0]
  def change
    create_table :products do |t|
      t.string :sku, null: false
      t.string :name
      t.decimal :price, precision: 10, scale: 2
      t.string :category
      t.timestamps
    end

    add_index :products, :sku, unique: true
  end
end
```

Run migrations:

```bash
bin/rails db:migrate
```

### Step 2: CSV Extractor

Create `app/services/csv_extractor.rb`:

```ruby
class CsvExtractor
  def self.extract(file_path)
    row_count = 0

    CSV.foreach(file_path, headers: true, header_converters: :symbol) do |row|
      row_count += 1
      yield row.to_h, row_count
    end

    row_count
  rescue Errno::ENOENT
    raise "File not found: #{file_path}"
  rescue CSV::MalformedCSVError => e
    raise "Invalid CSV format: #{e.message}"
  end
end
```

### Step 3: Product Transformer

Create `app/services/product_transformer.rb`:

```ruby
class ProductTransformer
  EMAIL_REGEX = /\A[\w+\-.]+@[a-z\d\-]+(\.[a-z\d\-]+)*\.[a-z]+\z/i

  def self.transform(row)
    errors = validate(row)
    return { valid: false, errors: errors } if errors.any?

    {
      valid: true,
      data: {
        sku: normalize_sku(row[:sku]),
        name: normalize_name(row[:name]),
        price: parse_price(row[:price]),
        category: row[:category]&.strip,
        updated_at: Time.current
      }
    }
  end

  private

  def self.validate(row)
    errors = []

    errors << "Missing required field: sku" if row[:sku].blank?
    errors << "Missing required field: name" if row[:name].blank?

    if row[:price].present?
      price = parse_price(row[:price])
      errors << "Invalid price format" if price.nil?
      errors << "Price must be positive" if price && price <= 0
    else
      errors << "Missing required field: price"
    end

    errors
  end

  def self.normalize_sku(sku)
    sku.to_s.strip.upcase
  end

  def self.normalize_name(name)
    name.to_s.strip.titleize
  end

  def self.parse_price(price_string)
    # Remove currency symbols and commas: "$1,234.56" => 1234.56
    cleaned = price_string.to_s.gsub(/[$,]/, '').strip
    Float(cleaned)
  rescue ArgumentError, TypeError
    nil
  end
end
```

### Step 4: Product Loader

Create `app/services/product_loader.rb`:

```ruby
class ProductLoader
  BATCH_SIZE = 1000

  def self.load(records)
    return 0 if records.empty?

    records.each_slice(BATCH_SIZE) do |batch|
      Product.upsert_all(
        batch,
        unique_by: :sku,
        update_only: [:name, :price, :category, :updated_at]
      )
    end

    records.size
  end
end
```

### Step 5: Import Job

Create `app/jobs/product_import_job.rb`:

```ruby
class ProductImportJob
  include Sidekiq::Worker
  sidekiq_options queue: :etl, retry: 3

  def perform(file_path)
    checksum = calculate_checksum(file_path)

    # Check if already imported
    if ImportLog.exists?(file_checksum: checksum)
      Rails.logger.info "File already imported: #{file_path}"
      return
    end

    results = { successful: [], failed: [], total: 0 }

    CsvExtractor.extract(file_path) do |row, row_number|
      results[:total] += 1
      result = ProductTransformer.transform(row)

      if result[:valid]
        results[:successful] << result[:data]
      else
        results[:failed] << { row: row, row_number: row_number, errors: result[:errors] }
        record_failure(row, result[:errors], file_path, row_number)
      end
    end

    # Batch load successful records
    loaded_count = ProductLoader.load(results[:successful])

    # Log import summary
    ImportLog.create!(
      file_name: File.basename(file_path),
      file_checksum: checksum,
      row_count: results[:total],
      successful_count: loaded_count,
      failed_count: results[:failed].size
    )

    log_summary(file_path, loaded_count, results[:failed].size)
  end

  sidekiq_retries_exhausted do |job, exception|
    Rails.logger.error "Import job failed permanently: #{job['args'].first}"
    Rails.logger.error "Error: #{exception.message}"
  end

  private

  def calculate_checksum(file_path)
    Digest::MD5.file(file_path).hexdigest
  end

  def record_failure(row, errors, source_file, row_number)
    FailedImport.create!(
      row_data: row.merge(row_number: row_number),
      error_message: errors.join('; '),
      source_file: source_file
    )
  end

  def log_summary(file_path, successful, failed)
    Rails.logger.info "=" * 60
    Rails.logger.info "Import Summary for #{File.basename(file_path)}"
    Rails.logger.info "=" * 60
    Rails.logger.info "Successful: #{successful}"
    Rails.logger.info "Failed: #{failed}"
    Rails.logger.info "=" * 60
  end
end
```

### Step 6: Configure Sidekiq

Add to `Gemfile`:

```ruby
gem 'sidekiq'
```

Install:

```bash
bundle install
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

### Step 7: Test the Pipeline

Start Redis and Sidekiq:

```bash
# Terminal 1
redis-server

# Terminal 2
bundle exec sidekiq -q etl
```

In Rails console:

```ruby
# Create test CSV
require 'csv'
CSV.open('test_products.csv', 'w') do |csv|
  csv << ['sku', 'name', 'price', 'category']
  csv << ['PROD-001', 'Wireless Mouse', '$29.99', 'Electronics']
  csv << ['PROD-002', 'USB Cable', '9.99', 'Electronics']
  csv << ['PROD-003', 'Notebook', 'invalid', 'Office']
  csv << ['', 'Missing SKU', '19.99', 'Office']
  csv << ['PROD-004', 'Keyboard', '$149.99', 'Electronics']
end

# Enqueue import
ProductImportJob.perform_async('test_products.csv')

# Wait a few seconds, then check results
Product.count  # => 3
Product.pluck(:sku, :name, :price)
# => [["PROD-001", "Wireless Mouse", 29.99], ...]

FailedImport.count  # => 2
FailedImport.pluck(:error_message)
# => ["Invalid price format", "Missing required field: sku"]

# Check import log
log = ImportLog.last
log.successful_count  # => 3
log.failed_count  # => 2

# Test idempotency - re-run same file
ProductImportJob.perform_async('test_products.csv')
# Should skip (file checksum already exists)
Product.count  # => Still 3
```

## Stretch Goals

1. **Add email notifications:**

```ruby
# In ProductImportJob after import completes
AdminMailer.import_summary(
  file: file_path,
  successful: loaded_count,
  failed: results[:failed].size,
  failed_rows: results[:failed]
).deliver_now
```

2. **Add progress tracking with Redis:**

```ruby
def perform(file_path)
  # Set total rows
  Redis.current.set("import:#{jid}:total", results[:total])

  # Update progress in loop
  Redis.current.incr("import:#{jid}:processed")

  # Check progress from another process
  progress = Redis.current.get("import:#{jid}:processed").to_i
  total = Redis.current.get("import:#{jid}:total").to_i
  percent = (progress.to_f / total * 100).round(2)
end
```

3. **Add retry mechanism for failed rows:**

```ruby
class RetryFailedImportJob
  include Sidekiq::Worker

  def perform(failed_import_id)
    failed = FailedImport.find(failed_import_id)
    result = ProductTransformer.transform(failed.row_data.symbolize_keys)

    if result[:valid]
      Product.upsert(result[:data], unique_by: :sku)
      failed.destroy
      Rails.logger.info "Retry successful for row #{failed.id}"
    else
      Rails.logger.error "Retry failed: #{result[:errors].join(', ')}"
    end
  end
end
```

4. **Add API extraction:**

```ruby
class ApiProductImporter
  def self.import(api_endpoint)
    page = 1
    loop do
      response = HTTParty.get(api_endpoint, query: { page: page, per_page: 100 })
      products = JSON.parse(response.body)

      break if products.empty?

      products.each do |product|
        result = ProductTransformer.transform(product.symbolize_keys)
        Product.upsert(result[:data], unique_by: :sku) if result[:valid]
      end

      page += 1
    end
  end
end
```

## Time Estimate
25 minutes

## Solution Notes

**Common gotchas:**
- Forgetting unique index on `sku` causes `upsert_all` to fail
- Not streaming CSV leads to memory issues with large files
- Missing error handling for file encoding issues (try `encoding: 'UTF-8'` option)
- Not tracking import status means you can't detect duplicate imports
- Batch size too large (>5000) can cause memory spikes

**Performance tips:**
- Use `insert_all` instead of `upsert_all` if you know records are new (2x faster)
- Process in larger batches (5000-10000) for faster imports
- Disable AR callbacks during bulk import: `Product.insert_all(batch, record_timestamps: true)`
- Use database triggers for complex validation instead of Rails validations
