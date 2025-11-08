# Zeitwerk/Autoloading & Boot Sequence

## What It Is
Zeitwerk is Rails' code loader (since Rails 6) that automatically loads classes and modules on demand by mapping file paths to Ruby constants. Autoloading happens in development; eager loading (loading all files upfront) happens in production. The boot sequence is the order Rails initializes components: config, gems, initializers, eager loading.

## Why It Matters
Misnamed files cause "uninitialized constant" errors. Circular dependencies freeze development servers. Slow boot times waste 30+ seconds per restart. Understanding Zeitwerk helps you structure code conventionally, debug autoload errors, and optimize boot time. Production apps eager-load to catch missing constants at deploy time, not runtime.

## When to Use
- Debugging: "uninitialized constant User" despite file existing
- Performance: boot takes >10 seconds; need to profile initializers
- Circular dependencies: "circular require" or stack overflow during autoload
- Production prep: ensure eager loading works before deploy

## Three Common Pitfalls
1. **File/class name mismatch:** `user_profile.rb` must define `UserProfile`, not `UserProfiles`. Zeitwerk is strict about naming.
2. **Circular dependencies in autoload:** `User` loads `Order` which loads `User` causes infinite loop. Fix: use strings (`has_many "orders"`) or extract shared logic.
3. **Autoload in production:** Don't. Autoload is disabled in production; missing constants crash at runtime. Run `bin/rails zeitwerk:check` before deploy.

---

## How Zeitwerk Works

Zeitwerk maps file paths to constants:

```
app/models/user.rb           → User
app/models/billing/invoice.rb → Billing::Invoice
app/services/pdf_generator.rb → PdfGenerator
```

**Convention:**
- `snake_case` file names → `CamelCase` constants
- Subdirectories become modules: `billing/` → `Billing::`
- One constant per file (no `class User; class Profile; end; end`)

When you reference `User`, Ruby triggers `const_missing`, which:
1. Checks Zeitwerk's registry
2. Loads `app/models/user.rb`
3. Defines the constant

---

## Autoload vs Eager Load

| Mode | When | How | Purpose |
|------|------|-----|---------|
| **Autoload** | Development/test | Load on first reference | Fast boot, reload changes |
| **Eager load** | Production | Load all files at boot | Catch errors early, thread-safe |

**Development:**
```ruby
# config/environments/development.rb
config.eager_load = false  # autoload instead
```

**Production:**
```ruby
# config/environments/production.rb
config.eager_load = true  # load everything upfront
```

**Check which files will eager-load:**
```ruby
Rails.autoloaders.main.all_expected_cpaths
```

---

## Rails Boot Sequence

1. **config/boot.rb** — loads Bundler, sets up gem environment
2. **config/application.rb** — defines application class, loads frameworks
3. **Gemfile gems** — loads in order (can add boot time)
4. **config/environments/{env}.rb** — environment-specific settings
5. **config/initializers/*.rb** — custom setup code (runs alphabetically)
6. **Eager loading** (production) — loads all autoload paths
7. **Database connection** — connects to DB
8. **Application ready** — server/console starts

**Profile boot time:**
```bash
RAILS_ENV=production time bin/rails runner 'puts "Booted"'
```

---

## Autoload Paths

Rails autoloads from:
- `app/models`
- `app/controllers`
- `app/helpers`
- `app/jobs`
- `app/mailers`
- etc.

**Add custom autoload paths:**
```ruby
# config/application.rb
config.autoload_paths += %W[#{config.root}/app/services #{config.root}/app/presenters]
```

**Check current paths:**
```ruby
Rails.autoloaders.main.dirs
```

---

## Debugging Autoload Errors

### Error: "Uninitialized constant User"

**Check:**
1. File exists: `app/models/user.rb`
2. File defines correct constant: `class User < ApplicationRecord`
3. File name matches constant: `user.rb` for `User`, `user_profile.rb` for `UserProfile`
4. Parent module exists: for `Billing::Invoice`, `app/models/billing.rb` must define `module Billing`

### Error: "Circular dependency detected"

**Cause:**
```ruby
# app/models/user.rb
class User < ApplicationRecord
  has_many :orders  # triggers Order load
end

# app/models/order.rb
class Order < ApplicationRecord
  belongs_to :user  # triggers User load → infinite loop
end
```

**Fix:**
Use strings to defer loading:
```ruby
class User < ApplicationRecord
  has_many :orders, class_name: "Order"
end
```

Or extract shared logic to a concern.

### Error: "Expected app/models/user.rb to define User, but did not"

**Cause:**
```ruby
# app/models/user.rb
class UserModel < ApplicationRecord  # wrong name
end
```

**Fix:**
Match file name to class name:
```ruby
class User < ApplicationRecord
end
```

---

## Zeitwerk Check

Before deploying, verify all constants:

```bash
bin/rails zeitwerk:check
```

Output:
```
Hold on, I am eager loading the application.
All is good!
```

If errors appear:
```
expected file app/models/user.rb to define constant User, but didn't
```

Fix the mismatch.

---

## Optimizing Boot Time

**Measure:**
```bash
time bin/rails runner 'puts "Booted"'
```

**Common slow spots:**
1. **Too many gems:** remove unused gems from Gemfile
2. **Heavy initializers:** defer non-critical setup (e.g., external API clients)
3. **Database seeds:** don't run in initializers
4. **Eager loading in dev:** set `config.eager_load = false`

**Profile initializers:**
```ruby
# config/environments/development.rb
config.after_initialize do
  Rails.logger.info "Boot completed in #{Time.now - Rails.application.config.beginning_time}s"
end

# config/application.rb
config.beginning_time = Time.now
```

---

## Trade-offs Box
- **Advantage:** Autoloading speeds development (no manual requires). Eager loading catches errors before production.
- **Cost:** Autoload errors can be cryptic. Zeitwerk enforces strict naming (no flexibility).
- **When to skip:** For gems/libraries, use explicit `require` statements. Zeitwerk is app-level, not gem-level.

---

## Debugging Checklist

When autoload fails:

1. Run `bin/rails zeitwerk:check` to verify all paths
2. Check file name matches constant: `user_profile.rb` → `UserProfile`
3. Ensure parent modules exist: `billing/invoice.rb` needs `billing.rb` with `module Billing`
4. Search for circular requires: `grep -r "class User" app/models/`
5. Check autoload paths: `Rails.autoloaders.main.dirs`
6. Restart server: some autoload errors cache until restart
7. In production, verify `config.eager_load = true`

---

## One-Minute Recap
- Zeitwerk maps file paths to constants using strict naming conventions
- Autoload (dev) loads on-demand; eager load (prod) loads upfront
- File/class name mismatches cause "uninitialized constant" errors
- Circular dependencies happen when autoloaded classes reference each other
- Run `bin/rails zeitwerk:check` before deploy to catch errors
