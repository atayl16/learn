# Exercise: Working with Legacy Code

## Objective

Apply characterization testing and seam-based refactoring to untested legacy code, safely extract business logic using dependency injection, and verify behavior remains unchanged throughout the refactoring process.

## Task

Given a legacy Rails controller with embedded business logic, no tests, and hard dependencies:

1. Write characterization tests capturing current behavior
2. Identify and extract seams for dependency injection
3. Refactor logic into a service object
4. Implement Strangler Fig pattern with feature flag
5. Verify all tests pass after refactoring

## Acceptance Criteria

- [ ] Characterization tests cover all code paths in legacy method
- [ ] Tests use doubles/stubs to avoid database and external API calls
- [ ] Seam extracted for external dependency (payment gateway)
- [ ] Service object implements same behavior with injected dependencies
- [ ] Feature flag controls routing between legacy and new implementation
- [ ] All characterization tests pass with both implementations
- [ ] Legacy code paths marked for removal with TODO comments

## Setup Code

### Legacy Controller (Untested)

Create `app/controllers/subscriptions_controller.rb`:

```ruby
class SubscriptionsController < ApplicationController
  def create
    user = User.find(params[:user_id])

    # Hard-coded payment gateway
    response = HTTParty.post(
      'https://payments.example.com/charge',
      body: {
        amount: params[:amount],
        token: params[:payment_token],
        email: user.email
      }.to_json,
      headers: { 'Content-Type' => 'application/json' }
    )

    if response.code == 200
      subscription = user.subscriptions.create!(
        plan: params[:plan],
        amount: params[:amount],
        status: 'active',
        payment_id: response['id']
      )

      # Send confirmation email
      UserMailer.subscription_confirmation(user.id, subscription.id).deliver_now

      # Log to third-party analytics
      HTTParty.post(
        'https://analytics.example.com/track',
        body: { event: 'subscription_created', user_id: user.id }.to_json
      )

      redirect_to subscription_path(subscription), notice: 'Subscription created!'
    else
      redirect_to new_subscription_path, alert: 'Payment failed'
    end
  end
end

```

This code has multiple problems:
- No tests
- Hard-coded external API calls (HTTParty)
- Business logic in controller
- Can't test without hitting real APIs

## Part 1: Write Characterization Tests (10 minutes)

Create `spec/controllers/subscriptions_controller_spec.rb`:

```ruby
require 'rails_helper'

RSpec.describe SubscriptionsController, type: :controller do
  describe 'POST #create' do
    let(:user) { double('User', id: 1, email: 'user@example.com', subscriptions: subscriptions) }
    let(:subscriptions) { double('Subscriptions') }
    let(:subscription) { double('Subscription', id: 99) }

    before do
      allow(User).to receive(:find).with('1').and_return(user)
    end

    context 'when payment succeeds' do
      before do
        # Stub payment gateway
        stub_request(:post, 'https://payments.example.com/charge')
          .to_return(status: 200, body: { id: 'pay_123' }.to_json)

        # Stub analytics
        stub_request(:post, 'https://analytics.example.com/track')
          .to_return(status: 200)

        # Stub subscription creation
        allow(subscriptions).to receive(:create!).and_return(subscription)

        # Stub mailer
        mailer = double('Mailer')
        allow(UserMailer).to receive(:subscription_confirmation).and_return(mailer)
        allow(mailer).to receive(:deliver_now)
      end

      it 'creates subscription with correct attributes' do
        expect(subscriptions).to receive(:create!).with(
          plan: 'premium',
          amount: '2999',
          status: 'active',
          payment_id: 'pay_123'
        )

        post :create, params: {
          user_id: 1,
          plan: 'premium',
          amount: '2999',
          payment_token: 'tok_123'
        }
      end

      it 'sends confirmation email' do
        mailer = double('Mailer')
        expect(UserMailer).to receive(:subscription_confirmation).with(1, 99).and_return(mailer)
        expect(mailer).to receive(:deliver_now)

        post :create, params: { user_id: 1, plan: 'premium', amount: '2999', payment_token: 'tok_123' }
      end

      it 'redirects to subscription page' do
        post :create, params: { user_id: 1, plan: 'premium', amount: '2999', payment_token: 'tok_123' }

        expect(response).to redirect_to(subscription_path(subscription))
      end
    end

    context 'when payment fails' do
      before do
        stub_request(:post, 'https://payments.example.com/charge')
          .to_return(status: 402, body: { error: 'Insufficient funds' }.to_json)
      end

      it 'does not create subscription' do
        expect(subscriptions).not_to receive(:create!)

        post :create, params: { user_id: 1, plan: 'premium', amount: '2999', payment_token: 'tok_123' }
      end

      it 'redirects to new subscription page with error' do
        post :create, params: { user_id: 1, plan: 'premium', amount: '2999', payment_token: 'tok_123' }

        expect(response).to redirect_to(new_subscription_path)
        expect(flash[:alert]).to eq('Payment failed')
      end
    end
  end
end

```

