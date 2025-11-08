# Exercise: Database Indexing

## Objective
Practice adding appropriate indexes to optimize common query patterns and verify usage with EXPLAIN ANALYZE.

## Task
You have a posts table with millions of rows. Users frequently query posts by author, publication status, and creation date. Add indexes to optimize these queries, then use EXPLAIN to verify Postgres uses them.

**Setup:**
```ruby
# Assume this schema
create_table :posts do |t|
  t.references :user, null: false
  t.string :title, null: false
  t.text :body
  t.string :status  # 'draft', 'published', 'archived'
  t.datetime :published_at
  t.timestamps
end
```

**Common queries:**
```ruby
# Query 1: User's published posts sorted by date
Post.where(user_id: 5, status: 'published').order(published_at: :desc).limit(20)

# Query 2: Recently published posts (homepage)
Post.where(status: 'published').where('published_at > ?', 1.week.ago).order(published_at: :desc)

# Query 3: User's drafts
Post.where(user_id: 5, status: 'draft')
```

## Acceptance Criteria
- [ ] Add composite index on `(user_id, status, published_at)` for Query 1
- [ ] Add partial index on `published_at` for published posts only for Query 2
- [ ] Add index on `user_id` (if not already present from foreign key)
- [ ] Run `EXPLAIN ANALYZE` on all three queries and verify "Index Scan" appears (not "Seq Scan")
- [ ] Document which index each query uses in comments
- [ ] Identify one query that would NOT benefit from an index and explain why

## Verification Steps
1. Run migrations and check `db/schema.rb` shows all indexes
2. Open psql and run `\d posts` to view indexes
3. Run `EXPLAIN ANALYZE SELECT * FROM posts WHERE user_id = 5 AND status = 'published' ORDER BY published_at DESC;` and confirm it uses the composite index
4. Run `EXPLAIN ANALYZE SELECT * FROM posts WHERE status = 'published' AND published_at > NOW() - INTERVAL '7 days';` and confirm it uses the partial index
5. Check index sizes: `SELECT indexrelname, pg_size_pretty(pg_relation_size(indexrelid)) FROM pg_stat_user_indexes WHERE schemaname = 'public' AND tablename = 'posts';`

## Stretch (Optional)
Add a GIN index on a `tags` array column and write a query that uses it to find posts with specific tags.

## Time Estimate
22 minutes
