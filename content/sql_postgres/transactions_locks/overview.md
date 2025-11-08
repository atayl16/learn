# Transactions, Isolation, and Locks

## What It Is
Transactions group multiple SQL statements into atomic units that succeed or fail together. ACID properties (Atomicity, Consistency, Isolation, Durability) ensure data integrity. Isolation levels control what concurrent transactions see. Locks prevent conflicting operations: row locks protect individual rows, table locks protect entire tables, and advisory locks coordinate application-level resources.

## Why It Matters
Without transactions, partial failures corrupt data: imagine charging a credit card but failing to create the order. Without proper isolation, concurrent requests cause race conditions. Without understanding locks, deadlocks crash background jobs and timeouts frustrate users. Seniors use transactions, isolation levels, and SELECT FOR UPDATE to prevent concurrency bugs.

## When to Use
- **Transactions:** Always for multi-step operations (debit account A, credit account B)
- **READ COMMITTED:** Default isolation level for most Rails apps
- **SERIALIZABLE:** When race conditions must be impossible (inventory management)
- **SELECT FOR UPDATE:** Lock rows during read-modify-write (decrement stock quantity)
- **Advisory locks:** Ensure only one background job processes a resource

## Three Common Pitfalls
1. **Forgetting to commit or rollback:** Long-running transactions hold locks and block other queries. Always commit or rollback explicitly.
2. **Wrong isolation level:** Using READ COMMITTED when REPEATABLE READ or SERIALIZABLE is needed allows phantom reads and lost updates.
3. **Deadlocks from inconsistent lock order:** Transaction A locks row 1 then row 2; Transaction B locks row 2 then row 1. Both wait forever. Fix by locking resources in consistent order.

---

## ACID Properties

**Atomicity:** All operations succeed or none do. Rollback on failure.

```ruby
ActiveRecord::Base.transaction do
  account_a.update!(balance: account_a.balance - 100)
  account_b.update!(balance: account_b.balance + 100)
end
# Both updates succeed or both roll back

```

**Consistency:** Data stays valid. Constraints enforced.

```ruby
# Foreign key prevents invalid data
order.update!(user_id: 99999)  # Raises if user 99999 doesn't exist

```

**Isolation:** Concurrent transactions don't interfere. Controlled via isolation levels.

**Durability:** Committed data survives crashes. Postgres writes to disk.

---

## Transactions in Rails

**Basic transaction:**

```ruby
ActiveRecord::Base.transaction do
  user.update!(credits: user.credits - 50)
  purchase.create!(user: user, amount: 50)
end

```

**Rollback on exception:**

```ruby
begin
  ActiveRecord::Base.transaction do
    order.update!(status: 'paid')
    inventory.update!(quantity: inventory.quantity - 1)
    raise "Payment failed" if payment_service.charge.failed?
  end
rescue => e
  # Transaction rolled back automatically
end

```

**Manual rollback:**

```ruby
ActiveRecord::Base.transaction do
  user.save!
  raise ActiveRecord::Rollback if some_condition
end

```

---

## Isolation Levels

**READ UNCOMMITTED:** Reads uncommitted changes from other transactions. Not supported by Postgres (upgrades to READ COMMITTED).

**READ COMMITTED (default):** Reads only committed data. Each statement sees latest committed values.

```ruby
# Transaction 1
user = User.find(1)  # balance = 100
sleep(5)
user.reload           # balance = 200 (if Transaction 2 committed)

```

**REPEATABLE READ:** Reads consistent snapshot. Same query returns same results within transaction.

```ruby
ActiveRecord::Base.transaction(isolation: :repeatable_read) do
  user = User.find(1)  # balance = 100
  sleep(5)
  user.reload           # balance = 100 (ignores other commits)
end

```

**SERIALIZABLE:** Strictest isolation. Transactions execute as if run sequentially. Raises serialization error if conflicts detected.

```ruby
ActiveRecord::Base.transaction(isolation: :serializable) do
  product = Product.find(1)
  product.update!(stock: product.stock - 1) if product.stock > 0
end
# Raises ActiveRecord::SerializationFailure if concurrent transaction modified stock

```

**When to use each:**
- READ COMMITTED: Default for web requests (fast, low contention)
- REPEATABLE READ: Reports or analytics needing consistent snapshot
- SERIALIZABLE: Inventory, financial transactions, or race-critical operations

---

## Row Locks (SELECT FOR UPDATE)

Lock rows to prevent concurrent modifications.

**Basic usage:**

```ruby
ActiveRecord::Base.transaction do
  product = Product.lock.find(1)  # SELECT * FROM products WHERE id = 1 FOR UPDATE
  product.update!(stock: product.stock - 1) if product.stock > 0
end

```

**SQL:**

```sql
BEGIN;
SELECT * FROM products WHERE id = 1 FOR UPDATE;
UPDATE products SET stock = stock - 1 WHERE id = 1;
COMMIT;

```

**Behavior:**
- Other transactions block on `SELECT FOR UPDATE` until lock released
- Prevents lost updates from concurrent read-modify-write

**Variants:**

