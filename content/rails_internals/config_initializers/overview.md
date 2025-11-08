# Configuration & Initializers

## What It Is
Rails configuration lives in `config/application.rb` (app-wide) and `config/environments/{env}.rb` (environment-specific). Initializers in `config/initializers/*.rb` run after frameworks load but before the app boots, setting up gems, constants, or custom logic. Credentials (`config/credentials.yml.enc`) store secrets encrypted with a master key.

## Why It Matters
Proper configuration keeps settings organized by environment (dev/test/prod). Initializers centralize setup code (payment gateways, observability tools, custom middleware). Credentials prevent committing secrets to version control. Seniors configure apps for 12-factor compliance, optimize boot time, and debug initializer load order.

## When to Use
- **Environment configs:** Database URLs, log levels, caching backends
- **Initializers:** Gem setup (Sidekiq, Sentry, S3), custom constants, middleware
- **Credentials:** API keys, database passwords, secret keys
- **Application.rb:** App-wide defaults (autoload paths, time zones, generators)

## Three Common Pitfalls
1. **Hardcoding secrets:** Never put `API_KEY = "abc123"` in code. Use `Rails.application.credentials` or ENV vars.
2. **Order-dependent initializers:** Initializers load alphabetically. If `b.rb` depends on `a.rb`, rename to ensure order (e.g., `01_a.rb`, `02_b.rb`).
3. **Slow initializers:** Loading large datasets or calling external APIs in initializers adds 5+ seconds to boot. Defer to runtime or background jobs.

---

## Environment Configuration

`config/application.rb` (all environments):
```ruby
module MyApp
  class Application < Rails::Application
    config.load_defaults 7.0
    config.time_zone = "Pacific Time (US & Canada)"
    config.active_record.default_timezone = :utc
    config.autoload_paths += %W[#{config.root}/app/services]
    config.generators.system_tests = nil
  end
end
```

`config/environments/development.rb`:
```ruby
Rails.application.configure do
  config.cache_classes = false
  config.eager_load = false
  config.consider_all_requests_local = true
  config.action_controller.perform_caching = false
  config.active_record.verbose_query_logs = true
end
```

`config/environments/production.rb`:
```ruby
Rails.application.configure do
  config.cache_classes = true
  config.eager_load = true
  config.consider_all_requests_local = false
  config.action_controller.perform_caching = true
  config.log_level = :info
  config.force_ssl = true
end
```

---

## Common Configuration Options

**Caching:**
```ruby
config.cache_store = :redis_cache_store, { url: ENV['REDIS_URL'] }
```

**Logging:**
```ruby
config.log_level = :debug  # :debug, :info, :warn, :error
config.log_formatter = ::Logger::Formatter.new
```

**Asset pipeline:**
```ruby
config.assets.compile = false  # precompile in production
config.assets.digest = true    # fingerprint assets
```

**Database:**
```ruby
config.active_record.schema_format = :sql  # use SQL instead of schema.rb
```

**Time zone:**
```ruby
config.time_zone = "Eastern Time (US & Canada)"
config.active_record.default_timezone = :local  # or :utc
```

---

## Initializers

Located in `config/initializers/*.rb`. Run alphabetically after frameworks load.

**Example: Sidekiq setup**

`config/initializers/sidekiq.rb`:
```ruby
Sidekiq.configure_server do |config|
  config.redis = { url: ENV['REDIS_URL'], network_timeout: 5 }
end

Sidekiq.configure_client do |config|
  config.redis = { url: ENV['REDIS_URL'], network_timeout: 5 }
end
```

**Example: Custom constants**

`config/initializers/constants.rb`:
```ruby
SUPPORT_EMAIL = "support@example.com"
MAX_UPLOAD_SIZE = 10.megabytes
ALLOWED_DOMAINS = %w[example.com mycompany.com]
```

**Example: Middleware**

`config/initializers/rack_attack.rb`:
```ruby
class Rack::Attack
  throttle('req/ip', limit: 300, period: 5.minutes) do |req|
    req.ip
  end

  throttle('api/ip', limit: 100, period: 1.minute) do |req|
    req.ip if req.path.start_with?('/api')
  end
end

Rails.application.config.middleware.use Rack::Attack
```

---

## Credentials and Secrets

**Edit credentials:**
```bash
EDITOR=nano bin/rails credentials:edit
```

**Structure (`config/credentials.yml.enc`):**
```yaml
secret_key_base: abc123...
aws:
  access_key_id: AKIAIOSFODNN7EXAMPLE
  secret_access_key: wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY
stripe:
  secret_key: sk_test_abc123
  publishable_key: pk_test_xyz789
```

**Access in code:**
```ruby
Rails.application.credentials.aws[:access_key_id]
# => "AKIAIOSFODNN7EXAMPLE"

Rails.application.credentials.stripe[:secret_key]
# => "sk_test_abc123"
```

**Master key:**
Stored in `config/master.key` (gitignored). On production, set via ENV var:
```bash
RAILS_MASTER_KEY=abc123...
```

**Per-environment credentials (Rails 6+):**
```bash
bin/rails credentials:edit --environment production
# Creates config/credentials/production.yml.enc
```

Access:
```ruby
Rails.application.credentials.secret_key
```

---

## Environment Variables

Use `.env` file (with `dotenv-rails` gem) for dev/test:

```bash
# .env
DATABASE_URL=postgres://localhost/myapp_development
REDIS_URL=redis://localhost:6379/0
STRIPE_SECRET_KEY=sk_test_abc123
```

Load in `Gemfile`:
```ruby
gem 'dotenv-rails', groups: [:development, :test]
```

Access:
```ruby
ENV['STRIPE_SECRET_KEY']
```

**Production:** Set ENV vars via hosting platform (Heroku config vars, AWS Secrets Manager, etc.).

---

## Initializer Load Order

Initializers run **alphabetically**. If `b.rb` depends on `a.rb`, use prefixes:

```
config/initializers/
  01_redis.rb
  02_sidekiq.rb    # depends on Redis being configured
  03_rack_attack.rb
```

**Check load order:**
```ruby
Dir["config/initializers/*.rb"].sort
```

**Alternative:** Use `config.after_initialize`:
```ruby
# config/application.rb
config.after_initialize do
  # Runs after all initializers
  SomeService.setup
end
```

---

## Trade-offs Box
- **Advantage:** Centralized config; per-environment overrides; encrypted secrets prevent leaks.
- **Cost:** Scattered config (application.rb + environments + initializers) can be hard to trace. Slow initializers delay boot.
- **When to skip:** For gem-specific config that gem handles internally (e.g., `ActiveStorage.service = :local` can go in `storage.yml`).

---

## Debugging Checklist

When config behaves unexpectedly:

1. Check environment: `Rails.env` in console
2. Inspect config: `Rails.configuration.cache_store`
3. List initializers: `Dir["config/initializers/*.rb"]`
4. Check credentials: `Rails.application.credentials.dig(:aws, :access_key_id)`
5. Verify master key exists: `cat config/master.key`
6. Profile boot time: `time bin/rails runner 'puts "Ready"'`
7. Add logging to initializers: `puts "Loading #{File.basename(__FILE__)}"`
8. Check ENV vars: `ENV['REDIS_URL']`

---

## One-Minute Recap
- `config/application.rb` sets app-wide defaults; `config/environments/{env}.rb` overrides per environment
- Initializers run alphabetically after frameworks load; use prefixes for order control
- Credentials store secrets encrypted; access with `Rails.application.credentials`
- Use ENV vars for dev/test (dotenv) and production (platform config)
- Avoid slow initializers that call external APIs or load large datasets
