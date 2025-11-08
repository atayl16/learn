# Exercise: Layering & Service Objects

## Objective

Refactor a fat model and controller into service, form, and policy objects with clear boundaries.

## Task

You have an `Order` model with a `complete!` method that validates inventory, charges payment, sends email, and updates status. The `OrdersController#create` action has 30 lines of nested logic. Extract this into layers:

1. Create a service object `CompleteOrder` that orchestrates the checkout flow
2. Build a form object `OrderCheckoutForm` that validates order params (items, shipping address, payment method)
3. Add a policy object `OrderPolicy` that checks if the current user can complete orders (must be the order owner or admin)
4. Create a presenter `OrderDecorator` that formats `total` as currency and renders a status badge

Use the Interactor gem for services, dry-validation for forms, Pundit for policies, and Draper for decorators.

## Acceptance Criteria

- [ ] Service object handles checkout in a single `call` method with private step methods
- [ ] Service fails gracefully with `context.fail!` if inventory or payment fails
- [ ] Form object validates presence of items, shipping address, and payment method before the service runs
- [ ] Policy object returns false for users who don't own the order (unless admin)
- [ ] Decorator adds `formatted_total` and `status_badge` methods without modifying the Order model
- [ ] Controller is under 10 lines: authorize, validate form, call service, handle result

## Verification Steps

1. Run `rspec spec/services/complete_order_spec.rb` and confirm all service steps are tested
2. Test form validation: `OrderCheckoutForm.new.call({}).failure?` returns true
3. Check policy: `OrderPolicy.new(other_user, order).complete?` returns false
4. In Rails console, call `Order.first.decorate.formatted_total` and see `"$42.50"`

## Stretch (Optional)

Add an organizer that chains multiple interactors: validate inventory, charge payment, send email as separate interactor classes using `Interactor::Organizer`.

## Time Estimate

22 minutes
