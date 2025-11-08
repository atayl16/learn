# Exercise: Memory & Garbage Collection Awareness

## Objective
Profile Ruby memory usage, interpret GC statistics, and optimize memory-heavy code using `memory_profiler`.

## Task
In a Rails app with bulk data processing:

1. Install and use `memory_profiler` to profile endpoint memory usage
2. Read and interpret `GC.stat` before and after operations
3. Identify memory bloat from loading all records vs batching
4. Optimize string concatenation and N+1 allocations
5. Compare memory usage before and after optimizations
6. Track object allocations by location

## Acceptance Criteria
- [ ] `memory_profiler` gem installed and profiling an endpoint
- [ ] Report shows allocated vs retained objects
- [ ] GC.stat logged before/after bulk operations
- [ ] Batch processing with `find_each` reduces memory by >50%
- [ ] String concatenation optimized using array join
- [ ] Memory profile identifies top 5 allocation hotspots
- [ ] Document shows memory reduction metrics

## Verification Steps

1. Unoptimized code profile:

```
Total allocated: 250 MB (2,500,000 objects)
Total retained: 50 MB (500,000 objects)

allocated memory by location:
  app/controllers/reports_controller.rb:10: 100 MB

```

2. After optimization:

```
Total allocated: 50 MB (500,000 objects)
Total retained: 10 MB (100,000 objects)

allocated memory by location:
  app/controllers/reports_controller.rb:10: 20 MB

```

3. GC stats comparison showing fewer live objects after optimization

## Setup Code

### Step 1: Create Rails App with Data

```bash
rails new memory_demo --skip-javascript
cd memory_demo
bin/rails generate model User name:string email:string
bin/rails generate model Post title:string body:text user:references
bin/rails db:migrate

```

**Seed data:**

```bash
bin/rails console

```

```ruby
# Create test data
500.times do |i|
  user = User.create(name: "User #{i}", email: "user#{i}@example.com")
  20.times do |j|
    Post.create(
      title: "Post #{j}",
      body: "Body content " * 100, # ~1.5 KB per post
      user: user
    )
  end
end

puts "Created #{User.count} users, #{Post.count} posts"

```

### Step 2: Install Memory Profiler

```bash
bundle add memory_profiler

```

### Step 3: Create Memory-Heavy Endpoint (Before Optimization)

Generate controller:

```bash
bin/rails generate controller Reports index

```

Edit `app/controllers/reports_controller.rb`:

```ruby
class ReportsController < ApplicationController
  def index
    # BEFORE: Memory-intensive implementation
    report = generate_report_unoptimized

    render plain: report
  end

  def optimized
    # AFTER: Optimized implementation
    report = generate_report_optimized

    render plain: report
  end

  private

  def generate_report_unoptimized
    # Problem 1: Loads all records into memory
    users = User.all.to_a

    # Problem 2: String concatenation in loop
    report = ""
    users.each do |user|
      # Problem 3: N+1 query
      report += "#{user.name}: #{user.posts.count} posts\n"
    end

    report
  end

  def generate_report_optimized
    # Solution 1: Batch processing
    report_lines = []

    User.find_each(batch_size: 100) do |user|
      # Solution 2: Array append + join
      # Solution 3: Eager load counter cache
      report_lines << "#{user.name}: #{user.posts.size} posts"
    end

    report_lines.join("\n")
  end
end

```

Add routes in `config/routes.rb`:

```ruby
Rails.application.routes.draw do
  get 'reports', to: 'reports#index'
  get 'reports/optimized', to: 'reports#optimized'
end

```

### Step 4: Profile Unoptimized Endpoint

Create `lib/tasks/profile_memory.rake`:

```ruby
require 'memory_profiler'

namespace :profile do
  desc "Profile memory usage of reports endpoint"
  task memory: :environment do
    puts "\n=== Profiling UNOPTIMIZED endpoint ==="

    # Clear GC state
    GC.start
    before_gc = GC.stat(:heap_live_slots)

    report = MemoryProfiler.report do
      ReportsController.new.send(:generate_report_unoptimized)
    end

    GC.start
    after_gc = GC.stat(:heap_live_slots)

    puts "\n--- Memory Report ---"
    report.pretty_print(scale_bytes: true)

    puts "\n--- GC Stats ---"
    puts "Live objects before: #{before_gc}"
    puts "Live objects after: #{after_gc}"
    puts "Leaked objects: #{after_gc - before_gc}"

    puts "\n=== Profiling OPTIMIZED endpoint ==="

    GC.start
    before_gc = GC.stat(:heap_live_slots)

    report = MemoryProfiler.report do
      ReportsController.new.send(:generate_report_optimized)
    end

    GC.start
    after_gc = GC.stat(:heap_live_slots)

    puts "\n--- Memory Report ---"
    report.pretty_print(scale_bytes: true)

    puts "\n--- GC Stats ---"
    puts "Live objects before: #{before_gc}"
    puts "Live objects after: #{after_gc}"
    puts "Leaked objects: #{after_gc - before_gc}"
  end
end

```

Run profile:

```bash
bin/rails profile:memory

```

