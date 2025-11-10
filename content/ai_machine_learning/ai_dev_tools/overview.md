# AI Development Workflows

## What It Is

AI development tools use large language models to assist with coding through autocomplete, code generation, debugging, and refactoring. GitHub Copilot provides inline suggestions as you type, completing functions and generating boilerplate. Cursor is an AI-native code editor with chat interfaces for codebase-wide refactoring and multi-file changes. Claude Code (the Anthropic CLI) executes complex workflows like "add authentication to this Rails app" by reading files, running tests, and committing changes autonomously. These tools integrate into daily workflows through IDE extensions, command-line interfaces, and code review automation that flags bugs, suggests improvements, and enforces team standards.

## Why It Matters

Writing Rails applications involves repetitive patterns: creating CRUD controllers, writing migrations, setting up test fixtures, configuring routes. AI tools handle this boilerplate in seconds, freeing developers to focus on business logic and architecture. A junior developer can generate production-quality code by describing requirements in plain English: "create a User model with email validation and password hashing." AI-assisted code review catches subtle bugs like N+1 queries, missing authorization checks, and race conditions that humans miss after hours of reviewing PRs. The difference between teams using AI tools effectively versus not using them is measured in 30-50% productivity gains on feature development and 40% reduction in bug introduction rates. Poor AI usage creates dependency: developers accepting suggestions without understanding them accumulate technical debt faster than manual coding.

## When to Use

- **Boilerplate generation:** Controllers, models, migrations, test files—let AI generate scaffolding from descriptions
- **Refactoring assistance:** "Extract this method into a service object" or "convert these callbacks to explicit method calls"
- **Test writing:** Generate test cases from implementation code, including edge cases and error conditions
- **Code review:** Automate detection of security vulnerabilities, performance issues, and style violations
- **Debugging:** Ask AI to analyze stack traces, explain error messages, and suggest fixes
- **Documentation:** Generate API docs, README sections, and inline comments from code
- **Learning:** Understand unfamiliar codebases by asking "what does this controller do?" or "why is this query slow?"

## Three Common Pitfalls

1. **Accepting AI suggestions without review:** Copilot suggests `User.where(active: true).map(&:email)` loading 10,000 records into memory when `User.where(active: true).pluck(:email)` is correct. Blindly accepting suggestions bypasses your judgment. Always read generated code, run tests, and verify logic before committing. Use AI as a pair programmer who types fast but needs oversight, not as a replacement for thinking.

2. **Over-reliance on prompt engineering:** Spending 20 minutes crafting the perfect prompt to generate a complex service object is slower than writing it yourself. AI tools excel at well-understood patterns (CRUD, migrations, tests) and struggle with novel business logic. Use AI for scaffolding and repetitive tasks, not for core algorithmic work or complex state machines. If you're rewriting prompts five times, switch to manual coding.

3. **Ignoring security implications:** AI-generated code may include vulnerabilities: SQL injection, missing authentication checks, or exposing sensitive data in logs. Example: AI suggests `Order.find(params[:id])` in an admin controller without checking `current_user.admin?`. Security requires human judgment—never deploy AI-generated authentication, authorization, or payment code without thorough review and penetration testing.

---

## GitHub Copilot: Inline Autocomplete

GitHub Copilot provides context-aware code completions as you type, trained on billions of lines of public code. It predicts next lines based on file context, function signatures, and comments.

### Basic Usage in Rails

**Scenario:** Writing a Rails controller action.

```ruby
# Type a comment describing what you want:
# Create a new article with title and body, assign to current user

# Copilot suggests:
def create
  @article = current_user.articles.build(article_params)
  if @article.save
    redirect_to @article, notice: 'Article created successfully.'
  else
    render :new, status: :unprocessable_entity
  end
end

private

def article_params
  params.require(:article).permit(:title, :body)
end
```

**When it helps:**
- Generating common patterns (CRUD actions, validations, callbacks)
- Completing repetitive code (test setups, factory definitions)
- Suggesting method names and parameters based on context

**When to ignore:**
- Complex business logic requiring domain knowledge
- Security-critical code (authentication, authorization, payments)
- Performance-sensitive queries (use profiling instead)

### Copilot for Test Generation

