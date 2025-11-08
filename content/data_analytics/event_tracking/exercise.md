# Exercise: Event Tracking with Ahoy

## Objective

Implement event tracking using Ahoy gem, create a conversion funnel, and ensure GDPR compliance with consent management and data deletion.

## Task

In a Rails application:

1. Install and configure Ahoy for event tracking
2. Track a 3-step signup funnel (started, info_added, completed)
3. Implement consent management before tracking events
4. Create a data deletion endpoint for GDPR compliance
5. Query events to calculate funnel conversion rates

## Acceptance Criteria

- [ ] Ahoy installed with visits and events tables migrated
- [ ] Three funnel events tracked: signup_started, email_added, signup_completed
- [ ] Events include user_id and relevant properties (email domain, plan type)
- [ ] Consent banner blocks tracking until user accepts
- [ ] Data deletion endpoint removes all user events and visits
- [ ] SQL query calculates conversion rate for each funnel step
- [ ] IP addresses masked in accordance with GDPR

## Verification Steps

### Step 1: Install Ahoy

```bash
# Add to Gemfile
bundle add ahoy_matey

bundle install

# Generate migrations
rails generate ahoy:install

# Run migrations
rails db:migrate

```

### Step 2: Configure Ahoy

Create `config/initializers/ahoy.rb`:

```ruby
Ahoy.api = false
Ahoy.mask_ips = true  # GDPR compliance
Ahoy.cookies = :none  # Don't set cookies until consent
Ahoy.visit_duration = 4.hours

```

### Step 3: Create Consent Management

Add to `config/routes.rb`:

```ruby
Rails.application.routes.draw do
  post '/consent/accept', to: 'consent#accept'
  post '/consent/reject', to: 'consent#reject'

  get '/signup', to: 'signups#new'
  post '/signup', to: 'signups#create'

  delete '/privacy/delete_data', to: 'privacy#delete_data'
end

```

Create `app/controllers/consent_controller.rb`:

```ruby
class ConsentController < ApplicationController
  skip_before_action :verify_authenticity_token

  def accept
    cookies[:analytics_consent] = {
      value: 'true',
      expires: 1.year,
      same_site: :lax
    }
    render json: { success: true }
  end

  def reject
    cookies.delete(:analytics_consent)
    render json: { success: true }
  end
end

```

### Step 4: Create Signup Funnel

Create `app/controllers/signups_controller.rb`:

```ruby
class SignupsController < ApplicationController
  skip_before_action :verify_authenticity_token

  def new
    track_event('signup_started', {
      source: params[:source] || 'direct',
      page: request.path
    })

    render json: { message: 'Signup form loaded' }
  end

  def create
    email = params[:email]
    plan = params[:plan] || 'free'

    # Track email step
    track_event('email_added', {
      email_domain: email&.split('@')&.last,
      plan: plan
    })

    # Simulate user creation
    user = User.create!(
      email: email,
      plan: plan,
      password: SecureRandom.hex(10)
    )

    # Associate future events with user
    ahoy.authenticate(user)

    # Track completion
    track_event('signup_completed', {
      user_id: user.id,
      plan: plan,
      email_domain: email.split('@').last
    })

    render json: {
      success: true,
      user_id: user.id
    }
  end

  private

  def track_event(name, properties = {})
    return unless tracking_enabled?

    ahoy.track(name, properties)
  end

  def tracking_enabled?
    cookies[:analytics_consent] == 'true'
  end
end

```

Ensure User model exists:

```bash
# If User model doesn't exist
rails generate model User email:string plan:string password_digest:string
rails db:migrate

```

Or create it manually in `app/models/user.rb`:

```ruby
class User < ApplicationRecord
  validates :email, presence: true, uniqueness: true
end

```

### Step 5: Create Data Deletion Endpoint

Create `app/controllers/privacy_controller.rb`:

