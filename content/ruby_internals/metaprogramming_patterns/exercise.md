# Exercise: Metaprogramming Patterns

## Objective
Build a simple DSL using `method_missing` and `define_method` to create a flexible configuration system. You'll implement metaprogramming techniques and learn when to prefer explicit methods over dynamic ones.

## Task
Create a `ConfigBuilder` class that allows setting and getting configuration values using both `method_missing` and `define_method`, then refactor to compare approaches.

## Acceptance Criteria
- [ ] `ConfigBuilder` handles undefined getter/setter methods via `method_missing`
- [ ] `respond_to_missing?` correctly reports available methods
- [ ] `define_method` version creates explicit methods for known config keys
- [ ] Both versions produce identical behavior but different introspection results
- [ ] Performance difference between approaches is measurable

## Setup

### Step 1: Create Test File

```bash
mkdir -p ~/metaprogramming_demo
cd ~/metaprogramming_demo
touch config_builder.rb
touch test_config.rb

```

### Step 2: Implement method_missing Version

Create `config_builder.rb`:

```ruby
class ConfigBuilder
  def initialize
    @config = {}
  end

  def method_missing(method_name, *args)
    method_string = method_name.to_s

    if method_string.end_with?("=")
      # Setter: config.database_url = "..."
      key = method_string.chomp("=").to_sym
      @config[key] = args.first
    elsif @config.key?(method_name)
      # Getter: config.database_url
      @config[method_name]
    else
      super
    end
  end

  def respond_to_missing?(method_name, include_private = false)
    method_string = method_name.to_s
    method_string.end_with?("=") || @config.key?(method_name) || super
  end

  def to_h
    @config
  end
end

```

### Step 3: Test method_missing Behavior

Create `test_config.rb`:

```ruby
require_relative "config_builder"

config = ConfigBuilder.new

# Set values dynamically
config.database_url = "postgres://localhost/mydb"
config.api_key = "secret123"
config.timeout = 30

# Get values
puts config.database_url
# => "postgres://localhost/mydb"

puts config.api_key
# => "secret123"

# Check introspection
puts config.respond_to?(:database_url)
# => true

puts config.respond_to?(:nonexistent)
# => false

# List all methods
puts config.methods.grep(/database/)
# => [] (method_missing doesn't create real methods!)

puts config.to_h
# => {:database_url=>"postgres://localhost/mydb", :api_key=>"secret123", :timeout=>30}

```

Run it:

```bash
ruby test_config.rb

```

### Step 4: Refactor Using define_method

Create `config_builder_explicit.rb`:

```ruby
class ConfigBuilderExplicit
  KNOWN_KEYS = [:database_url, :api_key, :timeout, :host, :port]

  def initialize
    @config = {}

    # Define getter and setter for each known key
    KNOWN_KEYS.each do |key|
      self.class.send(:define_method, key) do
        @config[key]
      end

      self.class.send(:define_method, "#{key}=") do |value|
        @config[key] = value
      end
    end
  end

  def to_h
    @config
  end
end

```

### Step 5: Test define_method Version

Create `test_explicit.rb`:

```ruby
require_relative "config_builder_explicit"

config = ConfigBuilderExplicit.new

config.database_url = "postgres://localhost/mydb"
config.api_key = "secret123"

puts config.database_url
# => "postgres://localhost/mydb"

# Introspection now works!
puts config.methods.grep(/database/)
# => [:database_url, :database_url=]

puts config.respond_to?(:api_key)
# => true

# But unknown keys raise NoMethodError
begin
  config.unknown_key = "value"
rescue NoMethodError => e
  puts "Error: #{e.message}"
end

```

### Step 6: Benchmark Performance

Create `benchmark_comparison.rb`:

```ruby
require "benchmark"
require_relative "config_builder"
require_relative "config_builder_explicit"

n = 100_000

Benchmark.bm(20) do |x|
  x.report("method_missing:") do
    config = ConfigBuilder.new
    n.times do
      config.database_url = "postgres://localhost"
      config.database_url
    end
  end

  x.report("define_method:") do
    config = ConfigBuilderExplicit.new
    n.times do
      config.database_url = "postgres://localhost"
      config.database_url
    end
  end
end

```

Run benchmark:

```bash
ruby benchmark_comparison.rb

```

**Expected output:**

```
                           user     system      total        real
method_missing:        0.050000   0.000000   0.050000 (  0.052341)
define_method:         0.010000   0.000000   0.010000 (  0.010234)

```

`define_method` is **5-10x faster** because Ruby doesn't walk the ancestor chain.

---

## Part 2: Build a Simple Query DSL

### Task 2.1: Create a Chainable Query Builder

