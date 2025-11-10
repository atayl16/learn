# Exercise: AI Development Workflows

## Objective

Practice using AI development tools to generate, refactor, and review Rails code, learning to distinguish between helpful AI suggestions and problematic ones.

## Task

Use AI tools (GitHub Copilot, Cursor, or Claude Code CLI) to complete three development scenarios:

1. Generate a Rails feature with tests using AI autocomplete
2. Refactor existing code using AI-assisted prompts
3. Review AI-generated code for bugs, security issues, and performance problems

## Acceptance Criteria

- [ ] Generated a complete Article CRUD feature with validations and tests
- [ ] Refactored a controller into service objects using AI assistance
- [ ] Identified at least 3 security or performance issues in AI-generated code
- [ ] Written corrected versions of problematic AI suggestions
- [ ] Created test coverage for edge cases that AI missed
- [ ] Documented lessons learned about AI tool strengths and limitations

## Setup

### Prerequisites

Install an AI coding tool:

**Option 1: GitHub Copilot (Recommended for this exercise)**

```bash
# Install VS Code GitHub Copilot extension
# Or install in your preferred IDE (RubyMine, Sublime, Vim)

# Verify installation by opening a Ruby file and typing:
# def hello
# (Copilot should suggest completion)
```

**Option 2: Cursor Editor**

```bash
# Download from https://cursor.sh
# Cursor is a VS Code fork with built-in AI chat
```

**Option 3: Claude Code CLI**

```bash
# Install Claude Code CLI (requires Anthropic API key)
npm install -g @anthropic-ai/claude-code
claude --version
```

### Create Exercise Rails App

```bash
# Create new Rails app
rails new ai_workshop --database=postgresql --skip-test
cd ai_workshop

# Add testing gems
cat >> Gemfile << 'EOF'

group :development, :test do
  gem 'rspec-rails', '~> 6.0'
  gem 'factory_bot_rails'
  gem 'faker'
  gem 'pry-rails'
end

group :test do
  gem 'shoulda-matchers', '~> 5.0'
  gem 'database_cleaner-active_record'
end
EOF

bundle install

# Initialize RSpec
rails generate rspec:install

# Configure Shoulda Matchers in spec/rails_helper.rb
cat >> spec/rails_helper.rb << 'EOF'

Shoulda::Matchers.configure do |config|
  config.integrate do |with|
    with.test_framework :rspec
    with.library :rails
  end
end
EOF

# Setup database
rails db:create
rails db:migrate

# Verify tests run
bundle exec rspec
```

---

## Part 1: AI-Assisted Feature Generation (8 minutes)

### Task: Generate Article Feature with AI

Use your AI tool to generate a complete Article feature by typing comments and letting AI complete the code.

### Step 1: Create Article Model

Create `app/models/article.rb` and use AI by typing this comment:

```ruby
# Article model with title, body, published_at, author (string)
# Validations: title presence and minimum 5 characters, body presence
# Scope: published (where published_at is not null), recent (order by created_at desc)
```

**Expected AI generation:**

```ruby
class Article < ApplicationRecord
  validates :title, presence: true, length: { minimum: 5 }
  validates :body, presence: true
  validates :author, presence: true

  scope :published, -> { where.not(published_at: nil) }
  scope :recent, -> { order(created_at: :desc) }

  def published?
    published_at.present?
  end
end
```

### Step 2: Create Migration with AI

Run migration generator, then let AI complete the migration file:

```bash
rails generate migration CreateArticles
```

Open `db/migrate/XXXXXX_create_articles.rb` and type:

```ruby
# Migration to create articles table with title string, body text, published_at datetime, author string
```

**Expected AI generation:**

```ruby
class CreateArticles < ActiveRecord::Migration[7.0]
  def change
    create_table :articles do |t|
      t.string :title, null: false
      t.text :body, null: false
      t.datetime :published_at
      t.string :author, null: false
      t.timestamps
    end

    add_index :articles, :published_at
    add_index :articles, :created_at
  end
end
```

Run migration:

```bash
rails db:migrate
```

### Step 3: Generate Controller with AI

Create `app/controllers/articles_controller.rb` and type:

```ruby
# ArticlesController with index (shows published articles), show, new, create, edit, update, destroy
# Use strong parameters, handle create/update failures with flash messages
```

**Review AI generation and verify:**
- Strong parameters method
- Proper flash messages
- Error handling with `render` on validation failures
- HTTP status codes (`:unprocessable_entity` for errors)

