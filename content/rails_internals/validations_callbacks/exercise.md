# Exercise: Validations, Callbacks & Concerns

## Objective
Write custom validations, add lifecycle callbacks, and extract shared logic into a concern.

## Task
In a Rails app with `Product` and `Article` models:

1. Add validations to ensure price > 0 and SKU is unique
2. Add a `before_save` callback that normalizes SKU to uppercase
3. Add an `after_commit` callback that logs product creation
4. Create a `Publishable` concern with `published` scope and validation
5. Include the concern in both models

## Acceptance Criteria
- [ ] Product validation rejects price ≤ 0
- [ ] SKU is automatically uppercased before save
- [ ] Log entry appears after product is created (not before commit)
- [ ] Both Product and Article have `.published` scope
- [ ] Both models validate `published_at` is in the past when published
- [ ] Can explain why `after_commit` is better than `after_create` for logging

## Verification Steps

1. Test validations in console:

```ruby
product = Product.new(name: "Widget", price: -5)
product.valid?  # => false
product.errors.full_messages  # => ["Price must be greater than 0"]

```

2. Test SKU normalization:

```ruby
product = Product.create!(name: "Gadget", price: 10, sku: "abc-123")
product.sku  # => "ABC-123"

```

3. Check log for `after_commit` message:

```
Product created: ABC-123

```

4. Test concern:

```ruby
Article.published.count
Product.published.count

```

## Setup Code

### Step 1: Create Models

```bash
rails new validations_demo --skip-javascript
cd validations_demo
bin/rails generate model Product name:string price:decimal sku:string published:boolean published_at:datetime
bin/rails generate model Article title:string body:text published:boolean published_at:datetime
bin/rails db:migrate

```

### Step 2: Add Validations

Edit `app/models/product.rb`:

```ruby
class Product < ApplicationRecord
  validates :name, presence: true
  validates :price, numericality: { greater_than: 0 }
  validates :sku, uniqueness: true, allow_blank: true

  before_save :normalize_sku
  after_commit :log_creation, on: :create

  private

  def normalize_sku
    self.sku = sku.upcase if sku.present?
  end

  def log_creation
    Rails.logger.info "Product created: #{sku}"
  end
end

```

### Step 3: Create Publishable Concern

Create `app/models/concerns/publishable.rb`:

```ruby
module Publishable
  extend ActiveSupport::Concern

  included do
    validates :published_at, presence: true, if: :published?
    validate :published_at_in_past, if: :published?

    scope :published, -> { where(published: true) }
    scope :unpublished, -> { where(published: false) }
  end

  def published_at_in_past
    return if published_at.blank?
    errors.add(:published_at, "must be in the past") if published_at > Time.current
  end

  def publish!
    update!(published: true, published_at: Time.current)
  end
end

```

### Step 4: Include Concern in Models

Edit `app/models/product.rb`:

```ruby
class Product < ApplicationRecord
  include Publishable
  # ... existing validations and callbacks
end

```

Edit `app/models/article.rb`:

```ruby
class Article < ApplicationRecord
  include Publishable
end

```

### Step 5: Test in Console

```bash
bin/rails console

```

```ruby
# Test validations
product = Product.new(name: "Widget", price: -5)
product.valid?  # => false
product.errors.full_messages

# Test SKU normalization
product = Product.create!(name: "Gadget", price: 10, sku: "abc-123")
product.sku  # => "ABC-123"

# Test concern
article = Article.create!(title: "Test", body: "Content", published: true, published_at: 1.day.ago)
Article.published.count  # => 1

# Test future date validation
article = Article.new(title: "Future", body: "Content", published: true, published_at: 1.day.from_now)
article.valid?  # => false
article.errors.full_messages  # => ["Published at must be in the past"]

# Test publish! method
product.publish!
product.published?  # => true

```

## Stretch (Optional)

1. Add a custom validator class:

Create `app/validators/email_validator.rb`:

```ruby
class EmailValidator < ActiveModel::EachValidator
  def validate_each(record, attribute, value)
    unless value =~ /\A[^@\s]+@[^@\s]+\z/
      record.errors.add(attribute, "is not a valid email")
    end
  end
end

```

Use in model:

```ruby
validates :contact_email, email: true

```

2. Add a callback that prevents deletion:

```ruby
before_destroy :prevent_if_published, prepend: true

def prevent_if_published
  if published?
    errors.add(:base, "Cannot delete published product")
    throw(:abort)
  end
end

```

## Time Estimate
20 minutes