Create `query_builder.rb`:

```ruby
class QueryBuilder
  def initialize(table)
    @table = table
    @conditions = []
    @order_by = nil
    @limit_value = nil
  end

  def where(condition)
    @conditions << condition
    self  # Return self for chaining
  end

  def order(column)
    @order_by = column
    self
  end

  def limit(n)
    @limit_value = n
    self
  end

  def to_sql
    sql = "SELECT * FROM #{@table}"
    sql += " WHERE #{@conditions.join(' AND ')}" if @conditions.any?
    sql += " ORDER BY #{@order_by}" if @order_by
    sql += " LIMIT #{@limit_value}" if @limit_value
    sql
  end
end

```

### Task 2.2: Test Chaining

Create `test_query.rb`:

```ruby
require_relative "query_builder"

query = QueryBuilder.new("users")
  .where("active = true")
  .where("age > 18")
  .order("created_at DESC")
  .limit(10)

puts query.to_sql
# => SELECT * FROM users WHERE active = true AND age > 18 ORDER BY created_at DESC LIMIT 10

```

---

## Part 3: Advanced - Class Macros

### Task 3.1: Build attr_accessor Using Metaprogramming

Create `custom_attr.rb`:

```ruby
module CustomAttr
  def custom_accessor(*attrs)
    attrs.each do |attr|
      define_method(attr) do
        instance_variable_get("@#{attr}")
      end

      define_method("#{attr}=") do |value|
        instance_variable_set("@#{attr}", value)
      end
    end
  end
end

class Person
  extend CustomAttr
  custom_accessor :name, :age, :email
end

person = Person.new
person.name = "Alice"
person.age = 30

puts person.name
# => "Alice"

puts person.methods.grep(/name/)
# => [:name, :name=]

```

---

## Stretch Goals

1. **Add type checking to ConfigBuilder:**

```ruby
def method_missing(method_name, *args)
  if method_name.to_s.end_with?("=")
    key = method_name.to_s.chomp("=").to_sym
    value = args.first
    raise TypeError, "Expected String" unless value.is_a?(String)
    @config[key] = value
  else
    super
  end
end

```

2. **Create a class macro that logs method calls:**

```ruby
module Loggable
  def log_calls(*method_names)
    method_names.each do |method_name|
      original_method = instance_method(method_name)

      define_method(method_name) do |*args, &block|
        puts "Calling #{method_name} with #{args.inspect}"
        original_method.bind(self).call(*args, &block)
      end
    end
  end
end

class Calculator
  extend Loggable

  def add(a, b)
    a + b
  end

  log_calls :add
end

calc = Calculator.new
calc.add(2, 3)
# => Calling add with [2, 3]
# => 5

```

3. **Use `instance_eval` to create a DSL:**

```ruby
class RouteBuilder
  def initialize(&block)
    @routes = []
    instance_eval(&block) if block_given?
  end

  def get(path, to:)
    @routes << { method: :get, path: path, controller: to }
  end

  def post(path, to:)
    @routes << { method: :post, path: path, controller: to }
  end

  def routes
    @routes
  end
end

routes = RouteBuilder.new do
  get "/users", to: "users#index"
  post "/users", to: "users#create"
end

puts routes.routes.inspect
# => [{:method=>:get, :path=>"/users", :controller=>"users#index"}, {:method=>:post, :path=>"/users", :controller=>"users#create"}]

```

---

## Verification

Run all tests:

```bash
ruby test_config.rb
ruby test_explicit.rb
ruby benchmark_comparison.rb
ruby test_query.rb
ruby custom_attr.rb

```

All scripts should run without errors and demonstrate:
- `method_missing` intercepts undefined methods
- `respond_to_missing?` maintains introspection
- `define_method` creates real methods (faster, better introspection)
- Chaining enables DSL-like syntax
- Class macros reduce boilerplate

---

## Solution Notes

**Common Gotchas:**

1. **Forgetting `respond_to_missing?`:** Always implement it when using `method_missing`.
2. **Not returning `self` for chaining:** DSL methods must return `self` to enable `.where(...).order(...)`.
3. **Using `define_method` at instance level:** Call it on `self.class` or inside class definition.
4. **Performance assumptions:** Always benchmark; `method_missing` is slower.
5. **Debugging confusion:** Use `obj.methods.grep(/pattern/)` to see what actually exists.

**Key Takeaways:**
- Use `define_method` when you know method names upfront.
- Reserve `method_missing` for truly dynamic cases (e.g., Rails `find_by_*`).
- Metaprogramming trades clarity for brevity; use sparingly.
- Always measure performance impact in real-world scenarios.

---

## Time Estimate
25 minutes
