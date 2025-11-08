# Database Indexing (B-tree, Partial, Composite)

## What It Is
Indexes are data structures that speed up queries by creating sorted lookup tables. Postgres supports B-tree (default), partial (filtered subset), composite (multi-column), GIN (arrays/JSONB), and GiST (geometric/full-text) indexes. Indexes trade write speed and disk space for faster reads.

## Why It Matters
Unindexed queries scan entire tables, which is acceptable for 100 rows but unacceptable for 1 million. Seniors add indexes strategically: too few causes slow queries, too many slows writes and wastes space. EXPLAIN reveals whether Postgres uses your index or ignores it.

## When to Use
- **Foreign keys:** Always index foreign key columns (`user_id`, `order_id`)
- **WHERE clauses:** Index columns frequently filtered (`WHERE status = 'active'`)
- **ORDER BY/sorting:** Index columns used for sorting large result sets
- **Partial indexes:** Index subset when querying specific values (`WHERE deleted_at IS NULL`)
- **Composite indexes:** Index multiple columns for queries with multiple filters

## Three Common Pitfalls
1. **Unused indexes waste space:** Adding indexes without verifying usage via EXPLAIN. Postgres may ignore your index if the query doesn't match the index structure.
2. **Wrong column order in composite indexes:** Order matters. Index `(user_id, created_at)` helps `WHERE user_id = X ORDER BY created_at` but not `WHERE created_at > Y`.
3. **Over-indexing small tables:** Indexes on tables under 10,000 rows rarely help. Sequential scans are often faster than index lookups for small datasets.

---

## B-tree Indexes (Default)

B-tree indexes support equality and range queries. Postgres creates B-tree indexes by default.

**Migration:**

```ruby
class AddIndexToUsersEmail < ActiveRecord::Migration[7.0]
  def change
    add_index :users, :email
  end
end

```

**SQL generated:**

```sql
CREATE INDEX index_users_on_email ON users USING btree (email);

```

**Use cases:**
- Equality: `WHERE email = 'user@example.com'`
- Range: `WHERE created_at > '2024-01-01'`
- Sorting: `ORDER BY created_at DESC`

**Verification:**

```sql
EXPLAIN SELECT * FROM users WHERE email = 'user@example.com';
-- Index Scan using index_users_on_email on users

```

---

## Composite Indexes (Multi-Column)

Index multiple columns together. Column order determines which queries benefit.

**Migration:**

```ruby
add_index :posts, [:user_id, :published_at]

```

**Effective queries:**

```sql
-- Uses index: starts with user_id
SELECT * FROM posts WHERE user_id = 5 ORDER BY published_at DESC;

-- Uses index: filters user_id, sorts published_at
SELECT * FROM posts WHERE user_id = 5 AND published_at > '2024-01-01';

```

**Ineffective queries:**

```sql
-- Ignores index: doesn't filter user_id
SELECT * FROM posts WHERE published_at > '2024-01-01';

```

**Rule:** Composite index `(a, b, c)` helps queries filtering `a`, `a + b`, or `a + b + c`, but not `b` or `c` alone.

---

## Partial Indexes

Index only rows matching a condition. Smaller, faster, and more efficient for filtered queries.

**Migration:**

```ruby
add_index :users, :email, where: "deleted_at IS NULL", name: "index_active_users_on_email"

```

**SQL:**

```sql
CREATE INDEX index_active_users_on_email ON users (email) WHERE deleted_at IS NULL;

```

**Use case:**

```ruby
# Uses partial index
User.where(deleted_at: nil).where(email: "user@example.com")

# Ignores partial index
User.where(email: "user@example.com")  # doesn't filter deleted_at

```

**Common patterns:**
- Boolean flags: `WHERE active = true`
- Soft deletes: `WHERE deleted_at IS NULL`
- Status filters: `WHERE status = 'pending'`

---

## GIN and GiST Indexes

**GIN (Generalized Inverted Index):** For arrays, JSONB, full-text search.

```ruby
# JSONB column
add_index :events, :metadata, using: :gin

# Array column
add_index :posts, :tag_ids, using: :gin

```

**Query:**

```ruby
Event.where("metadata @> ?", {source: "web"}.to_json)  # JSONB containment
Post.where("tag_ids && ARRAY[?]::integer[]", [1, 2])  # Array overlap

```

**GiST (Generalized Search Tree):** For geometric data, ranges, full-text.

```ruby
execute "CREATE INDEX index_locations_on_coords ON locations USING gist (coords);"

```

---

## Covering Indexes (Index-Only Scans)

Include extra columns so Postgres reads only the index, not the table.

**Postgres 11+:**

```ruby
add_index :users, :email, include: [:name, :created_at]

```

**SQL:**

```sql
CREATE INDEX index_users_on_email_covering ON users (email) INCLUDE (name, created_at);

```

**Benefit:**

```sql
-- Index-only scan: no table lookup
SELECT name, created_at FROM users WHERE email = 'user@example.com';

```

---

## When Indexes Hurt Performance

**Writes slow down:** Every INSERT/UPDATE/DELETE updates all indexes. 10 indexes = 10x slower writes.

**Index maintenance overhead:** Postgres must keep indexes sorted. Large bulk imports are faster with indexes dropped and rebuilt afterward.

**Example:**

```ruby
# Slow: 1M inserts with indexes
User.create!(email: "user#{i}@example.com")

# Fast: disable indexes, bulk insert, rebuild
remove_index :users, :email
User.insert_all(records)
add_index :users, :email

```

---

## Trade-offs Box
- **Advantage:** Indexes reduce query time from seconds to milliseconds by avoiding full table scans.
- **Cost:** Each index slows writes by 5-20% and consumes disk space. Unused indexes waste resources.
- **When to skip:** Small tables under 10,000 rows, bulk import jobs, columns never queried in WHERE/ORDER BY.

---

## Debugging Checklist

When queries are slow:

1. Run `EXPLAIN ANALYZE` and check for "Seq Scan on large_table" instead of "Index Scan"
2. Verify index exists in `db/schema.rb` or `\d table_name` in psql
3. Check if WHERE clause matches index columns exactly (case sensitivity, type casts)
4. For composite indexes, confirm query filters leftmost column(s)
5. Use `pg_stat_user_indexes` to find unused indexes: `SELECT * FROM pg_stat_user_indexes WHERE idx_scan = 0;`
6. Check index bloat: `SELECT indexrelname, pg_size_pretty(pg_relation_size(indexrelid)) FROM pg_stat_user_indexes;`
7. Rebuild bloated indexes: `REINDEX INDEX index_name;`

---

## One-Minute Recap
- B-tree indexes speed up WHERE, ORDER BY, and JOIN on indexed columns
- Composite indexes require queries to filter leftmost columns first
- Partial indexes are smaller and faster when filtering specific subsets
- GIN indexes support JSONB and array queries; GiST supports ranges and full-text
- Too many indexes slow writes; verify usage with EXPLAIN ANALYZE and pg_stat_user_indexes
