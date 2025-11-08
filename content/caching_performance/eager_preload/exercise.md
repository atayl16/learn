# Exercise: Eager Loading vs Preloading Strategies

## Objective
Compare `includes`, `preload`, `eager_load`, and `joins` by observing SQL queries and measuring performance.

## Task
Using a Rails app with posts, authors, and comments:

1. Create test data with indexed associations
2. Log queries for each loading method
3. Compare SQL output (separate queries vs JOINs)
4. Measure query time and memory usage
5. Test filtering scenarios to see when each method works

## Acceptance Criteria
- [ ] Database has 100+ posts with authors and comments
- [ ] Logs show `includes` using separate queries by default
- [ ] Logs show `includes` switching to LEFT JOIN when WHERE references associations
- [ ] `preload` always uses separate queries even with conditions
- [ ] `eager_load` always uses LEFT JOIN
- [ ] `joins` filters without loading association data (N+1 still occurs)
- [ ] Document shows query count and time for each method

## Verification Steps

1. Check logs for each method's SQL:
```bash
# includes (default)
Post.includes(:author).limit(10).to_a
# Should show 2 separate queries

# includes with association condition
Post.includes(:author).where(users: { verified: true }).to_a
# Should show LEFT JOIN

# preload (forced separate)
Post.preload(:author).limit(10).to_a
# Should show 2 separate queries

# eager_load (forced JOIN)
Post.eager_load(:author).limit(10).to_a
# Should show LEFT JOIN

# joins (no loading)
Post.joins(:author).limit(10).to_a
# Should show INNER JOIN but only SELECT posts.*
```

2. Verify memory usage comparison between methods

3. Test that `joins` doesn't load associations (N+1 test)

## Setup Code

### Step 1: Create Models

```bash
rails new eager_loading_demo --skip-javascript
cd eager_loading_demo
bin/rails generate model User name:string verified:boolean
bin/rails generate model Post title:string user:references
bin/rails generate model Comment body:text post:references
bin/rails db:migrate
```

**Add associations:**

`app/models/user.rb`:
```ruby
class User < ApplicationRecord
  has_many :posts
end
```

`app/models/post.rb`:
```ruby
class Post < ApplicationRecord
  belongs_to :user
  has_many :comments
end
```

`app/models/comment.rb`:
```ruby
class Comment < ApplicationRecord
  belongs_to :post
end
```

### Step 2: Seed Data

```bash
bin/rails console
```

```ruby
# Create test data
100.times do |i|
  user = User.create(name: "User #{i}", verified: i.even?)
  5.times do |j|
    post = Post.create(title: "Post #{j}", user: user)
    3.times do |k|
      Comment.create(body: "Comment #{k}", post: post)
    end
  end
end

puts "Created #{Post.count} posts, #{User.count} users, #{Comment.count} comments"
```

### Step 3: Enable Query Logging

Create `test/loading_strategies_test.rb`:
```ruby
require 'test_helper'

class LoadingStrategiesTest < ActiveSupport::TestCase
  setup do
    # Enable query logging
    ActiveRecord::Base.logger = Logger.new(STDOUT)
  end

  test "includes uses separate queries by default" do
    puts "\n=== includes (default) ==="
    posts = Post.includes(:user).limit(10).to_a
    posts.each { |p| p.user.name } # Should not trigger N+1
  end

  test "includes switches to JOIN with WHERE on association" do
    puts "\n=== includes with WHERE on association ==="
    posts = Post.includes(:user).where(users: { verified: true }).limit(10).to_a
  end

  test "preload forces separate queries" do
    puts "\n=== preload (forced separate) ==="
    posts = Post.preload(:user).limit(10).to_a
    posts.each { |p| p.user.name }
  end

  test "eager_load forces LEFT JOIN" do
    puts "\n=== eager_load (forced JOIN) ==="
    posts = Post.eager_load(:user).limit(10).to_a
    posts.each { |p| p.user.name }
  end

  test "joins filters without loading associations" do
    puts "\n=== joins (filter-only) ==="
    posts = Post.joins(:user).where(users: { verified: true }).limit(10).to_a

    # This WILL trigger N+1 because joins doesn't load users
    puts "\nAccessing user (expect N+1):"
    posts.first(3).each { |p| p.user.name }
  end

  test "nested includes" do
    puts "\n=== nested includes ==="
    posts = Post.includes(user: :posts, comments: []).limit(10).to_a
  end
end
```

### Step 4: Run Tests and Observe

```bash
bin/rails test test/loading_strategies_test.rb
```

Compare SQL output for each test.

### Step 5: Benchmark Performance

Create `lib/tasks/benchmark_loading.rake`:
```ruby
require 'benchmark'

namespace :loading do
  desc "Benchmark loading strategies"
  task benchmark: :environment do
    Benchmark.bm(15) do |x|
      x.report("includes") do
        Post.includes(:user).limit(100).each { |p| p.user.name }
      end

      x.report("preload") do
        Post.preload(:user).limit(100).each { |p| p.user.name }
      end

      x.report("eager_load") do
        Post.eager_load(:user).limit(100).each { |p| p.user.name }
      end

      x.report("joins (N+1)") do
        Post.joins(:user).limit(100).each { |p| p.user.name }
      end

      x.report("no loading") do
        Post.limit(100).each { |p| p.user.name }
      end
    end
  end
end
```

Run benchmark:
```bash
bin/rails loading:benchmark
```

### Step 6: Memory Profiling (Optional)

```bash
bundle add memory_profiler
```

```ruby
require 'memory_profiler'

report = MemoryProfiler.report do
  Post.includes(user: :posts).limit(100).to_a
end

report.pretty_print
```

Compare memory usage between `includes(:user)` and `includes(user: :posts)`.

## Stretch (Optional)

1. Use `EXPLAIN ANALYZE` to compare query plans:
```ruby
Post.includes(:user).limit(100).explain
Post.eager_load(:user).limit(100).explain
```

2. Test performance with 10,000 posts and see when JOINs become slower than separate queries.

3. Create a scope that conditionally includes associations:
```ruby
scope :with_associations, ->(include_user: false, include_comments: false) {
  query = all
  query = query.includes(:user) if include_user
  query = query.includes(:comments) if include_comments
  query
}
```

## Time Estimate
20 minutes
