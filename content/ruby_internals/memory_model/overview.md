# Ruby Memory Model & Object Allocation

## What It Is

Ruby's memory model governs how objects are allocated on the heap, tracked by the garbage collector (GC), and eventually freed. The Ruby heap is organized into pages containing object slots, with the GC using a tri-color mark-and-sweep algorithm plus optional compaction to reclaim unused memory. Memory profiling tools like memory_profiler and derailed_benchmarks measure allocation patterns, identify hotspots, and detect leaks where objects aren't released despite being unreachable.

## Why It Matters

Memory issues cause production incidents: bloated processes consume server RAM until they're OOM-killed, slow GC pauses freeze request threads, and memory leaks force frequent restarts. Understanding allocation patterns lets you optimize hot paths (reducing allocations in loops), detect retained references preventing GC (caches, global variables, closures), and tune GC parameters for your workload (server vs short-lived scripts).

## When to Use

- Diagnose high memory usage or OOM crashes in production Rails processes
- Optimize allocation hotspots in performance-critical endpoints or background jobs
- Investigate memory leaks where process size grows unbounded over time
- Tune GC parameters (RUBY_GC_HEAP_GROWTH_FACTOR, MALLOC_ARENA_MAX) for workload characteristics
- Profile memory impact before/after refactoring object-heavy code

## Three Common Pitfalls

1. **Global caches without eviction policies:** Storing objects in class variables, constants, or Redis without expiration causes unbounded growth. Each cached object stays in heap memory forever, preventing GC.
2. **Allocating in hot loops:** Creating temporary strings, arrays, or hashes inside frequently-called methods (per-request filters, N+1 queries) generates millions of objects. Use in-place operations or pre-allocate when possible.
3. **Closures capturing large scopes:** Blocks and procs retain references to all local variables in scope, even if unused. A single retained object can keep an entire request's object graph alive, preventing GC collection.

---

## Ruby Heap and Object Slots

The Ruby heap is organized into 16KB pages, each containing slots for objects:

```ruby
# Check current heap statistics
GC.stat
# => {:count=>50, :heap_allocated_pages=>200, :heap_live_slots=>80000, ...}

# Each page holds ~408 slots (40 bytes per slot)
# Strings >23 bytes allocate additional heap memory beyond the slot

```

Objects smaller than 40 bytes fit in a single slot. Larger objects (long strings, large arrays) allocate extra memory:

```ruby
require 'objspace'

# Small string: 1 slot
str1 = "hello"
ObjectSpace.memsize_of(str1)  # => 40 bytes

# Large string: 1 slot + heap allocation
str2 = "a" * 1000
ObjectSpace.memsize_of(str2)  # => 1040 bytes (slot + 1000 char buffer)

```

**Key insight:** Object count matters more than size for GC performance. 1000 small objects trigger GC more than one 1MB string.

---

## GC Phases: Mark, Sweep, Compact

Ruby's GC runs in phases:

**1. Mark Phase**

Starting from GC roots (stack variables, globals, constants), traverse object references and mark reachable objects:

```ruby
# GC roots include:
# - Local variables on stack
# - Instance variables of live objects
# - Constants and global variables
# - Objects in finalizer registry

class Cache
  @@data = {}  # GC root: retained forever unless explicitly cleared
end

```

**2. Sweep Phase**

Iterate through heap slots and free unmarked objects:

```ruby
# Trigger manual GC
GC.start

# Objects without references are swept
temp = Array.new(10_000) { |i| "string_#{i}" }
temp = nil  # Array and strings now unreachable

GC.start  # Sweep phase reclaims memory

```

**3. Compact Phase (Ruby 2.7+)**

Optionally move live objects together to reduce fragmentation:

```ruby
# Enable auto-compaction
GC.auto_compact = true

# Or trigger manually
GC.compact

# Reduces heap fragmentation, improves memory locality

```

Compaction is expensive (requires updating all references) but reduces memory fragmentation in long-running processes.

---

## Memory Profiling with memory_profiler

Track allocations per code path:

