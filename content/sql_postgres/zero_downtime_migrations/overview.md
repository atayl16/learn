# Zero-Downtime Migrations

## What It Is
Zero-downtime migrations modify database schema without locking tables or blocking production traffic. Techniques include adding columns without defaults, creating indexes concurrently, backfilling data in batches, and setting timeouts. The strong_migrations gem detects unsafe migrations before deployment.

## Why It Matters
Unsafe migrations lock tables for seconds or minutes, blocking all queries and causing timeouts. Adding an index to a 10-million-row table can lock writes for 30+ seconds. Seniors design migrations that run in production without downtime by avoiding exclusive locks and splitting risky operations into multiple steps.

## When to Use
- **Adding columns:** Always add nullable columns first, backfill later
- **Adding indexes:** Use `algorithm: :concurrently` to avoid blocking writes
- **Adding NOT NULL:** Backfill data first, add constraint second
- **Changing column types:** Create new column, dual-write, backfill, switch over
- **Deploying to production:** Always test migrations against production-sized data

## Three Common Pitfalls
1. **Adding columns with defaults in one step:** Postgres 10 and earlier rewrite the entire table. Add column without default, backfill in batches, then set default.
2. **Creating indexes without CONCURRENTLY:** Regular CREATE INDEX locks table for writes. Use `algorithm: :concurrently` to allow concurrent writes.
3. **Backfilling in a single transaction:** Updating millions of rows locks the table. Use batches of 1,000-10,000 rows with sleep between batches.

---

## Adding Columns Safely

**Unsafe (Postgres <11):**

```ruby
# Rewrites entire table, holding exclusive lock
add_column :users, :role, :string, default: 'user'

```

**Safe (multi-step):**

```ruby
# Step 1: Add column without default
class AddRoleToUsers < ActiveRecord::Migration[7.0]
  def change
    add_column :users, :role, :string
  end
end

# Step 2: Backfill in batches (separate migration or rake task)
class BackfillUserRoles < ActiveRecord::Migration[7.0]
  disable_ddl_transaction!

  def up
    User.in_batches(of: 10_000) do |batch|
      batch.update_all(role: 'user')
      sleep(0.01)  # Pause to reduce load
    end
  end
end

# Step 3: Add default for new rows
class SetDefaultRoleOnUsers < ActiveRecord::Migration[7.0]
  def change
    change_column_default :users, :role, 'user'
  end
end

# Step 4: Add NOT NULL constraint (optional)
class AddNotNullToUserRole < ActiveRecord::Migration[7.0]
  def change
    change_column_null :users, :role, false
  end
end

```

**Note:** Postgres 11+ optimizes adding columns with defaults but still requires caution for very large tables.

---

## Creating Indexes Concurrently

**Unsafe:**

```ruby
add_index :users, :email
# Acquires ShareLock, blocking INSERT/UPDATE/DELETE

```

**Safe:**

```ruby
class AddIndexToUsersEmail < ActiveRecord::Migration[7.0]
  disable_ddl_transaction!

  def change
    add_index :users, :email, algorithm: :concurrently
  end
end

```

**SQL:**

```sql
CREATE INDEX CONCURRENTLY index_users_on_email ON users (email);

```

**Behavior:**
- Allows concurrent writes during index creation
- Takes longer than regular index creation
- Fails if transaction is open (use `disable_ddl_transaction!`)

**Removing indexes:**

```ruby
class RemoveIndexFromUsersEmail < ActiveRecord::Migration[7.0]
  disable_ddl_transaction!

  def change
    remove_index :users, :email, algorithm: :concurrently
  end
end

```

---

## Backfilling Data in Batches

**Unsafe (single transaction):**

```ruby
def up
  User.update_all(verified: false)
  # Locks table for entire duration
end

```

**Safe (batched):**

```ruby
class BackfillUserVerified < ActiveRecord::Migration[7.0]
  disable_ddl_transaction!

  def up
    User.in_batches(of: 10_000).each_record do |user|
      user.update_column(:verified, false)
    end
  end
end

```

**Better (raw SQL for speed):**

```ruby
def up
  batch_size = 10_000
  last_id = 0

  loop do
    result = execute(<<-SQL)
      UPDATE users
      SET verified = false
      WHERE id > #{last_id} AND id <= #{last_id + batch_size}
      RETURNING id
    SQL

    break if result.count == 0

    last_id += batch_size
    sleep(0.01)  # Reduce load
  end
end

```

