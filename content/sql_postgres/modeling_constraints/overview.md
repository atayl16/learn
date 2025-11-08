# Modeling & Constraints (FKs, Uniques, Check)

## What It Is
Database constraints enforce rules at the schema level: foreign keys maintain referential integrity, unique constraints prevent duplicates, check constraints validate data ranges, and NOT NULL ensures required fields. Postgres enforces these before saving, catching invalid data that application validations might miss.

## Why It Matters
Constraints are the last line of defense against bad data. Application validations can be bypassed (bulk imports, console edits, bugs). Database constraints guarantee integrity even when code fails. Seniors design schemas that enforce business rules via constraints, not just Rails validations.

## When to Use
- **Foreign keys:** Always, for associations (user_id → users.id)
- **Unique constraints:** Prevent duplicates (email, SKU) across concurrent requests
- **Check constraints:** Validate ranges (price > 0, quantity >= 0)
- **NOT NULL:** Require critical fields (email, user_id)

## Three Common Pitfalls
1. **Missing foreign keys:** Rails associations don't create FKs automatically. Add them explicitly in migrations.
2. **Unique constraint vs unique index:** Similar but not identical. Unique constraints create indexes but also enforce integrity. Use constraints for data rules; indexes for performance.
3. **Check constraints ignored by ActiveRecord:** Rails doesn't generate check constraint validations automatically. Add both DB constraint and model validation.

---

## Foreign Keys

Ensure referential integrity: child rows must reference valid parent rows.

**Migration:**
```ruby
class CreateOrders < ActiveRecord::Migration[7.0]
  def change
    create_table :orders do |t|
      t.references :user, null: false, foreign_key: true
      t.decimal :total, precision: 10, scale: 2
      t.timestamps
    end
  end
end
```

**SQL generated:**
```sql
CREATE TABLE orders (
  id BIGSERIAL PRIMARY KEY,
  user_id BIGINT NOT NULL,
  total DECIMAL(10, 2),
  created_at TIMESTAMP NOT NULL,
  updated_at TIMESTAMP NOT NULL,
  CONSTRAINT fk_rails_abc123 FOREIGN KEY (user_id) REFERENCES users(id)
);
```

**Behavior:**
- Prevents inserting `order` with non-existent `user_id`
- Prevents deleting `user` with existing `orders` (unless `ON DELETE CASCADE`)

**On delete options:**
```ruby
t.references :user, foreign_key: { on_delete: :cascade }
# Deletes orders when user is deleted

t.references :user, foreign_key: { on_delete: :nullify }
# Sets user_id to NULL when user is deleted

t.references :user, foreign_key: { on_delete: :restrict }
# Prevents deleting user with orders (default)
```

---

## Unique Constraints

Prevent duplicate values across one or more columns.

**Single column:**
```ruby
class AddUniqueIndexToUsersEmail < ActiveRecord::Migration[7.0]
  def change
    add_index :users, :email, unique: true
  end
end
```

**SQL:**
```sql
CREATE UNIQUE INDEX index_users_on_email ON users (email);
```

**Multi-column (composite unique):**
```ruby
add_index :enrollments, [:user_id, :course_id], unique: true
# Ensures user can enroll in each course only once
```

**Unique constraint (Rails 6.1+):**
```ruby
create_table :products do |t|
  t.string :sku, null: false
end

add_index :products, :sku, unique: true, name: 'unique_sku'

# Or with constraint
execute <<-SQL
  ALTER TABLE products ADD CONSTRAINT unique_sku UNIQUE (sku);
SQL
```

---

## Check Constraints

Validate data meets conditions.

**Rails 6.1+ syntax:**
```ruby
class CreateProducts < ActiveRecord::Migration[7.0]
  def change
    create_table :products do |t|
      t.string :name, null: false
      t.decimal :price, precision: 10, scale: 2
      t.integer :quantity

      t.check_constraint "price > 0", name: "price_positive"
      t.check_constraint "quantity >= 0", name: "quantity_non_negative"
      t.timestamps
    end
  end
end
```

**SQL:**
```sql
CREATE TABLE products (
  ...
  CONSTRAINT price_positive CHECK (price > 0),
  CONSTRAINT quantity_non_negative CHECK (quantity >= 0)
);
```

**Adding constraint to existing table:**
```ruby
add_check_constraint :products, "price > 0", name: "price_positive"
```

**Removing:**
```ruby
remove_check_constraint :products, name: "price_positive"
```

---

## NOT NULL Constraints

Require values for critical columns.

```ruby
class CreateUsers < ActiveRecord::Migration[7.0]
  def change
    create_table :users do |t|
      t.string :email, null: false
      t.string :name, null: false
      t.string :nickname  # nullable
      t.timestamps
    end
  end
end
```

**Adding to existing column:**
```ruby
change_column_null :users, :email, false
```

**Safe multi-step process (zero-downtime):**
```ruby
# Step 1: Add default for existing NULLs
update("UPDATE users SET email = '' WHERE email IS NULL")

# Step 2: Add constraint
change_column_null :users, :email, false
```

---

## Exclusion Constraints (Advanced)

Prevent overlapping ranges (Postgres-specific).

**Example: No overlapping reservations**
```ruby
execute <<-SQL
  CREATE EXTENSION IF NOT EXISTS btree_gist;

  ALTER TABLE reservations
  ADD CONSTRAINT no_overlap
  EXCLUDE USING gist (
    room_id WITH =,
    tsrange(start_time, end_time) WITH &&
  );
SQL
```

This prevents reservations for the same room during overlapping times.

---

## Constraint Violations

**Handling errors:**
```ruby
user = User.create(email: existing_email)
# ActiveRecord::RecordNotUnique: PG::UniqueViolation: ERROR:  duplicate key value violates unique constraint "index_users_on_email"

begin
  User.create!(email: existing_email)
rescue ActiveRecord::RecordNotUnique
  # Handle duplicate
end
```

**Check constraint violation:**
```ruby
Product.create!(name: "Widget", price: -10)
# ActiveRecord::StatementInvalid: PG::CheckViolation: ERROR:  new row for relation "products" violates check constraint "price_positive"
```

---

## Trade-offs Box
- **Advantage:** Database constraints enforce integrity even when application code fails. Protect against bulk imports, console errors, and bugs.
- **Cost:** Constraints add overhead to writes. Complex check constraints can slow inserts/updates.
- **When to skip:** Rarely. Only skip FKs if using soft deletes or polymorphic associations without a clear parent.

---

## Debugging Checklist

When constraint errors occur:

1. Check error message for constraint name: `violates unique constraint "index_users_on_email"`
2. Find constraint in schema.rb or `\d table_name` in psql
3. For unique violations: check for race conditions (use `find_or_create_by` or locks)
4. For FK violations: verify parent record exists before inserting child
5. For check violations: inspect data values that failed
6. List all constraints: `SELECT conname, contype FROM pg_constraint WHERE conrelid = 'table_name'::regclass;`
7. Disable constraint temporarily (dev only): `SET CONSTRAINTS constraint_name DEFERRED;`

---

## One-Minute Recap
- Foreign keys enforce referential integrity; always add them for associations
- Unique constraints prevent duplicates; use for business-critical uniqueness (email, SKU)
- Check constraints validate data ranges (price > 0); add both DB constraint and Rails validation
- NOT NULL ensures required fields; use for critical columns
- Constraints protect data integrity when application validations fail
