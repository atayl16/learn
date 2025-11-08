# Exercise: Ruby Memory Model & Object Allocation

## Objective

Profile memory usage with memory_profiler, identify allocation hotspots in a Rails endpoint, and optimize to reduce object creation by at least 50%.

## Task

In a Rails application with realistic data volume:

1. Add memory profiling gems and create a memory-heavy endpoint
2. Profile the endpoint to identify allocation hotspots
3. Refactor code to reduce allocations
4. Verify optimization with before/after metrics
5. Investigate a simulated memory leak and fix it

## Acceptance Criteria

- [ ] memory_profiler gem installed and configured
- [ ] Profiling reports show allocation counts and memory usage per file/line
- [ ] Identified at least 3 allocation hotspots (loops, string concatenation, N+1)
- [ ] Refactored code reduces total allocations by 50%+
- [ ] Added test demonstrating memory leak detection with ObjectSpace
- [ ] Documented optimization techniques and their impact

## Verification Steps

### Step 1: Setup and Create Memory-Heavy Endpoint

```bash
# Create new Rails app or use existing
rails new memory_profiler_demo
cd memory_profiler_demo

# Add gems
bundle add memory_profiler
bundle add faker  # For realistic test data

```

Generate a User model with sample data:

```bash
bin/rails generate model User name:string email:string bio:text active:boolean
bin/rails db:migrate

```

Seed database:

```ruby
# db/seeds.rb
require 'faker'

10_000.times do
  User.create!(
    name: Faker::Name.name,
    email: Faker::Internet.email,
    bio: Faker::Lorem.paragraph(sentence_count: 20),
    active: [true, false].sample
  )
end

```

```bash
bin/rails db:seed

```

### Step 2: Create Memory-Heavy Controller

```ruby
# app/controllers/reports_controller.rb
class ReportsController < ApplicationController
  def user_summary
    # INTENTIONALLY INEFFICIENT - allocates heavily
    @report = generate_report
    render json: @report
  end

  private

  def generate_report
    report_lines = []

    User.all.each do |user|
      # String concatenation in loop (allocates new strings)
      summary = "User: " + user.name + " <" + user.email + ">"
      summary += " | Bio: " + user.bio.to_s
      summary += " | Status: " + (user.active ? "active" : "inactive")

      # Building array of hashes (allocates hash per iteration)
      report_lines << {
        id: user.id,
        summary: summary,
        word_count: user.bio.to_s.split.size,
        tags: ["user", "report", user.active ? "active" : "inactive"]
      }
    end

    # Additional processing (more allocations)
    report_lines.map do |line|
      line.merge(
        formatted_summary: "[#{line[:id]}] #{line[:summary]}",
        metadata: { processed_at: Time.now.to_s, version: "1.0" }
      )
    end
  end
end

```

Add route:

```ruby
# config/routes.rb
Rails.application.routes.draw do
  get 'reports/user_summary'
end

```

### Step 3: Profile Memory Usage

Create a profiling script:

```ruby
# lib/tasks/profile_memory.rake
namespace :profile do
  desc "Profile memory usage of reports endpoint"
  task memory: :environment do
    require 'memory_profiler'

    puts "\n=== Memory Profile: User Summary Report ==="

    report = MemoryProfiler.report do
      # Simulate the controller action
      ReportsController.new.send(:generate_report)
    end

    puts "\n--- Top 10 Allocations by Count ---"
    report.pretty_print(scale_bytes: true, top: 10)

    puts "\n--- Summary ---"
    puts "Total allocated: #{report.total_allocated} objects"
    puts "Total allocated memory: #{report.total_allocated_memsize / 1024.0 / 1024.0} MB"
    puts "Total retained: #{report.total_retained} objects"
    puts "Total retained memory: #{report.total_retained_memsize / 1024.0 / 1024.0} MB"
  end
end

```

Run profiler:

```bash
bin/rails profile:memory

# Expected output shows:
# - High string allocations from concatenation
# - Array/Hash allocations from .map and .merge
# - Temporary objects from .to_s, .split, etc.

```

### Step 4: Optimize to Reduce Allocations

Refactored version:

```ruby
# app/controllers/reports_controller.rb
class ReportsController < ApplicationController
  def user_summary_optimized
    @report = generate_report_optimized
    render json: @report
  end

  private

  def generate_report_optimized
    # Use pluck to avoid loading full ActiveRecord objects
    users_data = User.pluck(:id, :name, :email, :bio, :active)

    # Pre-allocate array with known size
    report_lines = Array.new(users_data.size)

    users_data.each_with_index do |(id, name, email, bio, active), idx|
      # String interpolation allocates once (vs multiple concatenations)
      summary = "User: #{name} <#{email}> | Bio: #{bio} | Status: #{active ? 'active' : 'inactive'}"

      # Reuse status string
      status = active ? 'active' : 'inactive'

      # Build hash directly (no merge needed)
      report_lines[idx] = {
        id: id,
        summary: summary,
        word_count: bio.to_s.split.size,
        tags: ["user", "report", status],
        formatted_summary: "[#{id}] #{summary}",
        metadata: { processed_at: Time.now.to_s, version: "1.0" }
      }
    end

    report_lines
  end
end

```