### Step 5: Add GC Instrumentation

Create `config/initializers/gc_stats.rb`:

```ruby
# Log GC stats on each request
Rails.application.config.after_initialize do
  ActiveSupport::Notifications.subscribe("process_action.action_controller") do |*args|
    event = ActiveSupport::Notifications::Event.new(*args)

    gc_stats = {
      count: GC.stat(:count),
      live_slots: GC.stat(:heap_live_slots),
      free_slots: GC.stat(:heap_free_slots),
      total_allocated: GC.stat(:total_allocated_objects)
    }

    Rails.logger.info "GC Stats after #{event.payload[:action]}: #{gc_stats}"
  end
end

```

### Step 6: Test Manual GC Stats

```bash
bin/rails console

```

```ruby
# Check GC stats
puts GC.stat

# Allocate objects and watch GC
before_count = GC.stat(:count)

100_000.times { |i| "string #{i}" }

after_count = GC.stat(:count)
puts "GC ran #{after_count - before_count} times"

# Force GC
GC.start
puts "After forced GC: #{GC.stat(:heap_live_slots)} live objects"

```

### Step 7: Object Allocation Tracking

Create `lib/tasks/track_allocations.rake`:

```ruby
namespace :profile do
  desc "Track object allocations by location"
  task allocations: :environment do
    require 'objspace'

    ObjectSpace.trace_object_allocations_start

    # Run code to profile
    ReportsController.new.send(:generate_report_unoptimized)

    ObjectSpace.trace_object_allocations_stop

    # Group by allocation location
    allocations = Hash.new(0)

    ObjectSpace.each_object do |obj|
      next unless ObjectSpace.allocation_sourcefile(obj)
      location = "#{ObjectSpace.allocation_sourcefile(obj)}:#{ObjectSpace.allocation_sourceline(obj)}"
      allocations[location] += 1
    end

    # Show top 20 allocation locations
    puts "\n=== Top 20 Allocation Hotspots ==="
    allocations.sort_by { |k, v| -v }.first(20).each do |location, count|
      puts "#{count.to_s.rjust(8)} objects: #{location}"
    end
  end
end

```

Run:

```bash
bin/rails profile:allocations

```

### Step 8: Benchmark Memory Impact

Create `lib/tasks/benchmark_memory.rake`:

```ruby
require 'benchmark'

namespace :benchmark do
  desc "Benchmark memory and time for reports"
  task memory: :environment do
    controller = ReportsController.new

    puts "\n=== Benchmarking Unoptimized ==="
    Benchmark.bm(20) do |x|
      x.report("Unoptimized:") do
        controller.send(:generate_report_unoptimized)
      end
    end

    puts "\n=== Benchmarking Optimized ==="
    Benchmark.bm(20) do |x|
      x.report("Optimized:") do
        controller.send(:generate_report_optimized)
      end
    end

    # Memory comparison
    puts "\n=== Memory Comparison ==="

    GC.start
    before = `ps -o rss= -p #{Process.pid}`.to_i

    controller.send(:generate_report_unoptimized)

    after_unopt = `ps -o rss= -p #{Process.pid}`.to_i

    GC.start
    controller.send(:generate_report_optimized)

    after_opt = `ps -o rss= -p #{Process.pid}`.to_i

    puts "Unoptimized RSS increase: #{after_unopt - before} KB"
    puts "Optimized RSS increase: #{after_opt - after_unopt} KB"
  end
end

```

Run:

```bash
bin/rails benchmark:memory

```

### Step 9: Add Counter Cache (Further Optimization)

Optimize N+1 counting with counter cache:

```bash
bin/rails generate migration AddPostsCountToUsers posts_count:integer

```

Edit migration:

```ruby
class AddPostsCountToUsers < ActiveRecord::Migration[7.0]
  def change
    add_column :users, :posts_count, :integer, default: 0, null: false

    # Backfill existing counts
    reversible do |dir|
      dir.up do
        User.find_each do |user|
          User.reset_counters(user.id, :posts)
        end
      end
    end
  end
end

```

```bash
bin/rails db:migrate

```

Update model:

```ruby
# app/models/post.rb
class Post < ApplicationRecord
  belongs_to :user, counter_cache: true
end

```

Update optimized report:

```ruby
def generate_report_optimized
  report_lines = []

  User.find_each(batch_size: 100) do |user|
    # Now uses cached count (no query)
    report_lines << "#{user.name}: #{user.posts_count} posts"
  end

  report_lines.join("\n")
end

```

Re-run profile to see further memory reduction.

## Stretch (Optional)

1. Tune GC settings and measure impact:

```bash
RUBY_GC_HEAP_GROWTH_FACTOR=1.2 bin/rails server

```

2. Create a memory leak detector:

```ruby
# Detect leaks by tracking live objects over requests
leaked = []
10.times do
  GC.start
  leaked << GC.stat(:heap_live_slots)
end
puts "Leak trend: #{leaked}" # Should be stable, not growing

```

3. Profile different batch sizes (100 vs 500 vs 1000) for optimal memory/speed trade-off.

## Time Estimate
20 minutes
