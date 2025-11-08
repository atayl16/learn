# Routing & Middleware Patterns

## What It Is
Rails routing maps HTTP requests (verb + path) to controller actions. RESTful routes follow conventions (`resources :posts` generates 7 routes). Middleware are Rack components that intercept requests before they reach the router, enabling cross-cutting concerns like auth, logging, or rate limiting. Constraints filter routes based on request properties.

## Why It Matters
Clean routing improves API discoverability and maintainability. Custom middleware centralizes logic (API versioning, request tracking) without cluttering controllers. Route constraints prevent invalid requests from reaching controllers. Seniors design routes for clarity, scope APIs with namespaces, and write middleware for app-wide concerns.

## When to Use
- **Resources:** RESTful CRUD operations
- **Namespaces:** Organize admin/api routes
- **Constraints:** Limit routes by domain, subdomain, or request format
- **Custom middleware:** Authentication, request logging, API versioning, rate limiting

## Three Common Pitfalls
1. **Non-RESTful routes:** Adding `get 'posts/archive'` clutters routes. Prefer resourceful routes: `get 'posts', to: 'posts#archive', constraints: { archive: true }`.
2. **Middleware order matters:** Auth middleware must run before rate limiting. Wrong order breaks logic.
3. **Route bloat:** Exposing all 7 RESTful actions when you only need 3 wastes routes. Use `only: [:index, :show]` or `except: [:destroy]`.

---

## RESTful Resources

Generate 7 standard routes:

```ruby
# config/routes.rb
resources :posts

```

Generates:

```
GET    /posts          posts#index
POST   /posts          posts#create
GET    /posts/new      posts#new
GET    /posts/:id/edit posts#edit
GET    /posts/:id      posts#show
PATCH  /posts/:id      posts#update
DELETE /posts/:id      posts#destroy

```

**Limit routes:**

```ruby
resources :posts, only: [:index, :show]
resources :comments, except: [:destroy]

```

**Nested resources:**

```ruby
resources :posts do
  resources :comments
end
# Generates /posts/:post_id/comments

```

**Shallow nesting (avoid deep nesting):**

```ruby
resources :posts do
  resources :comments, shallow: true
end
# /posts/:post_id/comments (create)
# /comments/:id (show, edit, update, destroy)

```

---

## Namespaces and Scopes

**Namespace (organizes controllers):**

```ruby
namespace :admin do
  resources :posts
end
# Routes to Admin::PostsController
# URL: /admin/posts

```

**Scope (URL only):**

```ruby
scope :api do
  resources :posts
end
# Routes to PostsController
# URL: /api/posts

```

**Module (controller only):**

```ruby
scope module: :api do
  resources :posts
end
# Routes to Api::PostsController
# URL: /posts

```

---

## Constraints

**Subdomain routing:**

```ruby
constraints subdomain: 'api' do
  resources :posts
end
# Matches http://api.example.com/posts

```

**Format constraints:**

```ruby
resources :posts, constraints: { format: 'json' }
# Only matches /posts.json

```

**Custom constraints (class-based):**

```ruby
# lib/constraints/api_version_constraint.rb
class ApiVersionConstraint
  def initialize(version)
    @version = version
  end

  def matches?(request)
    request.headers['Accept']&.include?("application/vnd.myapp.v#{@version}")
  end
end

# config/routes.rb
constraints ApiVersionConstraint.new(1) do
  resources :posts, controller: 'api/v1/posts'
end

constraints ApiVersionConstraint.new(2) do
  resources :posts, controller: 'api/v2/posts'
end

```

---

## Route Helpers

Rails generates helper methods:

```ruby
posts_path          # => "/posts"
post_path(@post)    # => "/posts/123"
new_post_path       # => "/posts/new"
edit_post_path(@post) # => "/posts/123/edit"

```

**Named routes:**

```ruby
get 'dashboard', to: 'pages#dashboard', as: :user_dashboard
# Generates: user_dashboard_path => "/dashboard"

```

**URL helpers:**

```ruby
posts_url  # => "http://example.com/posts" (absolute)
posts_path # => "/posts" (relative)

```

---

## Custom Middleware

**Use cases:**
- Request logging
- API authentication
- Rate limiting
- Request ID tracking
- Custom headers

**Example: Request Logger**

```ruby
# app/middleware/request_logger.rb
class RequestLogger
  def initialize(app)
    @app = app
  end

  def call(env)
    request = Rack::Request.new(env)
    Rails.logger.info "Incoming: #{request.request_method} #{request.path}"

    status, headers, response = @app.call(env)

    Rails.logger.info "Outgoing: #{status}"
    [status, headers, response]
  end
end

# config/application.rb
config.middleware.use RequestLogger

```

**Example: API Key Authentication**

```ruby
# app/middleware/api_key_auth.rb
class ApiKeyAuth
  def initialize(app)
    @app = app
  end

  def call(env)
    request = Rack::Request.new(env)

    if request.path.start_with?('/api')
      api_key = request.env['HTTP_X_API_KEY']
      unless valid_api_key?(api_key)
        return [401, { 'Content-Type' => 'application/json' }, ['{"error": "Unauthorized"}']]
      end
    end

    @app.call(env)
  end

  private

  def valid_api_key?(key)
    key == ENV['API_KEY']
  end
end

# config/application.rb
config.middleware.use ApiKeyAuth

```

**Insert middleware at specific position:**

```ruby
# Before a specific middleware
config.middleware.insert_before ActionDispatch::Static, ApiKeyAuth

# After a specific middleware
config.middleware.insert_after ActionDispatch::RequestId, RequestLogger

```

---

## Debugging Routes

**List all routes:**

```bash
bin/rails routes
bin/rails routes | grep posts
bin/rails routes -c posts  # routes for PostsController

```

**Check specific route:**

```bash
bin/rails routes | grep "posts#show"

```

**Test route matching in console:**

```ruby
Rails.application.routes.recognize_path("/posts/123", method: :get)
# => { controller: "posts", action: "show", id: "123" }

```

**Generate URL from route:**

```ruby
Rails.application.routes.url_helpers.post_path(123)
# => "/posts/123"

```

---

## Trade-offs Box
- **Advantage:** RESTful routes follow conventions; middleware centralizes logic; constraints prevent invalid requests.
- **Cost:** Overusing nested routes makes URLs unwieldy. Too many custom routes break REST conventions.
- **When to skip:** For non-CRUD actions (search, analytics), use custom routes with clear intent.

---

## Debugging Checklist

When routes misbehave:

1. Run `bin/rails routes` to see all routes
2. Check route order — first match wins
3. Verify controller/action exist: `PostsController#show`
4. Test route helpers: `post_path(123)` in console
5. Check constraints: subdomain, format, custom logic
6. Inspect middleware order: `bin/rails middleware`
7. Add logging to custom middleware to verify execution
8. Use `Rails.application.routes.recognize_path` to debug path matching

---

## One-Minute Recap
- RESTful resources generate 7 standard routes (index, show, create, update, destroy, new, edit)
- Namespaces organize routes and controllers (e.g., `namespace :admin`)
- Constraints filter routes by subdomain, format, or custom logic
- Custom middleware intercept requests for auth, logging, rate limiting
- Route helpers (`posts_path`, `post_url`) generate URLs; check with `bin/rails routes`
