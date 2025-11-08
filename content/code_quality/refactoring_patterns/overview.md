# Refactoring Patterns in Rails

## What It Is
Refactoring is the disciplined practice of restructuring code without changing its external behavior. In Rails, common refactoring patterns include Extract Service Object (moving business logic from controllers/models into dedicated classes), Replace Conditional with Polymorphism (substituting complex if/case statements with object-oriented designs), and Extract Method (breaking down long methods into smaller, named chunks). The goal is improving code readability, maintainability, and testability while preserving functionality.

## Why It Matters
Rails applications naturally accumulate complexity: controllers grow fat with business logic, models balloon with callbacks and validations, conditionals proliferate. Refactoring patterns prevent this decay. Extract Service keeps controllers thin by moving multi-step workflows (payment processing, report generation) into testable service objects. Replace Conditional with Polymorphism eliminates switch statements by leveraging inheritance or strategy patterns, making code extensible. Following SOLID principles—Single Responsibility, Open/Closed, Liskov Substitution, Interface Segregation, Dependency Inversion—ensures classes remain focused, flexible, and maintainable. Refactoring with tests guarantees you don't break functionality.

## When to Use
- Fat controllers exceeding 50 lines or handling multiple responsibilities
- Models with 10+ public methods or complex business logic unrelated to persistence
- Nested conditionals (if/elsif/case) that span 20+ lines or handle polymorphic behavior
- Duplicated code across controllers or models
- Before adding new features to legacy code (refactor first, then extend)
- When tests become hard to write due to tight coupling

## Three Common Pitfalls
1. **Refactoring without tests:** Changing code without test coverage risks silent breakage. Always write characterization tests before refactoring legacy code.
2. **Over-engineering:** Extracting every method into a service object or creating inheritance hierarchies for simple conditionals adds unnecessary abstraction. Refactor when pain is real, not preemptively.
3. **Big bang refactors:** Rewriting entire controllers or models in one PR makes code review impossible and introduces risk. Refactor incrementally: extract one service, fix one conditional, commit, repeat.

---

## Extract Service Object

Move complex business logic from controllers or models into Plain Old Ruby Objects (POROs):

**Before (Fat Controller):**

```ruby
class OrdersController < ApplicationController
  def create
    @order = Order.new(order_params)
    if @order.save
      @order.line_items.each { |item| InventoryService.decrement(item) }
      PaymentGateway.charge(@order.total, @order.payment_token)
      OrderMailer.confirmation(@order).deliver_later
      Analytics.track("order_created", @order.id)
      redirect_to @order, notice: "Order placed!"
    else
      render :new
    end
  end
end
```

**After (Service Object):**

```ruby
class OrderCreationService
  def initialize(order_params)
    @order_params = order_params
  end

  def call
    order = Order.new(@order_params)
    return ServiceResult.failure(order.errors) unless order.save

    decrement_inventory(order)
    charge_payment(order)
    send_confirmation(order)
    track_analytics(order)

    ServiceResult.success(order)
  end

  private

  def decrement_inventory(order)
    order.line_items.each { |item| InventoryService.decrement(item) }
  end

  def charge_payment(order)
    PaymentGateway.charge(order.total, order.payment_token)
  end

  def send_confirmation(order)
    OrderMailer.confirmation(order).deliver_later
  end

  def track_analytics(order)
    Analytics.track("order_created", order.id)
  end
end

class OrdersController < ApplicationController
  def create
    result = OrderCreationService.new(order_params).call
    if result.success?
      redirect_to result.value, notice: "Order placed!"
    else
      @order = Order.new(order_params)
      @order.errors.merge!(result.errors)
      render :new
    end
  end
end
```

**Benefits:**
- Controller stays thin (Single Responsibility)
- Service is easily testable in isolation
- Business logic is reusable (console scripts, background jobs)

---

## Replace Conditional with Polymorphism

Eliminate complex conditionals by delegating to subclasses or strategy objects:

**Before:**

```ruby
class InvoiceGenerator
  def generate(invoice)
    case invoice.type
    when "standard"
      apply_standard_discount(invoice)
    when "nonprofit"
      apply_nonprofit_discount(invoice)
    when "enterprise"
      apply_enterprise_discount(invoice)
    end
  end
end
```

**After (Strategy Pattern):**

```ruby
class InvoiceGenerator
  def generate(invoice)
    DiscountStrategy.for(invoice.type).apply_discount(invoice)
  end
end

class DiscountStrategy
  def self.for(type)
    { "standard" => StandardDiscount,
      "nonprofit" => NonprofitDiscount,
      "enterprise" => EnterpriseDiscount }[type].new
  end
end

class StandardDiscount
  def apply_discount(invoice)
    invoice.total *= 0.95
  end
end
```

**Benefits:**
- Adding new types requires new classes, not modifying existing code (Open/Closed Principle)
- Each strategy is independently testable

---

## Extract Method

Break long methods into smaller, well-named chunks:

**Before:**

```ruby
def process_payment(order)
  # Validate
  raise "Invalid amount" if order.total <= 0
  raise "Missing token" if order.payment_token.blank?

  # Charge
  response = PaymentGateway.charge(order.total, order.payment_token)
  raise "Payment failed" unless response.success?

  # Record
  order.update!(paid_at: Time.current, transaction_id: response.id)
end
```

**After:**

```ruby
def process_payment(order)
  validate_payment(order)
  response = charge_card(order)
  record_transaction(order, response)
end

private

def validate_payment(order)
  raise "Invalid amount" if order.total <= 0
  raise "Missing token" if order.payment_token.blank?
end

def charge_card(order)
  response = PaymentGateway.charge(order.total, order.payment_token)
  raise "Payment failed" unless response.success?
  response
end

def record_transaction(order, response)
  order.update!(paid_at: Time.current, transaction_id: response.id)
end
```

---

## SOLID Principles

- **Single Responsibility:** Each class does one thing (controllers route, models persist, services orchestrate)
- **Open/Closed:** Extend via new classes, not by modifying existing code
- **Liskov Substitution:** Subclasses substitute for base classes
- **Interface Segregation:** Prefer small, focused interfaces
- **Dependency Inversion:** Depend on abstractions, not implementations

---

## Refactoring with Tests

**Golden Rule:** Never refactor without tests.

1. **Write characterization tests** capturing current behavior:

```ruby
RSpec.describe OrderCreationService do
  it "creates order, charges card, sends email" do
    result = OrderCreationService.new(valid_params).call
    expect(result).to be_success
    expect(Order.count).to eq(1)
    expect(PaymentGateway).to have_received(:charge)
  end
end
```

2. **Refactor incrementally:** Extract one method, run tests, commit.
3. **Improve tests:** Write unit tests for each extracted class.

---

## Trade-offs
- **Advantage:** Cleaner, testable, maintainable code; easier onboarding for new developers.
- **Cost:** More files and indirection; can obscure flow if over-abstracted.
- **When to skip:** Simple CRUD actions rarely need service objects. Don't refactor prematurely.

---

## Key Terms
- **Extract Service Object**
- **Replace Conditional with Polymorphism**
- **Extract Method**
- **SOLID principles**
- **characterization tests**
- **fat controller**

---

## One-Minute Recap
Refactoring improves code without changing behavior. Extract Service moves business logic into testable POROs. Replace Conditional with Polymorphism uses inheritance/strategy to eliminate complex if/case statements. Extract Method breaks long methods into named chunks. Follow SOLID: Single Responsibility, Open/Closed, etc. Always refactor with tests—write characterization tests for legacy code, refactor incrementally, then improve test coverage.
