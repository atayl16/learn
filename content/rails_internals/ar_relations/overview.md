# Active Record Relations & Query Interface

## What It Is
ActiveRecord::Relation is a lazy, chainable query builder that translates Ruby method calls into SQL. Relations don't execute immediately; they defer database queries until you iterate, count, or call `to_a`. This enables composing complex queries by chaining `.where`, `.joins`, `.order`, etc.

## Why It Matters
Mastering relations prevents N+1 queries, reduces database load, and makes code reusable. Chaining allows building queries conditionally (filters, pagination, sorting) without string concatenation. Lazy loading means queries only run when needed, avoiding unnecessary database hits.

## When to Use
- Building complex filters: search, pagination, sorting
- Reusing query logic: scopes and class methods
- Optimizing: combining multiple conditions into one query
- Conditional queries: adding `.where` based on params

## Three Common Pitfalls
1. **Triggering queries unintentionally:** `.count`, `.each`, `.to_a`, `.first` all execute immediately. Assigning a relation (`users = User.where(...)`) doesn't query yet; calling `users.count` does.
2. **Overusing `find_by_sql`:** Raw SQL bypasses relation chaining and returns plain arrays. Prefer ActiveRecord methods for composability.
3. **Forgetting `distinct`:** `User.joins(:posts).where(posts: {published: true})` returns duplicate users if they have multiple posts. Add `.distinct` to deduplicate.

---

## Lazy Loading

Relations defer execution:

```ruby
# No query yet — just builds the relation
users = User.where(active: true)

# Query executes here
users.each { |u| puts u.name }
# SQL: SELECT * FROM users WHERE active = true
```

**When queries execute:**
- `.each`, `.map`, `.to_a` (enumeration)
- `.first`, `.last`, `.take` (single record)
- `.count`, `.sum`, `.average` (aggregates)
- `.exists?`, `.any?`, `.none?` (boolean checks)

**Check generated SQL:**
```ruby
User.where(active: true).to_sql
# => "SELECT \"users\".* FROM \"users\" WHERE \"users\".\"active\" = TRUE"
```

---

## Chaining Methods

Build queries step-by-step:

```ruby
User
  .where(active: true)
  .where("created_at > ?", 1.year.ago)
  .order(created_at: :desc)
  .limit(10)
# SELECT * FROM users
# WHERE active = true AND created_at > '2024-01-01'
# ORDER BY created_at DESC LIMIT 10
```

**Hash conditions:**
```ruby
User.where(role: "admin", active: true)
# WHERE role = 'admin' AND active = true
```

**SQL fragments (use placeholders to prevent SQL injection):**
```ruby
User.where("age > ?", 18)
User.where("name LIKE ?", "%John%")
```

**Arrays for IN clauses:**
```ruby
User.where(id: [1, 2, 3])
# WHERE id IN (1, 2, 3)
```

---

## Scopes

Encapsulate reusable query logic:

```ruby
class User < ApplicationRecord
  scope :active, -> { where(active: true) }
  scope :recent, -> { where("created_at > ?", 1.week.ago) }
  scope :admins, -> { where(role: "admin") }
end

User.active.recent.admins
# SELECT * FROM users
# WHERE active = true AND created_at > '2024-10-01' AND role = 'admin'
```

**Scopes with arguments:**
```ruby
scope :created_after, ->(date) { where("created_at > ?", date) }

User.created_after(1.month.ago)
```

**Class methods (alternative):**
```ruby
class User < ApplicationRecord
  def self.active
    where(active: true)
  end
end

User.active  # same as scope
```

---

## Joins and Includes

### Inner Join (only users with posts)
```ruby
User.joins(:posts)
# SELECT users.* FROM users INNER JOIN posts ON posts.user_id = users.id
```

### Left Outer Join (all users, with/without posts)
```ruby
User.left_joins(:posts)
# SELECT users.* FROM users LEFT OUTER JOIN posts ON posts.user_id = users.id
```

### Filtering joined tables
```ruby
User.joins(:posts).where(posts: { published: true })
# SELECT users.* FROM users
# INNER JOIN posts ON posts.user_id = users.id
# WHERE posts.published = true
```

### Preloading (avoid N+1)
```ruby
# Bad: N+1 queries
users = User.all
users.each { |u| puts u.posts.count }
# Query 1: SELECT * FROM users
# Query 2-N: SELECT * FROM posts WHERE user_id = 1 (repeated per user)

# Good: Eager load posts
users = User.includes(:posts)
users.each { |u| puts u.posts.count }
# Query 1: SELECT * FROM users
# Query 2: SELECT * FROM posts WHERE user_id IN (1,2,3,...)
```

**Difference:**
- `joins`: SQL JOIN, filters users, no preloading
- `includes`: Preloads associations, prevents N+1

---

## Aggregations

```ruby
User.count
# SELECT COUNT(*) FROM users

User.where(active: true).count
# SELECT COUNT(*) FROM users WHERE active = true

User.average(:age)
# SELECT AVG(age) FROM users

User.group(:role).count
# SELECT role, COUNT(*) FROM users GROUP BY role
# => {"admin" => 5, "user" => 120}
```

---

## Select and Pluck

**Select specific columns:**
```ruby
User.select(:id, :name)
# SELECT id, name FROM users
```

**Pluck (returns array, not ActiveRecord objects):**
```ruby
User.pluck(:email)
# => ["alice@ex.com", "bob@ex.com"]
# SELECT email FROM users

User.pluck(:id, :name)
# => [[1, "Alice"], [2, "Bob"]]
```

**Performance:** `pluck` is faster than `map` because it skips object instantiation.

---

## Or and Not

**Or:**
```ruby
User.where(role: "admin").or(User.where(active: true))
# WHERE (role = 'admin') OR (active = true)
```

**Not:**
```ruby
User.where.not(role: "guest")
# WHERE role != 'guest'
```

---

## Reordering and Reversing

```ruby
User.order(:created_at).reverse_order
# ORDER BY created_at DESC

User.reorder(name: :asc)
# Replaces existing order
```

---

## Trade-offs Box
- **Advantage:** Chainable, composable, lazy evaluation reduces unnecessary queries.
- **Cost:** Abstraction can hide inefficient SQL (e.g., accidental N+1). Always check generated SQL.
- **When to skip:** For very complex queries (CTEs, window functions), use `find_by_sql` or Arel.

---

## Debugging Checklist

When queries misbehave:

1. Check generated SQL: `relation.to_sql`
2. Enable query logging: `ActiveRecord::Base.logger = Logger.new(STDOUT)`
3. Use `explain`: `User.where(...).explain` to see query plan
4. Check for N+1 with Bullet gem
5. Verify associations: `has_many :posts` must exist for `.includes(:posts)`
6. Use `distinct` if joins return duplicates
7. Profile with `ActiveSupport::Notifications.subscribe("sql.active_record")`

---

## One-Minute Recap
- ActiveRecord::Relation is lazy: no query until enumeration/count/first
- Chain methods to build complex queries: `.where.joins.order.limit`
- Scopes encapsulate reusable query logic
- `joins` filters via SQL JOIN; `includes` preloads to avoid N+1
- Always check generated SQL with `.to_sql` and profile with `explain`
