# Exercise: Structured Logging with Lograge

## Objective
Configure lograge for JSON logging, add custom fields (user_id and request_id), and filter sensitive parameters from logs.

## Task
In a Rails application:

1. Install and configure lograge with JSON formatting
2. Add custom fields: request_id, user_id, and remote IP
3. Configure parameter filtering for passwords and API tokens
4. Make test requests and verify JSON log output
5. Confirm sensitive params appear as [FILTERED]

## Acceptance Criteria
- [ ] Lograge installed and enabled in development/production
- [ ] Logs output as single-line JSON per request
- [ ] JSON includes: method, path, status, duration, request_id, user_id
- [ ] Password parameters appear as [FILTERED] in logs
- [ ] Health check endpoint `/health` skipped from logging
- [ ] Log output readable via `tail -f log/development.log`

## Verification Steps

### Step 1: Install Lograge

```bash
# Add to Gemfile
bundle add lograge

bundle install
```

### Step 2: Configure Lograge

Create or edit `config/environments/development.rb`:

```ruby
Rails.application.configure do
  # Enable lograge for development testing
  config.lograge.enabled = true
  config.lograge.formatter = Lograge::Formatters::Json.new

  config.lograge.custom_options = lambda do |event|
    {
      time: event.time.iso8601,
      request_id: event.payload[:headers]['action_dispatch.request_id'],
      user_id: event.payload[:user_id],
      ip: event.payload[:ip]
    }
  end

  # Skip health checks
  config.lograge.ignore_custom = lambda do |event|
    event.payload[:path] == '/health'
  end
end
```

Apply same config to `config/environments/production.rb`.

### Step 3: Add Custom Payload Data

Edit `app/controllers/application_controller.rb`:

```ruby
class ApplicationController < ActionController::Base
  def append_info_to_payload(payload)
    super
    payload[:user_id] = current_user&.id
    payload[:ip] = request.remote_ip
  end

  private

  # Stub method for testing - replace with real authentication
  def current_user
    User.first if User.any?
  end
end
```

### Step 4: Configure Parameter Filtering

Edit `config/initializers/filter_parameter_logging.rb`:

```ruby
Rails.application.config.filter_parameters += [
  :password,
  :password_confirmation,
  :api_token,
  :secret_key,
  :api_key
]
```

### Step 5: Create Test Routes and Controller

Add to `config/routes.rb`:

```ruby
Rails.application.routes.draw do
  get '/health', to: 'health#show'
  post '/login', to: 'sessions#create'
  get '/users/:id', to: 'users#show'
end
```

Create `app/controllers/health_controller.rb`:

```ruby
class HealthController < ApplicationController
  skip_before_action :verify_authenticity_token

  def show
    render json: { status: 'ok' }
  end
end
```

Create `app/controllers/sessions_controller.rb`:

```ruby
class SessionsController < ApplicationController
  skip_before_action :verify_authenticity_token

  def create
    Rails.logger.info "Login attempt with params: #{params.inspect}"
    render json: { success: true }
  end
end
```

Create `app/controllers/users_controller.rb`:

```ruby
class UsersController < ApplicationController
  def show
    sleep 0.1 # Simulate work
    render json: { id: params[:id], name: 'Test User' }
  end
end
```

### Step 6: Test and Verify

Start Rails server:

```bash
bin/rails server
```

In another terminal, tail logs:

```bash
tail -f log/development.log
```

Make test requests:

```bash
# Should appear in logs as JSON
curl http://localhost:3000/users/123

# Should NOT appear in logs (ignored)
curl http://localhost:3000/health

# Should show [FILTERED] for password
curl -X POST http://localhost:3000/login \
  -H "Content-Type: application/json" \
  -d '{"email":"user@example.com","password":"secret123","api_token":"abc123"}'
```

Expected log output for `/users/123`:

```json
{"method":"GET","path":"/users/123","format":"*/*","controller":"UsersController","action":"show","status":200,"duration":105.23,"view":0.45,"db":0.0,"time":"2025-01-15T10:23:45-08:00","request_id":"abc123-def456","user_id":null,"ip":"127.0.0.1"}
```

Expected log output for `/login` (check password is filtered):

```
{"method":"POST","path":"/login","format":"json","controller":"SessionsController","action":"create","status":200,"params":{"email":"user@example.com","password":"[FILTERED]","api_token":"[FILTERED]"},...}
```

### Step 7: Verify in Rails Console

```ruby
# Check configuration
Rails.configuration.lograge.enabled
# => true

Rails.configuration.lograge.formatter
# => #<Lograge::Formatters::Json:0x00...>

Rails.application.config.filter_parameters
# => [:password, :password_confirmation, :api_token, :secret_key, :api_key, ...]
```

## Stretch (Optional)

1. Add exception tracking to logs:

```ruby
config.lograge.custom_options = lambda do |event|
  {
    time: event.time.iso8601,
    request_id: event.payload[:headers]['action_dispatch.request_id'],
    user_id: event.payload[:user_id],
    exception: event.payload[:exception]&.first,
    exception_message: event.payload[:exception]&.last
  }
end
```

2. Log SQL query counts per request:

```ruby
config.lograge.custom_options = lambda do |event|
  {
    query_count: event.payload[:db_queries_count],
    cache_hits: event.payload[:cache_hits]
  }
end
```

## Time Estimate
18 minutes
