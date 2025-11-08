# Exercise: Code Review Techniques

## Objective

Practice identifying critical issues, writing constructive feedback, and distinguishing blocking from non-blocking comments on sample pull requests.

## Task

You're reviewing three pull requests from your team. For each PR, identify issues, categorize them as blocking or non-blocking, and write feedback using the techniques from the overview.

---

### PR 1: User Authentication

**Code changes:**

```ruby
# app/controllers/sessions_controller.rb
class SessionsController < ApplicationController
  def create
    user = User.find_by(email: params[:email])
    if user && user.password == params[:password]
      session[:user_id] = user.id
      redirect_to dashboard_path
    else
      flash[:error] = "Invalid credentials"
      render :new
    end
  end
end

# app/models/user.rb
class User < ApplicationRecord
  validates :email, presence: true
end
```

**Your task:**
1. Identify at least 2 critical (blocking) issues
2. Identify at least 1 style or improvement (non-blocking) suggestion
3. Write review comments for each issue using the feedback structure from the overview

---

### PR 2: Order Processing

**Code changes:**

```ruby
# app/services/order_processor.rb
class OrderProcessor
  def process(order_id)
    order = Order.find(order_id)
    order.items.each do |item|
      item.update(status: "processed")
      InventoryService.decrement_stock(item.product_id, item.quantity)
    end
    order.update(status: "completed", processed_at: Time.now)
    OrderMailer.confirmation(order.id).deliver_now
  rescue => e
    puts "Error: #{e.message}"
  end
end
```

**Your task:**
1. Identify issues with database queries and performance
2. Identify issues with error handling
3. Identify issues with transaction safety
4. Write blocking vs non-blocking comments appropriately

---

### PR 3: Product Migration

**Code changes:**

```ruby
# db/migrate/20241108_remove_description_from_products.rb
class RemoveDescriptionFromProducts < ActiveRecord::Migration[7.0]
  def change
    remove_column :products, :description, :text
  end
end
```

**PR description:** "Removing unused description field from products table."

**Your task:**
1. Assess the migration safety for zero-downtime deployments
2. Check if the migration is reversible
3. Write feedback explaining deployment risks

---

## Acceptance Criteria

- [ ] PR 1: Identified password comparison vulnerability (blocking)
- [ ] PR 1: Identified missing password hashing/bcrypt (blocking)
- [ ] PR 1: Suggested validation improvements (non-blocking)
- [ ] PR 2: Flagged N+1 queries and suggested fix (blocking on high-traffic endpoints)
- [ ] PR 2: Identified missing transaction wrapper (blocking)
- [ ] PR 2: Noted error handling issues (blocking)
- [ ] PR 3: Explained two-phase deployment requirement (blocking)
- [ ] PR 3: Confirmed migration is not reversible (blocking)
- [ ] All comments use clear labels (BLOCKING, nit, question, etc.)
- [ ] All blocking comments explain the "why" and suggest a solution

## Verification Steps

Compare your review comments to these key issues:

**PR 1 Critical Issues:**
- Password stored and compared in plaintext (security vulnerability)
- Missing `has_secure_password` or bcrypt integration
- No rate limiting on login attempts

**PR 2 Critical Issues:**
- N+1 query on `order.items.each`
- No database transaction wrapping updates
- Error swallowing with generic rescue and `puts` instead of proper logging
- Sending email synchronously instead of background job

**PR 3 Critical Issues:**
- Dropping column will break running app servers during deployment
- Migration is not reversible (no `up`/`down` or reversible block)
- No deprecation period before column removal

## Stretch (Optional)

Create a custom review checklist for your team based on your most common PR issues. Include 5-8 items specific to your domain (e.g., "Verify Stripe idempotency keys" for payment PRs).

## Time Estimate

22 minutes

## Solution Notes

**Example review comment for PR 1:**

```
BLOCKING: This compares passwords in plaintext, which is a critical security vulnerability.
Passwords should never be stored or compared directly.

Suggested fix:
1. Add `gem 'bcrypt'` to Gemfile
2. Add `has_secure_password` to User model
3. Change comparison to `user.authenticate(params[:password])`
4. Ensure password is stored as `password_digest` in the database

See Rails security guide: https://guides.rubyonrails.org/security.html#user-management
```

**Example non-blocking comment for PR 2:**

```
nit: `Time.now` should be `Time.current` to respect the Rails timezone setting.
This prevents bugs when users are in different timezones. Not blocking since
processed_at is only used for admin reporting.
```