```ruby
# app/models/article.rb
class Article < ApplicationRecord
  validates :title, presence: true, length: { minimum: 5 }
  validates :body, presence: true
  belongs_to :user

  scope :published, -> { where.not(published_at: nil) }
  scope :recent, -> { order(published_at: :desc).limit(10) }
end

# Type in spec/models/article_spec.rb:
# RSpec tests for Article validations and scopes

# Copilot generates:
require 'rails_helper'

RSpec.describe Article, type: :model do
  describe 'validations' do
    it { should validate_presence_of(:title) }
    it { should validate_length_of(:title).is_at_least(5) }
    it { should validate_presence_of(:body) }
  end

  describe 'associations' do
    it { should belong_to(:user) }
  end

  describe 'scopes' do
    describe '.published' do
      it 'returns only published articles' do
        published = create(:article, published_at: 1.day.ago)
        draft = create(:article, published_at: nil)
        expect(Article.published).to include(published)
        expect(Article.published).not_to include(draft)
      end
    end

    describe '.recent' do
      it 'returns articles ordered by published_at descending' do
        old = create(:article, published_at: 1.week.ago)
        new = create(:article, published_at: 1.day.ago)
        expect(Article.recent.first).to eq(new)
      end
    end
  end
end
```

---

## Cursor: AI-Native Code Editor

Cursor is a fork of VS Code with built-in AI chat for codebase-wide operations. Unlike Copilot's inline suggestions, Cursor understands entire projects and can modify multiple files in one conversation.

### Multi-File Refactoring with Cursor

**Task:** "Extract order processing logic from OrdersController into a service object."

**Cursor chat conversation:**

```
You: Extract order processing from OrdersController#create into ProcessOrder service

Cursor reads:
- app/controllers/orders_controller.rb
- app/models/order.rb
- spec/controllers/orders_controller_spec.rb

Cursor generates:
1. app/services/process_order.rb
2. Updates app/controllers/orders_controller.rb
3. Creates spec/services/process_order_spec.rb
```

**Generated files:**

```ruby
# app/services/process_order.rb
class ProcessOrder
  def initialize(order)
    @order = order
  end

  def call
    ApplicationRecord.transaction do
      @order.update!(status: 'processing')
      charge_payment
      send_confirmation_email
      update_inventory
      @order.update!(status: 'completed', processed_at: Time.current)
    end
    true
  rescue => e
    @order.update(status: 'failed', error_message: e.message)
    false
  end

  private

  def charge_payment
    PaymentService.charge(@order.payment_method, @order.total_amount)
  end

  def send_confirmation_email
    OrderMailer.confirmation(@order.id).deliver_later
  end

  def update_inventory
    @order.items.each do |item|
      item.product.decrement!(:stock, item.quantity)
    end
  end
end

# app/controllers/orders_controller.rb (updated)
def create
  @order = current_user.orders.build(order_params)
  if @order.save && ProcessOrder.new(@order).call
    redirect_to @order, notice: 'Order processed successfully.'
  else
    flash.now[:alert] = 'Order processing failed.'
    render :new, status: :unprocessable_entity
  end
end
```

### Debugging with Cursor Chat

**Problem:** Tests failing with `ActiveRecord::RecordNotFound` in production but not in dev.

**Cursor conversation:**

```
You: Why does Order.find(params[:id]) raise RecordNotFound in production but works in dev?

Cursor analyzes:
- app/controllers/orders_controller.rb
- logs/production.log
- config/environments/production.rb

Cursor responds:
"The issue is likely a scope leak from authentication. In OrdersController, you're using:
  Order.find(params[:id])

This finds any order, including orders belonging to other users. Dev works because you test
with the same user. Production breaks when user A tries to access user B's order.

Fix: Use current_user scope:
  @order = current_user.orders.find(params[:id])

This scopes the query to current user's orders, raising RecordNotFound if unauthorized."
```

---

## Claude Code: Autonomous AI Agent

Claude Code is Anthropic's CLI tool for complex, multi-step development tasks. Unlike autocomplete tools, Claude Code can read files, execute commands, run tests, and commit changes based on high-level instructions.

### Adding Authentication with Claude Code

**Command:**

```bash
claude "Add Devise authentication to this Rails app with User model and email/password login"
```

**What Claude Code does:**

1. Reads existing codebase structure
2. Adds `gem 'devise'` to Gemfile and runs `bundle install`
3. Runs `rails generate devise:install`
4. Creates User model with Devise: `rails generate devise User`
5. Updates routes, adds authentication filters to controllers
6. Generates tests for authentication flows
7. Runs test suite to verify changes
8. Commits with message: "Add Devise authentication with User model"

**Generated code includes:**

```ruby
# app/controllers/application_controller.rb
class ApplicationController < ActionController::Base
  before_action :authenticate_user!
end

# app/controllers/articles_controller.rb
class ArticlesController < ApplicationController
  skip_before_action :authenticate_user!, only: [:index, :show]

  def create
    @article = current_user.articles.build(article_params)
    # ...
  end
end

# spec/requests/articles_spec.rb
RSpec.describe 'Articles', type: :request do
  describe 'POST /articles' do
    context 'when user is authenticated' do
      let(:user) { create(:user) }

      before { sign_in user }

      it 'creates article for current user' do
        post articles_path, params: { article: { title: 'Test', body: 'Body' } }
        expect(Article.last.user).to eq(user)
      end
    end

    context 'when user is not authenticated' do
      it 'redirects to login' do
        post articles_path, params: { article: { title: 'Test', body: 'Body' } }
        expect(response).to redirect_to(new_user_session_path)
      end
    end
  end
end
```

