# Exercise: Concurrency Primitives

## Objective
Build thread-safe code with Mutex, observe race conditions without synchronization, and compare Thread/Fiber/Ractor behavior under I/O and CPU workloads.

## Task
Create a Ruby script that:

1. Demonstrates a race condition in a counter (without Mutex)
2. Fixes the race condition using Mutex
3. Compares Thread vs Sequential execution for I/O-bound HTTP calls
4. (Optional) Uses Ractor for parallel CPU-bound work

## Acceptance Criteria
- [ ] Counter without Mutex produces incorrect results under concurrent access
- [ ] Counter with Mutex produces correct results (1000 increments = 1000)
- [ ] 5 threads making HTTP calls complete faster than sequential calls
- [ ] Script logs timing for sequential vs concurrent execution
- [ ] (Stretch) Ractor example processes array in parallel and returns results

## Setup Code

Create `concurrency_demo.rb`:

```ruby
require 'net/http'
require 'benchmark'

# Part 1: Race Condition Demo
class UnsafeCounter
  def initialize
    @count = 0
  end

  def increment
    # NOT atomic: read @count, add 1, write @count
    @count += 1
  end

  def value
    @count
  end
end

class SafeCounter
  def initialize
    @count = 0
    @mutex = Mutex.new
  end

  def increment
    @mutex.synchronize do
      @count += 1
    end
  end

  def value
    @mutex.synchronize { @count }
  end
end

puts "=== Part 1: Race Condition Demo ==="

# Test unsafe counter
unsafe = UnsafeCounter.new
threads = 10.times.map do
  Thread.new { 100.times { unsafe.increment } }
end
threads.each(&:join)
puts "Unsafe counter (expected 1000): #{unsafe.value}"

# Test safe counter
safe = SafeCounter.new
threads = 10.times.map do
  Thread.new { 100.times { safe.increment } }
end
threads.each(&:join)
puts "Safe counter (expected 1000): #{safe.value}"

# Part 2: I/O Concurrency with Threads
puts "\n=== Part 2: I/O-Bound Concurrency ==="

def fetch_url(id)
  uri = URI("https://jsonplaceholder.typicode.com/posts/#{id}")
  Net::HTTP.get(uri)
end

# Sequential execution
sequential_time = Benchmark.realtime do
  5.times { |i| fetch_url(i + 1) }
end
puts "Sequential (5 HTTP calls): #{sequential_time.round(2)}s"

# Concurrent execution with threads
concurrent_time = Benchmark.realtime do
  threads = 5.times.map do |i|
    Thread.new { fetch_url(i + 1) }
  end
  threads.each(&:join)
end
puts "Concurrent (5 threads): #{concurrent_time.round(2)}s"
puts "Speedup: #{(sequential_time / concurrent_time).round(2)}x"

```

## Verification Steps

1. Run the script:

```bash
ruby concurrency_demo.rb

```

2. Expected output:

```
=== Part 1: Race Condition Demo ===
Unsafe counter (expected 1000): 987  # ← Wrong! Race condition
Safe counter (expected 1000): 1000   # ← Correct with Mutex

=== Part 2: I/O-Bound Concurrency ===
Sequential (5 HTTP calls): 2.34s
Concurrent (5 threads): 0.52s
Speedup: 4.5x  # ← Threads excel at I/O

```

3. Observations:
   - Unsafe counter loses increments due to race conditions
   - Safe counter with Mutex is always correct
   - Threads provide 4-5x speedup for I/O-bound work (HTTP calls)

## Part 3: Fiber Example (Stretch)

Add this to demonstrate Fiber's manual control:

```ruby
puts "\n=== Part 3: Fiber Manual Control ==="

fiber = Fiber.new do
  puts "Fiber: Starting task"
  Fiber.yield "paused at checkpoint 1"
  puts "Fiber: Resumed, continuing"
  Fiber.yield "paused at checkpoint 2"
  puts "Fiber: Finished"
  "done"
end

puts "Main: Resuming fiber..."
puts "Result: #{fiber.resume}"  # => "paused at checkpoint 1"
puts "Main: Doing other work..."
puts "Result: #{fiber.resume}"  # => "paused at checkpoint 2"
puts "Main: Final resume..."
puts "Result: #{fiber.resume}"  # => "done"

```

## Part 4: Ractor Parallel Processing (Stretch, Ruby 3.0+)

Add this to compare Ractor parallelism:

```ruby
puts "\n=== Part 4: Ractor Parallel Processing ==="

# CPU-bound work: sum of squares
def cpu_work(numbers)
  numbers.map { |n| n ** 2 }.sum
end

data = (1..1_000_000).to_a

# Sequential
sequential_cpu = Benchmark.realtime do
  cpu_work(data)
end
puts "Sequential CPU work: #{sequential_cpu.round(2)}s"

# Parallel with Ractors (split into 4 chunks)
parallel_cpu = Benchmark.realtime do
  chunk_size = data.size / 4
  ractors = 4.times.map do |i|
    chunk = data[i * chunk_size, chunk_size]
    Ractor.new(chunk) do |nums|
      nums.map { |n| n ** 2 }.sum
    end
  end
  results = ractors.map(&:take)
  results.sum
end
puts "Parallel (4 Ractors): #{parallel_cpu.round(2)}s"
puts "Speedup: #{(sequential_cpu / parallel_cpu).round(2)}x"

```

**Note:** Ractor speedup depends on CPU cores. On a 4-core machine, expect ~3x speedup.

## Discussion Questions

1. Why does the unsafe counter lose increments?
2. When would you choose Fiber over Thread?
3. Why do threads speed up HTTP calls but not pure computation?
4. What happens if you remove `Mutex.synchronize` from the safe counter?
5. When should you use Ractor instead of forking processes?

## Time Estimate
25 minutes (15 min for Parts 1-2, 10 min for stretch goals)
