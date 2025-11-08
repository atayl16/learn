# Working with Legacy Code

## What It Is

Working with legacy code means modifying systems without adequate test coverage, unclear design decisions, and complex dependencies that resist change. A characterization test captures existing behavior without understanding internal implementation, creating a safety net before refactoring. A seam is a place where you can alter program behavior without editing code in that location—typically through dependency injection or method extraction. The Strangler Fig pattern gradually replaces legacy functionality by routing new features to modern code while legacy code continues serving existing requests.

## Why It Matters

Legacy codebases represent business value accumulated over years but resist evolution due to lack of tests and documentation. Adding features or fixing bugs without breaking existing functionality requires systematic techniques to understand behavior, isolate changes, and verify correctness. The ability to safely refactor legacy code determines whether systems can adapt to new requirements or ossify into unmaintainable liabilities. Organizations spend 60-80% of development time maintaining existing code, making legacy code skills directly impact team velocity.

## When to Use

- Inherit a codebase with <20% test coverage and no documentation
- Fix bugs in code sections without tests, fearing regression
- Extract business logic from monolithic controllers or models
- Replace deprecated dependencies or upgrade frameworks
- Migrate from legacy architecture to modern patterns incrementally

## Three Common Pitfalls

1. **Refactoring without tests first:** Changing code structure to "clean it up" without characterization tests means you can't detect behavioral changes. The result is silent bugs discovered weeks later in production. Always write tests that lock in current behavior before touching legacy code.

2. **Big-bang rewrites instead of incremental changes:** Teams commit to "rewrite from scratch" to avoid working with messy code, only to discover they can't replicate complex business rules built over years. Use Strangler Fig to replace functionality piece by piece while maintaining production stability.

3. **Breaking dependencies everywhere simultaneously:** Finding a seam in legacy code tempts you to inject dependencies throughout the system. This creates massive changesets that can't be reviewed or deployed safely. Isolate the smallest testable unit, add tests there, then expand coverage incrementally.

---

## Characterization Tests

Characterization tests document what code actually does, not what it should do:

```ruby
# Legacy code: unclear what this method returns
class OrderProcessor
  def calculate_discount(order)
    if order.total > 1000
      discount = order.total * 0.1
      discount += 50 if order.customer.vip?
      discount = 200 if discount > 200
    else
      discount = 0
    end
    discount
  end
end

```

Write tests capturing current behavior:

```ruby
# spec/models/order_processor_spec.rb
RSpec.describe OrderProcessor do
  describe '#calculate_discount' do
    let(:processor) { OrderProcessor.new }

    # Characterize exact current behavior
    it 'returns 0 for orders under $1000' do
      order = double(total: 999, customer: double(vip?: false))
      expect(processor.calculate_discount(order)).to eq(0)
    end

    it 'returns 10% for orders over $1000' do
      order = double(total: 1500, customer: double(vip?: false))
      expect(processor.calculate_discount(order)).to eq(150)
    end

    it 'adds $50 for VIP customers' do
      order = double(total: 1500, customer: double(vip?: true))
      expect(processor.calculate_discount(order)).to eq(200)
    end

    it 'caps discount at $200 even for VIPs' do
      order = double(total: 3000, customer: double(vip?: true))
      expect(processor.calculate_discount(order)).to eq(200)
    end
  end
end

```

Once tests pass, refactor with confidence:

```ruby
class OrderProcessor
  MAX_DISCOUNT = 200
  VIP_BONUS = 50
  DISCOUNT_RATE = 0.1
  MIN_ORDER_FOR_DISCOUNT = 1000

  def calculate_discount(order)
    return 0 unless order.total >= MIN_ORDER_FOR_DISCOUNT

    discount = order.total * DISCOUNT_RATE
    discount += VIP_BONUS if order.customer.vip?
    [discount, MAX_DISCOUNT].min
  end
end

```

Tests still pass, proving behavior unchanged.

---

## Finding Seams

A seam lets you inject test doubles without changing legacy code:

```ruby
# Legacy controller: hard to test because it calls external API
class ReportsController < ApplicationController
  def generate
    data = HTTParty.get("https://analytics.example.com/data")
    @report = ReportGenerator.new(data).build
    render :show
  end
end

```

**Seam 1: Extract method** creates injection point:

```ruby
class ReportsController < ApplicationController
  def generate
    data = fetch_analytics_data
    @report = ReportGenerator.new(data).build
    render :show
  end

  private

  def fetch_analytics_data
    HTTParty.get("https://analytics.example.com/data")
  end
end

```

Test by stubbing the seam:

```ruby
RSpec.describe ReportsController do
  describe 'GET #generate' do
    it 'generates report from analytics data' do
      allow(controller).to receive(:fetch_analytics_data).and_return({'users' => 100})

      get :generate

      expect(assigns(:report)).to be_present
    end
  end
end

```

**Seam 2: Dependency injection** for better design:

```ruby
class ReportsController < ApplicationController
  def generate
    data = analytics_client.fetch_data
    @report = ReportGenerator.new(data).build
    render :show
  end

  private

  def analytics_client
    @analytics_client ||= AnalyticsClient.new
  end
end

# Test with injected double
RSpec.describe ReportsController do
  let(:analytics_client) { double('AnalyticsClient') }
  before { allow(controller).to receive(:analytics_client).and_return(analytics_client) }

  it 'generates report from analytics data' do
    allow(analytics_client).to receive(:fetch_data).and_return({'users' => 100})

    get :generate

    expect(assigns(:report)).to be_present
  end
end

```

