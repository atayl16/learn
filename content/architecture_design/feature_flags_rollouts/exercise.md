# Exercise: Feature Flags & Safe Rollouts

## Objective

Implement a feature flag with Flipper, roll it out gradually, and monitor both branches.

## Task

You're launching a new recommendation algorithm for product suggestions. The feature is risky and needs gradual rollout:

1. Install Flipper and configure it with ActiveRecord adapter
2. Add a feature flag called `:new_recommendations` in the `ProductsController`
3. Enable the flag for 10% of users initially
4. Create a Flipper group called `:beta_testers` and enable the flag for that group
5. Add instrumentation to track `StatsD.increment("recommendations.new.shown")` and `StatsD.increment("recommendations.old.shown")`
6. Write RSpec tests for both flag-on and flag-off states
7. After 7 days (simulated), remove the flag and delete the old code path

## Acceptance Criteria

- [ ] Flipper is initialized and storing flags in the database
- [ ] `:new_recommendations` flag controls which recommendation logic runs
- [ ] 10% of users see the new algorithm (same user always sees same version)
- [ ] Beta testers always see the new algorithm regardless of percentage
- [ ] Both branches emit separate StatsD metrics
- [ ] Tests cover both branches with `Flipper.enable` and `Flipper.disable`

## Verification Steps

1. In Rails console, run `Flipper.enable_percentage_of_actors(:new_recommendations, 10)` and check `Flipper[:new_recommendations].percentage_of_actors_value` returns 10
2. Load the page multiple times with the same user and confirm they see consistent results
3. Enable `:beta_testers` group and confirm test user in that group always sees new algorithm
4. Run `rspec spec/controllers/products_controller_spec.rb` and confirm both flag states are tested

## Stretch (Optional)

Add a Rake task that lists all feature flags and their current state, flagging any older than 60 days as "needs cleanup."

## Time Estimate

21 minutes
