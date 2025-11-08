# Exercise: Modeling & Constraints

## Objective
Practice adding foreign keys, unique constraints, and check constraints to enforce data integrity at the database level.

## Task
You're building an e-commerce order system. Create migrations that add constraints to prevent invalid data: duplicate orders, negative prices, orphaned line items, and missing required fields.

## Acceptance Criteria
- [ ] Add foreign key from `line_items.order_id` to `orders.id` with cascade delete
- [ ] Add unique constraint on `orders` table for `(user_id, order_number)` to prevent duplicate order numbers per user
- [ ] Add check constraint on `line_items.quantity` to ensure `quantity > 0`
- [ ] Add check constraint on `line_items.price` to ensure `price >= 0`
- [ ] Add NOT NULL constraint to `orders.user_id` and `orders.status`
- [ ] Verify constraints work by attempting to insert invalid data in Rails console

## Verification Steps
1. Run `rails db:migrate` and confirm no errors
2. Check `db/schema.rb` shows all constraints: foreign keys, unique indexes, check constraints
3. Open Rails console and try `LineItem.create!(order_id: 99999, quantity: 1, price: 10)` - should raise FK violation
4. Try `LineItem.create!(order_id: valid_id, quantity: -5, price: 10)` - should raise check constraint violation
5. Try creating two orders with same `user_id` and `order_number` - should raise unique constraint violation
6. Run `\d orders` and `\d line_items` in psql to view all constraints

## Stretch (Optional)
Add an exclusion constraint to a `reservations` table that prevents overlapping time ranges for the same resource.

## Time Estimate
20 minutes
