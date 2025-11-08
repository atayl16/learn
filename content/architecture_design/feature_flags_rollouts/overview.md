# Feature Flags & Safe Rollouts

## What It Is

Feature flags toggle code paths at runtime without redeploying. Flipper and Unleash provide APIs to enable features for specific users, percentages, or groups. Rollout strategies (gradual percentage, beta users, admin-only) let you test features in production with limited risk. Flag cleanup removes old toggles once features are stable.

## Why It Matters

Deploying a new feature to all users risks site-wide failures. Feature flags let you deploy code behind a toggle, enable it for 5% of users, monitor errors, and roll back instantly without re-deploying. Flags decouple deployment from release, allow testing in production with real traffic, and enable A/B tests and gradual rollouts.

## When to Use

- Large features that need gradual rollout (new checkout flow, redesigned dashboard)
- Risky changes to critical paths (payment processing, authentication)
- A/B testing different implementations (algorithm variations, UI experiments)
- Kill switches to disable features without redeploying if errors spike
- Beta programs where specific users test new functionality

## Three Common Pitfalls

1. **Forgetting to remove old flags:** Dead flags accumulate in code, adding complexity and confusion. Set expiration dates in flag metadata and run regular audits to delete flags after full rollout.

2. **Over-flagging trivial changes:** Wrapping every change in a flag increases branching complexity and test burden. Reserve flags for risky or large features, not typo fixes or style tweaks.

3. **Ignoring flag state in tests:** Tests passing with flags on/off in different combinations ensures coverage. Test both branches or default to one state in CI, documenting the assumption.

---

## Feature Flags with Flipper

Flipper stores flag state in Redis, Postgres, or memory and checks if a feature is enabled for an actor.

```ruby
# config/initializers/flipper.rb
require "flipper"
require "flipper/adapters/active_record"

Flipper.configure do |config|
  config.default do
    adapter = Flipper::Adapters::ActiveRecord.new
    Flipper.new(adapter)
  end
end

# In controller
if Flipper.enabled?(:new_checkout, current_user)
  render :new_checkout
else
  render :old_checkout
end

```

Flipper checks `current_user` against the flag's rules. If enabled, the new path runs.

## Enabling for Percentages

Rollout to 10% of users randomly to catch issues before full release.

```ruby
# In Rails console or admin UI
Flipper.enable_percentage_of_actors(:new_checkout, 10)

# Affects 10% of users deterministically (same user always sees same state)
Flipper.enabled?(:new_checkout, current_user)

```

Increase percentage as confidence grows: 10% → 25% → 50% → 100%.

## Enabling for User Segments

Enable for specific groups: beta testers, admins, or paying customers.

```ruby
# Define a group
Flipper.register(:admins) do |actor|
  actor.respond_to?(:admin?) && actor.admin?
end

# Enable for group
Flipper.enable_group(:new_checkout, :admins)

# Check returns true for admins
Flipper.enabled?(:new_checkout, current_user)

```

Groups let you dogfood features internally before public launch.

## Enabling for Individual Users

Enable for specific test accounts or high-value customers.

```ruby
# Enable for one user
Flipper.enable_actor(:new_checkout, User.find(123))

# Check
Flipper.enabled?(:new_checkout, current_user)  # true if current_user.id == 123

```

Useful for debugging production issues with specific accounts.

## Monitoring Flagged Features

Track metrics separately for flag-on vs flag-off users to detect regressions.

```ruby
# Instrument flag usage
if Flipper.enabled?(:new_checkout, current_user)
  StatsD.increment("checkout.new.started")
  render :new_checkout
else
  StatsD.increment("checkout.old.started")
  render :old_checkout
end

```

Compare error rates, conversion rates, and latency between branches. If the new branch degrades, disable the flag instantly.

## Testing with Flags

Test both branches to ensure coverage.

```ruby
RSpec.describe CheckoutController do
  context "with new checkout flag" do
    before { Flipper.enable(:new_checkout) }

    it "renders new template" do
      get :show
      expect(response).to render_template(:new_checkout)
    end
  end

  context "without new checkout flag" do
    before { Flipper.disable(:new_checkout) }

    it "renders old template" do
      get :show
      expect(response).to render_template(:old_checkout)
    end
  end
end

```

Alternatively, default flags to one state in CI and document that the other branch is tested manually or in staging.

## Cleaning Up Old Flags

Once a feature is fully rolled out, remove the flag to reduce complexity.

```ruby
# Before cleanup
if Flipper.enabled?(:new_checkout, current_user)
  render :new_checkout
else
  render :old_checkout
end

# After cleanup (flag permanently enabled)
render :new_checkout

```

Delete the flag from Flipper, remove conditional logic, and delete the old code path. Set a reminder (30 days post-launch) to clean up.

## Unleash as an Alternative

Unleash provides a UI, SDKs, and advanced strategies (gradual rollout, custom constraints).

```ruby
# config/initializers/unleash.rb
UNLEASH = Unleash::Client.new(
  url: "https://unleash.example.com/api",
  app_name: "rails-app"
)

# In controller
if UNLEASH.is_enabled?("new_checkout", user_id: current_user.id)
  render :new_checkout
else
  render :old_checkout
end

```

Unleash adds an admin UI for non-engineers to toggle flags, useful for product managers running experiments.

---

## Trade-offs Box

- **Advantage:** Deploy risky features incrementally, monitor errors per segment, and roll back instantly without code changes.
- **Cost:** Flag checks add branching complexity; dead flags accumulate if not cleaned up; testing requires both branches.
- **When to skip:** Skip flags for trivial changes, internal tools with no user impact, or one-time scripts.

---

## Debugging Checklist

When flags behave unexpectedly, check:

1. Flag state in admin UI or console: `Flipper[:new_checkout].actors_value` shows enabled actors
2. Actor identity: Confirm `current_user.flipper_id` matches expected format
3. Percentage logic: Same user should see same state; use `Flipper.enabled?` directly to test
4. Group registration: Ensure groups are registered in an initializer before checks run
5. Cache inconsistency: If using Redis, flush cache or check TTL on flag keys
6. Test flag state: Confirm `Flipper.disable(:new_checkout)` runs before flag-off tests

---

## One-Minute Recap

- Feature flags decouple deployment from release, enabling gradual rollouts and instant rollback
- Flipper and Unleash provide percentage, group, and actor-based enabling strategies
- Monitor flagged features separately to detect regressions before full launch
- Test both flag-on and flag-off branches or document one branch as the default
- Clean up flags 30 days post-launch to prevent complexity from accumulating