### Workflow for AI-Driven Development

1. **High-level task description:** "Add pagination to articles index with 20 items per page"
2. **Claude Code execution:**
   - Installs kaminari gem
   - Updates ArticlesController#index with `.page(params[:page]).per(20)`
   - Updates view with pagination links
   - Adds tests for pagination behavior
   - Verifies tests pass
3. **Developer review:** Check generated code, verify edge cases, adjust styling
4. **Commit and deploy**

---

## Prompt-Driven Development

Prompt engineering for code generation follows patterns: be specific, provide context, specify constraints.

### Effective Prompts for Rails

**Bad prompt:**

```
Create a user model
```

**Good prompt:**

```
Create a Rails User model with:
- Email validation (unique, valid format)
- Password authentication using has_secure_password
- Admin boolean flag (default false)
- Timestamps
- Soft deletion using paranoia gem
Include RSpec model tests for validations and scopes
```

**Result:** Complete model with validations, tests, and migrations.

### Prompt Structure for Refactoring

```
Context: We have a 200-line OrdersController with business logic mixed into actions.

Task: Extract payment processing into a service object that:
- Accepts an Order and PaymentMethod
- Wraps operations in a database transaction
- Handles Stripe API errors gracefully
- Returns a result object with success/failure status

Constraints:
- Use Rails service object pattern (PORO with #call method)
- Include RSpec tests with VCR for Stripe API calls
- Update OrdersController to use the service
- Maintain backward compatibility with existing order flow
```

**AI generates:**
- `app/services/process_payment.rb`
- `spec/services/process_payment_spec.rb`
- Updated controller
- Error handling for Stripe::CardError, Stripe::APIConnectionError

---

## AI-Assisted Code Review

Tools like GitHub Copilot Labs, CodeRabbit, and Anthropic's Claude integrate with pull requests to automate review feedback.

### Automated Review Checks

**Example PR feedback from AI reviewer:**

```markdown
## Performance Issues

**File:** app/controllers/articles_controller.rb
**Line:** 15
**Issue:** N+1 query detected

def index
  @articles = Article.all
end

**Impact:** This loads articles without associated users, triggering N+1 when rendering
`article.user.name` in the view. For 100 articles, this executes 101 queries.

**Fix:**
@articles = Article.includes(:user)

---

## Security Concerns

**File:** app/controllers/orders_controller.rb
**Line:** 23
**Issue:** Missing authorization check

def show
  @order = Order.find(params[:id])
end

**Impact:** Any authenticated user can view any order by guessing IDs.

**Fix:**
@order = current_user.orders.find(params[:id])

Or use Pundit policy:
authorize @order

---

## Code Quality

**File:** app/services/export_orders.rb
**Line:** 42
**Issue:** Long method (30 lines)

**Suggestion:** Extract CSV generation into private methods:
- `csv_headers`
- `csv_row(order)`
- `format_date(datetime)`
```

### Setting Up AI Code Review

**GitHub Actions integration:**

```yaml
# .github/workflows/ai-review.yml
name: AI Code Review

on:
  pull_request:
    branches: [main]

jobs:
  ai-review:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - name: Run AI code review
        uses: anthropics/claude-code-review-action@v1
        with:
          anthropic_api_key: ${{ secrets.ANTHROPIC_API_KEY }}
          review_level: 'strict'
          focus_areas: 'security,performance,rails_best_practices'
```

---

## Debugging with AI

AI tools excel at diagnosing errors by analyzing stack traces, logs, and code context.

### Example: Debugging a Rails Error

**Error:**

```
NoMethodError: undefined method `name' for nil:NilClass
  app/views/articles/show.html.erb:12:in `_app_views_articles_show_html_erb___123456_70123456789'
  app/controllers/articles_controller.rb:8:in `show'
```

**AI debugging conversation:**

```
You: Why am I getting NoMethodError on article.user.name in articles/show?

AI analyzes:
- app/views/articles/show.html.erb (line 12: <%= @article.user.name %>)
- app/controllers/articles_controller.rb (line 8: @article = Article.find(params[:id]))
- app/models/article.rb (belongs_to :user)

AI response:
"The error occurs because some articles have `user_id: nil` (orphaned records).
The view calls `@article.user.name`, but `@article.user` is nil.