```ruby
Product.lock("FOR UPDATE NOWAIT").find(1)  # Raises error instead of waiting
Product.lock("FOR UPDATE SKIP LOCKED").where(processed: false).first  # Skips locked rows

```

---

## Table Locks

Lock entire table. Rarely needed; use for DDL or bulk operations.

**Exclusive lock (blocks all access):**

```ruby
ActiveRecord::Base.connection.execute("LOCK TABLE orders IN ACCESS EXCLUSIVE MODE")

```

**Share lock (allows reads, blocks writes):**

```ruby
ActiveRecord::Base.connection.execute("LOCK TABLE orders IN SHARE MODE")

```

**Warning:** Table locks block all queries. Avoid in production web requests.

---

## Deadlocks

Two transactions wait for each other's locks.

**Example:**

```ruby
# Transaction A
ActiveRecord::Base.transaction do
  User.lock.find(1)
  sleep(1)
  User.lock.find(2)  # Waits for Transaction B
end

# Transaction B
ActiveRecord::Base.transaction do
  User.lock.find(2)
  sleep(1)
  User.lock.find(1)  # Waits for Transaction A
end
# Deadlock detected! Postgres kills one transaction

```

**Fix: Lock in consistent order:**

```ruby
ids = [1, 2].sort  # Always lock in ascending order
User.lock.where(id: ids).order(:id).to_a

```

**Viewing deadlocks:**

```sql
SELECT * FROM pg_stat_activity WHERE wait_event_type = 'Lock';

```

---

## Advisory Locks

Application-level locks for coordinating resources. Unlike row locks, advisory locks are purely cooperative.

**Exclusive lock:**

```ruby
ActiveRecord::Base.connection.execute("SELECT pg_advisory_lock(12345)")
# Do work
ActiveRecord::Base.connection.execute("SELECT pg_advisory_unlock(12345)")

```

**Try lock (non-blocking):**

```ruby
locked = ActiveRecord::Base.connection.select_value("SELECT pg_try_advisory_lock(12345)")
if locked
  # Do work
  ActiveRecord::Base.connection.execute("SELECT pg_advisory_unlock(12345)")
else
  # Another process holds lock
end

```

**Use case:**

```ruby
# Ensure only one Sidekiq job processes a resource
def perform(resource_id)
  lock_id = Zlib.crc32("process_#{resource_id}")
  if ActiveRecord::Base.connection.select_value("SELECT pg_try_advisory_lock(#{lock_id})")
    begin
      process_resource(resource_id)
    ensure
      ActiveRecord::Base.connection.execute("SELECT pg_advisory_unlock(#{lock_id})")
    end
  else
    # Skip; another job is processing
  end
end

```

---

## Debugging Locks

**Find blocked queries:**

```sql
SELECT blocked_locks.pid AS blocked_pid,
       blocked_activity.usename AS blocked_user,
       blocking_locks.pid AS blocking_pid,
       blocking_activity.usename AS blocking_user,
       blocked_activity.query AS blocked_statement,
       blocking_activity.query AS blocking_statement
FROM pg_locks blocked_locks
JOIN pg_stat_activity blocked_activity ON blocked_activity.pid = blocked_locks.pid
JOIN pg_locks blocking_locks ON blocking_locks.locktype = blocked_locks.locktype
  AND blocking_locks.database IS NOT DISTINCT FROM blocked_locks.database
  AND blocking_locks.relation IS NOT DISTINCT FROM blocked_locks.relation
  AND blocking_locks.page IS NOT DISTINCT FROM blocked_locks.page
  AND blocking_locks.tuple IS NOT DISTINCT FROM blocked_locks.tuple
  AND blocking_locks.pid != blocked_locks.pid
JOIN pg_stat_activity blocking_activity ON blocking_activity.pid = blocking_locks.pid
WHERE NOT blocked_locks.granted;

```

**Kill blocking query:**

```sql
SELECT pg_terminate_backend(12345);  -- Replace with PID

```

---

## Trade-offs Box
- **Advantage:** Transactions and locks ensure data integrity and prevent race conditions in concurrent systems.
- **Cost:** Locks reduce throughput by serializing access. Long-running transactions block other queries.
- **When to skip:** Single-statement operations are atomic by default. Skip explicit transactions for simple creates/updates.

---

## Debugging Checklist

When encountering lock issues:

1. Check `pg_stat_activity` for queries in "waiting" state
2. Identify blocking PID using the blocked queries query above
3. Review blocking query: is it stuck in a long transaction?
4. Check for deadlocks in Postgres logs: `ERROR: deadlock detected`
5. Ensure locks acquired in consistent order (sorted by ID)
6. Reduce transaction duration: commit frequently, avoid sleep or external API calls inside transactions
7. Use `NOWAIT` or `SKIP LOCKED` to avoid indefinite blocking

---

## One-Minute Recap
- Transactions ensure atomicity; use for multi-step operations that must succeed or fail together
- Isolation levels control concurrency: READ COMMITTED (default), REPEATABLE READ (consistent snapshot), SERIALIZABLE (strictest)
- SELECT FOR UPDATE locks rows during read-modify-write to prevent lost updates
- Deadlocks occur when transactions wait for each other; fix by locking in consistent order
- Advisory locks coordinate application-level resources like background job processing
