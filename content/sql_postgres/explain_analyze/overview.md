# Reading Query Plans (EXPLAIN ANALYZE)

## What It Is
EXPLAIN shows how Postgres executes a query without running it. EXPLAIN ANALYZE executes the query and shows actual timing and row counts. Query plans reveal whether Postgres uses indexes, performs sequential scans, or chooses expensive joins. pg_stat_statements tracks query performance over time in production.

## Why It Matters
Slow queries cause timeouts, high CPU, and degraded user experience. EXPLAIN ANALYZE identifies bottlenecks: missing indexes, inefficient joins, or poor row estimates. Seniors use query plans to optimize slow queries from seconds to milliseconds. Ignoring EXPLAIN means guessing which indexes or rewrites help.

## When to Use
- **Slow queries:** Run EXPLAIN ANALYZE on any query taking over 100ms
- **Before adding indexes:** Verify Postgres will actually use the proposed index
- **After adding indexes:** Confirm the query plan changed and performance improved
- **Production monitoring:** Enable pg_stat_statements to track slowest queries over time

## Three Common Pitfalls
1. **Reading EXPLAIN without ANALYZE:** EXPLAIN shows estimated costs, but ANALYZE shows actual execution time. Always use ANALYZE for real performance data.
2. **Ignoring row estimate errors:** If "rows=1000" but "actual rows=50000", Postgres chose a bad plan. Update table statistics with ANALYZE table_name.
3. **Optimizing queries in empty dev databases:** Query plans differ between 100 rows and 1 million rows. Test with production-sized data.

---

## EXPLAIN vs EXPLAIN ANALYZE

**EXPLAIN (no execution):**
```sql
EXPLAIN SELECT * FROM users WHERE email = 'user@example.com';
```

**Output:**
```
Index Scan using index_users_on_email on users  (cost=0.42..8.44 rows=1 width=123)
  Index Cond: (email = 'user@example.com')
```

**EXPLAIN ANALYZE (executes query):**
```sql
EXPLAIN ANALYZE SELECT * FROM users WHERE email = 'user@example.com';
```

**Output:**
```
Index Scan using index_users_on_email on users  (cost=0.42..8.44 rows=1 width=123) (actual time=0.045..0.047 rows=1 loops=1)
  Index Cond: (email = 'user@example.com')
Planning Time: 0.123 ms
Execution Time: 0.089 ms
```

**Key differences:**
- EXPLAIN shows estimated cost and rows
- EXPLAIN ANALYZE shows actual time and rows
- ANALYZE modifies data for INSERT/UPDATE/DELETE (use with caution)

---

## Reading Query Plans

**Format:**
```
Node Type (cost=startup..total rows=estimate width=bytes) (actual time=first..last rows=count loops=iterations)
```

**Example:**
```
Seq Scan on users  (cost=0.00..1543.67 rows=50000 width=123) (actual time=0.012..15.234 rows=48923 loops=1)
```

**Fields:**
- **cost:** Startup cost (0.00) to total cost (1543.67) in arbitrary units
- **rows:** Estimated row count (50000)
- **width:** Average row size in bytes (123)
- **actual time:** Time to first row (0.012ms) and last row (15.234ms)
- **rows:** Actual row count (48923)
- **loops:** Number of times node executed (1)

---

## Common Scan Types

**Sequential Scan (Seq Scan):** Reads entire table row-by-row.
```
Seq Scan on users  (cost=0.00..1543.67 rows=50000 width=123)
  Filter: (status = 'active')
```
**When it appears:** No index, or Postgres estimates sequential scan is faster (small tables, selecting large percentage of rows).

**Index Scan:** Uses index to find rows, then fetches from table.
```
Index Scan using index_users_on_email on users  (cost=0.42..8.44 rows=1 width=123)
  Index Cond: (email = 'user@example.com')
```
**When it appears:** Query filters/sorts by indexed column(s).

**Index Only Scan:** Reads data directly from index without table lookup.
```
Index Only Scan using index_users_on_email_covering on users  (cost=0.42..4.44 rows=1 width=8)
  Index Cond: (email = 'user@example.com')
  Heap Fetches: 0
```
**When it appears:** Index contains all needed columns (covering index).

