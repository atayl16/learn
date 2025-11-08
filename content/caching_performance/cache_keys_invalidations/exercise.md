# Exercise: Cache Keys & Invalidation Strategies

## Objective
Implement automatic cache invalidation using `touch: true`, Russian-doll caching, and cache stampede prevention.

## Task
In a Rails app with posts and comments:

1. Set up `touch: true` to invalidate post cache when comments change
2. Implement Russian-doll caching for posts with nested comments
3. Test that cache keys change when child records update
4. Add `race_condition_ttl` to prevent cache stampede
5. Create manual invalidation for batch operations
6. Measure cache hit rate before/after optimization

## Acceptance Criteria
- [ ] `Comment` model has `belongs_to :post, touch: true`
- [ ] Creating/updating a comment changes post's `cache_key_with_version`
- [ ] Russian-doll caching nests post and comment fragments
- [ ] Logs show inner caches reused when only one comment changes
- [ ] Low-level cache uses `race_condition_ttl: 5.seconds`
- [ ] Manual invalidation clears cache on batch update
- [ ] Cache hit rate improves with Russian-doll pattern

## Verification Steps

1. Check cache key changes on child update:
```ruby
post = Post.first
old_key = post.cache_key_with_version
Comment.create(post: post, body: "New comment")
post.reload.cache_key_with_version # Should differ from old_key
```

2. Verify Russian-doll caching in logs:
```
# First render: all misses
Cache MISS: posts/all-20250108120000
Cache MISS: posts/1-20250108120000
Cache MISS: comments/1-20250108120000
Cache MISS: comments/2-20250108120000

# Update comment 1
# Second render: outer + post 1 miss, comment 2 hit
Cache MISS: posts/all-20250108120100
Cache MISS: posts/1-20250108120100
Cache MISS: comments/1-20250108120100
Cache HIT: comments/2-20250108120000
```

3. Test race_condition_ttl prevents stampede (simulate concurrent requests)

## Setup Code

### Step 1: Create Models

```bash
rails new cache_invalidation_demo --skip-javascript
cd cache_invalidation_demo
bin/rails generate scaffold Post title:string body:text
bin/rails generate model Comment body:text post:references
bin/rails db:migrate
```

**Add associations:**

`app/models/post.rb`:
```ruby
class Post < ApplicationRecord
  has_many :comments, dependent: :destroy
end
```

`app/models/comment.rb`:
```ruby
class Comment < ApplicationRecord
  belongs_to :post, touch: true  # ← Auto-invalidate post cache
end
```

### Step 2: Configure Cache Store

```bash
bundle add redis
```

Edit `config/environments/development.rb`:
```ruby
Rails.application.configure do
  config.cache_store = :redis_cache_store, { url: "redis://localhost:6379/1" }
end
```

### Step 3: Enable Cache Instrumentation

Create `config/initializers/cache_instrumentation.rb`:
```ruby
ActiveSupport::Notifications.subscribe("cache_read.active_support") do |*args|
  event = ActiveSupport::Notifications::Event.new(*args)
  hit = event.payload[:hit]
  key = event.payload[:key]

  # Shorten key for readability
  short_key = key.to_s.split("/").last(2).join("/")
  Rails.logger.info "CACHE #{hit ? 'HIT' : 'MISS'}: #{short_key}"
end
```

### Step 4: Seed Data

```bash
bin/rails console
```

```ruby
10.times do |i|
  post = Post.create(title: "Post #{i}", body: "Content #{i}")
  5.times do |j|
    Comment.create(body: "Comment #{j} on post #{i}", post: post)
  end
end

puts "Created #{Post.count} posts, #{Comment.count} comments"
```

### Step 5: Implement Russian-Doll Caching

Edit `app/views/posts/index.html.erb`:
```erb
<h1>Posts</h1>

<!-- Outer cache: all posts -->
<% cache ["posts", "all", @posts.maximum(:updated_at)] do %>
  <div id="posts">
    <% @posts.each do |post| %>
      <!-- Middle cache: individual post -->
      <% cache post do %>
        <div class="post">
          <h2><%= link_to post.title, post %></h2>
          <p><%= post.body %></p>

          <div class="comments">
            <h3>Comments:</h3>
            <!-- Inner cache: each comment -->
            <% post.comments.each do |comment| %>
              <% cache comment do %>
                <p class="comment"><%= comment.body %></p>
              <% end %>
            <% end %>
          </div>
        </div>
      <% end %>
    <% end %>
  </div>
<% end %>

<%= link_to "New post", new_post_path %>
```

Edit `app/controllers/posts_controller.rb`:
```ruby
class PostsController < ApplicationController
  def index
    @posts = Post.includes(:comments).all
  end

  # ... rest of controller
end
```

### Step 6: Test Cache Invalidation

