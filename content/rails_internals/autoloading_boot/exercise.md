# Exercise: Zeitwerk/Autoloading & Boot Sequence

## Objective
Debug autoload errors, verify Zeitwerk naming conventions, and measure boot time.

## Task
In a Rails app:

1. Create a service object with correct Zeitwerk naming
2. Intentionally create a naming mismatch and debug the error
3. Run `bin/rails zeitwerk:check` to verify conventions
4. Measure and log boot time

## Acceptance Criteria
- [ ] Service object `PdfGenerator` in `app/services/pdf_generator.rb` loads without error
- [ ] Misnamed file triggers "expected to define constant" error
- [ ] `bin/rails zeitwerk:check` passes after fixing the error
- [ ] Boot time logged to console on app startup
- [ ] Can explain why `user_profile.rb` must define `UserProfile`, not `UserProfiles`

## Verification Steps

1. Run `bin/rails console` and execute:

```ruby
PdfGenerator.new.generate
# Should output "Generating PDF..."

```

2. Run `bin/rails zeitwerk:check` — should see "All is good!"

3. Check boot time output:

```bash
bin/rails runner 'puts "Ready"'
# Should show: "Boot time: 2.3s"

```

## Setup Code

### Step 1: Add Custom Autoload Path

Edit `config/application.rb`:

```ruby
module YourApp
  class Application < Rails::Application
    config.autoload_paths += %W[#{config.root}/app/services]
  end
end

```

### Step 2: Create Service Object

Create `app/services/pdf_generator.rb`:

```ruby
class PdfGenerator
  def generate
    puts "Generating PDF..."
  end
end

```

Test in console:

```bash
bin/rails console
> PdfGenerator.new.generate
# Output: "Generating PDF..."

```

### Step 3: Create Naming Mismatch (Debugging Practice)

Rename file to `app/services/pdf_creator.rb` (but keep class name `PdfGenerator`):

```bash
mv app/services/pdf_generator.rb app/services/pdf_creator.rb

```

Try loading:

```bash
bin/rails console
> PdfGenerator.new
# Error: uninitialized constant PdfGenerator

```

Run Zeitwerk check:

```bash
bin/rails zeitwerk:check
# Error: expected file app/services/pdf_creator.rb to define constant PdfCreator, but didn't

```

**Fix:** Rename file back to `pdf_generator.rb`.

### Step 4: Measure Boot Time

Edit `config/application.rb`:

```ruby
module YourApp
  class Application < Rails::Application
    config.boot_start_time = Time.now

    config.after_initialize do
      boot_time = Time.now - config.boot_start_time
      puts "Boot time: #{boot_time.round(2)}s"
    end
  end
end

```

Run:

```bash
bin/rails runner 'puts "Ready"'
# Output: Boot time: 1.8s

```

### Step 5: Create Nested Module

Create `app/services/billing/invoice_generator.rb`:

```ruby
module Billing
  class InvoiceGenerator
    def generate
      puts "Generating invoice..."
    end
  end
end

```

**Note:** Zeitwerk automatically infers the `Billing` module from the directory. No `billing.rb` needed unless you want custom module code.

Test:

```bash
bin/rails console
> Billing::InvoiceGenerator.new.generate
# Output: "Generating invoice..."

```

## Stretch (Optional)

1. Add a circular dependency between two service objects and fix it:

Create `app/services/order_processor.rb`:

```ruby
class OrderProcessor
  def process
    PaymentHandler.new.charge  # loads PaymentHandler
  end
end

```

Create `app/services/payment_handler.rb`:

```ruby
class PaymentHandler
  def charge
    OrderProcessor.new.process  # circular!
  end
end

```

Try loading:

```bash
bin/rails console
> OrderProcessor.new.process
# Error: stack level too deep (circular dependency)

```

**Fix:** Use dependency injection or extract shared logic to a third class.

2. Profile which initializers are slow:

Edit `config/initializers/example.rb`:

```ruby
puts "Loading example initializer..."
sleep 0.5  # simulate slow initializer

```

Run `bin/rails runner 'puts "Ready"'` and see boot time increase.

## Time Estimate
18 minutes