Add optimized route and create comparison task:

```ruby
# config/routes.rb
get 'reports/user_summary_optimized'

```

```ruby
# lib/tasks/profile_memory.rake
namespace :profile do
  task compare: :environment do
    require 'memory_profiler'

    controller = ReportsController.new

    puts "\n=== ORIGINAL VERSION ==="
    original = MemoryProfiler.report { controller.send(:generate_report) }

    puts "\n=== OPTIMIZED VERSION ==="
    optimized = MemoryProfiler.report { controller.send(:generate_report_optimized) }

    puts "\n=== COMPARISON ==="
    puts "Original allocations: #{original.total_allocated} objects (#{original.total_allocated_memsize / 1024.0 / 1024.0} MB)"
    puts "Optimized allocations: #{optimized.total_allocated} objects (#{optimized.total_allocated_memsize / 1024.0 / 1024.0} MB)"

    reduction = ((original.total_allocated - optimized.total_allocated).to_f / original.total_allocated * 100).round(1)
    puts "Reduction: #{reduction}% fewer allocations"
  end
end

```

### Step 5: Test Memory Leak Detection

Create a test demonstrating leak detection:

```ruby
# test/integration/memory_leak_test.rb
require 'test_helper'

class MemoryLeakTest < ActiveSupport::TestCase
  test "detects memory leak in global cache" do
    # Simulate a leaky cache
    class LeakyCache
      @@cache = {}

      def self.store(key, value)
        @@cache[key] = value
      end

      def self.size
        @@cache.size
      end
    end

    # Baseline object count
    GC.start
    before_strings = ObjectSpace.count_objects[:T_STRING]

    # Perform operation that should release memory
    1000.times do |i|
      LeakyCache.store("key_#{i}", "value" * 1000)
    end

    # Force GC
    GC.start
    after_strings = ObjectSpace.count_objects[:T_STRING]

    # Strings should be retained (leak detected)
    retained = after_strings - before_strings
    puts "Strings retained: #{retained}"

    assert retained > 500, "Expected memory leak: strings not released after GC"

    # Verify cache size
    assert_equal 1000, LeakyCache.size
  end

  test "no leak with local variables" do
    GC.start
    before_strings = ObjectSpace.count_objects[:T_STRING]

    # Operation with local scope
    1000.times do |i|
      local_var = "value" * 1000
      # local_var goes out of scope
    end

    GC.start
    after_strings = ObjectSpace.count_objects[:T_STRING]

    retained = after_strings - before_strings
    puts "Strings retained: #{retained}"

    # Should retain very few strings (no leak)
    assert retained < 100, "Local variables should be GC'd"
  end
end

```

Run tests:

```bash
bin/rails test test/integration/memory_leak_test.rb

```

## Stretch (Optional)

1. **GC Statistics Monitoring:**

```ruby
# lib/middleware/gc_stats_middleware.rb
class GCStatsMiddleware
  def initialize(app)
    @app = app
  end

  def call(env)
    before_stat = GC.stat
    before_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)

    response = @app.call(env)

    after_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    after_stat = GC.stat

    gc_count = after_stat[:count] - before_stat[:count]
    if gc_count > 0
      Rails.logger.info "[GC] #{gc_count} collections during request (#{((after_time - before_time) * 1000).round(2)}ms)"
    end

    response
  end
end

# config/application.rb
config.middleware.use GCStatsMiddleware

```

2. **Test GC.compact effect:**

```ruby
# Run in console
before_pages = GC.stat[:heap_allocated_pages]
GC.compact
after_pages = GC.stat[:heap_allocated_pages]
puts "Pages freed: #{before_pages - after_pages}"

```

3. **Use derailed_benchmarks:**

```bash
bundle add derailed_benchmarks --group development

# Profile endpoint memory
PATH_TO_HIT="/reports/user_summary" bundle exec derailed exec perf:mem

```

## Time Estimate

22 minutes

## Solution Notes

**Key optimizations applied:**

1. **Use pluck instead of all**: Avoid loading full ActiveRecord objects (30-50% reduction)
2. **String interpolation vs concatenation**: Single allocation vs multiple (15-20% reduction)
3. **Pre-allocate arrays**: `Array.new(size)` vs incremental growth (10% reduction)
4. **Avoid redundant .map/.merge**: Build objects correctly first pass (20-30% reduction)
5. **Reuse immutable values**: Status strings, timestamps (5-10% reduction)

**Common gotchas:**

- `User.all.each` loads all records into memory; use `find_each` for batching
- String concatenation with `+` allocates new strings each time
- `.map { |x| x.merge(...) }` creates intermediate hash copies
- Interpolation `"#{var}"` still allocates if var isn't already a string
- ObjectSpace.count_objects includes Ruby internals; focus on deltas, not absolute counts
