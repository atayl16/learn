# Metaprogramming Patterns

## What It Is
Metaprogramming in Ruby is writing code that writes code at runtime. Ruby's dynamic nature allows methods to be defined on the fly (`define_method`), missing methods to be intercepted (`method_missing`), code to be evaluated in different contexts (`instance_eval`), and messages to be sent dynamically (`send`). These techniques enable elegant DSLs and reduce boilerplate, but come with trade-offs in readability and debuggability.

## Why It Matters
Metaprogramming powers Rails' declarative syntax: `has_many :posts` defines methods dynamically, `validates :email, presence: true` generates validation logic, and `scope :active, -> { ... }` creates chainable queries. Understanding these patterns helps you leverage Ruby's flexibility without sacrificing maintainability. Knowing when *not* to metaprogram is equally crucial.

## When to Use
- Creating DSLs for configuration or business logic (RSpec, Rails routing)
- Eliminating repetitive method definitions (attr_accessor patterns)
- Building framework-level abstractions (ActiveRecord associations)
- Forwarding method calls dynamically (delegators, proxies)

## Three Common Pitfalls
1. **Overusing method_missing:** It's a catch-all that breaks introspection (`respond_to?`), makes stack traces cryptic, and slows performance (Ruby checks all ancestors before calling `method_missing`). Define explicit methods whenever possible.
2. **Breaking respond_to?:** If you define `method_missing`, always override `respond_to_missing?` to maintain Ruby's introspection contract.
3. **Debugging nightmares:** Metaprogrammed code hides method definitions from grep/editors. Always document what gets generated and where. Consider using `Module.prepend` or class methods instead of heavy metaprogramming.

---

## method_missing

Intercepts calls to undefined methods:

```ruby
class DynamicFinder
  def method_missing(method_name, *args)
    if method_name.to_s.start_with?("find_by_")
      attribute = method_name.to_s.sub("find_by_", "")
      puts "Searching for #{attribute}: #{args.first}"
    else
      super
    end
  end

  def respond_to_missing?(method_name, include_private = false)
    method_name.to_s.start_with?("find_by_") || super
  end
end

finder = DynamicFinder.new
finder.find_by_email("alice@example.com")
# => Searching for email: alice@example.com

finder.respond_to?(:find_by_name)
# => true (thanks to respond_to_missing?)

```

**Rails example (ActiveRecord):**

```ruby
User.find_by_email("bob@example.com")
# Calls method_missing, generates: User.where(email: "bob@example.com").first

```

**When to avoid:** If you know the method names ahead of time, define them explicitly. `method_missing` is a last resort.

---

## define_method

Defines methods dynamically at runtime:

```ruby
class Report
  [:daily, :weekly, :monthly].each do |period|
    define_method("#{period}_sales") do
      puts "Fetching #{period} sales..."
    end
  end
end

report = Report.new
report.daily_sales
# => Fetching daily sales...

```

**Rails example (attr_accessor):**

```ruby
# ActiveModel::AttributeMethods uses define_method
class User
  [:name, :email].each do |attr|
    define_method(attr) { instance_variable_get("@#{attr}") }
    define_method("#{attr}=") { |val| instance_variable_set("@#{attr}", val) }
  end
end

```

**Advantage over method_missing:** Defined methods appear in `.methods`, show up in stack traces, and perform better.

---

## Class Macros

Class methods that generate instance methods or behavior:

```ruby
class ActiveRecord::Base
  def self.belongs_to(name)
    define_method(name) do
      # Load associated record
      association_id = send("#{name}_id")
      name.to_s.classify.constantize.find(association_id)
    end
  end
end

class Post < ActiveRecord::Base
  belongs_to :user
end

# Post.new.user calls dynamically defined method

```

**Rails examples:**
- `has_many :posts` → defines `posts`, `posts=`, `posts<<`, `posts.build`, etc.
- `validates :email, presence: true` → adds validation callback
- `attr_accessor :name` → defines `name` and `name=`

---

## Building DSLs

Domain-Specific Languages use metaprogramming to create expressive APIs:

```ruby
class QueryBuilder
  def initialize
    @conditions = []
  end

  def where(condition)
    @conditions << condition
    self
  end

  def order(column)
    @order = column
    self
  end

  def to_sql
    "SELECT * FROM users WHERE #{@conditions.join(' AND ')} ORDER BY #{@order}"
  end
end

query = QueryBuilder.new
         .where("active = true")
         .where("age > 18")
         .order("created_at")
query.to_sql
# => "SELECT * FROM users WHERE active = true AND age > 18 ORDER BY created_at"

```

**Rails routing DSL:**

```ruby
Rails.application.routes.draw do
  resources :posts do
    member do
      post :publish
    end
  end
end

```

