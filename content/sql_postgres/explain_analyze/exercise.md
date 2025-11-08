# Exercise: Reading Query Plans

## Objective
Practice reading EXPLAIN ANALYZE output to identify bottlenecks and verify index usage.

## Task
You have a slow query on an orders table. Run EXPLAIN ANALYZE, identify the bottleneck, add an appropriate index, and verify the query plan improves.

**Setup:**

```ruby
# Assume this schema with 100,000 orders
create_table :orders do |t|
  t.references :user, null: false, foreign_key: true
  t.string :status  # 'pending', 'completed', 'cancelled'
  t.decimal :total, precision: 10, scale: 2
  t.timestamps
end

# Slow query: find recent completed orders for a user
# User.find(5).orders.where(status: 'completed').order(created_at: :desc).limit(20)

```

**SQL equivalent:**

```sql
SELECT * FROM orders
WHERE user_id = 5 AND status = 'completed'
ORDER BY created_at DESC
LIMIT 20;

```

## Acceptance Criteria
- [ ] Run `EXPLAIN ANALYZE` on the query and capture the output
- [ ] Identify whether query uses "Seq Scan" or "Index Scan"
- [ ] Calculate actual execution time from EXPLAIN ANALYZE output
- [ ] Add an appropriate composite index on `(user_id, status, created_at)`
- [ ] Run `EXPLAIN ANALYZE` again and verify plan shows "Index Scan"
- [ ] Document the performance improvement (execution time before vs after)

## Verification Steps
1. Run query with `EXPLAIN (ANALYZE, BUFFERS)` before adding index and save output
2. Check for "Seq Scan" or high-cost nodes in the plan
3. Add composite index and run `ANALYZE orders;` to update statistics
4. Run `EXPLAIN (ANALYZE, BUFFERS)` again and compare execution time
5. Verify "Index Scan using index_orders_on_user_id_status_created_at" appears
6. Document improvement: "Execution Time: X ms → Y ms"

## Stretch (Optional)
Enable pg_stat_statements in your local Postgres and query it to find the slowest queries after running several test queries.

## Time Estimate
20 minutes