---

## Strangler Fig Pattern

Replace legacy code by routing new requests to modern implementation while old code handles existing functionality:

```ruby
# Legacy: Fat controller with business logic
class OrdersController < ApplicationController
  def create
    # 200 lines of order processing logic
    order = Order.new(order_params)
    # ... complex validation
    # ... inventory checks
    # ... payment processing
    # ... email notifications
    order.save
  end
end

```

**Phase 1:** Route new feature to service object:

```ruby
class OrdersController < ApplicationController
  def create
    if use_new_order_flow?
      result = Orders::CreateService.new(order_params, current_user).call
      if result.success?
        redirect_to result.order
      else
        @errors = result.errors
        render :new
      end
    else
      # Original legacy code stays untouched
      order = Order.new(order_params)
      # ... 200 lines of legacy logic
    end
  end

  private

  def use_new_order_flow?
    # Feature flag or gradual rollout
    current_user.beta_features_enabled? || params[:use_new_flow]
  end
end

```

**Phase 2:** Modern service with tests:

```ruby
module Orders
  class CreateService
    def initialize(params, user)
      @params = params
      @user = user
    end

    def call
      ActiveRecord::Base.transaction do
        order = build_order
        check_inventory!
        process_payment!
        send_notifications
        Result.success(order)
      end
    rescue => e
      Result.failure(e.message)
    end

    private
    # Clean, tested methods
  end
end

```

**Phase 3:** Once stable, remove legacy code:

```ruby
class OrdersController < ApplicationController
  def create
    result = Orders::CreateService.new(order_params, current_user).call
    if result.success?
      redirect_to result.order
    else
      @errors = result.errors
      render :new
    end
  end
end

```

---

## Breaking Dependencies for Testing

Legacy code often has hard dependencies on databases, file systems, or external services:

```ruby
# Untestable: database and file system coupling
class UserExporter
  def export_to_csv
    users = User.where(active: true)
    CSV.open('exports/users.csv', 'w') do |csv|
      users.each { |u| csv << [u.id, u.email] }
    end
    EmailService.send_export_notification
  end
end

```

**Break dependencies with parameters:**

```ruby
class UserExporter
  def initialize(user_scope: User.where(active: true),
                 file_writer: CSVFileWriter.new,
                 notifier: EmailNotifier.new)
    @user_scope = user_scope
    @file_writer = file_writer
    @notifier = notifier
  end

  def export_to_csv
    @file_writer.write('exports/users.csv') do |writer|
      @user_scope.find_each do |user|
        writer << [user.id, user.email]
      end
    end
    @notifier.send_export_notification
  end
end

```

**Now testable with doubles:**

```ruby
RSpec.describe UserExporter do
  it 'exports active users to CSV' do
    users = [double(id: 1, email: 'a@test.com'), double(id: 2, email: 'b@test.com')]
    user_scope = double(find_each: nil)
    allow(user_scope).to receive(:find_each).and_yield(users[0]).and_yield(users[1])

    file_writer = double('CSVFileWriter')
    expect(file_writer).to receive(:write).with('exports/users.csv').and_yield(file_writer)
    expect(file_writer).to receive(:<<).with([1, 'a@test.com'])
    expect(file_writer).to receive(:<<).with([2, 'b@test.com'])

    notifier = double('EmailNotifier')
    expect(notifier).to receive(:send_export_notification)

    exporter = UserExporter.new(user_scope: user_scope,
                                file_writer: file_writer,
                                notifier: notifier)
    exporter.export_to_csv
  end
end

```

---

## Trade-offs Box

- **Advantage:** Characterization tests let you refactor fearlessly without understanding complex logic; Strangler Fig allows incremental migration with zero downtime.
- **Cost:** Writing characterization tests for large legacy systems takes time before delivering features; maintaining parallel code paths (old + new) adds complexity.
- **When to skip:** For isolated scripts or one-off tasks, immediate rewrite may be faster than adding tests first. For actively-developed code with good coverage, use standard refactoring techniques.

---

## Debugging Checklist

When working with legacy code:

1. Identify the smallest unit you need to change (method, class, module)
2. Write characterization tests capturing current behavior, bugs included
3. Run tests—if they fail, adjust tests to match actual behavior
4. Look for seams: method boundaries, class initialization, external calls
5. Extract methods to create seams if none exist
6. Break hard dependencies by adding parameters with default values
7. Refactor incrementally: extract constant, rename variable, add method
8. Run tests after each micro-change to verify behavior unchanged
9. Use feature flags for Strangler Fig pattern, route 5% traffic initially
10. Monitor production metrics during migration, ready to rollback

---

## One-Minute Recap

- Characterization tests lock in current behavior without understanding implementation
- Seams are injection points where you can alter behavior for testing
- Strangler Fig pattern replaces legacy code incrementally using feature flags
- Break dependencies by adding parameters with default production values
- Always write tests before refactoring; change code structure, not behavior
