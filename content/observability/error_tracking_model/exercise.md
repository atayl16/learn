# Exercise: Error Tracking Mental Model

## Objective
Integrate Sentry for error tracking, add custom context (user_id, request_id), and configure filtering to reduce noise.

## Task
In a Rails application:

1. Install and configure Sentry with a DSN
2. Add user context and custom tags to every request
3. Create a test endpoint that raises an exception
4. Configure filtering to skip validation errors
5. Verify errors appear in Sentry dashboard with full context

## Acceptance Criteria
- [ ] Sentry gem installed and initialized with DSN
- [ ] Errors include user_id, email, and request_id in context
- [ ] Custom tags added: tenant_id and environment
- [ ] before_send callback filters ActiveRecord::RecordInvalid errors
- [ ] Test exception appears in Sentry with all context fields
- [ ] Validation errors do NOT appear in Sentry

## Verification Steps

### Step 1: Sign Up for Sentry

1. Go to https://sentry.io and create free account
2. Create a new project (select "Rails")
3. Copy the DSN (looks like: `https://abc123@o123.ingest.sentry.io/456`)

### Step 2: Install Sentry

```bash
# Add to Gemfile
bundle add sentry-ruby
bundle add sentry-rails

bundle install

```

### Step 3: Configure Sentry

Create `config/initializers/sentry.rb`:

```ruby
Sentry.init do |config|
  config.dsn = ENV['SENTRY_DSN']
  config.breadcrumbs_logger = [:active_support_logger, :http_logger]

  # Only enable in production/staging (or development for testing)
  config.enabled_environments = %w[production staging development]
  config.environment = Rails.env

  # Filter sensitive data
  config.send_default_pii = false

  # Filter routine errors
  config.before_send = lambda do |event, hint|
    exception = hint[:exception]

    # Skip validation errors
    if exception.is_a?(ActiveRecord::RecordInvalid)
      Rails.logger.info "Sentry: Skipping RecordInvalid error"
      return nil
    end

    event
  end
end

```

Set environment variable:

```bash
# In .env or terminal
export SENTRY_DSN="https://your-dsn-here@sentry.io/project-id"

```

### Step 4: Add Context in ApplicationController

Edit `app/controllers/application_controller.rb`:

```ruby
class ApplicationController < ActionController::Base
  before_action :set_sentry_context

  private

  def set_sentry_context
    Sentry.set_user(
      id: current_user&.id,
      email: current_user&.email
    )

    Sentry.set_tags(
      tenant_id: current_tenant&.id,
      locale: I18n.locale
    )

    Sentry.set_context(:request_details, {
      request_id: request.request_id,
      ip: request.remote_ip,
      path: request.path
    })
  end

  # Stub methods for testing
  def current_user
    OpenStruct.new(id: 123, email: 'test@example.com')
  end

  def current_tenant
    OpenStruct.new(id: 'tenant-abc')
  end
end

```

### Step 5: Create Test Controller

Add route to `config/routes.rb`:

```ruby
Rails.application.routes.draw do
  get '/error_test', to: 'errors#test_error'
  post '/validation_test', to: 'errors#test_validation'
end

```

Create `app/controllers/errors_controller.rb`:

```ruby
class ErrorsController < ApplicationController
  skip_before_action :verify_authenticity_token

  def test_error
    Rails.logger.info "About to raise test error"

    # Add custom context for this specific error
    Sentry.set_context(:custom_data, {
      test_type: 'manual_trigger',
      timestamp: Time.current.iso8601
    })

    raise StandardError, "This is a test error from #{current_user&.email}"
  end

  def test_validation
    # This should NOT appear in Sentry due to before_send filter
    user = User.new
    user.save! # Will raise ActiveRecord::RecordInvalid if validations fail
  rescue ActiveRecord::RecordInvalid => e
    render json: { error: e.message }, status: :unprocessable_entity
  end
end

```

### Step 6: Create User Model with Validation

```bash
bin/rails generate model User email:string
bin/rails db:migrate

```

Edit `app/models/user.rb`:

```ruby
class User < ApplicationRecord
  validates :email, presence: true
end

```

### Step 7: Test Error Tracking

Start Rails server:

```bash
bin/rails server

```

Trigger test error:

```bash
curl http://localhost:3000/error_test

```

You should see error in terminal and Sentry dashboard.

Test validation error (should NOT appear in Sentry):

```bash
curl -X POST http://localhost:3000/validation_test

```

Check Rails logs for "Sentry: Skipping RecordInvalid error" message.

### Step 8: Verify in Sentry Dashboard

1. Log into Sentry dashboard
2. Navigate to your project
3. Check Issues tab - should see "This is a test error from test@example.com"
4. Click the issue and verify:
   - User email: test@example.com
   - User ID: 123
   - Tags: tenant_id = tenant-abc
   - Context: request_id, ip, path
   - Custom data: test_type, timestamp
5. Confirm validation error does NOT appear

### Step 9: Test Manual Exception Capture

In Rails console:

```ruby
# Test basic capture
Sentry.capture_message("Test message from console")

# Test with extra context
begin
  1 / 0
rescue => e
  Sentry.capture_exception(e, extra: {
    calculation: 'division',
    dividend: 1,
    divisor: 0
  })
end

# Verify DSN configured
Sentry.configuration.dsn
# => Should show your DSN

# Check environment
Sentry.configuration.environment
# => "development"

```

## Stretch (Optional)

1. Add breadcrumbs for debugging:

```ruby
Sentry.add_breadcrumb(
  Sentry::Breadcrumb.new(
    category: 'auth',
    message: 'User logged in',
    level: 'info'
  )
)

```

2. Configure custom fingerprinting:

```ruby
config.before_send = lambda do |event, hint|
  if hint[:exception].is_a?(Timeout::Error)
    event.fingerprint = ['timeout']
  end
  event
end

```

3. Set up release tracking with git:

```bash
git rev-parse HEAD > REVISION

```

```ruby
config.release = File.read('REVISION').strip rescue 'unknown'

```

## Time Estimate
16 minutes