```bash
bin/rails console
```

```ruby
# Test touch: true
post = Post.first
puts "Before: #{post.cache_key_with_version}"

Comment.create(post: post, body: "This should touch the post")

post.reload
puts "After: #{post.cache_key_with_version}"
# Keys should differ

# Test manual cache inspection
Rails.cache.clear
ApplicationController.render(partial: "posts/post", locals: { post: post })
Rails.cache.exist?(post.cache_key_with_version) # => true
```

### Step 7: Add Cache Stampede Prevention

Create `app/models/statistics.rb`:
```ruby
class Statistics
  def self.total_comments
    # Without prevention: cache stampede on expiration
    Rails.cache.fetch("stats/total_comments", expires_in: 1.hour) do
      sleep 2 # Simulate expensive query
      Comment.count
    end
  end

  def self.total_comments_safe
    # With race_condition_ttl: serves stale data during regeneration
    Rails.cache.fetch(
      "stats/total_comments_safe",
      expires_in: 1.hour,
      race_condition_ttl: 10.seconds
    ) do
      sleep 2 # Simulate expensive query
      Comment.count
    end
  end
end
```

Test stampede scenario:
```ruby
# Clear cache
Rails.cache.delete("stats/total_comments")

# Simulate 10 concurrent requests (all will regenerate)
threads = 10.times.map do
  Thread.new { Statistics.total_comments }
end
threads.each(&:join)
# Logs show all 10 threads ran the slow query

# With race_condition_ttl
Rails.cache.delete("stats/total_comments_safe")
threads = 10.times.map do
  Thread.new { Statistics.total_comments_safe }
end
threads.each(&:join)
# Only 1-2 threads regenerate, others use stale data
```

### Step 8: Manual Invalidation

Add method to clear post caches:

`app/models/post.rb`:
```ruby
class Post < ApplicationRecord
  has_many :comments, dependent: :destroy

  def self.clear_all_caches
    # Manual invalidation for batch operations
    Rails.cache.delete_matched("posts/*")
    Rails.logger.info "Cleared all post caches"
  end

  after_commit :clear_stats_cache, on: [:create, :destroy]

  private

  def clear_stats_cache
    Rails.cache.delete("stats/total_posts")
  end
end
```

Test:
```ruby
Post.clear_all_caches
```

### Step 9: Benchmark Cache Efficiency

Create `lib/tasks/cache_stats.rake`:
```ruby
namespace :cache do
  desc "Test Russian-doll cache efficiency"
  task test_efficiency: :environment do
    Rails.cache.clear
    posts = Post.includes(:comments).limit(5)

    # First render: all misses
    puts "\n=== First Render (All Misses) ==="
    ApplicationController.render(partial: "posts/post", collection: posts)

    # Second render: all hits
    puts "\n=== Second Render (All Hits) ==="
    ApplicationController.render(partial: "posts/post", collection: posts)

    # Update one comment
    posts.first.comments.first.update(body: "Updated comment")

    # Third render: outer + one post + one comment miss, rest hit
    puts "\n=== After Updating One Comment ==="
    ApplicationController.render(partial: "posts/post", collection: posts)
  end
end
```

Run:
```bash
bin/rails cache:test_efficiency
```

### Step 10: Cache Hit Rate Tracking

Add to application controller:

`app/controllers/application_controller.rb`:
```ruby
class ApplicationController < ActionController::Base
  around_action :track_cache_stats

  private

  def track_cache_stats
    @cache_hits = 0
    @cache_misses = 0

    subscriber = ActiveSupport::Notifications.subscribe("cache_read.active_support") do |*args|
      event = ActiveSupport::Notifications::Event.new(*args)
      if event.payload[:hit]
        @cache_hits += 1
      else
        @cache_misses += 1
      end
    end

    yield

    total = @cache_hits + @cache_misses
    rate = total > 0 ? (@cache_hits.to_f / total * 100).round(2) : 0
    logger.info "Cache Stats: #{@cache_hits} hits, #{@cache_misses} misses (#{rate}% hit rate)"
  ensure
    ActiveSupport::Notifications.unsubscribe(subscriber) if subscriber
  end
end
```

## Stretch (Optional)

1. Implement cache versioning:
```ruby
# Invalidate all product caches by bumping version
Rails.cache.fetch("products/v2") { Product.all.to_a }
```

2. Add distributed lock with Redlock:
```bash
bundle add redlock
```

```ruby
lock_manager = Redlock::Client.new([ENV['REDIS_URL']])
lock_manager.lock("expensive_calc", 5000) do
  # Only one process enters this block
  Rails.cache.fetch("expensive_data") { expensive_calculation }
end
```

3. Test cache invalidation cascade with 3 levels (posts → comments → likes).

## Time Estimate
25 minutes