Uses `instance_eval` to evaluate the block in the context of a router object.

---

## send and public_send

Call methods dynamically by name:

```ruby
class User
  def name
    "Alice"
  end

  private

  def secret
    "password123"
  end
end

user = User.new
user.send(:name)
# => "Alice"

user.send(:secret)
# => "password123" (bypasses privacy)

user.public_send(:secret)
# => NoMethodError (respects privacy)

```

**Use case:** Delegators, method forwarding, dynamic dispatching.

**Danger:** `send` bypasses encapsulation. Prefer `public_send` unless you intentionally need private access.

---

## instance_eval and class_eval

Execute code in the context of an object or class:

```ruby
class Box
  def initialize
    @contents = []
  end
end

box = Box.new
box.instance_eval do
  @contents << "Item 1"
  @contents << "Item 2"
end

box.instance_eval { @contents }
# => ["Item 1", "Item 2"]

```

**class_eval (define methods on classes):**

```ruby
User.class_eval do
  def full_name
    "#{first_name} #{last_name}"
  end
end

```

**Rails example (concerns):**

```ruby
module Taggable
  extend ActiveSupport::Concern

  included do
    has_many :tags
  end
end

# ActiveSupport::Concern uses class_eval to inject has_many when included

```

---

## When NOT to Use Metaprogramming

### 1. When Explicit Code is Clearer

**Bad:**

```ruby
[:name, :email, :phone].each do |attr|
  define_method("print_#{attr}") { puts send(attr) }
end

```

**Good:**

```ruby
def print_name
  puts name
end

def print_email
  puts email
end

```

### 2. When It Breaks Tooling

Metaprogramming hides method definitions from:
- Code editors (autocomplete, go-to-definition)
- Static analysis tools (RuboCop, Sorbet)
- Grep/search
- New team members reading code

### 3. When Performance Matters

`method_missing` is 10x slower than defined methods because Ruby walks the entire ancestor chain first.

### 4. When Debugging Becomes Painful

Stack traces from metaprogrammed code are harder to follow. If you're spending more time debugging than you saved writing code, stop metaprogramming.

---

## Rails Metaprogramming Examples

### has_many (ActiveRecord)

```ruby
class User < ApplicationRecord
  has_many :posts
end

# Generates these methods:
# - user.posts
# - user.posts=(posts)
# - user.post_ids
# - user.posts.build(attrs)
# - user.posts.create(attrs)
# - user.posts.destroy_all

```

**How it works:**

```ruby
def self.has_many(name, **options)
  define_method(name) do
    # Load association
  end

  define_method("#{name}=") do |records|
    # Assign association
  end

  # ... many more methods
end

```

### validates (ActiveModel)

```ruby
class User < ApplicationRecord
  validates :email, presence: true, uniqueness: true
end

```

**How it works:**

```ruby
def self.validates(*attributes, **options)
  options.each do |validator_name, validator_options|
    validator_class = "#{validator_name}_validator".classify.constantize
    validator_class.new(attributes: attributes, **validator_options).validate(self)
  end
end

```

---

## Best Practices

1. **Document generated methods:** Use YARD comments or README to list what gets created.
2. **Fail fast:** Raise clear errors when metaprogramming setup fails.
3. **Benchmark:** Profile `method_missing` vs. `define_method` if performance matters.
4. **Override respond_to_missing?:** Always pair with `method_missing`.
5. **Use modules for DSLs:** Keep metaprogramming isolated in mixins/concerns.
6. **Prefer class methods over instance_eval:** Easier to trace.
7. **Test edge cases:** Missing methods, nil arguments, wrong types.

---

## Debugging Checklist

When metaprogrammed code breaks:

1. Check what methods exist: `obj.methods.grep(/pattern/)`
2. Inspect method source: `obj.method(:foo).source_location`
3. Enable verbose logging: `set_trace_func` or `TracePoint`
4. Check `respond_to?` and `respond_to_missing?` consistency
5. Use `Kernel#caller` to trace where methods are defined
6. Search for `define_method`, `class_eval`, `instance_eval` in codebase
7. Add `puts` inside metaprogramming blocks to see what gets generated

---

## One-Minute Recap
- `method_missing` intercepts undefined methods; always pair with `respond_to_missing?`
- `define_method` creates methods dynamically; prefer over `method_missing` when possible
- Class macros (`has_many`, `validates`) are class methods that generate instance behavior
- DSLs use `instance_eval` and chaining for expressive APIs
- `send` / `public_send` call methods by name; `public_send` respects privacy
- Avoid metaprogramming when explicit code is clearer, faster, or more debuggable
- Rails uses metaprogramming extensively; understanding it unlocks framework internals
