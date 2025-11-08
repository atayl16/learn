# Exercise: CSRF, CORS & Input Validation

## Objective

Configure CORS for a cross-origin frontend, implement strong params for input validation, and verify protection against SQL injection and XSS attacks.

## Task

You're securing an API called by a React SPA on `https://frontend.example.com`. Configure rack-cors to whitelist this origin, set up strong params in `PostsController` to allow only `title` and `body`, and test that SQL injection via query params is blocked. Verify CORS headers and preflight responses.

1. Add `rack-cors` gem and configure `config/initializers/cors.rb` to allow `https://frontend.example.com`
2. Set CORS to allow GET, POST, PUT, DELETE with credentials enabled
3. Implement strong params in `PostsController` whitelisting `title` and `body` only
4. Add a search endpoint using parameterized queries: `Post.where("title LIKE ?", "%#{params[:q]}%")`
5. Test CORS preflight with curl, verifying `Access-Control-Allow-Origin` header
6. Attempt SQL injection via search param and confirm it's escaped

## Acceptance Criteria

- [ ] CORS headers allow `https://frontend.example.com` only, not wildcard
- [ ] Preflight OPTIONS request returns 204 with `Access-Control-Allow-Methods` header
- [ ] `POST /api/posts` accepts `{title, body}` but ignores `{admin: true}` or other disallowed fields
- [ ] Search endpoint `GET /api/posts/search?q=test` uses parameterized query
- [ ] SQL injection attempt like `?q='; DROP TABLE posts--` is escaped and safe
- [ ] CORS credentials enabled: `Access-Control-Allow-Credentials: true`

## Verification Steps

1. Execute `curl -X OPTIONS -H "Origin: https://frontend.example.com" http://localhost:3000/api/posts` and verify response includes `Access-Control-Allow-Origin: https://frontend.example.com`
2. Check `Access-Control-Allow-Methods` includes POST, PUT, DELETE
3. Execute `curl -X POST -H "Origin: https://frontend.example.com" http://localhost:3000/api/posts -d '{"title": "Test", "body": "Content", "admin": true}'` and verify `admin` is ignored
4. Check `log/development.log` for SQL query confirming `admin` was not in INSERT
5. Execute `curl "http://localhost:3000/api/posts/search?q='; DROP TABLE posts--"` and verify error or escaped query in logs (no table drop)
6. Inspect SQL log for parameterized query: `WHERE title LIKE $1` not `WHERE title LIKE '...'`
7. Execute `curl -H "Origin: https://evil.com" http://localhost:3000/api/posts` and verify CORS blocks it (no `Access-Control-Allow-Origin` header)

## Stretch (Optional)

Add rate limiting to the search endpoint to prevent query-based DDoS, and implement content sanitization for the `body` field to strip HTML tags before saving.

## Time Estimate

24 minutes
