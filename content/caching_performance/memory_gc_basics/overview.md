# Memory & Garbage Collection Awareness

## What It Is
Ruby's garbage collector (GC) automatically frees memory from unused objects. Every object allocation (strings, hashes, Active Record models) consumes memory until GC runs. GC stats (`GC.stat`) show how often GC runs, how much memory is used, and how many objects exist. Memory profiling tools like `memory_profiler` identify which code allocates the most objects, helping you optimize memory-heavy endpoints.

## Why It Matters
Memory bloat degrades performance: servers slow down as they approach RAM limits, triggering frequent GC pauses that block request processing. A single endpoint allocating 100MB per request can cause OOM crashes under load. Production apps with memory leaks restart servers nightly. Understanding object allocation and GC behavior helps you write memory-efficient code and diagnose production memory issues.

## When to Use
- Profiling slow endpoints with high memory usage
- Investigating memory leaks (memory grows over time, never released)
- Optimizing bulk operations (CSV imports, batch jobs)
- Tuning GC settings for specific workloads
- Monitoring production memory via APM tools (New Relic, Datadog)

## Three Common Pitfalls
1. **Loading large collections into memory:** `Post.all.to_a` on 100k records allocates millions of objects. Use `find_each` to batch process.
2. **Ignoring GC stats in production:** Memory grows slowly until OOM crash. Monitor `GC.stat[:heap_live_slots]` and restart if it trends upward.
3. **Over-optimizing premature:** Not every allocation is a problem. Profile first; optimize only the top memory offenders (80/20 rule).

---

## Ruby Object Allocation

Every Ruby expression allocates objects:

```ruby
# Allocates: 1 string, 1 array, 1 hash
user = User.find(1)
# Allocates: 1 User instance, multiple strings/hashes from DB adapter

# Allocates: N User objects + attributes (strings, integers)
users = User.limit(1000).to_a
```

Use `ObjectSpace` to count allocations:

```ruby
before = GC.stat(:total_allocated_objects)

1000.times { |i| "string #{i}" }

after = GC.stat(:total_allocated_objects)
puts "Allocated: #{after - before} objects" # ~1000 strings
```

---

## GC Statistics

Inspect GC behavior:

```ruby
GC.stat
# Returns hash with metrics:
# {
#   count: 42,                  # Times GC ran
#   heap_allocated_pages: 150,
#   heap_live_slots: 50000,     # Currently live objects
#   total_allocated_objects: 1200000,
#   malloc_increase_bytes: 500000
# }
```

**Key metrics:**
- `count`: GC runs (high count = frequent pauses)
- `heap_live_slots`: Active objects in memory
- `total_allocated_objects`: Cumulative allocations
- `malloc_increase_bytes`: Memory from C extensions

**Monitor in production:**
```ruby
# Log GC stats per request
Rails.logger.info "GC count: #{GC.stat(:count)}, Live objects: #{GC.stat(:heap_live_slots)}"
```

---

## Memory Profiler Gem

Profile memory usage by code:

```ruby
# Gemfile
gem 'memory_profiler'

require 'memory_profiler'

report = MemoryProfiler.report do
  1000.times { User.create(name: "User") }
end

report.pretty_print
```

**Output:**
```
Total allocated: 50.2 MB (500,000 objects)
Total retained: 12.5 MB (125,000 objects)

allocated memory by gem:
  activerecord-7.0.0: 30.1 MB
  app/models: 15.0 MB

allocated objects by location:
  app/models/user.rb:10: 250,000 objects
  activerecord/lib/connection.rb:42: 100,000 objects
```

**Allocated vs Retained:**
- Allocated: total objects created during profiling
- Retained: objects still in memory after GC (potential leaks)

---

## Profiling Endpoints

Profile controller actions:

```ruby
# In controller
def index
  report = MemoryProfiler.report do
    @posts = Post.includes(:author).limit(100).to_a
  end

  report.pretty_print(to_file: 'tmp/memory_profile.txt')

  render :index
end
```

Check `tmp/memory_profile.txt` for allocation hotspots.

**Automate profiling in tests:**
```ruby
# test/performance/memory_test.rb
require 'test_helper'
require 'memory_profiler'

class MemoryTest < ActiveSupport::TestCase
  test "posts index memory usage" do
    report = MemoryProfiler.report do
      get posts_path
    end

    assert report.total_allocated_memsize < 10.megabytes, "Allocates too much memory"
  end
end
```

---

