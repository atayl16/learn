# Fragment & Low-Level Caching

## What It Is
Fragment caching stores rendered view partials in a cache store (memory, Redis, Memcached), skipping database queries and template rendering on subsequent requests. Low-level caching uses `Rails.cache.fetch` to cache arbitrary data like API responses or expensive calculations. Both reduce CPU and database load by serving precomputed results.

## Why It Matters
Fragment caching can reduce view rendering time from 500ms to 5ms when hitting cached keys. A cached product listing avoids querying thousands of records and rendering complex ERB templates. Low-level caching prevents redundant API calls or calculations that run on every request. Production apps routinely achieve 70-90% cache hit rates, cutting server costs by half.

## When to Use
- Fragment caching: expensive partials, product listings, user dashboards, navigation menus
- Low-level caching: external API calls, complex calculations, aggregated statistics
- Skip caching: user-specific content that varies per request, data that changes every second
- Cache stores: memory for single-server dev, Redis/Memcached for production multi-server
- Measure first: only cache if profiling shows rendering/computation is slow

## Three Common Pitfalls
1. **Stale cache keys:** Cached fragment doesn't invalidate when underlying data changes. Use `cache_key_with_version` or `touch: true` to auto-expire.
2. **Over-caching user-specific content:** Caching `current_user.name` across requests serves wrong user's data. Scope cache keys by user ID.
3. **Memory exhaustion:** Caching too much in memory store causes OOM. Set `max_size` or use Redis with eviction policies.

---

## Fragment Caching in Views

Wrap expensive partials with `cache` block:

```erb
<!-- app/views/posts/index.html.erb -->
<% @posts.each do |post| %>
  <% cache post do %>
    <div class="post">
      <h2><%= post.title %></h2>
      <p><%= post.body %></p>
      <small>By <%= post.author.name %> at <%= post.created_at %></small>
    </div>
  <% end %>
<% end %>
```

**Generated cache key:**
```
views/posts/123-20250108120000/a3f2b1c4d5e6f7
```

Cache expires automatically when `post.updated_at` changes (Rails uses `cache_key_with_version`).

---

## Low-Level Caching

Cache arbitrary data with `Rails.cache.fetch`:

```ruby
# app/models/statistics.rb
class Statistics
  def self.daily_revenue
    Rails.cache.fetch("stats/daily_revenue/#{Date.today}", expires_in: 1.hour) do
      # Expensive calculation
      Order.where(created_at: Date.today.all_day).sum(:total)
    end
  end
end
```

**First call:** Runs query, stores result in cache.
**Subsequent calls:** Returns cached value without hitting database.

---

## Cache Stores

Rails supports multiple backends:

**Memory store (development):**
```ruby
# config/environments/development.rb
config.cache_store = :memory_store, { size: 64.megabytes }
```

**Redis (production):**
```ruby
# Gemfile
gem 'redis'

# config/environments/production.rb
config.cache_store = :redis_cache_store, { url: ENV['REDIS_URL'], expires_in: 1.day }
```

**Memcached:**
```ruby
gem 'dalli'
config.cache_store = :mem_cache_store, "cache1.example.com", "cache2.example.com"
```

**Comparison:**
- Memory: fast but single-server, lost on restart
- Redis: persists, multi-server, supports complex eviction
- Memcached: simple, high throughput, no persistence

---

## Cache Key Design

Good cache keys are specific and auto-expiring:

```ruby
# BAD: never expires
Rails.cache.fetch("user_posts") { @user.posts.to_a }

# GOOD: expires when user or posts change
Rails.cache.fetch(["user_posts", @user, @user.posts.maximum(:updated_at)]) do
  @user.posts.to_a
end

# BETTER: use cache_key helper
Rails.cache.fetch([@user, "posts", @user.posts.maximum(:updated_at)]) do
  @user.posts.to_a
end
```

**Array keys:** Rails joins with `/` to create string key.

