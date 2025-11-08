# Exercise: Zero-Downtime Migrations

## Objective
Practice writing safe, zero-downtime migrations for adding columns, indexes, and constraints to large tables.

## Task
You have a `posts` table with 5 million rows in production. You need to add an `author_name` column with a default value, create an index, and enforce NOT NULL. Write migrations that won't lock the table or cause downtime.

**Current schema:**

```ruby
create_table :posts do |t|
  t.references :user, null: false, foreign_key: true
  t.string :title, null: false
  t.text :body
  t.timestamps
end

```

**Requirements:**
- Add `author_name` string column with default `'Anonymous'`
- Backfill existing posts with user's name
- Add NOT NULL constraint
- Create index on `author_name`

## Acceptance Criteria
- [ ] Migration 1: Add `author_name` column without default or NOT NULL
- [ ] Migration 2: Backfill `author_name` in batches of 10,000, using raw SQL for speed
- [ ] Migration 3: Set default value for `author_name` to `'Anonymous'`
- [ ] Migration 4: Add NOT NULL constraint to `author_name`
- [ ] Migration 5: Create index on `author_name` concurrently
- [ ] All migrations use `disable_ddl_transaction!` where appropriate
- [ ] Verify no exclusive locks held using `SELECT * FROM pg_locks WHERE mode = 'AccessExclusiveLock';`

## Verification Steps
1. Run each migration in sequence and check execution time
2. Monitor `pg_stat_activity` during migrations to verify no blocking queries
3. Verify index created: `\d posts` shows index_posts_on_author_name
4. Check schema.rb shows `null: false` and `default: 'Anonymous'`
5. Create a new post and verify `author_name` defaults to 'Anonymous'
6. Test rollback: migrations should cleanly reverse

## Stretch (Optional)
Install strong_migrations gem, add an unsafe migration, and observe the warning. Fix it based on the suggestion.

## Time Estimate
25 minutes
