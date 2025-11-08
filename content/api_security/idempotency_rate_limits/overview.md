# Idempotency Keys & Rate Limiting

## What It Is

Idempotency keys allow clients to retry requests safely by sending a unique `Idempotency-Key` header. The server caches the result for that key, returning the same response if the request is repeated. Rate limiting throttles clients to N requests per time window using algorithms like token bucket, returning 429 Too Many Requests when exceeded.

## Why It Matters

Network failures cause clients to retry POST requests, creating duplicate charges or records. Idempotency keys prevent this by deduplicating retries. Rate limiting defends against abuse, brute-force attacks, and runaway scripts that overwhelm servers. Together they ensure APIs are safe to retry and resilient under load.

## When to Use

- Protecting payment or order creation endpoints from duplicate submissions
- Handling mobile clients with flaky connections that auto-retry
- Preventing credential stuffing or brute-force login attempts
- Throttling public API endpoints to enforce usage tiers
- Defending against DDoS attacks or resource exhaustion

## Three Common Pitfalls

1. **Caching idempotency results indefinitely:** Storing every key forever fills Redis or the database. Expire keys after 24 hours; clients should retry with a new key if requests are older.
2. **Rate limiting authenticated users globally:** Blocking all users when one abuses the API punishes everyone. Use per-user or per-IP limits with separate buckets.
3. **Returning 429 without Retry-After header:** Clients don't know when to retry. Include `Retry-After: 60` to indicate when the limit resets.

---

## Idempotency-Key Header

Clients generate a unique key (UUID) and send it with POST/PATCH/DELETE requests.

```ruby
# Client sends:
# POST /api/orders
# Idempotency-Key: a1b2c3d4-e5f6-7890-abcd-ef1234567890

# OrdersController
def create
  idempotency_key = request.headers['Idempotency-Key']
  return render json: {error: 'Idempotency-Key required'}, status: :bad_request unless idempotency_key

  cached = Rails.cache.read("idempotency:#{idempotency_key}")
  return render json: cached[:body], status: cached[:status] if cached

  order = Order.create!(order_params)
  response = {data: order, status: :created}
  Rails.cache.write("idempotency:#{idempotency_key}", {body: {data: order}, status: 201}, expires_in: 24.hours)

  render json: response[:body], status: response[:status]
end
```

If the client retries with the same key, the cached response is returned without creating a duplicate order.

## Redis-Based Deduplication

Use Redis for fast lookups and automatic expiration.

```ruby
# config/initializers/redis.rb
REDIS = Redis.new(url: ENV['REDIS_URL'] || 'redis://localhost:6379/0')

# ApplicationController
def deduplicate(key)
  cache_key = "idempotency:#{key}"
  cached = REDIS.get(cache_key)

  if cached
    result = JSON.parse(cached, symbolize_names: true)
    render json: result[:body], status: result[:status]
  else
    yield.tap do |result|
      REDIS.setex(cache_key, 24.hours.to_i, {body: result[:body], status: result[:status]}.to_json)
    end
  end
end
```

Call `deduplicate(idempotency_key) { perform_operation }` to wrap the operation.

## Rate Limiting with Rack::Attack

Rack::Attack is middleware for throttling and blocking requests.

```ruby
# Gemfile
gem 'rack-attack'

# config/initializers/rack_attack.rb
Rack::Attack.cache.store = ActiveSupport::Cache::RedisCacheStore.new(url: ENV['REDIS_URL'])

Rack::Attack.throttle('api/ip', limit: 100, period: 1.minute) do |req|
  req.ip if req.path.start_with?('/api')
end

Rack::Attack.throttle('api/user', limit: 1000, period: 1.hour) do |req|
  req.env['current_user']&.id if req.path.start_with?('/api')
end

# Customize 429 response
Rack::Attack.throttled_responder = lambda do |env|
  retry_after = env['rack.attack.match_data'][:period]
  [
    429,
    {'Content-Type' => 'application/json', 'Retry-After' => retry_after.to_s},
    [{error: 'Too many requests', retry_after: retry_after}.to_json]
  ]
end
```

This limits each IP to 100 requests/minute and each user to 1000 requests/hour.

## Token Bucket Algorithm

Tokens refill at a constant rate. Each request consumes a token. When the bucket is empty, requests are blocked.

```ruby
# Custom token bucket implementation
class TokenBucket
  def initialize(capacity:, refill_rate:)
    @capacity = capacity
    @refill_rate = refill_rate  # tokens per second
  end

  def allow?(key)
    now = Time.now.to_f
    bucket_key = "bucket:#{key}"
    data = REDIS.hgetall(bucket_key)

    tokens = data['tokens']&.to_f || @capacity
    last_refill = data['last_refill']&.to_f || now

    # Refill tokens based on elapsed time
    elapsed = now - last_refill
    tokens = [@capacity, tokens + (elapsed * @refill_rate)].min

    if tokens >= 1
      tokens -= 1
      REDIS.hset(bucket_key, 'tokens', tokens, 'last_refill', now)
      REDIS.expire(bucket_key, 3600)
      true
    else
      false
    end
  end
end
```

More flexible than fixed windows but requires custom code.

## Retry-After and Rate Limit Headers

Return headers so clients know their status.

```ruby
# ApplicationController
after_action :set_rate_limit_headers

def set_rate_limit_headers
  response.set_header('X-RateLimit-Limit', '1000')
  response.set_header('X-RateLimit-Remaining', rate_limit_remaining)
  response.set_header('X-RateLimit-Reset', rate_limit_reset_time.to_i)
end

def rate_limit_remaining
  # Fetch from Redis based on current_user or IP
  1000 - (REDIS.get("rate:#{current_user.id}") || 0).to_i
end

def rate_limit_reset_time
  Time.now.beginning_of_hour + 1.hour
end
```

Clients read these to know when they can retry.

---

## Trade-offs Box

- **Advantage:** Idempotency prevents duplicates; rate limiting protects against abuse and load spikes.
- **Cost:** Requires Redis for caching and coordination; adds latency for cache lookups.
- **When to skip:** For internal admin endpoints with trusted users or read-only GET endpoints (already idempotent).

---

## Debugging Checklist

When idempotency or rate limiting misbehaves, check:

1. Verify `Idempotency-Key` header is sent: inspect request headers in logs
2. Confirm Redis is running and accessible: `redis-cli ping`
3. Check cache expiration: `TTL idempotency:key` in redis-cli
4. Test rate limit thresholds: send rapid requests with curl in a loop
5. Inspect Rack::Attack logs for throttles: `grep 'Rack::Attack' log/production.log`
6. Validate `Retry-After` header is returned: `curl -I` after hitting limit

---

## One-Minute Recap

- Idempotency keys let clients safely retry POST/PATCH/DELETE by caching results in Redis
- Expire cached idempotency keys after 24 hours to prevent unbounded growth
- Use rack-attack for rate limiting with per-IP and per-user throttles
- Return 429 Too Many Requests with `Retry-After` header when limits are exceeded
- Include `X-RateLimit-*` headers so clients know their quota and reset time
