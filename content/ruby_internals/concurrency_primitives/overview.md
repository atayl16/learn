# Concurrency Primitives (Ractor, Fiber, Thread)

## What It Is
Ruby provides three concurrency primitives: Thread for concurrent execution, Fiber for cooperative multitasking, and Ractor for true parallelism. Each operates differently under Ruby's Global VM Lock (GVL), which prevents true parallel execution of Ruby code in threads. Understanding when to use each primitive and how to write thread-safe code with Mutex is critical for building performant, scalable Rails applications.

## Why It Matters
Most Rails apps use background job processors (Sidekiq, GoodJob) that rely on threads for concurrency. Without understanding thread safety, you'll ship race conditions that corrupt data in production. Knowing when the GVL allows parallelism (I/O-bound work) versus when it doesn't (CPU-bound work) helps you optimize throughput. Ractors (Ruby 3.0+) enable CPU parallelism but require copying data between actors. Fibers power Async gems and cooperative task switching.

## When to Use
- **Thread:** I/O-bound tasks (HTTP calls, DB queries) where threads yield the GVL during waits. Most Sidekiq workers use threads.
- **Fiber:** Event-driven systems (web servers like Falcon), cooperative scheduling, or when you need manual control over task switching.
- **Ractor:** CPU-bound parallel processing (image resizing, data transformation) where you need to bypass the GVL.
- **Mutex:** Protecting shared state (instance variables, class variables, globals) accessed by multiple threads.

## Three Common Pitfalls
1. **Assuming threads = parallelism:** Ruby's GVL prevents parallel Ruby code execution. Threads help with I/O concurrency but won't parallelize CPU work. Use Ractors for true parallelism.
2. **Missing Mutex protection:** Concurrent writes to shared state (incrementing counters, modifying hashes) cause race conditions. Always use Mutex to synchronize access.
3. **Passing mutable objects to Ractors:** Ractors require deep-copying most objects or using shareable frozen objects. Passing mutable state raises `Ractor::IsolationError`.

---

## Thread: Concurrent Execution

Threads run concurrently but share memory. The GVL prevents parallel Ruby code execution but releases during I/O:

```ruby
# Concurrent I/O (3 HTTP calls in parallel)
threads = 3.times.map do |i|
  Thread.new do
    response = Net::HTTP.get(URI("https://api.example.com/#{i}"))
    puts "Got response #{i}"
  end
end
threads.each(&:join)  # Wait for all threads

```

**Key behavior:**
- Threads share memory (instance variables, globals)
- GVL allows one thread to execute Ruby code at a time
- I/O operations (HTTP, DB, file reads) release the GVL, enabling concurrency
- CPU-bound work (parsing, computation) holds the GVL, blocking other threads

---

## Fiber: Cooperative Multitasking

Fibers are lightweight, manually-scheduled execution contexts:

```ruby
fiber = Fiber.new do
  puts "Fiber started"
  Fiber.yield "paused"
  puts "Fiber resumed"
  "done"
end

puts fiber.resume  # => "Fiber started", returns "paused"
puts fiber.resume  # => "Fiber resumed", returns "done"

```

**When to use Fibers:**
- Building custom schedulers (Async gem uses Fibers for async/await)
- Event-driven servers (Falcon web server)
- Generators or lazy evaluation

**Not for:** Typical Rails apps. Stick with threads unless you need fine-grained control over scheduling.

---

## Ractor: True Parallelism (Ruby 3.0+)

Ractors are isolated execution units that run in parallel:

```ruby
# Parallel CPU work (bypasses GVL)
ractor = Ractor.new(name: "worker") do
  data = Ractor.receive  # Wait for message
  result = data.map { |n| n * n }  # CPU-bound work
  result
end

ractor.send([1, 2, 3, 4, 5])
puts ractor.take  # => [1, 4, 9, 16, 25]

```

**Key constraints:**
- Ractors don't share memory (copies or moves data between actors)
- Most objects are deep-copied when sent
- Frozen, immutable objects can be shared without copying
- Raises `Ractor::IsolationError` for unshareable objects (I/O, Threads)

**Use cases:**
- Parallel data processing (CSV parsing, image resizing)
- Multi-core utilization for CPU-heavy tasks
- Replacing forking for parallelism in memory-constrained environments

---

## Mutex: Thread Safety

Mutex (mutual exclusion) prevents race conditions by serializing access to shared state:

```ruby
class Counter
  def initialize
    @count = 0
    @mutex = Mutex.new
  end

  def increment
    @mutex.synchronize do
      @count += 1  # Atomic: no race condition
    end
  end

  def value
    @mutex.synchronize { @count }
  end
end

# Without Mutex, concurrent increments lose updates
counter = Counter.new
threads = 10.times.map { Thread.new { 100.times { counter.increment } } }
threads.each(&:join)
puts counter.value  # => 1000 (correct with Mutex)

```

**Critical sections:**
- Any code modifying shared state (instance vars, class vars, globals) needs Mutex
- Read-modify-write operations (`@count += 1`) are NOT atomic without Mutex
- Thread-safe data structures (Queue, SizedQueue) use Mutex internally

---

## The Global VM Lock (GVL)

Ruby's GVL ensures only one thread executes Ruby code at a time:

**When GVL is released:**
- I/O operations (network, disk, DB queries)
- C extensions that call `rb_thread_call_without_gvl`
- Sleep, blocking system calls

**When GVL is held:**
- Pure Ruby computation (loops, method calls, parsing)
- Object allocation, garbage collection

**Implication:** 10 threads doing CPU work won't run faster than 1 thread. But 10 threads doing HTTP calls can run 10x faster than sequential calls.

---

## Decision Matrix

| Primitive | Use For | Parallelism | Shares Memory | Complexity |
|-----------|---------|-------------|---------------|------------|
| **Thread** | I/O-bound concurrency (Sidekiq, HTTP) | No (GVL) | Yes | Low |
| **Fiber** | Custom schedulers, event loops | No | Yes | Medium |
| **Ractor** | CPU-bound parallelism | Yes (bypasses GVL) | No (copies) | High |

**Rule of thumb:**
- Start with threads for background jobs and I/O
- Use Ractors when profiling shows CPU is the bottleneck
- Use Fibers only for event-driven architectures or frameworks

---

## Trade-offs Box
- **Threads:** Easy to use but limited by GVL for CPU work. Risk race conditions without Mutex.
- **Fibers:** Full control over scheduling but requires manual yielding. Hard to debug.
- **Ractors:** True parallelism but high overhead (copying data) and API restrictions.

---

## Debugging Checklist

When concurrency fails:

1. Check for race conditions — add Mutex around shared state modifications
2. Profile with `thread_id` logging — see which thread is executing what
3. Verify GVL release — use `strace` or profiler to confirm I/O releases GVL
4. Test under concurrency — `10.times.map { Thread.new { ... } }` to trigger races
5. Check Ractor isolation errors — ensure sent objects are frozen or copyable
6. Use `Thread.current.backtrace` to debug deadlocks
7. Monitor thread count — too many threads cause scheduler thrashing

---

## One-Minute Recap
- Ruby has three concurrency primitives: Thread (concurrent, GVL-limited), Fiber (cooperative), Ractor (parallel)
- GVL prevents parallel Ruby execution but releases during I/O
- Threads excel at I/O-bound work; Ractors handle CPU-bound parallelism
- Always use Mutex to protect shared state from race conditions
- Fibers are for custom schedulers, not typical Rails apps
