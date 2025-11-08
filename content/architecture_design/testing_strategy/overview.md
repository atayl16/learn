# Testing Strategy (Unit/Request/System)

## What It Is

A testing strategy defines the ratio and focus of unit tests (isolated classes), request tests (HTTP endpoints without JavaScript), and system tests (full browser workflows). The test pyramid recommends many fast unit tests, fewer request tests, and minimal slow system tests. FactoryBot generates test data, VCR records HTTP interactions, and SimpleCov measures coverage.

## Why It Matters

A test suite with only system tests takes 20+ minutes to run and fails with cryptic browser errors. A suite with only unit tests misses integration bugs between models, controllers, and external APIs. Balancing test types catches bugs at the right layer: unit tests verify logic, request tests confirm endpoints work, system tests validate user flows.

## When to Use

- Unit tests for models, services, and POROs with clear inputs and outputs
- Request tests for API endpoints, JSON responses, and controller authorization
- System tests for critical user flows (signup, checkout) involving JavaScript
- VCR for tests hitting external APIs (payment gateways, webhooks)
- Factories when tests need customized data; fixtures for shared static data

## Three Common Pitfalls

1. **Testing everything through the UI:** System tests are 10-100x slower than unit tests and fail with vague errors ("element not found"). Test business logic in unit tests and reserve system tests for integration smoke tests of critical paths.

2. **Stubbing internal methods:** Stubbing private methods or ActiveRecord queries couples tests to implementation and breaks on refactors. Stub external dependencies (HTTP, file system) but test internal behavior through public interfaces.

3. **Ignoring test speed:** A 10-minute suite discourages running tests before commits. Profile with `rspec --profile 10`, move slow tests to a nightly build, or refactor factory usage to reduce database writes.

---

## The Test Pyramid

The pyramid guides test ratios: 70% unit, 20% request, 10% system.

```ruby
# Unit test: fast, isolated, no database
RSpec.describe OrderCalculator do
  it "applies discount to subtotal" do
    calculator = OrderCalculator.new(subtotal: 100, discount_percent: 10)
    expect(calculator.total).to eq(90)
  end
end

# Request test: hits controller, touches database
RSpec.describe "POST /orders", type: :request do
  it "creates an order and returns JSON" do
    post "/orders", params: { order: { item_id: 1, quantity: 2 } }
    expect(response).to have_http_status(:created)
    expect(Order.count).to eq(1)
  end
end

# System test: full browser, JavaScript enabled
RSpec.describe "checkout flow", type: :system do
  it "completes purchase with Stripe" do
    visit "/checkout"
    fill_in "Card number", with: "4242424242424242"
    click_button "Pay"
    expect(page).to have_content("Order complete")
  end
end
```

Unit tests run in milliseconds. Request tests take seconds. System tests take 10+ seconds each.

## Factories vs Fixtures

FactoryBot generates customizable test data. Fixtures load static YAML into the database.

```ruby
# spec/factories/users.rb
FactoryBot.define do
  factory :user do
    email { Faker::Internet.email }
    password { "password123" }

    trait :admin do
      role { "admin" }
    end
  end
end

# In test
user = create(:user)  # writes to database
admin = build(:user, :admin)  # no database write
```

Use factories for tests requiring specific attributes. Use fixtures for shared reference data (countries, currencies) loaded once per suite.

## Stubbing HTTP with VCR

VCR records HTTP requests and replays them in tests, avoiding rate limits and flaky network calls.

```ruby
# spec/support/vcr.rb
VCR.configure do |config|
  config.cassette_library_dir = "spec/fixtures/vcr_cassettes"
  config.hook_into :webmock
  config.filter_sensitive_data("<API_KEY>") { ENV["STRIPE_KEY"] }
end

# In test
RSpec.describe StripePaymentService do
  it "charges a card", :vcr do
    result = StripePaymentService.charge(amount: 1000, token: "tok_visa")
    expect(result.success?).to be true
  end
end
```

First run records the request to `spec/fixtures/vcr_cassettes/`. Subsequent runs replay it instantly. The `:vcr` tag wraps the test in a cassette.

## WebMock for Stubbing

WebMock stubs HTTP without recording real responses. Useful for error scenarios VCR can't capture.

```ruby
RSpec.describe WeatherService do
  it "handles API timeouts" do
    stub_request(:get, "https://api.weather.com/current")
      .to_timeout

    expect {
      WeatherService.current_temperature
    }.to raise_error(Net::OpenTimeout)
  end

  it "parses successful responses" do
    stub_request(:get, "https://api.weather.com/current")
      .to_return(status: 200, body: { temp: 72 }.to_json)

    expect(WeatherService.current_temperature).to eq(72)
  end
end
```

WebMock gives full control over response bodies, status codes, and network errors.

## System Tests with Capybara

Capybara drives a headless browser (Selenium, Cuprite) to test JavaScript interactions.

```ruby
# spec/system/checkout_spec.rb
RSpec.describe "checkout", type: :system do
  before do
    driven_by(:selenium_chrome_headless)
  end

  it "calculates total with JavaScript" do
    visit "/checkout"
    fill_in "Quantity", with: "3"
    expect(page).to have_content("Total: $30.00")  # updated via JS
  end
end
```

System tests are slow. Limit them to critical user flows and use request tests for API coverage.

## Test Coverage with SimpleCov

SimpleCov reports line coverage but doesn't measure test quality.

```ruby
# spec/spec_helper.rb
require "simplecov"
SimpleCov.start "rails" do
  add_filter "/spec/"
  add_filter "/config/"
end

# After running tests
# open coverage/index.html
```

Aim for 80%+ coverage on models and services. Skip coverage for views and configuration. High coverage doesn't guarantee bug-free code; it shows untested areas.

---

## Trade-offs Box

- **Advantage:** Balanced test types catch bugs at the right layer and run in minutes, not hours.
- **Cost:** Maintaining VCR cassettes and system tests requires setup; factories add indirection over fixtures.
- **When to skip:** Skip system tests for API-only apps; skip VCR if you control the external service and can use test mode.

---

## Debugging Checklist

When tests fail or slow down, check:

1. Test timing: Run `rspec --profile 10` to find the slowest examples
2. Factory usage: Count database writes with `ActiveRecord::Base.connection.query_cache.size` in tests
3. VCR cassettes: Delete and re-record if API behavior changed
4. WebMock conflicts: Ensure WebMock stubs don't overlap with VCR cassettes
5. System test screenshots: Check `tmp/screenshots/` for failure artifacts
6. Coverage gaps: Review SimpleCov report for untested conditional branches

---

## One-Minute Recap

- Test pyramid: 70% unit tests (fast, isolated), 20% request tests (endpoints), 10% system tests (browser flows)
- Use FactoryBot for customizable test data; use fixtures for static reference data
- VCR records HTTP interactions; WebMock stubs without recording
- System tests with Capybara validate JavaScript flows but run 10-100x slower than unit tests
- SimpleCov measures coverage; aim for 80%+ on models and services, skip views and config
