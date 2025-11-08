# Layering & Service Objects

## What It Is

Service objects extract complex business logic from models and controllers into dedicated classes with a single responsibility. Form objects handle input validation outside models. Policy objects encapsulate authorization logic for reuse. Presenters wrap models to add view-specific formatting without polluting domain logic.

## Why It Matters

Fat models accumulate hundreds of lines mixing persistence, validation, and business rules, making tests slow and changes risky. Controllers that orchestrate multi-step workflows become untestable and hard to refactor. Service objects isolate business logic, form objects decouple validation from persistence, and policy objects centralize authorization. Each layer has a clear boundary.

## When to Use

- Multi-step operations spanning multiple models (order checkout, user onboarding)
- Complex validation rules that don't map to database constraints
- Authorization logic reused across controllers and background jobs
- View formatting that doesn't belong in models (currency, date ranges)
- Operations that send emails, call APIs, or mix domain and infrastructure concerns

## Three Common Pitfalls

1. **Service objects calling other services:** Nesting services creates hidden dependencies and makes stack traces hard to follow. Extract shared logic into plain objects or use composition with explicit dependencies.

2. **Form objects without clear boundaries:** Using form objects for simple CRUD duplicates ActiveRecord validations and adds indirection. Reserve them for complex input with nested attributes or business validation beyond database constraints.

3. **Over-layering simple operations:** A User.create call doesn't need a service, form, and policy. Start with Rails defaults (model validations, controller authorization) and extract layers only when complexity or reuse demands it.

---

## Service Objects with Interactor

Service objects encapsulate a single business operation. The Interactor gem provides a standard interface with context and failure handling.

```ruby
# app/services/checkout_order.rb
class CheckoutOrder
  include Interactor

  def call
    validate_inventory
    charge_payment
    send_confirmation
  end

  private

  def validate_inventory
    context.fail!(error: "Out of stock") unless context.order.items_in_stock?
  end

  def charge_payment
    result = PaymentGateway.charge(context.order.total)
    context.fail!(error: "Payment declined") unless result.success?
  end

  def send_confirmation
    OrderMailer.receipt(context.order).deliver_later
  end
end

# In controller
result = CheckoutOrder.call(order: @order)
if result.success?
  redirect_to order_path(@order)
else
  flash[:error] = result.error
  render :checkout
end

```

The service coordinates steps without bloating the Order model. Each private method handles one concern.

## Form Objects with dry-validation

Form objects validate input before touching models. Useful for signup forms, wizards, or nested attributes.

```ruby
# app/forms/user_registration_form.rb
class UserRegistrationForm < Dry::Validation::Contract
  params do
    required(:email).filled(:string)
    required(:password).filled(:string)
    required(:password_confirmation).filled(:string)
    optional(:newsletter).filled(:bool)
  end

  rule(:password, :password_confirmation) do
    key.failure("must match password") if values[:password] != values[:password_confirmation]
  end
end

# In controller
form = UserRegistrationForm.new
result = form.call(params[:user])

if result.success?
  User.create!(result.to_h.except(:password_confirmation))
else
  @errors = result.errors.to_h
  render :new
end

```

The form validates without creating a User. Separates input validation from persistence.

## Policy Objects with Pundit

Policy objects answer authorization questions. Pundit conventions keep policies consistent and testable.

```ruby
# app/policies/post_policy.rb
class PostPolicy
  attr_reader :user, :post

  def initialize(user, post)
    @user = user
    @post = post
  end

  def update?
    user.admin? || post.author_id == user.id
  end

  def destroy?
    user.admin?
  end
end

# In controller
authorize @post  # raises Pundit::NotAuthorizedError if update? returns false
@post.update!(post_params)

# In background job or service
PostPolicy.new(current_user, post).update?  # no controller required

```

Policies move authorization out of callbacks and before filters, making it reusable across contexts.

## Presenters with Draper

Presenters add view-specific methods to models without touching the model class. Draper integrates with Rails helpers.

```ruby
# app/decorators/order_decorator.rb
class OrderDecorator < Draper::Decorator
  delegate_all

  def formatted_total
    h.number_to_currency(total)
  end

  def status_badge
    h.content_tag :span, status, class: "badge badge-#{status_color}"
  end

  private

  def status_color
    case status
    when "pending" then "warning"
    when "paid" then "success"
    else "secondary"
    end
  end
end

# In controller
@order = Order.find(params[:id]).decorate

# In view
<%= @order.formatted_total %>  <!-- $42.50 -->
<%= @order.status_badge %>  <!-- <span class="badge badge-success">paid</span> -->

```

View logic stays out of Order model and helper modules. The decorator wraps the model at the controller boundary.

---

## Trade-offs Box

- **Advantage:** Each layer has a single responsibility, making tests faster and changes safer.
- **Cost:** More files and indirection; simple CRUD operations become harder to trace.
- **When to skip:** Single-model validations, basic CRUD, operations with no cross-cutting concerns.

---

## Debugging Checklist

When layered code breaks, check:

1. Service context failures: `result.failure?` and `result.error` show where the chain broke
2. Form validation errors: `result.errors.to_h` lists field-specific failures
3. Policy denials: Logs show which policy method returned false
4. Decorator method errors: Check if the underlying model has the delegated attribute
5. Layer boundaries: Confirm services don't call other services; forms don't save models directly

---

## One-Minute Recap

- Service objects isolate multi-step business operations from models and controllers
- Form objects validate input without touching persistence or model callbacks
- Policy objects centralize authorization for reuse across controllers and jobs
- Presenters wrap models to add view formatting without polluting domain logic
- Extract layers only when complexity or reuse justifies the indirection
