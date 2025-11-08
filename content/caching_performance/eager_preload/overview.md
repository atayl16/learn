# Eager Loading vs Preloading Strategies

## What It Is
Rails provides four methods for loading associations: `includes`, `preload`, `eager_load`, and `joins`. Each uses different SQL strategies (separate queries vs JOINs) and handles conditions differently. Choosing the right one impacts query performance, memory usage, and whether your conditions work correctly.

## Why It Matters
Using the wrong loading method can degrade performance or produce incorrect results. `includes` with WHERE conditions on associations silently switches to a LEFT JOIN, which may not match your expectations. Large JOINs can be slower than two indexed queries. Understanding when to force `preload` (separate queries) vs `eager_load` (JOIN) vs `joins` (filter-only) prevents subtle bugs and performance regressions.

## When to Use
- `includes`: Default choice for eager loading; Rails auto-selects strategy
- `preload`: Force separate queries when JOINs would be too expensive
- `eager_load`: Force LEFT JOIN when filtering on associated table columns
- `joins`: Filter main records by associations without loading association data
- Nested associations: avoid fetching data you won't use

## Three Common Pitfalls
1. **Using includes with WHERE on associations:** Rails switches to LEFT JOIN, but you wanted separate queries. Use `preload` to force separate queries or `eager_load` if JOIN is intentional.
2. **Over-fetching with nested includes:** `includes(author: [:posts, :comments, :company])` loads massive data sets. Only include associations you iterate over.
3. **Using joins when you need association data:** `Post.joins(:author)` filters posts but doesn't load authors. Accessing `post.author` still triggers N+1 queries.

---

## includes: Smart Auto-Selection

`includes` picks the best strategy based on your query:

```ruby
# Uses preload (2 separate queries)
Post.includes(:author).limit(10)
# SELECT * FROM posts LIMIT 10
# SELECT * FROM users WHERE id IN (...)

# Switches to eager_load (LEFT JOIN) when WHERE references association
Post.includes(:author).where(users: { verified: true })
# SELECT posts.*, users.* FROM posts LEFT JOIN users ON users.id = posts.user_id WHERE users.verified = true

```

Use `includes` as the default. Rails chooses efficiently unless you need explicit control.

---

## preload: Force Separate Queries

`preload` always uses separate queries, never JOINs:

```ruby
# 2 queries regardless of conditions
Post.preload(:author).where(title: "Rails Guide")
# SELECT * FROM posts WHERE title = 'Rails Guide'
# SELECT * FROM users WHERE id IN (...)

```

**When to use:**
- Large JOINs are slow (thousands of rows multiplied across associations)
- You want predictable separate queries for profiling
- Database indexes favor separate queries over JOINs

**Cannot do:**

```ruby
# ERROR: users table not in FROM clause
Post.preload(:author).where(users: { verified: true })

```

Use `eager_load` or `joins` for filtering on associations.

---

## eager_load: Force LEFT JOIN

`eager_load` always uses a single LEFT JOIN:

```ruby
Post.eager_load(:author).where(users: { verified: true })
# SELECT posts.*, users.*
# FROM posts
# LEFT OUTER JOIN users ON users.id = posts.user_id
# WHERE users.verified = true

```

**When to use:**
- Filtering or ordering by associated table columns
- You need one query for EXPLAIN ANALYZE profiling
- Database query planner optimizes JOINs well (indexed foreign keys)

**Trade-off:** Loads all data into memory at once. Large result sets can cause memory spikes.

---

## joins: Filter Without Loading Associations

`joins` adds INNER JOIN to filter records but doesn't load association data:

```ruby
# Only loads posts, not authors
Post.joins(:author).where(users: { verified: true })
# SELECT posts.* FROM posts INNER JOIN users ON users.id = posts.user_id WHERE users.verified = true

# Accessing author still triggers N+1
@posts.each { |post| post.author.name } # N queries!

```

**When to use:**
- Filtering main table by association attributes
- You don't need the association data (e.g., checking existence)
- Reducing data transfer when associations are large

**Combine with includes for best of both:**

```ruby
# Filter + eager load
Post.joins(:author).includes(:author).where(users: { verified: true })

```

---

## Choosing the Right Method

| Method       | SQL Strategy        | Loads Associations | Allows WHERE on Associations | Use Case                        |
|--------------|---------------------|--------------------|-----------------------------|----------------------------------|
| `includes`   | Auto (preload/JOIN) | Yes                | Yes (switches to JOIN)      | Default eager loading            |
| `preload`    | Separate queries    | Yes                | No                          | Force 2 queries, avoid JOINs     |
| `eager_load` | LEFT JOIN           | Yes                | Yes                         | Filter/order by associations     |
| `joins`      | INNER JOIN          | No                 | Yes                         | Filter-only, don't load data     |

---

## Nested Associations

Load multiple levels:

```ruby
# 3 queries: posts, authors, companies
Post.includes(author: :company)

# Only load what you use
Post.includes(:author, :tags) # authors AND tags
Post.includes(author: [:company, :certifications]) # nested

```

**Avoid over-fetching:**

```ruby
# BAD: loads all comments even if you only show authors
Post.includes(author: :comments)

# GOOD: only load what the view iterates
Post.includes(:author)

```

Profile memory usage with `ObjectSpace` or `memory_profiler` gem to catch bloated includes.

---

## Conditional Loading

Load associations only when needed:

```ruby
# Conditional includes based on params
query = Post.all
query = query.includes(:author) if params[:show_author]
query = query.includes(:tags) if params[:show_tags]

```

**Use scopes:**

```ruby
class Post < ApplicationRecord
  scope :with_author, -> { includes(:author) }
  scope :with_full_details, -> { includes(author: :company, tags: :category) }
end

# Clean controller
@posts = Post.with_author.limit(20)

```

---

## Measuring Impact

Compare query counts:

```ruby
# Before
Post.all.each { |p| p.author.name } # 51 queries

# After
Post.includes(:author).each { |p| p.author.name } # 2 queries

```

Check memory usage:

```ruby
require 'memory_profiler'

report = MemoryProfiler.report do
  Post.includes(author: :company).limit(1000).to_a
end

report.pretty_print

```

Use `EXPLAIN ANALYZE` to compare JOIN vs separate queries performance.

---

## Trade-offs Box
- **Advantage:** Choosing the right loading strategy can reduce queries from hundreds to 2-5, improving response time by 10-100x.
- **Cost:** Eager loading increases memory usage by loading all association data upfront, which can cause OOM errors on large datasets.
- **When to skip:** When N is tiny (<5), when associations are rarely accessed, or when two queries are faster than one large JOIN.

---

## Debugging Checklist

When optimizing loading strategies:

1. Log queries with `ActiveRecord::Base.logger = Logger.new(STDOUT)` to see SQL
2. Compare query plans: `EXPLAIN ANALYZE` for JOINs vs separate queries
3. Check Bullet gem warnings for unused eager loading (memory waste)
4. Profile memory with `memory_profiler` gem on large result sets
5. Verify foreign key indexes exist: `SELECT * FROM pg_indexes WHERE tablename = 'posts'`
6. Test `includes` vs `preload` vs `eager_load` on production data sizes
7. Measure response time and memory in staging before deploying

---

## One-Minute Recap
- `includes` auto-picks strategy; use as default for eager loading
- `preload` forces separate queries; use when JOINs are expensive
- `eager_load` forces LEFT JOIN; use for filtering on associations
- `joins` filters without loading; use when you don't need association data
- Avoid over-fetching nested associations; only load what you iterate over
