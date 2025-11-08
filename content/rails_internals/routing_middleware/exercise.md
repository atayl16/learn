# Exercise: Routing & Middleware Patterns

## Objective
Design RESTful routes with namespaces and constraints, then write custom middleware for request logging.

## Task
In a Rails app:

1. Create nested routes for `posts` and `comments`
2. Add an `admin` namespace with routes for managing posts
3. Write custom middleware that logs request paths and response times
4. Add a subdomain constraint for an API namespace

## Acceptance Criteria
- [ ] Routes exist for `/posts/:post_id/comments`
- [ ] Admin routes exist at `/admin/posts`
- [ ] Custom middleware logs all requests with timing
- [ ] API routes only match `api.` subdomain
- [ ] `bin/rails routes` shows all expected routes
- [ ] Can explain difference between `namespace` and `scope module:`

## Verification Steps

1. Run `bin/rails routes | grep comments` and see nested routes
2. Visit `/admin/posts` and see admin controller response
3. Check `log/development.log` for middleware output:
```
Request: GET /posts
Response: 200 in 45ms
```
4. Test subdomain constraint (if using `lvh.me` or similar)

## Setup Code

### Step 1: Create App and Models

```bash
rails new routing_demo --skip-javascript
cd routing_demo
bin/rails generate scaffold Post title:string body:text
bin/rails generate model Comment body:text post:references
bin/rails db:migrate
```

### Step 2: Define Routes

Edit `config/routes.rb`:
```ruby
Rails.application.routes.draw do
  root 'posts#index'

  # Nested resources (shallow to avoid deep URLs)
  resources :posts do
    resources :comments, shallow: true, only: [:index, :create]
  end

  # Admin namespace
  namespace :admin do
    resources :posts, only: [:index, :edit, :update]
  end

  # API with subdomain constraint
  constraints subdomain: 'api' do
    namespace :api do
      namespace :v1 do
        resources :posts, only: [:index, :show]
      end
    end
  end
end
```

### Step 3: Create Admin Controller

Create `app/controllers/admin/posts_controller.rb`:
```ruby
module Admin
  class PostsController < ApplicationController
    def index
      @posts = Post.all
      render json: @posts
    end

    def edit
      @post = Post.find(params[:id])
      render json: @post
    end

    def update
      @post = Post.find(params[:id])
      if @post.update(post_params)
        render json: @post
      else
        render json: @post.errors, status: :unprocessable_entity
      end
    end

    private

    def post_params
      params.require(:post).permit(:title, :body)
    end
  end
end
```

### Step 4: Create API Controller

Create `app/controllers/api/v1/posts_controller.rb`:
```ruby
module Api
  module V1
    class PostsController < ApplicationController
      def index
        @posts = Post.all
        render json: @posts
      end

      def show
        @post = Post.find(params[:id])
        render json: @post
      end
    end
  end
end
```

### Step 5: Create Custom Middleware

Create `app/middleware/request_timer.rb`:
```ruby
class RequestTimer
  def initialize(app)
    @app = app
  end

  def call(env)
    start_time = Time.now
    request = Rack::Request.new(env)

    Rails.logger.info "Request: #{request.request_method} #{request.path}"

    status, headers, response = @app.call(env)

    duration = ((Time.now - start_time) * 1000).round
    Rails.logger.info "Response: #{status} in #{duration}ms"

    [status, headers, response]
  end
end
```

Add to `config/application.rb`:
```ruby
module RoutingDemo
  class Application < Rails::Application
    # ... existing config
    config.middleware.use RequestTimer
  end
end
```

### Step 6: Test Routes

```bash
# List all routes
bin/rails routes

# Filter by controller
bin/rails routes -c posts
bin/rails routes -c admin/posts
bin/rails routes -c api/v1/posts

# Test in console
Rails.application.routes.recognize_path("/posts/1/comments", method: :get)
# => { controller: "comments", action: "index", post_id: "1" }
```

### Step 7: Create Sample Data and Test

```bash
bin/rails console
```

```ruby
# Create posts
3.times { |i| Post.create(title: "Post #{i}", body: "Body #{i}") }

# Test routes
post = Post.first
Rails.application.routes.url_helpers.post_comments_path(post)
# => "/posts/1/comments"

Rails.application.routes.url_helpers.admin_posts_path
# => "/admin/posts"
```

Start server and test:
```bash
bin/rails server
# Visit http://localhost:3000/posts
# Visit http://localhost:3000/admin/posts
# Check log/development.log for timing output
```

## Stretch (Optional)

1. Add route constraints for format:
```ruby
resources :posts, constraints: { format: 'json' }
```

2. Create a custom constraint class for API versioning:
```ruby
# lib/constraints/api_version.rb
class ApiVersion
  def initialize(version)
    @version = version
  end

  def matches?(request)
    request.headers['Accept']&.include?("application/vnd.myapp.v#{@version}+json")
  end
end

# config/routes.rb
namespace :api do
  constraints ApiVersion.new(1) do
    resources :posts, controller: 'v1/posts'
  end

  constraints ApiVersion.new(2) do
    resources :posts, controller: 'v2/posts'
  end
end
```

3. Add middleware to reject requests without API key for /api routes:
```ruby
class ApiKeyCheck
  def initialize(app)
    @app = app
  end

  def call(env)
    request = Rack::Request.new(env)

    if request.path.start_with?('/api')
      api_key = request.env['HTTP_X_API_KEY']
      unless api_key == 'secret'
        return [401, { 'Content-Type' => 'application/json' }, ['{"error": "Unauthorized"}']]
      end
    end

    @app.call(env)
  end
end
```

## Time Estimate
18 minutes
