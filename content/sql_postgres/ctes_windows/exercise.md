# Exercise: CTEs and Window Functions

## Objective
Practice using Common Table Expressions and window functions to solve analytics queries.

## Task
You have an e-commerce database with orders and products. Write queries using CTEs and window functions to answer business questions.

**Setup:**
```ruby
# Schema
create_table :orders do |t|
  t.references :user, null: false
  t.decimal :total, precision: 10, scale: 2
  t.timestamps
end

create_table :products do |t|
  t.string :name
  t.string :category
  t.integer :sales_count
  t.decimal :price, precision: 10, scale: 2
  t.timestamps
end
```

**Business questions:**
1. Find the top 3 products by sales in each category
2. Calculate each order's total and the running total of all orders by date
3. For each product, show current price, previous price (by created_at), and price change
4. Find users who spent more than the average order total

## Acceptance Criteria
- [ ] Query 1: Use ROW_NUMBER with PARTITION BY category and ORDER BY sales_count DESC
- [ ] Query 2: Use SUM() OVER with ORDER BY for running total
- [ ] Query 3: Use LAG() to get previous price and calculate difference
- [ ] Query 4: Use a CTE to calculate average order total, then filter users
- [ ] All queries return correct results when tested against sample data
- [ ] Run EXPLAIN ANALYZE on each query and verify performance is acceptable

## Verification Steps
1. Insert sample data: 10 categories, 50 products, 100 orders from 20 users
2. Run Query 1 and verify exactly 3 products per category (or fewer if category has < 3 products)
3. Run Query 2 and manually verify running total matches sum of all previous orders
4. Run Query 3 and verify price_change = current_price - previous_price
5. Run Query 4 and verify all returned users have sum(orders.total) > average
6. Check query plans: ensure indexes are used where appropriate

## Stretch (Optional)
Write a recursive CTE to query a hierarchical categories table (parent_id references categories.id) and display the full category path for each product.

## Time Estimate
22 minutes