Solutions:
1. Add presence validation: `belongs_to :user, optional: false`
2. Use safe navigation: `<%= @article.user&.name || 'Unknown Author' %>`
3. Clean up orphaned records: `Article.where(user_id: nil).destroy_all`
4. Add database constraint: `add_foreign_key :articles, :users`

Recommendation: Combine #1 and #4 to prevent future orphans, and #2 for existing data."
```

### Debugging Performance Issues

**Problem:** Dashboard page loads in 8 seconds.

**AI conversation:**

```
You: [paste Rails server logs showing request time 8000ms]

AI analyzes logs and suggests:
"The slow request shows 247 SQL queries for a single page load. This is a classic N+1 problem.

Likely causes:
1. Loading users for each article: @articles.each { |a| a.user.name }
2. Loading comments for each article: @articles.each { |a| a.comments.count }

Fix with eager loading:
@articles = Article.includes(:user, :comments).limit(20)

Expected result: 3 queries instead of 247, page load under 200ms."
```

---

## Best Practices for AI Development Tools

### Do's

- **Review all generated code:** Run tests, check for edge cases, verify security
- **Use AI for scaffolding:** Let AI generate boilerplate, then customize business logic
- **Iterate with AI:** Start with a prompt, refine based on output, regenerate
- **Learn from suggestions:** When Copilot suggests unfamiliar code, research why it works
- **Combine tools:** Use Copilot for inline completions, Cursor for refactoring, Claude Code for complex tasks

### Don'ts

- **Don't commit without testing:** AI-generated code may have subtle bugs or security issues
- **Don't skip code review:** Treat AI contributions like junior developer code—review thoroughly
- **Don't trust AI for security:** Authentication, authorization, and payment logic require human expertise
- **Don't over-prompt:** If you're rewriting a prompt 5 times, switch to manual coding
- **Don't rely on AI for novel logic:** AI excels at patterns, struggles with unique business rules

---

## Trade-offs Box

- **Advantage:** AI tools accelerate boilerplate generation, reduce context switching, catch common bugs in code review, and help debug unfamiliar errors. Productivity gains of 30-50% on feature development are common.
- **Cost:** Requires subscription fees ($10-20/month per developer), introduces dependency on external services, and risks accumulating technical debt if developers accept suggestions without understanding. Security vulnerabilities can slip through if AI-generated authentication or authorization code isn't reviewed.
- **When to skip:** Use manual coding for complex business logic, novel algorithms, or security-critical features. AI tools struggle with domain-specific requirements and may generate incorrect code for edge cases.

---

## Debugging Checklist

When AI tools produce incorrect or problematic code:

1. **Verify test coverage:** Run test suite—AI may generate code that passes tests but fails edge cases
2. **Check security implications:** Review for SQL injection, missing authorization, exposed secrets
3. **Profile performance:** Use `rack-mini-profiler` or `bullet` to detect N+1 queries in generated code
4. **Read generated code line-by-line:** Don't merge based on "looks right"—understand every line
5. **Compare with team standards:** Ensure AI code matches your style guide, architecture patterns
6. **Test edge cases:** AI generates happy-path code—manually add tests for nil values, empty arrays, timeouts
7. **Review dependencies:** Check if AI added gems—review security, maintenance status, license compatibility

---

## Key Terms

- **GitHub Copilot** - AI pair programmer providing inline code suggestions based on context
- **Cursor** - AI-native code editor for multi-file refactoring and codebase-wide chat
- **Claude Code** - Anthropic's CLI for autonomous task execution (file reading, testing, committing)
- **Prompt engineering** - Crafting effective instructions for AI to generate desired code
- **Autocomplete** - Real-time code suggestions as you type (Copilot, TabNine, Codeium)
- **AI agent** - Autonomous system that executes multi-step tasks without constant human guidance
- **Code review automation** - AI systems that analyze PRs for bugs, performance issues, style violations
- **Context window** - Amount of code AI can see at once (typically 8k-128k tokens)

---

## One-Minute Recap

AI development tools like GitHub Copilot, Cursor, and Claude Code accelerate Rails development through inline autocomplete, multi-file refactoring, and autonomous task execution. Use AI for boilerplate generation (controllers, models, tests), code review automation (detecting N+1 queries, security issues), and debugging (analyzing stack traces, suggesting fixes). Always review generated code for correctness, security, and performance—treat AI as a fast-typing junior developer, not a replacement for expertise. Effective prompt engineering requires specificity: describe context, constraints, and desired outcome. Avoid over-reliance on AI for novel business logic or security-critical features. Combine tools strategically: Copilot for inline suggestions, Cursor for refactoring, Claude Code for complex workflows. AI-driven development delivers 30-50% productivity gains when used with judgment and thorough review.
