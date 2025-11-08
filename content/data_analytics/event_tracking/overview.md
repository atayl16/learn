# Event Tracking & Analytics

## What It Is

Event tracking captures user interactions (clicks, page views, purchases) as structured data points with consistent schemas. Each event contains a name, timestamp, user identifier, and custom properties. Ahoy is a Rails gem for first-party tracking; Segment is a third-party integration hub that routes events to analytics tools (Mixpanel, Amplitude, Google Analytics). Client-side JavaScript tracking fires events from browsers; server-side tracking records events from controllers or background jobs.

## Why It Matters

Product decisions require data on how users actually behave, not assumptions. Event tracking answers questions like "What percentage of users complete checkout?" or "Which features drive retention?" Funnels reveal drop-off points in multi-step workflows. Without structured schemas, events become inconsistent (user_id vs userId) and queries break. GDPR compliance requires consent management, data deletion, and anonymization. Production analytics is table stakes for data-driven teams.

## When to Use

- Building conversion funnels (signup → activation → purchase)
- A/B testing feature variants and measuring impact
- Tracking feature adoption across user segments
- Debugging user-reported issues with session replays
- Generating product dashboards and reports
- Meeting compliance requirements (GDPR, CCPA)

## Three Common Pitfalls

1. **Inconsistent event schemas:** Developers add properties ad-hoc without a naming convention, creating events like `user_signup` and `UserSignedUp` with different property names. Establish a schema registry and lint events before they reach production.
2. **Client-side only tracking:** Ad blockers and browser extensions block JavaScript tracking, causing 20-30% data loss. Use server-side tracking for critical business events (purchases, subscriptions) that must be accurate.
3. **Missing GDPR consent:** Tracking users before consent violates GDPR and risks fines. Implement consent banners, respect Do Not Track, and provide data deletion endpoints. Use session storage instead of cookies before consent.

---

## Event Schema Design

Define consistent naming and property types:

```ruby
# Good: Consistent snake_case schema
{
  event: "order_completed",
  user_id: 123,
  properties: {
    order_id: "abc123",
    total_cents: 4999,
    item_count: 3,
    currency: "USD"
  },
  timestamp: "2025-01-15T10:23:45Z"
}

# Bad: Inconsistent naming and types
{
  event: "OrderComplete",
  userID: "123",
  total: "$49.99",  # String instead of integer
  items: "3"        # String instead of integer
}

```

Use an event catalog to document every event name and property. Tools like Avo, Iteratively, or a simple YAML file enforce consistency.

---

## Client-Side vs Server-Side Tracking

**Client-side JavaScript** fires events from user browsers:

```javascript
// Using Segment.js
analytics.track('Button Clicked', {
  button_name: 'signup',
  page: '/pricing'
});

```

**Advantages:** Captures DOM interactions, page views, and client context (screen size, browser).

**Disadvantages:** Blocked by ad blockers; unreliable for critical events.

**Server-side Rails** tracks events from controllers:

```ruby
# app/controllers/orders_controller.rb
def create
  @order = current_user.orders.create!(order_params)

  Analytics.track(
    user_id: current_user.id,
    event: 'order_completed',
    properties: {
      order_id: @order.id,
      total_cents: @order.total_cents
    }
  )
end

```

**Advantages:** Cannot be blocked; accurate for business metrics; no PII in browser.

**Disadvantages:** Misses client-side interactions like hovers and scrolling.

**Best practice:** Use server-side for revenue events, client-side for engagement metrics.

---

## Building Funnels

Funnels measure conversion through multi-step flows:

```ruby
# Track funnel steps
class CheckoutController < ApplicationController
  def start
    track_event('checkout_started', cart_value: current_cart.total)
  end

  def add_shipping
    track_event('shipping_info_added', shipping_method: params[:method])
  end

  def add_payment
    track_event('payment_info_added')
  end

  def complete
    track_event('order_completed', order_id: @order.id)
  end

  private

  def track_event(name, properties = {})
    Analytics.track(
      user_id: current_user&.id || session[:anonymous_id],
      event: name,
      properties: properties
    )
  end
end

```

Analyze with SQL or tools:

```sql
-- Calculate funnel drop-off
SELECT
  COUNT(DISTINCT CASE WHEN event = 'checkout_started' THEN user_id END) as started,
  COUNT(DISTINCT CASE WHEN event = 'shipping_info_added' THEN user_id END) as added_shipping,
  COUNT(DISTINCT CASE WHEN event = 'order_completed' THEN user_id END) as completed
FROM events
WHERE timestamp > NOW() - INTERVAL '7 days';

```

Mixpanel and Amplitude provide funnel UIs that calculate conversion rates automatically.

---

## Ahoy Integration

Ahoy provides first-party tracking with visit and event models:

```ruby
# Gemfile
gem 'ahoy_matey'

# Install
rails generate ahoy:install
rails db:migrate

# Track events in controllers
ahoy.track "Product Viewed", product_id: @product.id

# Query events
Ahoy::Event.where(name: "Product Viewed").where("properties->>'product_id' = ?", "123")

# Track visits
Ahoy::Visit.where(user: current_user).last

```

Ahoy stores data in PostgreSQL JSONB columns, enabling fast queries. It respects Do Not Track headers and provides data deletion for GDPR.

---

## Segment/Mixpanel Integration

**Segment** routes events to multiple destinations:

```ruby
# Gemfile
gem 'analytics-ruby'

# config/initializers/segment.rb
Analytics = Segment::Analytics.new(
  write_key: ENV['SEGMENT_WRITE_KEY']
)

# Track event
Analytics.track(
  user_id: current_user.id,
  event: 'Order Completed',
  properties: { revenue: 49.99 }
)

```

**Mixpanel** analyzes user behavior and retention:

```ruby
# Gemfile
gem 'mixpanel-ruby'

# config/initializers/mixpanel.rb
$mixpanel = Mixpanel::Tracker.new(ENV['MIXPANEL_TOKEN'])

# Track event
$mixpanel.track(current_user.id, 'Order Completed', revenue: 49.99)

# Set user properties
$mixpanel.people.set(current_user.id, {
  '$email': current_user.email,
  'plan': 'premium'
})

```

Both tools provide dashboards, funnels, and retention cohorts without writing SQL.

---

## GDPR Considerations

Comply with privacy regulations:

1. **Obtain consent before tracking:**

```ruby
# Only track if consent given
if cookies[:analytics_consent] == 'true'
  ahoy.track("Page Viewed", path: request.path)
end

```

2. **Anonymize IP addresses:**

```ruby
# config/initializers/ahoy.rb
Ahoy.mask_ips = true

```

3. **Provide data deletion:**

```ruby
# app/controllers/privacy_controller.rb
def delete_data
  user = current_user
  Ahoy::Event.where(user: user).delete_all
  Ahoy::Visit.where(user: user).delete_all
  render json: { success: true }
end

```

4. **Store minimal PII:** Use hashed user IDs instead of emails in events.

5. **Set data retention policies:** Delete events older than required period.

---

## Trade-offs Box

- **Advantage:** Event tracking quantifies user behavior for data-driven decisions and reveals product usage patterns invisible in server logs.
- **Cost:** Schema drift creates inconsistent data; third-party tools add vendor dependencies and monthly costs; compliance overhead requires consent management.
- **When to skip:** Internal tools with < 10 users; prototypes where iteration speed matters more than metrics; apps with strict zero-tracking privacy requirements.

---

## Debugging Checklist

When events are missing or incorrect:

1. Check event name spelling: `Ahoy::Event.pluck(:name).uniq`
2. Verify user_id is set: `Ahoy::Event.where(user_id: nil).count`
3. Inspect event properties: `Ahoy::Event.last.properties`
4. Check ad blocker status: Test in incognito mode
5. Verify API keys: `ENV['SEGMENT_WRITE_KEY']` is set
6. Test with curl: Send test event to API endpoint
7. Check rate limits: Third-party APIs may throttle
8. Review consent state: Confirm tracking is enabled for user

---

## One-Minute Recap

- Event tracking captures user actions as structured data with consistent schemas (name, timestamp, properties)
- Client-side tracking captures browser interactions but is blocked by ad blockers; server-side is reliable for business metrics
- Funnels measure conversion through multi-step flows and identify drop-off points
- Ahoy provides first-party tracking in Rails; Segment routes events to multiple analytics tools
- GDPR requires consent management, IP anonymization, data deletion, and minimal PII storage
