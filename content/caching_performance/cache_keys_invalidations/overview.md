# Cache Keys & Invalidation Strategies

## What It Is
Cache keys uniquely identify cached data. Rails generates keys from model IDs and `updated_at` timestamps, so changes auto-expire stale cache entries. Invalidation strategies control when to purge or refresh cached data: automatic (using `touch: true` on associations), manual (calling `Rails.cache.delete`), or time-based (expires_in). Russian-doll caching nests cache fragments to reuse unchanged portions.

## Why It Matters
Stale cache bugs serve outdated data to users, causing incorrect prices, missing content, or security issues. Poor cache key design means editing a comment doesn't invalidate the cached blog post. Cache stampedes occur when thousands of requests simultaneously regenerate expired cache, overloading the database. Correct invalidation and stampede prevention keep caches fresh without degrading performance.

## When to Use
- Automatic invalidation: associated records via `touch: true`
- Manual invalidation: complex business logic (multi-model updates, batch imports)
- Time-based expiration: statistics, external API data, approximate counts
- Russian-doll caching: nested partials (posts containing comments)
- Cache stampede prevention: high-traffic endpoints with slow cache regeneration

## Three Common Pitfalls
1. **Forgetting touch: true on associations:** Editing a comment doesn't update post's `updated_at`, so cached post shows old comment. Add `belongs_to :post, touch: true`.
2. **Using static cache keys:** `Rails.cache.fetch("posts")` never expires when posts change. Include version/timestamp in key.
3. **Cache stampede on expiration:** 1000 concurrent requests hit expired cache, all regenerate simultaneously. Use `race_condition_ttl` or distributed locks.

---

## Cache Key Basics

Rails generates cache keys from model's `cache_key_with_version`:

```ruby
post = Post.find(1)
post.cache_key_with_version
# => "posts/1-20250108123045678901234"
#     model / id - updated_at (microseconds)
```

When `updated_at` changes, the cache key changes → cache miss → fresh render.

**In views:**
```erb
<% cache post do %>
  <%= render post %>
<% end %>
```

Automatically uses `post.cache_key_with_version`.

---

## Automatic Invalidation with touch: true

Update parent record when child changes:

```ruby
# app/models/comment.rb
class Comment < ApplicationRecord
  belongs_to :post, touch: true
end
```

**Behavior:**
```ruby
post = Post.find(1)
old_key = post.cache_key_with_version
# => "posts/1-20250108120000000000000"

# Create a comment
Comment.create(post: post, body: "Nice post")

# Post's updated_at is touched
post.reload.cache_key_with_version
# => "posts/1-20250108120100000000000" (new timestamp)
```

Cached post fragment now has a new key → cache miss → re-render with new comment.

---

## Russian-Doll Caching

Nest caches to reuse unchanged fragments:

```erb
<!-- Outer cache: expires when ANY post changes -->
<% cache ["posts", @posts.maximum(:updated_at)] do %>
  <% @posts.each do |post| %>
    <!-- Inner cache: expires when THIS post changes -->
    <% cache post do %>
      <%= render post %>

      <!-- Nested: each comment cached separately -->
      <% post.comments.each do |comment| %>
        <% cache comment do %>
          <%= render comment %>
        <% end %>
      <% end %>
    <% end %>
  <% end %>
<% end %>
```

