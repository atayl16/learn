# Validations, Callbacks & Concerns

## What It Is
Validations ensure model data meets business rules before saving to the database. Callbacks are hooks that run at specific lifecycle events (before/after create, update, destroy). Concerns are modules that extract shared logic across models, using `ActiveSupport::Concern` for clean inclusion.

## Why It Matters
Validations prevent bad data from entering the database. Callbacks automate side effects (logging, cache clearing, notifications) but can cause hidden bugs if overused. Concerns keep models DRY and testable. Seniors know when to use callbacks vs service objects, and how to avoid callback hell.

## When to Use
- **Validations:** Always, for data integrity (presence, format, uniqueness)
- **Callbacks:** Simple, model-centric logic (audit logs, cache invalidation, denormalization)
- **Concerns:** Extract shared validations, scopes, or methods across models
- **Avoid callbacks for:** External API calls, complex business logic (use service objects instead)

## Three Common Pitfalls
1. **Callbacks run in transactions:** A `before_save` callback that calls an external API can slow saves or cause rollbacks. Use `after_commit` for side effects outside the transaction.
2. **Callback chains are hard to debug:** `User.create` might trigger 10+ callbacks across models. Hidden logic makes bugs elusive. Keep callbacks minimal.
3. **Validations skip with `update_attribute` / `save(validate: false)`:** These bypass validations. Prefer `update!` to enforce validations.

---

## Built-in Validations

Common validators:

```ruby
class User < ApplicationRecord
  validates :email, presence: true, uniqueness: true
  validates :age, numericality: { greater_than: 0, less_than: 150 }
  validates :name, length: { minimum: 2, maximum: 50 }
  validates :role, inclusion: { in: %w[admin user guest] }
  validates :username, format: { with: /\A[a-zA-Z0-9_]+\z/ }
end

```

**Conditional validations:**

```ruby
validates :ssn, presence: true, if: :us_resident?

def us_resident?
  country == "US"
end

```

**Custom validations:**

```ruby
validate :email_domain_allowed

def email_domain_allowed
  return if email.blank?
  domain = email.split("@").last
  errors.add(:email, "domain not allowed") unless %w[example.com mycompany.com].include?(domain)
end

```

---

## Validation Lifecycle

Validations run:
- **Before save:** `valid?` returns true/false
- **On create/update:** `create!`, `save!`, `update!` raise if invalid
- **Skipped by:** `update_attribute`, `save(validate: false)`, `update_column`

Check validity:

```ruby
user = User.new(email: "")
user.valid?  # => false
user.errors.full_messages  # => ["Email can't be blank"]

```

---

## Callbacks

Lifecycle hooks:

```ruby
class Order < ApplicationRecord
  before_validation :normalize_phone
  before_save :calculate_total
  after_save :clear_cache
  after_commit :send_confirmation_email, on: :create
  before_destroy :cancel_subscriptions

  private

  def normalize_phone
    self.phone = phone.gsub(/\D/, "") if phone.present?
  end

  def calculate_total
    self.total = line_items.sum(&:price)
  end

  def clear_cache
    Rails.cache.delete("order_#{id}")
  end

  def send_confirmation_email
    OrderMailer.confirmation(self).deliver_later
  end

  def cancel_subscriptions
    subscriptions.each(&:cancel!)
  end
end

```

**Callback order:**
1. `before_validation`
2. **Validation runs**
3. `after_validation`
4. `before_save`
5. `before_create` / `before_update`
6. **Database write**
7. `after_create` / `after_update`
8. `after_save`
9. **Transaction commits**
10. `after_commit`

**Use `after_commit` for:**
- Sending emails (jobs)
- Calling external APIs
- Clearing caches
- Anything outside the transaction

**Never in callbacks:**
- Complex business logic (move to services)
- Long-running operations (queue jobs instead)
- Multiple database writes (risk cascading failures)

---

## Callback Dangers

### Callback Hell

```ruby
# BAD: Nested side effects
class User < ApplicationRecord
  after_create :create_profile
  after_create :send_welcome_email
  after_create :notify_admin
  after_create :update_analytics
end

# Profile creation triggers more callbacks...
class Profile < ApplicationRecord
  after_create :generate_avatar
  after_create :set_defaults
end

```

**Problem:** Creating a user triggers 6+ callbacks across models. Hard to debug and test.

**Solution:** Use service objects:

```ruby
class UserRegistration
  def call(params)
    user = User.create!(params)
    Profile.create!(user: user)
    WelcomeMailer.deliver_later(user)
    AnalyticsService.track_signup(user)
    user
  end
end

```

### Callbacks Break Expectations

```ruby
user = User.new(email: "test@example.com")
user.save  # Triggers 5 callbacks, sends email, calls API

```

**Problem:** `save` is expected to be a database operation. Hidden side effects surprise developers.

**Solution:** Explicit service methods:

```ruby
UserService.register(user)  # Clear intent

```

---

## Concerns

Extract shared logic:

```ruby
# app/models/concerns/taggable.rb
module Taggable
  extend ActiveSupport::Concern

  included do
    has_many :tags, as: :taggable
    scope :tagged_with, ->(name) { joins(:tags).where(tags: { name: name }) }
  end

  def tag_names
    tags.pluck(:name).join(", ")
  end
end

# app/models/post.rb
class Post < ApplicationRecord
  include Taggable
end

# app/models/article.rb
class Article < ApplicationRecord
  include Taggable
end

```

**What `ActiveSupport::Concern` does:**
- `included` block runs when module is included
- Handles dependency resolution (concerns can include other concerns)
- Cleaner than vanilla Ruby modules

**When to use:**
- Shared validations (e.g., `Publishable` for posts/articles)
- Common scopes (e.g., `Searchable` with full-text search)
- Polymorphic associations (e.g., `Commentable`)

**When to skip:**
- Logic used by only one model (keep it in the model)
- Complex orchestration (use service objects)

---

## Trade-offs Box
- **Advantage:** Validations prevent bad data; callbacks automate repetitive tasks; concerns DRY up models.
- **Cost:** Callbacks hide logic and complicate testing. Overuse leads to tight coupling.
- **When to skip:** For complex workflows, use explicit service objects instead of callbacks.

---

## Debugging Checklist

When validations/callbacks misbehave:

1. Check `model.errors.full_messages` after failed save
2. Inspect callback order: `Model._save_callbacks.map(&:filter)`
3. Add logging to callbacks: `Rails.logger.info "Running #{__method__}"`
4. Use `save(validate: false)` to temporarily skip validations (debugging only)
5. Test callbacks in isolation: `model.run_callbacks(:save) { model.save! }`
6. Check for skipped validations: ensure using `update!`, not `update_attribute`
7. Verify `after_commit` runs outside transaction: check logs for timing

---

## One-Minute Recap
- Validations enforce data integrity and run before save
- Callbacks hook into lifecycle events (before/after create/update/destroy)
- Use `after_commit` for side effects outside transactions (emails, APIs)
- Avoid callback hell: prefer explicit service objects for complex logic
- Concerns extract shared logic across models using `ActiveSupport::Concern`
