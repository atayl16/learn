# CSRF, CORS & Input Validation

## What It Is

CSRF (Cross-Site Request Forgery) tricks authenticated users into executing unwanted actions via malicious sites. Rails protects with token validation. CORS (Cross-Origin Resource Sharing) controls which domains can call your API via `Access-Control-Allow-Origin` headers. Input validation uses strong params and sanitization to block SQL injection and XSS.

## Why It Matters

CSRF lets attackers transfer funds or delete data if your API trusts cookies without verifying origin. Missing CORS headers block legitimate single-page apps from calling your API. Unvalidated inputs enable SQL injection (stealing data) or XSS (executing scripts in users' browsers).

## When to Use

- Exposing APIs to JavaScript frontends on different domains
- Building session-based APIs (not token-based) that need CSRF protection
- Accepting user-generated content that will be displayed to others
- Handling query params or JSON inputs in API endpoints
- Supporting third-party integrations with cross-origin requests

## Three Common Pitfalls

1. **Using CORS wildcard in production:** `Access-Control-Allow-Origin: *` lets any site call your API, bypassing authentication. Whitelist specific origins instead.
2. **Disabling CSRF protection for all API endpoints:** Token-based APIs don't need CSRF, but session-based ones do. Disable selectively, not globally.
3. **Trusting user input in SQL or HTML:** Raw params in `where("name = '#{params[:name]}'")` enables SQL injection. Use parameterized queries or ActiveRecord scopes.

---

## CORS Basics

CORS headers tell browsers which origins can access your API.

```ruby
# Gemfile
gem 'rack-cors'

# config/initializers/cors.rb
Rails.application.config.middleware.insert_before 0, Rack::Cors do
  allow do
    origins 'https://myapp.com', 'https://staging.myapp.com'
    resource '/api/*',
      headers: :any,
      methods: [:get, :post, :put, :patch, :delete, :options],
      credentials: true
  end
end
```

`origins` whitelists domains. `credentials: true` allows cookies. Never use `origins '*'` with `credentials: true`.

## Preflight Requests

Browsers send OPTIONS requests before POST/PUT/DELETE to check permissions.

```http
OPTIONS /api/users HTTP/1.1
Origin: https://myapp.com
Access-Control-Request-Method: POST
Access-Control-Request-Headers: Authorization
```

Rails responds with:

```http
HTTP/1.1 204 No Content
Access-Control-Allow-Origin: https://myapp.com
Access-Control-Allow-Methods: POST, GET, PUT, DELETE
Access-Control-Allow-Headers: Authorization, Content-Type
Access-Control-Max-Age: 86400
```

`Max-Age` caches preflight for 24 hours, reducing overhead.

## CSRF Protection

Rails includes CSRF tokens in forms and verifies them on POST/PUT/DELETE.

```ruby
# ApplicationController (default for session-based apps)
protect_from_forgery with: :exception

# For APIs using tokens, disable CSRF
class Api::BaseController < ActionController::API
  # No CSRF protection needed; token auth is stateless
end

# For session-based APIs
class SessionsController < ApplicationController
  protect_from_forgery with: :null_session  # Returns 422 on invalid token
end
```

Token-based APIs (JWT, bearer tokens) skip CSRF since attackers can't steal tokens from cookies.

## Strong Parameters

Whitelist allowed params to prevent mass assignment.

```ruby
# UsersController
def create
  @user = User.new(user_params)
  @user.save!
  render json: @user
end

private

def user_params
  params.require(:user).permit(:email, :password, :full_name)
end
```

Prevents attackers from passing `{admin: true}` to escalate privileges.

## Input Validation

Validate and sanitize all inputs. Use ActiveRecord validations and parameterized queries.

```ruby
# Model validations
class User < ApplicationRecord
  validates :email, format: { with: URI::MailTo::EMAIL_REGEXP }
  validates :full_name, length: { maximum: 100 }
end

# Parameterized queries (safe)
User.where("email = ?", params[:email])

# Dangerous (SQL injection)
User.where("email = '#{params[:email]}'")  # DON'T DO THIS
```

ActiveRecord escapes params automatically. Avoid raw SQL strings.

## Preventing XSS

Escape user content when rendering. Rails escapes ERB by default.

```erb
<!-- Safe: ERB escapes HTML -->
<p><%= @user.bio %></p>

<!-- Unsafe: Renders raw HTML -->
<p><%= raw @user.bio %></p>
<p><%== @user.bio %></p>
```

For JSON APIs, don't use `html_safe` on user input. Return plain text; let clients escape.

## Preventing SQL Injection

Always use parameterized queries or ActiveRecord methods.

```ruby
# Safe
Post.where(status: params[:status])
Post.where("status = ?", params[:status])

# Unsafe
Post.where("status = '#{params[:status]}'")
# Attack: params[:status] = "'; DROP TABLE posts--"
```

Use `Arel` or scopes for complex queries. Never interpolate user input.

## OWASP Top 10 Context

CSRF is A01 (Broken Access Control). Injection is A03. XSS is A07. Input validation addresses all three.

---

## Trade-offs Box

- **Advantage:** CORS enables cross-origin apps; CSRF prevents session hijacking; input validation blocks injection attacks.
- **Cost:** CORS preflight adds latency; strong params require explicit whitelisting; sanitization can break legitimate input.
- **When to skip:** CORS not needed for same-origin APIs; CSRF not needed for stateless token APIs; strict validation may block edge cases.

---

## Debugging Checklist

When CORS, CSRF, or validation issues arise, check:

1. Verify CORS headers in response: `curl -I -H "Origin: https://myapp.com" http://localhost:3000/api/users`
2. Check preflight response: `curl -X OPTIONS -H "Origin: https://myapp.com" http://localhost:3000/api/users`
3. Confirm CSRF token present: inspect `<meta name="csrf-token">` in HTML or `X-CSRF-Token` header
4. Test strong params: try sending disallowed fields and verify 422 or ignored
5. Inspect SQL logs for raw interpolation: look for `WHERE status = '...'` vs `WHERE status = $1`
6. Validate escaping: render `<script>alert('xss')</script>` and confirm it displays as text, not executes

---

## One-Minute Recap

- Configure CORS with whitelisted origins; never use `*` with credentials in production
- Disable CSRF for token-based APIs; enable for session-based ones
- Use strong params to whitelist allowed fields and prevent mass assignment
- Always use parameterized queries or ActiveRecord methods to prevent SQL injection
- Escape user content in views; Rails ERB escapes by default unless you use `raw` or `html_safe`