### Step 4: Generate Model Tests with AI

Create `spec/models/article_spec.rb` and type:

```ruby
# RSpec tests for Article validations, scopes, and published? method
```

**Verify AI generates tests for:**
- Title presence and length validations
- Body and author presence
- Published scope (includes published, excludes unpublished)
- Recent scope (orders correctly)
- `published?` method (returns true/false correctly)

Run tests:

```bash
bundle exec rspec spec/models/article_spec.rb
```

**If tests fail, this is your first learning moment:** AI generated invalid code. Fix and document the issue.

---

## Part 2: AI-Assisted Refactoring (7 minutes)

### Task: Refactor Controller Logic into Service Object

You've been given this problematic controller code. Use AI to refactor it into a service object.

Create `app/controllers/orders_controller.rb`:

```ruby
class OrdersController < ApplicationController
  def create
    @order = Order.new(order_params)
    @order.user = current_user

    if @order.save
      # Process payment
      begin
        Stripe::Charge.create(
          amount: (@order.total * 100).to_i,
          currency: 'usd',
          source: params[:stripe_token],
          description: "Order #{@order.id}"
        )
      rescue Stripe::CardError => e
        @order.update(status: 'payment_failed')
        redirect_to @order, alert: "Payment failed: #{e.message}"
        return
      end

      # Update inventory
      @order.items.each do |item|
        product = item.product
        product.update(stock: product.stock - item.quantity)
      end

      # Send email
      OrderMailer.confirmation(@order.id).deliver_now

      @order.update(status: 'completed')
      redirect_to @order, notice: 'Order placed successfully!'
    else
      render :new, status: :unprocessable_entity
    end
  end

  private

  def order_params
    params.require(:order).permit(:total, items_attributes: [:product_id, :quantity])
  end
end
```

### Refactoring Steps

1. **Prompt AI with:**

```
Extract payment processing, inventory update, and email sending from OrdersController
into a ProcessOrder service object. The service should:
- Accept an order and stripe_token
- Wrap operations in a database transaction
- Handle Stripe errors gracefully
- Return success/failure status with error messages
- Follow Rails service object pattern (PORO with #call method)
```

2. **Review AI-generated service object for:**
   - Database transaction wrapping
   - Proper error handling
   - Return value structure (success boolean + error message)
   - Private method extraction

3. **Update controller to use service:**

```ruby
def create
  @order = current_user.orders.build(order_params)

  if @order.save
    result = ProcessOrder.new(@order, params[:stripe_token]).call

    if result[:success]
      redirect_to @order, notice: 'Order placed successfully!'
    else
      redirect_to @order, alert: "Order failed: #{result[:error]}"
    end
  else
    render :new, status: :unprocessable_entity
  end
end
```

4. **Generate service tests with AI prompt:**

```
RSpec tests for ProcessOrder service including:
- Successful order processing
- Stripe card error handling
- Inventory update failures
- Transaction rollback on errors
Use mocks for Stripe and email delivery
```

**Check for these common AI mistakes:**
- Missing `ApplicationRecord.transaction do ... end`
- Not rolling back inventory changes on payment failure
- Synchronous email delivery (`deliver_now` instead of `deliver_later`)
- No idempotency checks for Stripe charges

---

## Part 3: Code Review Challenge (5 minutes)

### Task: Review AI-Generated Code for Issues

Below is code generated by an AI tool. Your job is to identify **all security, performance, and correctness issues.**

```ruby
# app/controllers/admin/users_controller.rb
class Admin::UsersController < ApplicationController
  def index
    @users = User.all
  end

  def show
    @user = User.find(params[:id])
    @orders = @user.orders
  end

  def destroy
    user = User.find(params[:id])
    user.destroy
    redirect_to admin_users_path, notice: 'User deleted'
  end

  def export_csv
    users = User.all
    csv_data = users.map { |u| "#{u.email},#{u.created_at}" }.join("\n")
    send_data csv_data, filename: 'users.csv'
  end
end

# app/models/user.rb
class User < ApplicationRecord
  has_many :orders
  validates :email, presence: true

  def self.search(query)
    where("email LIKE '%#{query}%'")
  end
end

# app/services/import_users.rb
class ImportUsers
  def self.call(file_path)
    CSV.foreach(file_path, headers: true) do |row|
      User.create(
        email: row['email'],
        password: row['password'],
        admin: row['admin']
      )
    end
  end
end
```