**Run tests:** `bundle exec rspec spec/controllers/subscriptions_controller_spec.rb`

Tests should pass, locking in current behavior.

## Part 2: Extract Seams (5 minutes)

Modify controller to create testable seams:

```ruby
class SubscriptionsController < ApplicationController
  def create
    user = User.find(params[:user_id])
    response = process_payment(user, params[:amount], params[:payment_token])

    if response.code == 200
      subscription = user.subscriptions.create!(
        plan: params[:plan],
        amount: params[:amount],
        status: 'active',
        payment_id: response['id']
      )

      send_confirmation(user, subscription)
      track_analytics(user)

      redirect_to subscription_path(subscription), notice: 'Subscription created!'
    else
      redirect_to new_subscription_path, alert: 'Payment failed'
    end
  end

  private

  def process_payment(user, amount, token)
    HTTParty.post(
      'https://payments.example.com/charge',
      body: { amount: amount, token: token, email: user.email }.to_json,
      headers: { 'Content-Type' => 'application/json' }
    )
  end

  def send_confirmation(user, subscription)
    UserMailer.subscription_confirmation(user.id, subscription.id).deliver_now
  end

  def track_analytics(user)
    HTTParty.post(
      'https://analytics.example.com/track',
      body: { event: 'subscription_created', user_id: user.id }.to_json
    )
  end
end

```

**Run tests again:** They still pass, proving behavior unchanged.

## Part 3: Create Service Object (8 minutes)

Create `app/services/subscriptions/create_service.rb`:

```ruby
module Subscriptions
  class CreateService
    Result = Struct.new(:success?, :subscription, :error)

    def initialize(user:, plan:, amount:, payment_token:,
                   payment_gateway: PaymentGateway.new,
                   mailer: UserMailer,
                   analytics: AnalyticsTracker.new)
      @user = user
      @plan = plan
      @amount = amount
      @payment_token = payment_token
      @payment_gateway = payment_gateway
      @mailer = mailer
      @analytics = analytics
    end

    def call
      payment_result = @payment_gateway.charge(
        amount: @amount,
        token: @payment_token,
        email: @user.email
      )

      return Result.new(false, nil, 'Payment failed') unless payment_result.success?

      subscription = @user.subscriptions.create!(
        plan: @plan,
        amount: @amount,
        status: 'active',
        payment_id: payment_result.id
      )

      @mailer.subscription_confirmation(@user.id, subscription.id).deliver_now
      @analytics.track('subscription_created', user_id: @user.id)

      Result.new(true, subscription, nil)
    rescue => e
      Result.new(false, nil, e.message)
    end
  end
end

```

Create wrapper classes for external dependencies:

```ruby
# app/services/payment_gateway.rb
class PaymentGateway
  PaymentResult = Struct.new(:success?, :id)

  def charge(amount:, token:, email:)
    response = HTTParty.post(
      'https://payments.example.com/charge',
      body: { amount: amount, token: token, email: email }.to_json,
      headers: { 'Content-Type' => 'application/json' }
    )

    PaymentResult.new(response.code == 200, response['id'])
  end
end

# app/services/analytics_tracker.rb
class AnalyticsTracker
  def track(event, data)
    HTTParty.post(
      'https://analytics.example.com/track',
      body: { event: event }.merge(data).to_json
    )
  end
end

```

**Write service tests:**

