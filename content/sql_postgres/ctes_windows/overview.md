# CTEs and Window Functions

## What It Is
Common Table Expressions (CTEs) are temporary named result sets defined with WITH. They simplify complex queries by breaking them into readable steps. Window functions (ROW_NUMBER, RANK, LAG, LEAD) compute values across rows related to the current row, useful for rankings, running totals, and comparing adjacent rows.

## Why It Matters
CTEs make nested subqueries readable. Window functions solve problems that require self-joins or application-level iteration. Seniors use CTEs to organize multi-step analytics queries and window functions to rank results, calculate deltas, or find top N per group without multiple queries.

## When to Use
- **CTEs:** Break complex queries into logical steps, recursively query hierarchies, or reuse subquery results
- **ROW_NUMBER/RANK:** Find top N items per category (top 3 products per seller)
- **LAG/LEAD:** Compare current row with previous/next row (price changes, streaks)
- **Running totals:** Calculate cumulative sums over ordered data

## Three Common Pitfalls
1. **Materializing CTEs unnecessarily:** Postgres 12+ optimizes CTEs by inlining them. Use MATERIALIZED keyword only when needed.
2. **Forgetting PARTITION BY:** Window functions without PARTITION BY operate on entire result set, not per group.
3. **Using window functions where GROUP BY suffices:** Window functions are powerful but slower than GROUP BY for simple aggregations. Use GROUP BY when you don't need row-level details.

---

## Common Table Expressions (CTEs)

**Basic syntax:**
```sql
WITH cte_name AS (
  SELECT ...
)
SELECT * FROM cte_name;
```

**Example: Find users with above-average orders:**
```sql
WITH avg_orders AS (
  SELECT AVG(total) AS avg_total FROM orders
)
SELECT users.*
FROM users
JOIN orders ON orders.user_id = users.id
JOIN avg_orders ON orders.total > avg_orders.avg_total;
```

**Rails (raw SQL):**
```ruby
sql = <<-SQL
  WITH avg_orders AS (
    SELECT AVG(total) AS avg_total FROM orders
  )
  SELECT users.*
  FROM users
  JOIN orders ON orders.user_id = users.id
  CROSS JOIN avg_orders
  WHERE orders.total > avg_orders.avg_total
SQL

User.find_by_sql(sql)
```

**Multiple CTEs:**
```sql
WITH active_users AS (
  SELECT id FROM users WHERE last_login > NOW() - INTERVAL '30 days'
),
recent_orders AS (
  SELECT user_id, SUM(total) AS total_spent
  FROM orders
  WHERE created_at > NOW() - INTERVAL '30 days'
  GROUP BY user_id
)
SELECT users.*, recent_orders.total_spent
FROM users
JOIN active_users ON active_users.id = users.id
JOIN recent_orders ON recent_orders.user_id = users.id;
```

---

## Recursive CTEs

Query hierarchical data (org charts, category trees).

**Schema:**
```ruby
create_table :categories do |t|
  t.string :name
  t.references :parent, foreign_key: { to_table: :categories }
end
```

**Recursive query:**
```sql
WITH RECURSIVE category_tree AS (
  -- Base case: root categories
  SELECT id, name, parent_id, 1 AS level
  FROM categories
  WHERE parent_id IS NULL

  UNION ALL

  -- Recursive case: children
  SELECT c.id, c.name, c.parent_id, ct.level + 1
  FROM categories c
  JOIN category_tree ct ON c.parent_id = ct.id
)
SELECT * FROM category_tree ORDER BY level, name;
```

---

## Window Functions Basics

**Syntax:**
```sql
function_name() OVER (
  PARTITION BY column
  ORDER BY column
  ROWS/RANGE frame_clause
)
```

**Without PARTITION BY:** Operates on entire result set.
**With PARTITION BY:** Operates within each partition (group).

---

## ROW_NUMBER

Assign unique sequential numbers to rows.

**Find top 3 products per category:**
```sql
WITH ranked_products AS (
  SELECT
    products.*,
    ROW_NUMBER() OVER (PARTITION BY category_id ORDER BY sales DESC) AS rank
  FROM products
)
SELECT * FROM ranked_products WHERE rank <= 3;
```

**Rails:**
```ruby
sql = <<-SQL
  WITH ranked_products AS (
    SELECT products.*,
           ROW_NUMBER() OVER (PARTITION BY category_id ORDER BY sales DESC) AS rank
    FROM products
  )
  SELECT * FROM ranked_products WHERE rank <= 3
SQL

Product.find_by_sql(sql)
```

---

## RANK and DENSE_RANK