**Scenario: User edits comment ID 42 on post ID 5:**
1. Comment 42's cache expires (updated_at changed)
2. Post 5's cache expires (touched by comment)
3. Outer "posts" cache expires (Post 5's updated_at changed)
4. On re-render:
   - Outer cache misses → renders all posts
   - Post 5 cache misses → renders post with comments
   - Comment 42 cache misses → renders comment
   - Other posts/comments still cached → reused

Minimizes re-rendering to only changed portions.

---

## Manual Invalidation

Delete cache explicitly when auto-invalidation isn't suitable:

```ruby
# Single key
Rails.cache.delete("trending_posts")

# Multiple keys
Rails.cache.delete_matched("user_#{user_id}/*")

# In callbacks
class Product < ApplicationRecord
  after_commit :clear_category_cache

  private

  def clear_category_cache
    Rails.cache.delete("category/#{category_id}/products")
  end
end
```

Use `after_commit` not `after_save` to ensure transaction completes before cache clears.

---

## Cache Key Versioning Strategies

**Include version in key:**
```ruby
# Bump version to invalidate all instances
Rails.cache.fetch("posts/v2") { Post.all.to_a }
```

**Include max timestamp:**
```ruby
Rails.cache.fetch(["posts", Post.maximum(:updated_at)]) do
  Post.all.to_a
end
```

**Include dependent data:**
```ruby
# Cache expires when user OR their posts change
Rails.cache.fetch([@user, @user.posts.maximum(:updated_at)]) do
  render_user_dashboard(@user)
end
```

---

## Cache Stampede Prevention

When cache expires, multiple requests simultaneously regenerate it, overloading the database.

**Problem:**
```ruby
# 1000 concurrent requests hit this
Rails.cache.fetch("expensive_data", expires_in: 1.hour) do
  # All 1000 threads execute this slow query
  ExpensiveCalculation.run
end
```

**Solution 1: race_condition_ttl**
```ruby
Rails.cache.fetch("expensive_data", expires_in: 1.hour, race_condition_ttl: 10.seconds) do
  ExpensiveCalculation.run
end
```

When cache expires, Rails serves stale data for 10 seconds while ONE thread regenerates. Other threads get stale data instead of all regenerating.

**Solution 2: Distributed lock (Redlock)**
```ruby
gem 'redlock'

lock_manager = Redlock::Client.new([ENV['REDIS_URL']])

lock_manager.lock("expensive_data_lock", 10_000) do |locked|
  if locked
    Rails.cache.fetch("expensive_data", expires_in: 1.hour) do
      ExpensiveCalculation.run
    end
  else
    # Another process is regenerating, return stale or wait
    Rails.cache.read("expensive_data")
  end
end
```

---

## Time-Based vs Event-Based Invalidation

**Time-based (expires_in):**
```ruby
# Good for: approximate data, external APIs, statistics
Rails.cache.fetch("stats/daily_revenue", expires_in: 15.minutes) do
  calculate_revenue
end
```

**Event-based (cache_key_with_version):**
```erb
<!-- Good for: user-facing content that must be fresh -->
<% cache post do %>
  <%= render post %>
<% end %>
```

Combine both:
```ruby
Rails.cache.fetch([post, "sidebar"], expires_in: 1.hour) do
  render_sidebar(post)
end
```

Cache expires after 1 hour OR when post changes (whichever comes first).

---

## Conditional Cache Keys

Scope by user, locale, or features:

```erb
<% cache [post, current_user.admin?, I18n.locale] do %>
  <%= render post %>
<% end %>
```

**Key changes when:**
- Post updates
- User's admin status changes
- Locale switches (I18n.locale)

Each combination gets a separate cache entry.

---

## Trade-offs Box
- **Advantage:** Proper cache key design auto-invalidates on changes, preventing stale data bugs; Russian-doll caching maximizes reuse.
- **Cost:** Aggressive touching cascades updates across models, causing unnecessary cache misses; complex key logic is hard to debug.
- **When to skip:** Simple apps with few caches, data that changes every request, or when manual invalidation is clearer than automatic.

---

## Debugging Checklist

When caches serve stale data or miss too often:

1. Log cache keys: `Rails.logger.debug "Cache key: #{post.cache_key_with_version}"`
2. Verify `touch: true` on associations: `Comment.reflect_on_all_associations(:belongs_to)`
3. Check `updated_at` changes: `post.reload.updated_at` after child update
4. Inspect cache contents: `Rails.cache.read(key)` to see stored value
5. Test cache expiration: update record, verify cache key changes
6. Monitor stampede: check logs for simultaneous slow queries
7. Validate race_condition_ttl: ensure stale data acceptable for brief window
8. Profile cache hit rate: low rate suggests over-invalidation

---

## One-Minute Recap
- Cache keys include `updated_at` timestamps for auto-invalidation
- Use `touch: true` on associations to invalidate parent caches when children change
- Russian-doll caching nests fragments to minimize re-rendering
- Prevent cache stampede with `race_condition_ttl` or distributed locks
- Combine time-based (`expires_in`) and event-based invalidation for optimal freshness