**Bitmap Index Scan:** Scans index, builds bitmap of matching rows, then fetches rows.
```
Bitmap Heap Scan on users  (cost=12.34..567.89 rows=500 width=123)
  Recheck Cond: (created_at > '2024-01-01')
  -> Bitmap Index Scan on index_users_on_created_at  (cost=0.00..12.21 rows=500 width=0)
```
**When it appears:** Query returns moderate percentage of rows (5-15%).

---

## Join Strategies

**Nested Loop:** Outer loop iterates rows, inner loop finds matches. Fast for small datasets.
```
Nested Loop  (cost=0.85..123.45 rows=10 width=256)
  -> Index Scan on orders  (cost=0.42..8.44 rows=1 width=128)
  -> Index Scan on line_items  (cost=0.43..115.00 rows=10 width=128)
```
**Problem:** Nested loops with large outer rows become O(N*M).

**Hash Join:** Builds hash table of one side, probes with other side. Fast for large datasets.
```
Hash Join  (cost=234.56..1567.89 rows=5000 width=256)
  Hash Cond: (orders.user_id = users.id)
  -> Seq Scan on orders  (cost=0.00..1200.00 rows=5000 width=128)
  -> Hash  (cost=200.00..200.00 rows=2000 width=128)
        -> Seq Scan on users  (cost=0.00..200.00 rows=2000 width=128)
```

**Merge Join:** Sorts both sides, then merges. Efficient when inputs are pre-sorted.

---

## Identifying Bottlenecks

**High cost nodes:**
```
Seq Scan on large_table  (cost=0.00..150000.00 rows=1000000 width=200)
```
**Fix:** Add index if filtering or sorting.

**Nested loop with large rows:**
```
Nested Loop  (cost=0.00..5000000.00 rows=100000 width=256)
```
**Fix:** Consider hash join or add index to reduce inner loop cost.

**Sort on disk:**
```
Sort  (cost=12345.67..13456.78 rows=50000 width=200)
  Sort Key: created_at DESC
  Sort Method: external merge  Disk: 12345kB
```
**Fix:** Increase work_mem or add index on sort column.

---

## Using pg_stat_statements

Enable in postgresql.conf:
```
shared_preload_libraries = 'pg_stat_statements'
pg_stat_statements.track = all
```

**Find slowest queries:**
```sql
SELECT query, calls, mean_exec_time, total_exec_time
FROM pg_stat_statements
ORDER BY mean_exec_time DESC
LIMIT 10;
```

**Find most frequent queries:**
```sql
SELECT query, calls
FROM pg_stat_statements
ORDER BY calls DESC
LIMIT 10;
```

**Reset statistics:**
```sql
SELECT pg_stat_statements_reset();
```

---

## Trade-offs Box
- **Advantage:** EXPLAIN ANALYZE reveals exact bottlenecks and verifies index usage without guessing.
- **Cost:** EXPLAIN ANALYZE executes queries, which can be slow or modify data (INSERT/UPDATE/DELETE).
- **When to skip:** Skip for destructive queries in production; use EXPLAIN (no ANALYZE) or test in staging.

---

## Debugging Checklist

When queries are slow:

1. Run `EXPLAIN ANALYZE` and check total execution time
2. Look for "Seq Scan" on large tables; consider adding index
3. Check "actual rows" vs "rows estimate"; if 10x+ off, run `ANALYZE table_name`
4. Identify highest-cost nodes (sorts, nested loops, seq scans)
5. For joins, verify join columns are indexed
6. Check for "Sort Method: external merge Disk" and increase work_mem if needed
7. Use pg_stat_statements to find slowest queries over time in production

---

## One-Minute Recap
- EXPLAIN shows estimated query plan; EXPLAIN ANALYZE shows actual execution time
- Seq Scan reads entire table; Index Scan uses index; Index Only Scan reads index only
- Nested loops are fast for small datasets but slow for large joins
- High-cost nodes (sorts, seq scans) indicate missing indexes or bad query structure
- pg_stat_statements tracks slowest queries in production over time