```ruby
# Gemfile
gem 'memory_profiler'

# In code
require 'memory_profiler'

report = MemoryProfiler.report do
  1000.times do
    User.where(active: true).pluck(:email)
  end
end

report.pretty_print

# Output shows:
# Total allocated: 50000 objects (2.5 MB)
# Top allocations:
#   app/models/user.rb:15  - 30000 String objects
#   activerecord-7.0.4/lib/active_record/result.rb:45 - 10000 Array objects

```

**What to look for:**
- High allocation counts in your code (vs gems)
- Temporary objects created in loops
- Unexpected large allocations (serialization, JSON parsing)

---

## Profiling with derailed_benchmarks

Test memory usage of entire request paths:

```bash
# Gemfile
gem 'derailed_benchmarks', group: :development

# Profile a controller action
bundle exec derailed bundle:mem

# Output:
# TOP: 85.5 MB
#   require 'active_support' => 12.3 MB
#   require 'action_view' => 8.7 MB

# Profile specific endpoint
DERAILED_SCRIPT_COUNT=100 bundle exec derailed exec perf:mem_over_time

```

This runs requests repeatedly and measures memory growth, revealing leaks or high allocations.

---

## Identifying Memory Leaks

A leak occurs when objects remain reachable (preventing GC) despite being logically unused:

```ruby
# Leak example: global cache without eviction
class ReportCache
  @@reports = {}

  def self.fetch(id)
    @@reports[id] ||= Report.find(id).generate_expensive_data
  end
end

# Every unique ID stays in memory forever
1_000_000.times { |i| ReportCache.fetch(i) }

```

**Detection strategy:**

```ruby
# Track object counts over time
before = ObjectSpace.count_objects
1000.times { do_operation }
GC.start
after = ObjectSpace.count_objects

# Compare counts
(after.keys & before.keys).each do |key|
  diff = after[key] - before[key]
  puts "#{key}: +#{diff}" if diff > 0
end

```

Look for growing counts of T_STRING, T_ARRAY, T_HASH, or T_DATA (native objects).

---

## GC Tuning Parameters

Environment variables control GC behavior:

```bash
# Increase heap growth factor for fewer GC cycles (trades memory for speed)
export RUBY_GC_HEAP_GROWTH_FACTOR=1.2  # Default: 1.1

# Increase heap size before triggering GC
export RUBY_GC_HEAP_INIT_SLOTS=100000  # Default: 10000

# Reduce malloc arena fragmentation (glibc-specific)
export MALLOC_ARENA_MAX=2

```

**When to tune:**
- High GC time in NewRelic/Scout (increase growth factor)
- Frequent restarts due to memory limits (decrease growth factor)
- Many short-lived processes (use defaults)

---

## Trade-offs Box

- **Advantage:** Profiling reveals allocation hotspots (100x speedup from eliminating string concatenation in loops); tuning GC reduces pause frequency in high-throughput apps.
- **Cost:** Memory optimization adds code complexity (object pooling, in-place operations); aggressive GC tuning trades memory for CPU or vice versa.
- **When to skip:** Pre-optimization wastes time; profile production first. Don't tune GC until memory issues appear in metrics.

---

## Debugging Checklist

When investigating memory issues:

1. Check process memory growth: `ps aux | grep ruby` or metrics dashboard
2. Profile allocations with memory_profiler in development
3. Run derailed_benchmarks to measure request memory impact
4. Search for global variables, class variables, constants holding collections
5. Inspect closures/blocks for unintended variable captures
6. Check for missing pagination (loading entire tables into memory)
7. Review caching layers for unbounded growth (no TTL, no eviction)
8. Use ObjectSpace.each_object to count instances of specific classes
9. Enable GC.stat logging to track heap growth over time
10. Test with GC.compact to see if fragmentation is the issue

---

## One-Minute Recap

- Ruby heap stores objects in 40-byte slots across 16KB pages; large objects allocate additional memory
- GC uses mark-sweep-compact: mark reachable objects, sweep unreachable ones, optionally compact fragmentation
- memory_profiler shows per-line allocations; derailed_benchmarks profiles full request memory usage
- Leaks occur when objects stay reachable (globals, caches, closures) despite being logically unused
- Tune GC via environment variables only after profiling reveals specific bottlenecks