## Object Allocation Tracking

Track allocations per line:

```ruby
require 'objspace'

ObjectSpace.trace_object_allocations_start

1000.times { User.create(name: "User") }

ObjectSpace.trace_object_allocations_stop

# Find where most objects were allocated
allocations = ObjectSpace.each_object.group_by do |obj|
  ObjectSpace.allocation_sourcefile(obj)
end

allocations.each do |file, objs|
  puts "#{file}: #{objs.size} objects"
end
```

Use for debugging which gems or lines allocate heavily.

---

## Common Memory Bloat Patterns

**1. Loading all records:**
```ruby
# BAD: loads 100k records into memory
User.all.each { |user| process(user) }

# GOOD: batches in 1k chunks
User.find_each(batch_size: 1000) { |user| process(user) }
```

**2. N+1 allocations:**
```ruby
# BAD: allocates 1 User object per post
posts.each { |post| post.user.name }

# GOOD: allocates N users once
posts = Post.includes(:user)
posts.each { |post| post.user.name }
```

**3. String concatenation in loops:**
```ruby
# BAD: creates N string objects
result = ""
1000.times { result += "x" }

# GOOD: single array + join
result = []
1000.times { result << "x" }
result.join
```

---

## GC Tuning (Advanced)

Adjust GC behavior via environment variables:

```bash
# Increase heap size before GC runs (reduces frequency but uses more RAM)
export RUBY_GC_HEAP_GROWTH_FACTOR=1.1
export RUBY_GC_HEAP_INIT_SLOTS=600000
export RUBY_GC_MALLOC_LIMIT=16000000

bin/rails server
```

**Trade-off:** Larger heaps reduce GC pauses but consume more memory.

**Monitor impact:**
```ruby
# Before tuning
GC.stat(:count) # => 150 (many GC runs)

# After tuning
GC.stat(:count) # => 50 (fewer GC runs, but higher RAM usage)
```

Test in staging before production. Over-tuning can cause OOM.

---

## Memory Leak Detection

Memory leak: memory grows over time, never released.

**Test for leaks:**
```ruby
# Run in production console
before = GC.stat(:heap_live_slots)
GC.start # Force GC

# Perform actions
100.times { get '/posts' }

GC.start
after = GC.stat(:heap_live_slots)

puts "Leaked objects: #{after - before}"
```

If `after` significantly exceeds `before`, investigate retained objects.

**Common leak sources:**
- Class variables storing references
- Global caches without expiration
- C extensions not freeing memory

---

## Production Memory Monitoring

Track memory metrics:

```ruby
# config/initializers/memory_monitoring.rb
Rails.application.config.after_initialize do
  Thread.new do
    loop do
      sleep 60
      stats = {
        live_objects: GC.stat(:heap_live_slots),
        gc_count: GC.stat(:count),
        rss_mb: `ps -o rss= -p #{Process.pid}`.to_i / 1024
      }
      Rails.logger.info "Memory stats: #{stats}"
    end
  end
end
```

**APM tools (preferred):**
- New Relic: memory per transaction
- Datadog: heap size, GC time
- Scout APM: memory allocations by endpoint

Set alerts for memory thresholds (e.g., alert if RSS > 1GB).

---

## Trade-offs Box
- **Advantage:** Memory profiling identifies allocation hotspots, reducing memory usage by 30-70% and preventing OOM crashes.
- **Cost:** Profiling adds overhead (10-50% slower); GC tuning requires careful testing to avoid trading memory for crashes.
- **When to skip:** When memory usage is low (<500MB per worker), endpoints are fast, and no OOM issues occur in production.

---

## Debugging Checklist

When investigating memory issues:

1. Profile endpoint with `memory_profiler` to find allocation hotspots
2. Check `GC.stat(:heap_live_slots)` before/after requests for leaks
3. Use `find_each` instead of `all.each` for large datasets
4. Verify eager loading doesn't over-fetch (use Bullet gem)
5. Monitor production RSS (resident set size) via APM or `ps`
6. Look for retained objects: `report.total_retained_memsize`
7. Test GC tuning in staging before production
8. Check for global variables or class variables holding references

---

## One-Minute Recap
- Ruby GC automatically frees unused objects; track with `GC.stat`
- Use `memory_profiler` gem to identify code allocating most memory
- Common bloat: loading all records, N+1, string concatenation in loops
- Use `find_each` for batch processing large datasets
- Monitor production memory with APM tools; alert on thresholds
