# Error Tracking Mental Model

## What It Is
Error tracking services (Sentry, Rollbar, Honeybadger) capture exceptions from production applications, group similar errors via fingerprinting, and provide context (stack traces, user data, request params). They automatically detect new errors, track resolution status, and integrate with deployment pipelines to correlate errors with code releases. Error tracking converts noisy exception logs into actionable incident reports.

## Why It Matters
Application logs mix errors with normal requests, making it hard to spot new failures. Error trackers surface critical issues immediately via alerts and group thousands of identical errors into single issues to prevent alert fatigue. Adding context (user_id, request_id, environment variables) connects errors to specific users or deployments for faster debugging. Release tracking identifies which deploy introduced a regression.

## When to Use
- Monitoring production exceptions without SSH access or log grep
- Tracking error frequency trends and detecting new exception types
- Connecting errors to specific users, tenants, or feature flags
- Identifying which deploy or code change introduced a bug
- Prioritizing fixes based on error volume and affected users

## Three Common Pitfalls
1. **Tracking too many errors:** Logging validation errors or expected exceptions (404s, authentication failures) creates noise. Use before_send callbacks to filter routine errors and focus on unexpected failures.
2. **Missing critical context:** Errors without user_id, request_id, or custom tags are hard to reproduce. Configure context in initializers and controllers to include tenant, feature flags, and experiment variants.
3. **Alert fatigue:** Sending Slack/email for every error trains teams to ignore alerts. Set thresholds (10 errors in 5 minutes) or alert only on new error types to maintain urgency.

---

## Error Tracking Service Integration

Install and configure Sentry:

```ruby
# Gemfile
gem 'sentry-ruby'
gem 'sentry-rails'

# config/initializers/sentry.rb
Sentry.init do |config|
  config.dsn = ENV['SENTRY_DSN']
  config.environment = Rails.env
  config.enabled_environments = %w[production staging]

  # Set release version for deploy tracking
  config.release = ENV['GIT_COMMIT_SHA'] || 'unknown'

  # Sample rate: send 10% of events in high-traffic apps
  config.traces_sample_rate = 0.1
end

```

Sentry now captures all unhandled exceptions automatically.

---

## Adding Context to Errors

Enrich errors with user and request data:

```ruby
# app/controllers/application_controller.rb
class ApplicationController < ActionController::Base
  before_action :set_sentry_context

  private

  def set_sentry_context
    Sentry.set_user(
      id: current_user&.id,
      email: current_user&.email,
      username: current_user&.username
    )

    Sentry.set_tags(
      tenant_id: current_tenant&.id,
      feature_flag: experiment_variant,
      locale: I18n.locale
    )

    Sentry.set_context(:request_details, {
      request_id: request.request_id,
      ip: request.remote_ip,
      user_agent: request.user_agent
    })
  end
end

```

Every error now includes user, tenant, and request metadata for debugging.

---

## Manual Error Reporting

Capture exceptions in rescue blocks:

```ruby
def process_payment(order)
  PaymentGateway.charge(order.total)
rescue PaymentGateway::NetworkError => e
  Sentry.capture_exception(e, extra: {
    order_id: order.id,
    amount: order.total,
    payment_method: order.payment_method
  })
  raise
end

```

Send custom messages for non-exception issues:

```ruby
if inventory.stock < order.quantity
  Sentry.capture_message(
    "Insufficient inventory",
    level: :warning,
    extra: {
      product_id: inventory.product_id,
      requested: order.quantity,
      available: inventory.stock
    }
  )
end

```

---

## Error Grouping and Fingerprinting

Sentry groups errors by stack trace similarity. Customize grouping:

```ruby
Sentry.init do |config|
  config.before_send = lambda do |event, hint|
    # Group all timeouts together regardless of endpoint
    if hint[:exception].is_a?(Timeout::Error)
      event.fingerprint = ['timeout-error']
    end

    # Group by custom business logic
    if hint[:exception].message.include?('Payment failed')
      event.fingerprint = ['payment-failure', event.tags[:payment_method]]
    end

    event
  end
end

```

Custom fingerprints prevent one issue from creating dozens of separate alerts.

---

## Release Tracking

Connect errors to deployments:

```ruby
# config/initializers/sentry.rb
Sentry.init do |config|
  config.release = ENV.fetch('HEROKU_SLUG_COMMIT', 'dev')
  config.environment = ENV.fetch('RAILS_ENV', 'development')
end

```

In deployment script:

```bash
# Notify Sentry of new release
curl https://sentry.io/api/0/organizations/my-org/releases/ \
  -H "Authorization: Bearer $SENTRY_AUTH_TOKEN" \
  -d '{"version":"'"$GIT_COMMIT"'","projects":["my-app"]}'

```

Sentry dashboard shows which release introduced each error.

---

## Filtering Routine Errors

Reduce noise by skipping expected errors:

```ruby
Sentry.init do |config|
  config.before_send = lambda do |event, hint|
    exception = hint[:exception]

    # Skip validation errors
    return nil if exception.is_a?(ActiveRecord::RecordInvalid)

    # Skip common HTTP errors
    return nil if exception.is_a?(ActionController::RoutingError)
    return nil if event.request&.path == '/health'

    event
  end

  # Breadcrumbs help debug but increase data sent
  config.breadcrumbs_logger = [:active_support_logger]
end

```

---

## Trade-offs Box
- **Advantage:** Error trackers group thousands of identical errors into single issues and alert on new exception types immediately.
- **Cost:** Adds third-party dependency; high-traffic apps may need sampling to stay within plan limits.
- **When to skip:** For internal tools with <100 users, exception logging to files may suffice; error trackers shine at scale (1000+ daily active users).

---

## Debugging Checklist

When errors aren't appearing in tracker:

1. Verify DSN configured: `Sentry.configuration.dsn.present?`
2. Check environment enabled: `Sentry.configuration.enabled_environments`
3. Test manually: `Sentry.capture_message('test')` in console
4. Review before_send filters: Ensure they don't return nil
5. Check internet connectivity: Sentry requires outbound HTTPS
6. Inspect event sampling: `traces_sample_rate` may drop events
7. Verify exception not rescued globally: Check ApplicationController
8. Review rate limits: Sentry may throttle high-volume apps

---

## One-Minute Recap
- Error trackers (Sentry, Rollbar, Honeybadger) capture exceptions with context instead of mixing them into logs
- Add user_id, tenant_id, and request_id via before_action for debugging context
- Fingerprinting groups similar errors to prevent duplicate alerts
- Release tracking connects errors to specific deploys via git commit SHA
- Filter routine errors (validations, 404s) with before_send callbacks to prevent alert fatigue
