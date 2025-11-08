# Request Lifecycle & Middleware

## What It Is
The Rails request lifecycle describes how an HTTP request flows from the web server through Rack middleware, routing, controller filters, action execution, and view rendering before returning a response. Middleware are Rack components that wrap the application, processing requests/responses in layers.

## Why It Matters
Understanding the request flow helps you debug slow endpoints, add custom middleware for cross-cutting concerns (logging, auth, rate limiting), and profile where time is spent. Production issues like missing CSRF tokens, wrong content types, or slow responses often trace back to middleware configuration or filter chains.

## When to Use
- Debugging: request never reaches controller, params missing, session not persisting
- Performance: identify which middleware/filters add latency
- Custom logic: add authentication, request tracking, or API versioning at the middleware level
- Profiling: pinpoint bottlenecks using Rack Mini Profiler or APM tools

## Three Common Pitfalls
1. **Middleware order matters:** CSRF protection must run after session middleware. Wrong order causes "invalid authenticity token" errors.
2. **Before filters block action execution:** A `before_action` that doesn't return/render halts the filter chain. Forgetting to `redirect_to` or `render` leaves requests hanging.
3. **Params parsing happens in middleware:** Malformed JSON/XML triggers exceptions in `ActionDispatch::Request` before your controller runs. Add error handling in middleware, not just controllers.

---

## The Rack Interface

Rails sits on top of Rack, a minimal Ruby web server interface. Every Rack app is a Ruby object responding to `call(env)`:

```ruby
class SimpleApp
  def call(env)
    # env: hash with HTTP_*, rack.*, PATH_INFO, etc.
    [200, {"Content-Type" => "text/plain"}, ["Hello World"]]
  end
end
```

Rails wraps this in layers of middleware before your controller code runs.

---

## Middleware Stack

View your app's middleware:

```bash
bin/rails middleware
```

Output (simplified):
```
use Rack::Sendfile
use ActionDispatch::Static
use Rack::Lock
use ActionDispatch::RequestId
use Rack::Runtime
use Rack::MethodOverride
use ActionDispatch::RemoteIp
use ActionDispatch::ShowExceptions
use ActionDispatch::DebugExceptions
use ActionDispatch::Callbacks
use ActionDispatch::Cookies
use ActionDispatch::Session::CookieStore
use ActionDispatch::Flash
use ActionDispatch::ContentSecurityPolicy
use Rack::Head
use Rack::ConditionalGet
use Rack::ETag
use ActionDispatch::ParamsParser  # ← Parses JSON/XML into params
run MyApp::Application.routes
```

**Key middleware roles:**
- `ActionDispatch::Static`: serves assets from `public/`
- `ActionDispatch::RequestId`: assigns `X-Request-Id` for tracing
- `Rack::MethodOverride`: converts `_method=PATCH` to PATCH verb
- `ActionDispatch::Cookies` / `Session::CookieStore`: manage cookies/session
- `ActionDispatch::Flash`: temporary session messages
- `ActionDispatch::ParamsParser`: deserializes JSON/XML request bodies

---

## Request Flow (Full Trace)

1. **Web server (Puma/Unicorn)** receives HTTP request
2. **Rack middleware stack** processes in order (top to bottom)
3. **Router** matches route, extracts params (`id`, `format`)
4. **Controller instantiation** creates controller instance
5. **Before filters** run in order (authentication, authorization)
6. **Action method** executes (`def show ... end`)
7. **After filters** run (logging, cleanup)
8. **View rendering** (ERB/Jbuilder) or JSON serialization
9. **Response middleware** (ETag, compression) processes in reverse order
10. **HTTP response** sent back to client

---

## Before/After/Around Filters

Filters run around your action:

```ruby
class UsersController < ApplicationController
  before_action :authenticate_user!
  before_action :set_user, only: [:show, :edit, :update]
  after_action :log_user_view, only: :show

  def show
    # @user set by before_action
  end

  private

  def set_user
    @user = User.find(params[:id])
  end

  def log_user_view
    Rails.logger.info "User #{@user.id} viewed by #{current_user.id}"
  end
end
```

**Filter chain halting:**
If a `before_action` calls `redirect_to` or `render`, the chain stops. Subsequent filters and the action don't run.

---

## Profiling the Lifecycle

Use Rack Mini Profiler to see timing breakdown:

```ruby
# Gemfile
gem 'rack-mini-profiler'

# config/environments/development.rb
config.middleware.use Rack::MiniProfiler
```

Visit any page; a speed badge appears in the top-left corner. Click it to see:
- **Middleware time:** which middleware layers add latency
- **Controller time:** filter + action + view
- **SQL queries:** count and duration

**Hotspot identification:**
- If middleware > 100ms: check session store, static file serving, or custom middleware
- If controller > 500ms: check N+1 queries, slow APIs, or heavy computations
- If view > 200ms: check fragment caching, partial rendering, or complex helpers

---

## Trade-offs Box
- **Advantage:** Middleware centralizes cross-cutting concerns (logging, auth, compression) without cluttering controllers.
- **Cost:** Each middleware layer adds 1-5ms latency. Too many custom middleware slow all requests.
- **When to skip:** For simple scripts/Rake tasks, skip the full middleware stack and call models directly.

---

## Debugging Checklist

When requests behave unexpectedly:

1. Check `bin/rails middleware` output — verify order and presence
2. Add logging to middleware: `Rails.logger.debug "Middleware X: #{env['PATH_INFO']}"`
3. Check `before_action` chains — ensure no filter halts prematurely
4. Inspect `params` in controller — verify middleware parsed body correctly
5. Use `curl -v` to see raw request/response headers
6. Profile with Rack Mini Profiler or add `Rails.logger.info "Action started at #{Time.now}"`
7. Check exception logs — middleware errors often don't bubble to views
8. Verify session middleware is configured if using cookies/flash

---

## One-Minute Recap
- Rails requests flow through Rack middleware → router → controller filters → action → view
- Middleware handle cross-cutting concerns (sessions, params parsing, logging)
- Before filters can halt the chain by rendering/redirecting
- Profile with Rack Mini Profiler to find bottlenecks
- Middleware order matters for security (CSRF after session)