### Issues to Find

List all issues with category (security/performance/correctness) and fix:

1. **Issue:** _______________
   - **Category:** _______________
   - **Fix:** _______________

2. **Issue:** _______________
   - **Category:** _______________
   - **Fix:** _______________

3. **Issue:** _______________
   - **Category:** _______________
   - **Fix:** _______________

(Continue for all issues found)

---

## Verification Steps

### Part 1 Verification

```bash
# Run Article specs
bundle exec rspec spec/models/article_spec.rb

# Check model in console
rails console
> article = Article.create(title: "Test Article", body: "Content", author: "AI")
> article.valid?
> article.published?
> Article.published.count
```

### Part 2 Verification

```bash
# Run service specs
bundle exec rspec spec/services/process_order_spec.rb

# Verify service exists and has correct interface
rails console
> result = ProcessOrder.new(order, 'tok_visa').call
> result.keys  # Should include :success and :error
```

### Part 3 Verification

Compare your findings to the solutions below.

---

## Solution Notes

### Part 1: Common AI Generation Issues

**Issue 1: Migrations missing null constraints**

AI often generates:
```ruby
t.string :title
```

Should be:
```ruby
t.string :title, null: false
```

**Issue 2: Missing indexes on frequently queried columns**

AI forgets:
```ruby
add_index :articles, :published_at
```

**Issue 3: Test coverage gaps**

AI generates happy-path tests but misses edge cases:
- Empty title (length validation edge case)
- Nil vs empty string handling
- Published scope with mixed published_at values

### Part 2: Service Object Patterns

**Good AI-generated service structure:**

```ruby
class ProcessOrder
  def initialize(order, stripe_token)
    @order = order
    @stripe_token = stripe_token
  end

  def call
    ApplicationRecord.transaction do
      charge_payment
      update_inventory
      send_confirmation
      @order.update!(status: 'completed')
    end

    { success: true, error: nil }
  rescue Stripe::CardError => e
    { success: false, error: e.message }
  rescue StandardError => e
    { success: false, error: "Order processing failed: #{e.message}" }
  end

  private

  def charge_payment
    Stripe::Charge.create(
      amount: (@order.total * 100).to_i,
      currency: 'usd',
      source: @stripe_token,
      description: "Order #{@order.id}",
      idempotency_key: "order_#{@order.id}"
    )
  end

  def update_inventory
    @order.items.each do |item|
      item.product.decrement!(:stock, item.quantity)
    end
  end

  def send_confirmation
    OrderMailer.confirmation(@order.id).deliver_later
  end
end
```

**AI commonly misses:**
- Idempotency key for Stripe (allows safe retries)
- `deliver_later` instead of `deliver_now` (avoids blocking)
- Proper exception hierarchy (catch specific errors first)

### Part 3: Code Review Solutions

**Issue 1: Missing authentication check**
- **Category:** Security
- **Issue:** No `before_action :require_admin!` or authorization
- **Fix:** Add `before_action :authenticate_admin!`

**Issue 2: SQL injection in search**
- **Category:** Security
- **Issue:** `where("email LIKE '%#{query}%'")` allows SQL injection
- **Fix:** `where("email LIKE ?", "%#{query}%")` or `where("email LIKE :query", query: "%#{query}%")`

**Issue 3: N+1 query in show action**
- **Category:** Performance
- **Issue:** `@orders = @user.orders` triggers N+1 when rendering order details
- **Fix:** `@orders = @user.orders.includes(:items, :products)`

**Issue 4: Missing authorization in destroy**
- **Category:** Security
- **Issue:** Admin can delete any user, including themselves or other admins
- **Fix:** Add checks: `return if user.admin? || user == current_user`

**Issue 5: CSV export loads all users**
- **Category:** Performance
- **Issue:** `User.all.map` loads all records into memory
- **Fix:** Use `find_each` and streaming: `CSV.generate { |csv| User.find_each { |u| csv << [u.email, u.created_at] } }`

**Issue 6: Plaintext password in import**
- **Category:** Security
- **Issue:** Creates user with plaintext password: `password: row['password']`
- **Fix:** Use `password_digest` or `has_secure_password` with proper password hashing

**Issue 7: Mass assignment vulnerability**
- **Category:** Security
- **Issue:** Directly assigns `admin: row['admin']` allowing privilege escalation
- **Fix:** Remove admin from CSV import, or require separate authorization

