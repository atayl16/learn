# Report Generation Strategies

## What It Is

Report generation in Rails involves exporting large datasets to CSV, Excel, or PDF formats while maintaining acceptable response times and server resource usage. Production report systems must handle millions of rows, stream data to avoid memory exhaustion, cache expensive analytical queries, and queue long-running exports as background jobs.

## Why It Matters

Poorly implemented reports are a top cause of production outages. A single unoptimized export loading 500,000 rows into memory causes 2GB+ RAM spikes, triggering OOM kills and cascading failures. Streaming reports reduce memory from O(N) to O(1). Background jobs prevent 60-second request timeouts. Query caching eliminates redundant 30-second analytical queries when multiple users download the same daily report.

## When to Use

- CSV exports: any dataset over 1,000 rows should stream, over 10,000 rows should background process
- Excel exports: use background jobs for >5,000 rows due to XLSX formatting overhead
- Caching: analytical reports with GROUP BY, window functions, or multi-table JOINs taking >2 seconds
- Streaming: always stream CSV to prevent memory bloat, even for medium datasets
- Direct download: only for reports completing in <5 seconds with <1,000 rows

## Three Common Pitfalls

1. **Loading all rows into memory:** Using `Post.all.to_a` or `User.pluck(:email)` for large datasets loads millions of records into RAM, causing 500 errors. Always use `find_each` or CSV streaming.
2. **Blocking the web process:** Running a 45-second report export in a controller action hits Rack timeout (30s default), returns 500, but job keeps running. Move to Sidekiq with status polling.
3. **No query caching for repeated reports:** Ten users downloading the same "Monthly Sales" report each trigger a 20-second GROUP BY query. Cache query results with Rails.cache for 1 hour and serve from memory.

---

## CSV Streaming

Stream CSV rows directly to the HTTP response without buffering in memory:

```ruby
# app/controllers/reports_controller.rb
class ReportsController < ApplicationController
  def users_csv
    headers['Content-Type'] = 'text/csv'
    headers['Content-Disposition'] = 'attachment; filename=users.csv'
    headers['Last-Modified'] = Time.current.httpdate

    # Disable Rack buffering for streaming
    self.response_body = generate_csv_enumerator
  end

  private

  def generate_csv_enumerator
    Enumerator.new do |csv|
      # Stream CSV header
      csv << CSV.generate_line(['ID', 'Email', 'Created At'])

      # Stream rows in batches (find_each uses 1000 default)
      User.find_each do |user|
        csv << CSV.generate_line([user.id, user.email, user.created_at])
      end
    end
  end
end
```

**Memory usage:** 50MB constant regardless of dataset size.

**Before:** Loading 100,000 users with `.to_a` consumed 1.8GB RAM.

**After:** Streaming maintains 50MB RAM usage.

---

## Background Jobs for Large Exports

Offload slow reports to Sidekiq and notify users via email:

```ruby
# app/jobs/report_export_job.rb
class ReportExportJob < ApplicationJob
  queue_as :reports

  def perform(user_id, report_type, filters)
    user = User.find(user_id)
    filename = "#{report_type}_#{Time.current.to_i}.csv"
    filepath = Rails.root.join('tmp', filename)

    # Generate CSV file
    CSV.open(filepath, 'w') do |csv|
      csv << ['ID', 'Email', 'Revenue', 'Status']

      Report.generate(report_type, filters).find_each do |row|
        csv << [row.id, row.email, row.revenue, row.status]
      end
    end

    # Upload to S3
    s3_url = S3Uploader.upload(filepath, "reports/#{filename}")

    # Email download link
    ReportMailer.export_ready(user, s3_url).deliver_now

    # Cleanup
    File.delete(filepath)
  end
end

# app/controllers/reports_controller.rb
def export
  ReportExportJob.perform_later(current_user.id, params[:type], filters)
  flash[:notice] = "Report queued. You'll receive an email with download link."
  redirect_to reports_path
end
```

Users receive email with S3 presigned URL valid for 7 days.

---

## Caching Expensive Analytical Queries

Cache aggregated results for slow queries:

```ruby
class ReportsController < ApplicationController
  def monthly_revenue
    @report_data = Rails.cache.fetch("monthly_revenue_#{Date.current.month}", expires_in: 1.hour) do
      # Expensive query with GROUP BY and window functions
      ActiveRecord::Base.connection.execute(<<~SQL).to_a
        SELECT
          DATE_TRUNC('day', created_at) as day,
          SUM(amount) as revenue,
          COUNT(*) as order_count,
          AVG(amount) OVER (ORDER BY DATE_TRUNC('day', created_at) ROWS 7 PRECEDING) as moving_avg
        FROM orders
        WHERE created_at >= DATE_TRUNC('month', CURRENT_DATE)
        GROUP BY DATE_TRUNC('day', created_at)
        ORDER BY day
      SQL
    end

    render json: @report_data
  end
end
```

**Query time:** 23 seconds (uncached) → 8ms (cached).

Cache key includes month to auto-expire on month boundary.

---

## Excel Generation with caxlsx_rails

For formatted Excel exports with charts and styling:

```ruby
# Gemfile
gem 'caxlsx'
gem 'caxlsx_rails'

# app/views/reports/sales.xlsx.axlsx
wb = xlsx_package.workbook

wb.add_worksheet(name: "Sales Report") do |sheet|
  # Header row with bold styling
  sheet.add_row ['Date', 'Product', 'Revenue', 'Units'], style: wb.styles.add_style(b: true)

  # Data rows (use find_each for large datasets)
  @sales.find_each do |sale|
    sheet.add_row [sale.date, sale.product_name, sale.revenue, sale.units]
  end

  # Add chart
  sheet.add_chart(Axlsx::Chart, title: "Revenue Trend") do |chart|
    chart.add_series data: sheet["C2:C#{@sales.count + 1}"], labels: sheet["A2:A#{@sales.count + 1}"]
  end
end

# app/controllers/reports_controller.rb
def sales
  @sales = Sale.where('created_at >= ?', 30.days.ago)

  respond_to do |format|
    format.xlsx # Renders sales.xlsx.axlsx
  end
end
```

For >5,000 rows, move Excel generation to background job due to XLSX formatting overhead.

---

## Best Practices

1. **Always stream CSV:** Use enumerators and `find_each` to maintain O(1) memory usage regardless of row count.
2. **Background jobs for slow exports:** Any report taking >5 seconds should be async with email notification.
3. **Cache analytical queries:** Store aggregated results in Rails.cache with 1-hour TTL for repeated downloads.
4. **Presigned S3 URLs:** Store large exports in S3, send time-limited download links (avoid database BLOB storage).
5. **Monitor memory and query time:** Track P95 response time and memory usage per report type in APM.

---

## Key Terms

- **streaming:** generating CSV row-by-row without loading full dataset into memory
- **find_each:** ActiveRecord batch iterator that fetches 1,000 records at a time
- **enumerator:** Ruby object that yields values lazily without materializing full collection
- **presigned URL:** time-limited S3 download link that expires after N hours
- **query caching:** storing expensive query results in Rails.cache (Redis/Memcached)

---

## Summary

Report generation requires streaming for memory efficiency, background jobs for long-running exports, and caching for repeated analytical queries. Stream CSV with enumerators, queue Excel exports via Sidekiq, cache aggregated results for 1 hour, and serve downloads from S3 with presigned URLs. These patterns prevent OOM errors, timeout failures, and redundant expensive queries.

**Next steps:** Complete the exercise to build a streaming CSV report with background processing and query caching.
