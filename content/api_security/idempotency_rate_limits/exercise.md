# Exercise: Idempotency Keys & Rate Limiting

## Objective

Implement idempotency key handling for POST requests and configure rack-attack to rate limit API endpoints, returning appropriate headers.

## Task

You're protecting a payment API from duplicate charges and abuse. Add idempotency key support to `PaymentsController#create`, caching results in Redis with 24-hour expiration. Install rack-attack and configure it to limit requests to 10 per minute per IP for `/api/payments`, returning 429 with `Retry-After` header when exceeded.

1. Add `redis` and `rack-attack` gems to Gemfile and run `bundle install`
2. Configure Redis connection in `config/initializers/redis.rb`
3. Implement idempotency logic in `PaymentsController#create`: check for `Idempotency-Key` header, cache result
4. Create `config/initializers/rack_attack.rb` with throttle for `/api/payments` (10 requests/minute per IP)
5. Customize `Rack::Attack.throttled_responder` to return JSON with `Retry-After` header
6. Test with curl, verifying cached responses and 429 after 10 requests

## Acceptance Criteria

- [ ] `POST /api/payments` requires `Idempotency-Key` header, returns 400 if missing
- [ ] Retrying with same key returns cached response without creating duplicate payment
- [ ] Cached responses expire after 24 hours
- [ ] Sending 11 requests in 1 minute returns 429 on the 11th request
- [ ] 429 response includes `Retry-After: 60` header and JSON error message
- [ ] `X-RateLimit-Limit` and `X-RateLimit-Remaining` headers included in responses

## Verification Steps

1. Start Redis: `redis-server`
2. Generate a UUID: `uuid=$(uuidgen)` and execute `curl -X POST -H "Idempotency-Key: $uuid" http://localhost:3000/api/payments -d '{"amount": 100}'`, verify 201 Created
3. Repeat step 2 with same UUID, verify identical response and no duplicate payment in database
4. Execute 11 requests rapidly with different keys: `for i in {1..11}; do curl -X POST -H "Idempotency-Key: $(uuidgen)" http://localhost:3000/api/payments -d '{"amount": 10}'; done` and verify 11th returns 429
5. Check 429 response headers: `curl -I -X POST http://localhost:3000/api/payments` (after limit hit) and verify `Retry-After: 60`
6. Wait 60 seconds and retry, verifying request succeeds
7. Check Redis keys: `redis-cli KEYS "idempotency:*"` and verify keys exist

## Stretch (Optional)

Implement per-user rate limiting (separate from IP-based) that allows authenticated users higher limits (100 requests/hour) compared to anonymous users (10 requests/minute).

## Time Estimate

23 minutes
