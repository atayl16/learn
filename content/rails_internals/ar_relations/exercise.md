# Exercise: Active Record Relations & Query Interface

## Objective
Build complex queries using scopes, chaining, and lazy evaluation without triggering N+1 queries.

## Task
In a Rails app with `User` and `Post` models:

1. Create scopes for filtering active users and recent posts
2. Write a query that finds active users with published posts from the last week
3. Use `includes` to preload posts and avoid N+1
4. Check the generated SQL and verify it's efficient

## Acceptance Criteria
- [ ] `User.active` scope returns only `active: true` users
- [ ] `Post.recent` scope returns posts from the last 7 days
- [ ] Query finds users with recent published posts using joins
- [ ] Eager loading with `includes(:posts)` prevents N+1 when iterating
- [ ] `.to_sql` output shows expected WHERE and JOIN clauses
- [ ] `development.log` shows 2 queries (users + posts), not N queries

## Verification Steps

1. Run in console:

```ruby
users = User.active.joins(:posts).where(posts: { published: true, created_at: 7.days.ago.. }).distinct
puts users.to_sql
# Verify SQL has JOIN and WHERE clauses

```

2. Check N+1 prevention:

```ruby
users = User.includes(:posts).limit(5)
users.each { |u| puts "#{u.name}: #{u.posts.count} posts" }
# Check log: should show 2 queries, not 6

```

3. Test scopes:

```ruby
User.active.count
Post.recent.count

```

## Setup Code

### Step 1: Create Models

```bash
rails new relations_demo --skip-javascript
cd relations_demo
bin/rails generate model User name:string email:string active:boolean role:string
bin/rails generate model Post title:string body:text published:boolean user:references
bin/rails db:migrate

```

### Step 2: Add Scopes

Edit `app/models/user.rb`:

```ruby
class User < ApplicationRecord
  has_many :posts

  scope :active, -> { where(active: true) }
  scope :admins, -> { where(role: "admin") }
  scope :with_posts, -> { joins(:posts).distinct }
end

```

Edit `app/models/post.rb`:

```ruby
class Post < ApplicationRecord
  belongs_to :user

  scope :published, -> { where(published: true) }
  scope :recent, -> { where("created_at > ?", 7.days.ago) }
end

```

### Step 3: Seed Data

```bash
bin/rails console

```

```ruby
# Create users
5.times do |i|
  User.create(name: "User #{i}", email: "user#{i}@example.com", active: i.even?, role: i < 2 ? "admin" : "user")
end

# Create posts
User.all.each do |user|
  3.times do |j|
    Post.create(
      user: user,
      title: "Post #{j} by #{user.name}",
      body: "Content...",
      published: j.odd?,
      created_at: (10 - j).days.ago
    )
  end
end

```

### Step 4: Test Chaining

```ruby
# Active users with published posts
users = User.active.joins(:posts).where(posts: { published: true }).distinct
puts users.to_sql

# Verify SQL:
# SELECT DISTINCT users.* FROM users
# INNER JOIN posts ON posts.user_id = users.id
# WHERE users.active = true AND posts.published = true

```

### Step 5: Prevent N+1

**Bad (N+1):**

```ruby
users = User.limit(3)
users.each { |u| puts "#{u.name}: #{u.posts.count}" }
# Check log: 1 query for users + 3 queries for posts = 4 total

```

**Good (eager loading):**

```ruby
users = User.includes(:posts).limit(3)
users.each { |u| puts "#{u.name}: #{u.posts.count}" }
# Check log: 1 query for users + 1 query for posts = 2 total

```

### Step 6: Aggregations

```ruby
# Count by role
User.group(:role).count
# => {"admin" => 2, "user" => 3}

# Average posts per user
User.joins(:posts).group("users.id").count.values.sum / User.count.to_f

```

## Stretch (Optional)

1. Create a scope that combines multiple conditions:

```ruby
scope :active_admins_with_recent_posts, -> {
  active.admins.joins(:posts).where(posts: { created_at: 7.days.ago.. }).distinct
}

```

2. Use `pluck` to extract emails efficiently:

```ruby
User.active.pluck(:email)
# Returns array of emails without instantiating User objects

```

3. Add an `or` condition:

```ruby
User.where(role: "admin").or(User.where(active: true))

```

## Time Estimate
20 minutes
