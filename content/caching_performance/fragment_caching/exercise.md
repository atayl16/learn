# Exercise: Fragment & Low-Level Caching

## Objective
Implement fragment caching in views and low-level caching in models, then measure cache hit rates and performance gains.

## Task
In a Rails app with posts and comments:

1. Add fragment caching to post list partial
2. Implement low-level caching for expensive calculation
3. Configure Redis cache store
4. Instrument cache hits/misses
5. Measure rendering time before and after caching
6. Test cache invalidation when records update

## Acceptance Criteria
- [ ] Fragment cache wraps post list rendering
- [ ] Cache keys auto-expire when post `updated_at` changes
- [ ] Low-level cache stores aggregated comment count
- [ ] Redis configured as cache store in development
- [ ] Logs show cache HIT/MISS for each read
- [ ] Benchmark shows >80% rendering time reduction on cache hit
- [ ] Updating a post invalidates its cache entry

## Verification Steps

1. First request (cache miss):

```
Cache MISS: views/posts/123-20250108120000/...
Post Load (15.2ms)
Rendered posts/_post.html.erb (25.3ms)
Completed 200 OK in 150ms

```

2. Second request (cache hit):

```
Cache HIT: views/posts/123-20250108120000/...
Completed 200 OK in 12ms

```

3. After updating post:

```
Cache MISS: views/posts/123-20250108130000/...
(New cache key due to updated_at change)

```

## Setup Code

### Step 1: Create Rails App

```bash
rails new caching_demo --skip-javascript
cd caching_demo
bin/rails generate scaffold Post title:string body:text
bin/rails generate model Comment body:text post:references
bin/rails db:migrate

```

**Add associations:**

`app/models/post.rb`:

```ruby
class Post < ApplicationRecord
  has_many :comments
end

```

`app/models/comment.rb`:

```ruby
class Comment < ApplicationRecord
  belongs_to :post
end

```

### Step 2: Configure Redis Cache Store

```bash
bundle add redis

```

Edit `config/environments/development.rb`:

```ruby
Rails.application.configure do
  # ... existing config

  config.cache_store = :redis_cache_store, {
    url: ENV.fetch("REDIS_URL", "redis://localhost:6379/1"),
    expires_in: 1.hour
  }
end

```

Start Redis (if not running):

```bash
# macOS: brew services start redis
# Linux: sudo systemctl start redis
# Or use Docker: docker run -p 6379:6379 redis

```

### Step 3: Seed Data

```bash
bin/rails console

```

```ruby
20.times do |i|
  post = Post.create(title: "Post #{i}", body: "Body content #{i}")
  rand(5..15).times do |j|
    Comment.create(body: "Comment #{j}", post: post)
  end
end

puts "Created #{Post.count} posts, #{Comment.count} comments"

```

### Step 4: Add Fragment Caching

Edit `app/views/posts/index.html.erb`:

```erb
<h1>Posts</h1>

<div id="posts">
  <% @posts.each do |post| %>
    <% cache post do %>
      <%= render post %>
    <% end %>
  <% end %>
</div>

<%= link_to "New post", new_post_path %>

```

Edit `app/views/posts/_post.html.erb`:

```erb
<div class="post">
  <h2><%= link_to post.title, post %></h2>
  <p><%= post.body %></p>
  <small>
    <%= post.comments.count %> comments
    | Created <%= time_ago_in_words(post.created_at) %> ago
  </small>
</div>

```

### Step 5: Add Low-Level Caching

Create `app/models/post_statistics.rb`:

```ruby
class PostStatistics
  def self.total_comments_today
    Rails.cache.fetch("stats/comments_today/#{Date.today}", expires_in: 15.minutes) do
      Comment.where(created_at: Date.today.all_day).count
    end
  end

  def self.average_comments_per_post
    Rails.cache.fetch("stats/avg_comments", expires_in: 1.hour) do
      (Comment.count.to_f / Post.count).round(2)
    end
  end
end

```

Add to `app/views/posts/index.html.erb`:

```erb
<div class="stats">
  <p>Comments today: <%= PostStatistics.total_comments_today %></p>
  <p>Avg comments/post: <%= PostStatistics.average_comments_per_post %></p>
</div>

```

### Step 6: Instrument Cache Hits/Misses

Create `config/initializers/cache_instrumentation.rb`:

```ruby
ActiveSupport::Notifications.subscribe("cache_read.active_support") do |*args|
  event = ActiveSupport::Notifications::Event.new(*args)
  hit = event.payload[:hit]
  key = event.payload[:key]

  Rails.logger.info "CACHE #{hit ? 'HIT' : 'MISS'}: #{key}"
end

```

Restart server to load initializer.

### Step 7: Benchmark Performance

Create `lib/tasks/benchmark_caching.rake`:

```ruby
require 'benchmark'

namespace :cache do
  desc "Benchmark fragment caching"
  task benchmark: :environment do
    post = Post.first

    # Clear cache
    Rails.cache.clear

    Benchmark.bm(20) do |x|
      x.report("First render (miss)") do
        ApplicationController.render(partial: "posts/post", locals: { post: post })
      end

      x.report("Second render (hit)") do
        ApplicationController.render(partial: "posts/post", locals: { post: post })
      end

      # Clear and test again
      Rails.cache.clear

      x.report("After cache clear") do
        ApplicationController.render(partial: "posts/post", locals: { post: post })
      end
    end
  end
end

```

Run benchmark:

```bash
bin/rails cache:benchmark

```

### Step 8: Test Cache Invalidation

```bash
bin/rails console

```

```ruby
# Check cache key
post = Post.first
puts post.cache_key_with_version
# => "posts/1-20250108120000000000000"

# Render partial to populate cache
ApplicationController.render(partial: "posts/post", locals: { post: post })

# Check if cached
Rails.cache.exist?(post.cache_key_with_version) # => true

# Update post (changes updated_at)
post.update(title: "Updated Title")

# Old cache key still exists but won't be used
puts post.cache_key_with_version
# => "posts/1-20250108130000000000000" (new timestamp)

# New render will miss cache with new key
ApplicationController.render(partial: "posts/post", locals: { post: post })

```

### Step 9: Manual Cache Operations

```ruby
# Write to cache
Rails.cache.write("my_key", "my_value", expires_in: 5.minutes)

# Read from cache
Rails.cache.read("my_key") # => "my_value"

# Fetch (read or write)
Rails.cache.fetch("expensive_calc", expires_in: 1.hour) do
  sleep 2 # Simulate slow calculation
  42
end

# Delete
Rails.cache.delete("my_key")

# Clear all
Rails.cache.clear

```

## Stretch (Optional)

1. Implement Russian-doll caching:

```erb
<% cache ["posts", @posts.maximum(:updated_at)] do %>
  <% @posts.each do |post| %>
    <% cache post do %>
      <%= render post %>
    <% end %>
  <% end %>
<% end %>

```

2. Add cache hit rate tracking to a dashboard:

```ruby
# Track in Redis
hits = Rails.cache.redis.get("cache_hits").to_i
misses = Rails.cache.redis.get("cache_misses").to_i
rate = (hits.to_f / (hits + misses) * 100).round(2)

```

3. Compare memory vs Redis cache stores by benchmarking 1000 reads.

## Time Estimate
22 minutes
