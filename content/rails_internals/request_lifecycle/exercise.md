# Exercise: Request Lifecycle & Middleware

## Objective
Trace a Rails request through middleware and controller filters, then profile to identify timing bottlenecks.

## Task
In a Rails app (create a new one if needed):

1. Add Rack Mini Profiler and view the middleware stack
2. Create a `PostsController` with a `before_action` that logs timing
3. Add a custom middleware that logs request paths
4. Trigger a request and analyze the profiler output

## Acceptance Criteria
- [ ] `bin/rails middleware` output shows custom middleware in the stack
- [ ] Custom middleware logs every incoming request path to `Rails.logger`
- [ ] `PostsController#index` has a `before_action` that logs "Filter started"
- [ ] Rack Mini Profiler badge appears and shows middleware timing breakdown
- [ ] `development.log` contains middleware log, filter log, and SQL queries for the request

## Verification Steps

1. Run `bin/rails middleware` and confirm your custom middleware appears

2. Check `log/development.log` for:
```
CustomMiddleware: Processing /posts
Filter started
  Post Load (0.3ms)  SELECT "posts".* FROM "posts"
Completed 200 OK in 15ms
```

3. Open browser, click Rack Mini Profiler badge, screenshot showing:
   - Middleware timing
   - Controller timing
   - SQL query count

## Setup Code

### Step 1: Add Rack Mini Profiler

```bash
# In an existing Rails app or create new
rails new profiler_demo --skip-javascript
cd profiler_demo
bundle add rack-mini-profiler
```

Edit `config/environments/development.rb`:
```ruby
Rails.application.configure do
  # ... existing config
  config.middleware.use Rack::MiniProfiler
end
```

### Step 2: Create Custom Middleware

Create `app/middleware/request_logger.rb`:
```ruby
class RequestLogger
  def initialize(app)
    @app = app
  end

  def call(env)
    request = Rack::Request.new(env)
    Rails.logger.info "CustomMiddleware: Processing #{request.path}"
    @app.call(env)
  end
end
```

Add to `config/application.rb`:
```ruby
module ProfilerDemo
  class Application < Rails::Application
    # ... existing config
    config.middleware.use RequestLogger
  end
end
```

### Step 3: Create Controller with Filters

```bash
bin/rails generate controller Posts index
```

Edit `app/controllers/posts_controller.rb`:
```ruby
class PostsController < ApplicationController
  before_action :log_filter_start

  def index
    @posts = Post.all
    render plain: "Found #{@posts.count} posts"
  end

  private

  def log_filter_start
    Rails.logger.info "Filter started at #{Time.now}"
  end
end
```

### Step 4: Create Sample Data

```bash
bin/rails generate model Post title:string body:text
bin/rails db:migrate
bin/rails console
```

In console:
```ruby
5.times { |i| Post.create(title: "Post #{i}", body: "Body #{i}") }
```

### Step 5: Test Request

```bash
bin/rails server
# Visit http://localhost:3000/posts
# Check Rack Mini Profiler badge in top-left
```

## Stretch (Optional)

Add an `after_action` that logs the response status code:

```ruby
after_action :log_response_status

private

def log_response_status
  Rails.logger.info "Response status: #{response.status}"
end
```

Trigger a 404 by visiting `/posts/999` and verify the log shows `404`.

## Time Estimate
20 minutes