**RANK:** Gaps after ties (1, 2, 2, 4).
**DENSE_RANK:** No gaps after ties (1, 2, 2, 3).

```sql
SELECT
  name,
  score,
  RANK() OVER (ORDER BY score DESC) AS rank,
  DENSE_RANK() OVER (ORDER BY score DESC) AS dense_rank
FROM students;
```

**Result:**
```
name    | score | rank | dense_rank
--------|-------|------|------------
Alice   | 100   | 1    | 1
Bob     | 95    | 2    | 2
Charlie | 95    | 2    | 2
David   | 90    | 4    | 3
```

---

## LAG and LEAD

Access previous or next row within partition.

**Calculate price changes:**
```sql
SELECT
  date,
  price,
  LAG(price) OVER (ORDER BY date) AS prev_price,
  price - LAG(price) OVER (ORDER BY date) AS price_change
FROM stock_prices;
```

**Result:**
```
date       | price | prev_price | price_change
-----------|-------|------------|-------------
2024-01-01 | 100   | NULL       | NULL
2024-01-02 | 105   | 100        | 5
2024-01-03 | 102   | 105        | -3
```

**Rails:**
```ruby
sql = <<-SQL
  SELECT
    date,
    price,
    LAG(price) OVER (ORDER BY date) AS prev_price,
    price - LAG(price) OVER (ORDER BY date) AS price_change
  FROM stock_prices
SQL

StockPrice.find_by_sql(sql)
```

---

## Running Totals and Moving Averages

**Running total:**
```sql
SELECT
  date,
  amount,
  SUM(amount) OVER (ORDER BY date ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) AS running_total
FROM transactions;
```

**3-day moving average:**
```sql
SELECT
  date,
  value,
  AVG(value) OVER (ORDER BY date ROWS BETWEEN 2 PRECEDING AND CURRENT ROW) AS moving_avg_3day
FROM metrics;
```

---

## CTEs vs Subqueries

**Subquery (less readable):**
```sql
SELECT *
FROM users
WHERE id IN (
  SELECT user_id
  FROM orders
  WHERE total > (SELECT AVG(total) FROM orders)
);
```

**CTE (more readable):**
```sql
WITH avg_total AS (
  SELECT AVG(total) AS avg FROM orders
),
high_value_orders AS (
  SELECT user_id FROM orders, avg_total WHERE total > avg_total.avg
)
SELECT * FROM users WHERE id IN (SELECT user_id FROM high_value_orders);
```

**Performance:** Postgres 12+ inlines CTEs like subqueries. Use MATERIALIZED to force evaluation once.

```sql
WITH materialized_cte AS MATERIALIZED (
  SELECT expensive_computation() AS result
)
SELECT * FROM materialized_cte;
```

---

## Window Functions in Rails

**Arel:**
```ruby
# ROW_NUMBER with partition
window = Arel::Nodes::Window.new.partition(Product.arel_table[:category_id]).order(Product.arel_table[:sales].desc)
row_number = Arel::Nodes::NamedFunction.new('ROW_NUMBER', []).over(window)

Product.select(Product.arel_table[Arel.star], row_number.as('rank'))
```

**Raw SQL (simpler):**
```ruby
sql = <<-SQL
  SELECT products.*,
         ROW_NUMBER() OVER (PARTITION BY category_id ORDER BY sales DESC) AS rank
  FROM products
SQL

Product.find_by_sql(sql)
```

---

## Trade-offs Box
- **Advantage:** CTEs improve readability by naming subqueries. Window functions eliminate self-joins and multiple queries.
- **Cost:** Window functions can be slower than GROUP BY for simple aggregations. Recursive CTEs risk infinite loops without proper base cases.
- **When to skip:** Use GROUP BY instead of window functions when you only need aggregated results, not row-level details.

---

## Debugging Checklist

When CTE or window function queries are slow:

1. Run EXPLAIN ANALYZE to check if CTE is being materialized unnecessarily
2. Add indexes on PARTITION BY and ORDER BY columns
3. For recursive CTEs, verify base case terminates and doesn't scan entire table
4. Replace window functions with GROUP BY if row-level details aren't needed
5. Check for redundant window definitions; reuse WINDOW clause for multiple functions
6. Use MATERIALIZED keyword if CTE result is reused multiple times
7. Profile query with pg_stat_statements to identify bottlenecks

---

## One-Minute Recap
- CTEs (WITH) break complex queries into readable named steps
- Recursive CTEs query hierarchical data like org charts or category trees
- ROW_NUMBER assigns unique ranks; RANK/DENSE_RANK handle ties differently
- LAG/LEAD access previous/next rows for calculating deltas or streaks
- Window functions partition data with PARTITION BY and order with ORDER BY
