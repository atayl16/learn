# Exercise: Transactions, Isolation, and Locks

## Objective
Practice using transactions, SELECT FOR UPDATE, and isolation levels to prevent race conditions in concurrent operations.

## Task
You're building a ticket reservation system. Multiple users can simultaneously attempt to reserve the same ticket. Implement locking to ensure only one user successfully reserves each ticket.

**Setup:**

```ruby
class Ticket < ApplicationRecord
  # status: 'available', 'reserved', 'sold'
end

# Schema
create_table :tickets do |t|
  t.string :seat_number, null: false
  t.string :status, default: 'available'
  t.references :user, foreign_key: true
  t.timestamps
end

```

**Scenario:**
Two users (User 1 and User 2) simultaneously try to reserve the last available ticket (Ticket #42).

## Acceptance Criteria
- [ ] Implement `reserve_ticket(ticket_id, user_id)` method using a transaction and SELECT FOR UPDATE
- [ ] Verify only one user successfully reserves the ticket when both call the method concurrently
- [ ] Handle the case where ticket is already reserved (raise error or return false)
- [ ] Test with two Rails consoles simulating concurrent requests
- [ ] Implement a second version using SERIALIZABLE isolation level instead of SELECT FOR UPDATE
- [ ] Compare both approaches: which is faster? Which is safer?

## Verification Steps
1. Create 10 available tickets in the database
2. Open two Rails console windows
3. In Console 1: `reserve_ticket(1, user_a.id)`
4. In Console 2 (within 2 seconds): `reserve_ticket(1, user_b.id)`
5. Verify only one console succeeds; the other raises an error or returns false
6. Check `Ticket.find(1).user_id` matches the successful user
7. Run `SELECT * FROM pg_stat_activity` during concurrent requests to see locks

## Stretch (Optional)
Implement advisory locks to ensure only one background job processes a batch of tickets at a time.

## Time Estimate
24 minutes