**Issue 8: No error handling in CSV import**
- **Category:** Correctness
- **Issue:** Failed user creation is silently ignored
- **Fix:** Add error handling and logging:
```ruby
User.create!(email: row['email'], ...)
rescue ActiveRecord::RecordInvalid => e
  Rails.logger.error "Failed to import user: #{e.message}"
```

---

## Stretch (Optional)

### 1. Add AI-Powered Code Review Automation

Install and configure `danger` gem to automate code review:

```bash
# Add to Gemfile
gem 'danger', group: :development

bundle install

# Create Dangerfile
cat > Dangerfile << 'EOF'
# Warn for large PRs
warn("Large PR: Consider breaking into smaller changes") if git.lines_of_code > 400

# Check for missing tests
has_app_changes = !git.modified_files.grep(/app/).empty?
has_spec_changes = !git.modified_files.grep(/spec/).empty?
warn("Missing tests: Consider adding specs for your changes") if has_app_changes && !has_spec_changes

# Detect N+1 patterns
git.modified_files.each do |file|
  next unless file.end_with?('.rb')

  contents = File.read(file)
  if contents.match?(/\.each\s+do.*\.(find|where|first)/)
    warn("Possible N+1 query in #{file}")
  end
end
EOF
```

### 2. Create AI Prompt Library

Document effective prompts for your team:

```ruby
# config/ai_prompts.md

# AI Prompt Library for Rails Development

## Generating Models

```
Create a Rails [MODEL_NAME] model with:
- Attributes: [LIST ATTRIBUTES WITH TYPES]
- Validations: [SPECIFY VALIDATIONS]
- Associations: [BELONGS_TO, HAS_MANY, ETC]
- Scopes: [DESCRIBE SCOPES]
Include migration with proper indexes and null constraints.
```

## Generating Tests

```
RSpec tests for [MODEL/SERVICE/CONTROLLER] covering:
- All validations with edge cases
- Association tests
- Custom methods with success and failure paths
- Error handling for [SPECIFIC ERROR TYPES]
Use shoulda-matchers where applicable.
```

## Refactoring

```
Extract [FUNCTIONALITY] from [SOURCE] into [PATTERN] that:
- [CONSTRAINT 1]
- [CONSTRAINT 2]
- [ERROR HANDLING REQUIREMENTS]
Maintain backward compatibility and include tests.
```
```

### 3. Measure AI Tool Impact

Track before/after metrics:

```ruby
# Track time spent on tasks
# Before AI: Measure time to generate model + tests
# After AI: Measure time to review and correct AI-generated code

# Track bug rates
# Compare bug density in AI-generated vs manual code
# Review security issues in PRs using AI tools

# Document findings in team retrospective
```

### 4. Create Custom Copilot Training

Configure custom completions for your team:

```json
// .github/copilot-instructions.json
{
  "conventions": {
    "service_objects": "Use PORO with #call method returning hash with :success and :error keys",
    "controllers": "Keep actions thin, delegate to services, use strong parameters",
    "tests": "Use RSpec with shoulda-matchers, FactoryBot for fixtures"
  },
  "forbidden_patterns": [
    "No inline SQL in models or controllers",
    "No synchronous email delivery in web requests",
    "No mass assignment without strong parameters"
  ]
}
```

---

## Time Estimate

20 minutes
- Part 1: 8 minutes (generating feature)
- Part 2: 7 minutes (refactoring)
- Part 3: 5 minutes (code review)

---

## Key Takeaways

After completing this exercise, you should understand:

1. **AI excels at patterns:** Generating CRUD controllers, models, tests—things it has seen thousands of times
2. **AI struggles with security:** Authentication, authorization, and payment logic require human review
3. **AI misses edge cases:** Generated tests cover happy paths but miss nil values, empty arrays, race conditions
4. **AI needs guidance:** Specific prompts with constraints yield better results than vague requests
5. **Review is essential:** Treat AI code like junior developer contributions—thorough review required
6. **Iteration improves output:** Refine prompts based on initial AI responses to get closer to desired code
7. **Context matters:** AI with access to your entire codebase (Cursor, Claude Code) generates more consistent code than autocomplete-only tools

Use AI as a productivity multiplier, not a replacement for understanding. The best developers use AI to handle boilerplate quickly, then focus their expertise on architecture, security, and complex business logic.
