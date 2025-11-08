# N+1 Query Detection & Resolution

## What It Is
An N+1 query problem occurs when your code executes one query to fetch a collection of records, then N additional queries to fetch associated records for each item. For example, loading 50 posts and their authors triggers 1 query for posts + 50 queries for authors (51 total).

## Why It Matters
N+1 queries are the most common performance bottleneck in Rails applications. A single endpoint fetching 100 records with N+1 issues can generate thousands of database queries, increasing response time from 50ms to 5 seconds. Production dashboards show N+1 as the top contributor to slow API endpoints and page loads.

## When to Use
- Profiling slow endpoints that make hundreds of queries
- Code review: checking loops that access associations
- Development: running Bullet gem to detect N+1 during feature work
- Optimization: when query count is high but individual queries are fast
- Acceptable N+1: small collections (N < 5) where eager loading would fetch unnecessary data

## Three Common Pitfalls
1. **Over-eager loading:** Using `includes` for associations you don't need wastes memory and slows queries. Profile first, then optimize only the associations you iterate over.
2. **Mixing includes and conditions:** Writing `User.includes(:posts).where("posts.published = true")` triggers two queries instead of a single JOIN. Use `eager_load` or `joins` for filtered associations.
3. **Hidden N+1 in views:** Controllers may look clean, but partials and helpers often access associations. Run Bullet in test suite to catch these.

---

## Identifying N+1 Queries

Check your logs for repeated queries with only the foreign key changing:

```ruby
# Controller
@posts = Post.all
@posts.each { |post| puts post.author.name }
```

**Log output:**
```
Post Load (0.5ms)  SELECT "posts".* FROM "posts"
User Load (0.3ms)  SELECT "users".* FROM "users" WHERE "users"."id" = 1
User Load (0.3ms)  SELECT "users".* FROM "users" WHERE "users"."id" = 2
User Load (0.3ms)  SELECT "users".* FROM "users" WHERE "users"."id" = 3
# ... 47 more identical queries
```

You execute 1 + N queries (51 total for 50 posts).

---

## Using Bullet Gem

Add Bullet to automatically detect N+1 queries during development and tests:

```ruby
# Gemfile
group :development, :test do
  gem 'bullet'
end

# config/environments/development.rb
config.after_initialize do
  Bullet.enable = true
  Bullet.alert = true
  Bullet.console = true
  Bullet.rails_logger = true
end
```

When you trigger an N+1, Bullet logs:

```
USE eager loading detected
  Post => [:author]
  Add to your query: .includes(:author)
```

Run your test suite with Bullet enabled to catch N+1 issues before code review.

---

## Solution 1: includes

Use `includes` for most cases. Rails loads associations in a second query:

```ruby
# Executes 2 queries: 1 for posts, 1 for all authors
@posts = Post.includes(:author)
@posts.each { |post| puts post.author.name }
```

**Log output:**
```
Post Load (0.5ms)  SELECT "posts".* FROM "posts"
User Load (1.2ms)  SELECT "users".* FROM "users" WHERE "users"."id" IN (1, 2, 3, ...)
```

`includes` decides between `preload` (separate queries) or `eager_load` (LEFT JOIN) based on your query.

---

## Solution 2: preload

Force separate queries even if you add conditions:

```ruby
# Always uses 2 queries (1 for posts, 1 for authors)
@posts = Post.preload(:author).where(published: true)
@posts.each { |post| puts post.author.name }
```

Use `preload` when you want to ensure separate queries for performance reasons (large JOINs can be slower than two small queries).

---

## Solution 3: eager_load

Force a single LEFT JOIN query:

```ruby
# Single query with LEFT JOIN
@posts = Post.eager_load(:author).where("users.verified = true")
```

**Log output:**
```
SELECT "posts".*, "users".*
FROM "posts"
LEFT OUTER JOIN "users" ON "users"."id" = "posts"."author_id"
WHERE "users"."verified" = true
```

Use `eager_load` when you need to filter by associated table columns.

---

## Solution 4: joins

Only fetch the main records, not the association:

```ruby
# Filters posts by author but doesn't load author objects
@posts = Post.joins(:author).where(users: { verified: true })
@posts.each { |post| post.author.name } # Still triggers N+1!
```

Use `joins` for filtering, not for loading associations. If you need the association data, use `eager_load` instead.

---

## Nested Associations

Eager load multiple levels:

```ruby
# Loads posts, their authors, and each author's company
@posts = Post.includes(author: :company)
@posts.each do |post|
  puts "#{post.title} by #{post.author.name} at #{post.author.company.name}"
end
```

**Generates 3 queries:**
1. Posts
2. Authors (WHERE id IN ...)
3. Companies (WHERE id IN ...)

---

## Trade-offs Box
- **Advantage:** Eager loading reduces query count from O(N) to O(1), often improving response time by 10-100x.
- **Cost:** Loads all association data into memory, which can bloat memory usage for large result sets or unused associations.
- **When to skip:** When N is small (<5), when you only need the association for a few records, or when profiling shows memory pressure.

---

## Debugging Checklist

When optimizing N+1 queries:

1. Run Bullet gem in development/test to auto-detect N+1 issues
2. Check logs for repeated queries with pattern `WHERE "table"."id" = ?`
3. Profile query count before/after: compare `ActiveRecord::Base.connection.query_cache.size`
4. Verify associations are actually used — don't eager load unused data
5. Test memory impact: large `includes` can cause OOM on big datasets
6. Measure response time — sometimes two indexed queries beat one massive JOIN
7. Check views/partials for hidden association access (common in helpers)

---

## One-Minute Recap
- N+1 queries execute 1 + N database calls when iterating over associations
- Bullet gem auto-detects N+1 issues during development and testing
- Use `includes` for most cases, `eager_load` for filtering on associations, `preload` to force separate queries
- Nested associations use `includes(author: :company)` syntax
- Skip eager loading when N is small or associations are rarely accessed