```ruby
# spec/services/subscriptions/create_service_spec.rb
require 'rails_helper'

RSpec.describe Subscriptions::CreateService do
  describe '#call' do
    let(:user) { double('User', id: 1, email: 'user@test.com', subscriptions: subscriptions) }
    let(:subscriptions) { double('Subscriptions') }
    let(:subscription) { double('Subscription', id: 99) }
    let(:payment_gateway) { double('PaymentGateway') }
    let(:mailer) { double('Mailer', deliver_now: true) }
    let(:mailer_class) { double('UserMailer', subscription_confirmation: mailer) }
    let(:analytics) { double('AnalyticsTracker') }

    subject(:service) do
      described_class.new(
        user: user,
        plan: 'premium',
        amount: '2999',
        payment_token: 'tok_123',
        payment_gateway: payment_gateway,
        mailer: mailer_class,
        analytics: analytics
      )
    end

    context 'when payment succeeds' do
      before do
        allow(payment_gateway).to receive(:charge).and_return(
          double(success?: true, id: 'pay_123')
        )
        allow(subscriptions).to receive(:create!).and_return(subscription)
        allow(analytics).to receive(:track)
      end

      it 'returns success result with subscription' do
        result = service.call

        expect(result.success?).to be true
        expect(result.subscription).to eq(subscription)
      end

      it 'sends confirmation email' do
        expect(mailer_class).to receive(:subscription_confirmation).with(1, 99)
        service.call
      end

      it 'tracks analytics event' do
        expect(analytics).to receive(:track).with('subscription_created', user_id: 1)
        service.call
      end
    end

    context 'when payment fails' do
      before do
        allow(payment_gateway).to receive(:charge).and_return(
          double(success?: false, id: nil)
        )
      end

      it 'returns failure result' do
        result = service.call

        expect(result.success?).to be false
        expect(result.error).to eq('Payment failed')
      end

      it 'does not create subscription' do
        expect(subscriptions).not_to receive(:create!)
        service.call
      end
    end
  end
end

```

## Part 4: Implement Strangler Fig Pattern (5 minutes)

Update controller to support both paths:

```ruby
class SubscriptionsController < ApplicationController
  def create
    if use_new_subscription_flow?
      create_with_service
    else
      create_legacy # TODO: Remove after migration complete
    end
  end

  private

  def use_new_subscription_flow?
    # Feature flag or gradual rollout
    current_user&.feature_enabled?(:new_subscription_flow) || params[:use_new_flow]
  end

  def create_with_service
    user = User.find(params[:user_id])
    result = Subscriptions::CreateService.new(
      user: user,
      plan: params[:plan],
      amount: params[:amount],
      payment_token: params[:payment_token]
    ).call

    if result.success?
      redirect_to subscription_path(result.subscription), notice: 'Subscription created!'
    else
      redirect_to new_subscription_path, alert: result.error
    end
  end

  def create_legacy
    # Original implementation (seams extracted)
    user = User.find(params[:user_id])
    response = process_payment(user, params[:amount], params[:payment_token])

    if response.code == 200
      subscription = user.subscriptions.create!(
        plan: params[:plan],
        amount: params[:amount],
        status: 'active',
        payment_id: response['id']
      )

      send_confirmation(user, subscription)
      track_analytics(user)

      redirect_to subscription_path(subscription), notice: 'Subscription created!'
    else
      redirect_to new_subscription_path, alert: 'Payment failed'
    end
  end

  # Seam methods...
end

```

## Verification Steps

1. Run all tests:

```bash
bundle exec rspec

```

All tests should pass for both legacy and new implementations.

2. Test in Rails console:

```ruby
# Create test user
user = User.create!(email: 'test@example.com', name: 'Test User')

# Test new service directly
result = Subscriptions::CreateService.new(
  user: user,
  plan: 'premium',
  amount: '2999',
  payment_token: 'tok_test',
  payment_gateway: double(charge: double(success?: true, id: 'pay_123')),
  mailer: double(subscription_confirmation: double(deliver_now: true)),
  analytics: double(track: true)
).call

result.success? # => true

```

3. Monitor feature flag rollout in production (pseudo-code):

```ruby
# Start with 5% of users
FeatureFlag.set(:new_subscription_flow, percentage: 5)

# Monitor error rates, then increase
FeatureFlag.set(:new_subscription_flow, percentage: 25)
FeatureFlag.set(:new_subscription_flow, percentage: 50)
FeatureFlag.set(:new_subscription_flow, percentage: 100)

# Remove legacy code path
```

## Stretch Goals

- [ ] Add retry logic to PaymentGateway for transient failures
- [ ] Implement circuit breaker pattern for external API calls
- [ ] Add background job for analytics tracking (non-blocking)
- [ ] Extract mailer call to background job
- [ ] Add integration tests using VCR to record/replay HTTP requests
- [ ] Implement idempotency keys to prevent duplicate charges

## Time Estimate

25 minutes
