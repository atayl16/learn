# DSL Design Patterns

## What It Is

A Domain-Specific Language (DSL) is a mini-language tailored to a specific problem domain, making code read like natural instructions. Ruby's flexible syntax and metaprogramming features make it ideal for internal DSLs—code that looks like configuration but executes as Ruby. Common examples: RSpec's `describe/it`, FactoryBot's `factory :user do`, Rails routes, and Rake tasks.

## Why It Matters

Well-designed DSLs improve readability by hiding boilerplate and expressing intent clearly. They let developers think in domain terms (e.g., "factory," "route," "test") instead of Ruby mechanics. But poorly designed DSLs become "magic"—hard to debug, test, or understand. Senior engineers balance expressiveness with transparency, knowing when to build a DSL versus plain Ruby classes.

## When to Use

- **Configuration:** app settings, feature flags, test factories
- **Declarative APIs:** routing (Rails), state machines, validation rules
- **Testing frameworks:** RSpec's fluent assertions, Capybara's visit/click
- **Builder patterns:** HTML/XML generation, query builders (ActiveRecord)

## Three Common Pitfalls

1. **Overusing `instance_eval` without context:** `instance_eval` changes `self`, making instance variables and methods confusing. Prefer block parameters or builder objects for clarity.
2. **Too much magic:** If developers can't grep for method definitions or need a guide to understand code flow, the DSL is too implicit. Explicitness beats cleverness.
3. **No escape hatch:** DSLs should degrade gracefully to plain Ruby when edge cases arise. Always provide a way to drop down to explicit code.

---

## Core Building Blocks

### 1. `instance_eval` — Change Context

Evaluates a block in the context of an object, changing `self`:

```ruby
class ConfigBuilder
  def initialize
    @settings = {}
  end

  def setting(key, value)
    @settings[key] = value
  end

  def build(&block)
    instance_eval(&block)
    @settings
  end
end

config = ConfigBuilder.new.build do
  setting :timeout, 30
  setting :retries, 3
end
# => { timeout: 30, retries: 3 }
```

**Trade-off:** Clean syntax, but `self` changes. Instance variables like `@my_var` from outer scope won't be accessible inside the block.

**Better alternative (block parameter):**

```ruby
def build
  yield(self)
  @settings
end

config = ConfigBuilder.new.build do |c|
  c.setting :timeout, 30
end
```

Block parameters make `self` explicit, avoiding confusion.

---

### 2. `class_eval` — Define Methods Dynamically

Executes code in the context of a class, useful for monkey-patching or metaprogramming:

```ruby
class User; end

User.class_eval do
  def greet
    "Hello, #{name}"
  end
end

user = User.new
user.greet  # method defined dynamically
```

**Use case:** Gems that extend ActiveRecord models (e.g., Devise adding `authenticatable` methods).

---

### 3. Builder Pattern — Fluent Chaining

Builders return `self` to enable method chaining:

```ruby
class QueryBuilder
  def initialize
    @conditions = []
    @order = nil
  end

  def where(condition)
    @conditions << condition
    self  # return self for chaining
  end

  def order(field)
    @order = field
    self
  end

  def to_sql
    sql = "SELECT * FROM users"
    sql += " WHERE #{@conditions.join(' AND ')}" if @conditions.any?
    sql += " ORDER BY #{@order}" if @order
    sql
  end
end

query = QueryBuilder.new.where("active = true").where("age > 18").order("created_at")
query.to_sql
# => "SELECT * FROM users WHERE active = true AND age > 18 ORDER BY created_at"
```

**Fluent interfaces** make code read left-to-right like prose. ActiveRecord uses this pattern extensively.

---

## Real-World DSL Examples

### FactoryBot

```ruby
FactoryBot.define do
  factory :user do
    name { "Alice" }
    email { "alice@example.com" }

    trait :admin do
      role { "admin" }
    end
  end
end

create(:user, :admin)
```

**How it works:**

1. `define` takes a block and calls `instance_eval`
2. `factory` registers a factory in a hash
3. Methods like `name`, `email` store attribute definitions
4. `create` builds the object using stored definitions

---

### RSpec

```ruby
describe User do
  it "validates email format" do
    user = User.new(email: "invalid")
    expect(user).not_to be_valid
  end
end
```

**How it works:**

1. `describe` creates an `ExampleGroup` class
2. `it` defines a test method
3. `expect` builds a matcher object
4. `be_valid` delegates to `user.valid?`

RSpec's DSL hides class definitions and test harness setup, letting you focus on behavior.

---

## Designing Your Own DSL

### Step 1: Define the Goal

**Bad DSL goal:** "Make Ruby look like JSON."
**Good DSL goal:** "Let users configure caching rules without knowing Redis internals."

### Step 2: Start with Plain Ruby

Before metaprogramming, write the desired usage in plain Ruby:

```ruby
cache = CacheConfig.new
cache.add_rule(:user_profile, ttl: 3600)
cache.add_rule(:session, ttl: 1800)
```

### Step 3: Add Syntactic Sugar (If Needed)

```ruby
CacheConfig.configure do
  rule :user_profile, ttl: 3600
  rule :session, ttl: 1800
end
```

This is cleaner if you have many rules. Implement with:

```ruby
class CacheConfig
  def self.configure(&block)
    config = new
    config.instance_eval(&block)
    config
  end

  def rule(name, ttl:)
    @rules ||= {}
    @rules[name] = ttl
  end
end
```

### Step 4: Provide Escape Hatches

```ruby
CacheConfig.configure do
  rule :user_profile, ttl: 3600

  # Drop to plain Ruby for complex logic
  if ENV["PRODUCTION"]
    rule :session, ttl: 1800
  else
    rule :session, ttl: 60
  end
end
```

---

## Balancing Magic vs. Explicitness

### Too Much Magic

```ruby
config do
  setting :timeout  # where does this value come from?
end
```

Implicit behavior (reading from ENV?) makes debugging hard.

### Just Right

```ruby
config do |c|
  c.timeout = ENV.fetch("TIMEOUT", 30)
end
```

Explicit sources, clear flow.

### Trade-offs Box

- **Advantage:** DSLs reduce boilerplate and improve readability for repetitive tasks.
- **Cost:** Debugging is harder—stack traces go through metaprogramming layers. Requires documentation.
- **When to skip:** For one-off logic or when plain Ruby is already clear. Don't DSL for the sake of DSL.

---

## Debugging Checklist

1. **Check `self`:** If methods aren't found, verify what `self` is inside `instance_eval` blocks.
2. **Inspect generated code:** Use `method(:foo).source_location` to find where methods are defined.
3. **Trace execution:** `set_trace_func` or `TracePoint` shows method calls through DSL layers.
4. **Avoid deep nesting:** DSLs inside DSLs become unreadable. Keep it shallow.
5. **Document the DSL:** Include examples and explain the "magic."

---

## One-Minute Recap

- DSLs make code expressive by using Ruby as a configuration language
- `instance_eval` changes `self`; prefer block parameters for clarity
- Builder pattern chains methods via `return self`
- RSpec and FactoryBot exemplify clean DSL design
- Balance magic vs. explicitness: readability > cleverness
- Provide escape hatches to plain Ruby for edge cases