---

## Expiration Strategies

**Time-based:**
```ruby
Rails.cache.fetch("trending_posts", expires_in: 15.minutes) do
  Post.order(views: :desc).limit(10)
end
```

**Version-based (auto-expire on model change):**
```erb
<% cache ["sidebar", @user] do %>
  <%= render "shared/sidebar" %>
<% end %>
```

If `@user.updated_at` changes, cache key changes → cache miss → re-render.

**Manual deletion:**
```ruby
Rails.cache.delete("user_posts/#{@user.id}")
Rails.cache.delete_matched("user_posts/*") # Delete all matching
```

---

## Measuring Cache Performance

Track hit/miss rates:

```ruby
# config/initializers/cache_instrumentation.rb
ActiveSupport::Notifications.subscribe("cache_read.active_support") do |*args|
  event = ActiveSupport::Notifications::Event.new(*args)
  hit = event.payload[:hit]
  Rails.logger.info "Cache #{hit ? 'HIT' : 'MISS'}: #{event.payload[:key]}"
end
```

**Rack Mini Profiler** shows cache hits in speed badge.

**Production monitoring:** Track hit rate via Datadog/New Relic.

---

## Fragment Caching Best Practices

**Cache the expensive part:**
```erb
<!-- DON'T cache entire page with user-specific header -->
<% cache do %>
  <%= render "header" %> <!-- user-specific! -->
  <%= render "posts" %>
<% end %>

<!-- DO cache just the posts -->
<%= render "header" %>
<% cache "posts_list" do %>
  <%= render "posts" %>
<% end %>
```

**Scope by user when needed:**
```erb
<% cache [current_user, "dashboard"] do %>
  Welcome <%= current_user.name %>
<% end %>
```

**Nest caches (Russian-doll pattern):**
```erb
<% cache ["posts", @posts.maximum(:updated_at)] do %>
  <% @posts.each do |post| %>
    <% cache post do %>
      <%= render post %>
    <% end %>
  <% end %>
<% end %>
```

Outer cache expires when any post changes. Inner caches allow partial reuse.

---

## When NOT to Cache

Skip caching for:
- **Real-time data:** stock prices, live scores (data changes constantly)
- **User-specific without scoping:** `current_user` content cached globally
- **Small, fast queries:** `User.find(1)` is faster than cache lookup
- **First-time traffic:** cache warm-up can slow initial requests

Profile first. If rendering takes <10ms, caching overhead may exceed savings.

---

## Trade-offs Box
- **Advantage:** Fragment caching reduces rendering time by 40-80% for expensive views; low-level caching eliminates redundant API calls.
- **Cost:** Stale cache bugs serve outdated data; cache storage uses memory/Redis; complexity in key design and invalidation.
- **When to skip:** Fast queries (<10ms), real-time data, single-user content without scoping, or when cache overhead exceeds rendering cost.

---

## Debugging Checklist

When caching doesn't work as expected:

1. Check cache store is configured: `Rails.cache.class` in console
2. Verify cache keys: log `Rails.cache.fetch(key) { ... }` to see actual keys
3. Clear cache: `Rails.cache.clear` to test fresh rendering
4. Check expiration: `Rails.cache.read(key)` to inspect stored value
5. Monitor hit/miss: subscribe to `cache_read.active_support` notifications
6. Profile memory: ensure cache store isn't causing OOM (check `max_size`)
7. Test invalidation: change record and verify cache key changes
8. Check Redis connection: `Rails.cache.redis.ping` for Redis store

---

## One-Minute Recap
- Fragment caching stores rendered partials; low-level caching stores arbitrary data
- Use `cache` block in views, `Rails.cache.fetch` in models/controllers
- Cache stores: memory (dev), Redis (production multi-server), Memcached (simple)
- Design cache keys to auto-expire on data changes (use `cache_key_with_version`)
- Measure hit rates to validate caching improves performance