```ruby
class PrivacyController < ApplicationController
  skip_before_action :verify_authenticity_token
  before_action :authenticate_user!

  def delete_data
    user = current_user

    # Delete all events and visits
    Ahoy::Event.where(user: user).delete_all
    Ahoy::Visit.where(user: user).delete_all

    # Optionally delete the user account
    # user.destroy

    render json: {
      success: true,
      message: 'All tracking data deleted'
    }
  end

  private

  def authenticate_user!
    # Simplified authentication for exercise
    user_id = params[:user_id] || request.headers['X-User-Id']
    @current_user = User.find_by(id: user_id)

    unless @current_user
      render json: { error: 'Unauthorized' }, status: :unauthorized
    end
  end

  def current_user
    @current_user
  end
end

```

### Step 6: Test Event Tracking

Start Rails server:

```bash
bin/rails server

```

Test funnel flow:

```bash
# Step 1: Start signup (no consent - should not track)
curl -v http://localhost:3000/signup?source=google

# Check cookies - should have ahoy_visit but no consent
# Events should be created only if consent exists

# Step 2: Accept consent
curl -X POST http://localhost:3000/consent/accept \
  -H "Cookie: ahoy_visit=abc123" \
  -c cookies.txt

# Step 3: Start signup again (with consent)
curl http://localhost:3000/signup?source=google \
  -b cookies.txt

# Step 4: Complete signup
curl -X POST http://localhost:3000/signup \
  -H "Content-Type: application/json" \
  -b cookies.txt \
  -d '{
    "email": "user@example.com",
    "plan": "premium"
  }'

```

### Step 7: Query Funnel Conversion

Open Rails console:

```ruby
# Check events were created
Ahoy::Event.pluck(:name).tally
# => {"signup_started"=>1, "email_added"=>1, "signup_completed"=>1}

# Calculate funnel conversion
started = Ahoy::Event.where(name: 'signup_started').count
email_added = Ahoy::Event.where(name: 'email_added').count
completed = Ahoy::Event.where(name: 'signup_completed').count

puts "Started: #{started}"
puts "Email Added: #{email_added} (#{(email_added.to_f / started * 100).round(1)}%)"
puts "Completed: #{completed} (#{(completed.to_f / started * 100).round(1)}%)"

# Check properties
Ahoy::Event.where(name: 'signup_completed').last.properties
# => {"user_id"=>1, "plan"=>"premium", "email_domain"=>"example.com"}

# Verify IP masking
Ahoy::Visit.last.ip
# => Should show masked IP like "127.0.0.0"

```

Or use SQL:

```sql
SELECT
  name,
  COUNT(*) as event_count,
  COUNT(DISTINCT user_id) as unique_users
FROM ahoy_events
WHERE time > NOW() - INTERVAL '1 day'
GROUP BY name
ORDER BY name;

```

### Step 8: Test Data Deletion

```bash
# Delete user data
curl -X DELETE http://localhost:3000/privacy/delete_data \
  -H "X-User-Id: 1"

```

Verify in console:

```ruby
user = User.first
Ahoy::Event.where(user: user).count
# => 0
Ahoy::Visit.where(user: user).count
# => 0

```

## Stretch (Optional)

1. Add session-based anonymous tracking before user signup:

```ruby
# Track with anonymous ID
anonymous_id = session[:anonymous_id] ||= SecureRandom.uuid
ahoy.track('page_viewed', anonymous_id: anonymous_id)

# Later associate with user
ahoy.authenticate(user)

```

2. Create a funnel report endpoint:

```ruby
# app/controllers/analytics_controller.rb
def funnel_report
  funnel_data = Ahoy::Event
    .where(name: ['signup_started', 'email_added', 'signup_completed'])
    .group(:name)
    .count

  render json: funnel_data
end

```

3. Export user data for GDPR data portability:

```ruby
def export_data
  events = Ahoy::Event.where(user: current_user)
  render json: events.as_json(only: [:name, :properties, :time])
end

```

## Time Estimate

22 minutes