---

## Adding NOT NULL Constraints Safely

**Unsafe:**

```ruby
change_column_null :users, :email, false
# Scans entire table with exclusive lock

```

**Safe:**

```ruby
# Step 1: Backfill NULLs
class BackfillUserEmails < ActiveRecord::Migration[7.0]
  disable_ddl_transaction!

  def up
    User.where(email: nil).in_batches(of: 10_000) do |batch|
      batch.update_all(email: '')
      sleep(0.01)
    end
  end
end

# Step 2: Add NOT NULL constraint
class AddNotNullToUserEmail < ActiveRecord::Migration[7.0]
  def change
    change_column_null :users, :email, false
  end
end

```

**Postgres 12+ (safer):**

```ruby
# Add check constraint first (validates new rows only)
add_check_constraint :users, "email IS NOT NULL", name: "users_email_null", validate: false

# Validate existing rows (can run concurrently)
validate_check_constraint :users, name: "users_email_null"

# Promote to NOT NULL
change_column_null :users, :email, false

# Remove check constraint
remove_check_constraint :users, name: "users_email_null"

```

---

## Changing Column Types

**Unsafe:**

```ruby
change_column :users, :age, :bigint
# Rewrites table, exclusive lock

```

**Safe (multi-step):**

```ruby
# Step 1: Add new column
add_column :users, :age_bigint, :bigint

# Step 2: Dual-write (application code)
user.update(age: 25, age_bigint: 25)

# Step 3: Backfill existing rows
User.where(age_bigint: nil).in_batches(of: 10_000) do |batch|
  batch.update_all("age_bigint = age")
  sleep(0.01)
end

# Step 4: Swap columns
rename_column :users, :age, :age_int
rename_column :users, :age_bigint, :age

# Step 5: Remove old column
remove_column :users, :age_int

```

---

## Setting Lock Timeouts

Prevent migrations from waiting indefinitely for locks.

```ruby
class AddIndexToUsersEmail < ActiveRecord::Migration[7.0]
  disable_ddl_transaction!

  def up
    execute "SET lock_timeout = '5s'"
    add_index :users, :email, algorithm: :concurrently
  end

  def down
    remove_index :users, :email, algorithm: :concurrently
  end
end

```

**Behavior:**
- If lock not acquired within 5 seconds, migration fails instead of hanging
- Retry migration during low-traffic window

---

## Using strong_migrations Gem

Install:

```ruby
gem 'strong_migrations'

```

**Detects unsafe operations:**

```ruby
add_column :users, :role, :string, default: 'user'
# StrongMigrations::UnsafeMigration: Adding a column with a default value is unsafe

```

**Suggests safe alternatives:**

```
Use this safer approach instead:

  class AddRoleToUsers < ActiveRecord::Migration[7.0]
    def change
      add_column :users, :role, :string
      change_column_default :users, :role, 'user'
    end
  end

```

---

## Trade-offs Box
- **Advantage:** Zero-downtime migrations eliminate production outages and user-facing errors during deployments.
- **Cost:** Requires multiple deployment steps and more complex migration code. Backfilling large tables takes hours.
- **When to skip:** Small tables under 10,000 rows can handle brief locks. Skip for staging or development environments.

---

## Debugging Checklist

When migrations cause downtime:

1. Check for exclusive locks: `SELECT * FROM pg_locks WHERE mode = 'AccessExclusiveLock';`
2. Identify long-running migrations: `SELECT * FROM pg_stat_activity WHERE state = 'active' AND query LIKE '%ALTER TABLE%';`
3. Verify `algorithm: :concurrently` used for index creation
4. Confirm batching used for backfills (check migration code)
5. Test migration on production-sized dataset in staging
6. Use `lock_timeout` to fail fast instead of blocking indefinitely
7. Review strong_migrations warnings before deploying

---

## One-Minute Recap
- Add columns without defaults, backfill in batches, then set default
- Create indexes concurrently with `algorithm: :concurrently` to avoid blocking writes
- Backfill data in batches of 1,000-10,000 rows with sleep between batches
- Add NOT NULL constraints after backfilling to avoid table scans
- Use strong_migrations gem to detect unsafe migrations before deployment
