# Exercise: DSL Design Patterns

## Objective

Build a configuration DSL using the builder pattern and `instance_eval`, then refactor it to use block parameters for better clarity. You'll create a database connection configuration DSL similar to Rails' `database.yml`.

## Task

Create a `DatabaseConfig` DSL that lets users configure database connections with a clean, readable syntax.

### Desired Usage

```ruby
config = DatabaseConfig.build do
  database "myapp_production"
  host "db.example.com"
  port 5432
  pool_size 10
  timeout 5000

  replica do
    host "replica1.example.com"
    port 5432
  end
end

config.to_h
# => { database: "myapp_production", host: "db.example.com", port: 5432,
#      pool_size: 10, timeout: 5000, replica: { host: "replica1.example.com", port: 5432 } }
```

---

## Part 1: Basic DSL (10 minutes)

### Task 1.1: Implement `DatabaseConfig` with `instance_eval`

Create a file `database_config.rb`:

```ruby
class DatabaseConfig
  attr_reader :settings

  def initialize
    @settings = {}
  end

  def self.build(&block)
    config = new
    config.instance_eval(&block)
    config
  end

  def database(name)
    @settings[:database] = name
  end

  def host(value)
    @settings[:host] = value
  end

  def port(value)
    @settings[:port] = value
  end

  def pool_size(value)
    @settings[:pool_size] = value
  end

  def timeout(value)
    @settings[:timeout] = value
  end

  def to_h
    @settings
  end
end
```

**Test it in IRB:**

```ruby
require_relative "database_config"

config = DatabaseConfig.build do
  database "myapp_production"
  host "db.example.com"
  port 5432
  pool_size 10
end

puts config.to_h
# => { database: "myapp_production", host: "db.example.com", port: 5432, pool_size: 10 }
```

**Acceptance Criteria:**

- [ ] `DatabaseConfig.build` accepts a block
- [ ] Methods like `database`, `host`, `port` set configuration values
- [ ] `to_h` returns a hash of settings
- [ ] Chaining is not required (each method call is independent)

---

## Part 2: Add Nested Configuration (10 minutes)

### Task 2.1: Support Nested `replica` Block

Add support for configuring replicas:

```ruby
def replica(&block)
  replica_config = DatabaseConfig.new
  replica_config.instance_eval(&block)
  @settings[:replica] = replica_config.to_h
end
```

**Test nested blocks:**

```ruby
config = DatabaseConfig.build do
  database "myapp_production"
  host "db.example.com"

  replica do
    host "replica1.example.com"
    port 5433
  end
end

puts config.to_h
# => { database: "myapp_production", host: "db.example.com",
#      replica: { host: "replica1.example.com", port: 5433 } }
```

**Acceptance Criteria:**

- [ ] `replica` accepts a block
- [ ] Nested block sets replica-specific configuration
- [ ] `to_h` includes nested `:replica` key

---

## Part 3: Refactor to Block Parameters (10 minutes)

### Task 3.1: Replace `instance_eval` with Explicit Block Parameter

Refactor to make `self` explicit:

```ruby
class DatabaseConfig
  attr_reader :settings

  def initialize
    @settings = {}
  end

  def self.build(&block)
    config = new
    block.call(config)  # Pass config as parameter instead of instance_eval
    config
  end

  # ... same methods ...

  def replica(&block)
    replica_config = DatabaseConfig.new
    block.call(replica_config)
    @settings[:replica] = replica_config.to_h
  end

  def to_h
    @settings
  end
end
```

**Updated usage:**

```ruby
config = DatabaseConfig.build do |c|
  c.database "myapp_production"
  c.host "db.example.com"

  c.replica do |r|
    r.host "replica1.example.com"
  end
end
```

**Acceptance Criteria:**

- [ ] Block receives `config` as a parameter (e.g., `do |c|`)
- [ ] `self` remains unchanged inside the block
- [ ] Behavior is identical to `instance_eval` version

---

## Part 4: Add Method Chaining (5 minutes)

### Task 4.1: Enable Fluent Interface

Make methods return `self` for chaining:

```ruby
def database(name)
  @settings[:database] = name
  self
end

def host(value)
  @settings[:host] = value
  self
end

# ... update all methods to return self ...
```

**Test chaining:**

```ruby
config = DatabaseConfig.new
  .database("myapp_production")
  .host("db.example.com")
  .port(5432)

puts config.to_h
```

**Acceptance Criteria:**

- [ ] All configuration methods return `self`
- [ ] Methods can be chained in sequence
- [ ] Both block and chaining styles work

---

## Stretch Goals

### 1. Add Validation

```ruby
def port(value)
  raise ArgumentError, "Port must be between 1-65535" unless (1..65535).cover?(value)
  @settings[:port] = value
  self
end
```

### 2. Support Multiple Replicas

```ruby
def replica(&block)
  @settings[:replicas] ||= []
  replica_config = DatabaseConfig.new
  block.call(replica_config)
  @settings[:replicas] << replica_config.to_h
  self
end
```

Usage:

```ruby
config = DatabaseConfig.build do |c|
  c.replica { |r| r.host "replica1.example.com" }
  c.replica { |r| r.host "replica2.example.com" }
end
```

### 3. Add `method_missing` for Dynamic Keys

```ruby
def method_missing(method, *args)
  if args.length == 1
    @settings[method] = args.first
    self
  else
    super
  end
end

def respond_to_missing?(method, include_private = false)
  args.length == 1 || super
end
```

Usage:

```ruby
config.custom_setting "value"  # No need to define method explicitly
```

---

## Verification Steps

### Test All Features

```ruby
# Full test
config = DatabaseConfig.build do |c|
  c.database "production_db"
  c.host "primary.example.com"
  c.port 5432
  c.pool_size 20

  c.replica do |r|
    r.host "replica.example.com"
    r.port 5433
  end
end

result = config.to_h
puts result

# Expected output:
# {
#   database: "production_db",
#   host: "primary.example.com",
#   port: 5432,
#   pool_size: 20,
#   replica: { host: "replica.example.com", port: 5433 }
# }
```

### Compare Both Approaches

Create a table comparing `instance_eval` vs block parameters:

| Aspect | `instance_eval` | Block Parameter |
|--------|----------------|-----------------|
| `self` context | Changes to config object | Remains unchanged |
| Syntax | `database "value"` | `c.database "value"` |
| Access to outer scope | Lost | Maintained |
| Debugging clarity | Harder (different `self`) | Easier (explicit receiver) |

**Which is better?** Block parameters are generally preferred for clarity, but `instance_eval` looks cleaner for pure DSLs (like RSpec).

---

## Time Estimate

25 minutes total

## Solution Notes

**Common gotchas:**

1. **Forgetting to return `self`:** Without `self`, chaining breaks.
2. **Scope confusion with `instance_eval`:** Instance variables from outer scope aren't accessible.
3. **No validation:** Always validate inputs (port ranges, required fields).

**Best practices:**

- Provide both DSL and plain Ruby interfaces
- Document expected usage with examples
- Keep DSLs shallow—avoid deeply nested blocks
- Use block parameters for clarity unless simplicity demands `instance_eval`
