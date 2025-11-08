# Exercise: Configuration & Initializers

## Objective
Configure a Rails app with environment-specific settings, write an initializer, and store secrets in credentials.

## Task
In a Rails app:

1. Add a custom autoload path for `app/services`
2. Create an initializer that sets a global constant
3. Configure caching differently in dev vs production
4. Store an API key in credentials and access it

## Acceptance Criteria
- [ ] Services auto-load from `app/services`
- [ ] Global constant `MAX_UPLOAD_SIZE` accessible in controllers
- [ ] Development uses memory cache; production uses Redis
- [ ] API key stored encrypted in `config/credentials.yml.enc`
- [ ] Can access API key via `Rails.application.credentials`
- [ ] Can explain why credentials are better than ENV vars for committed config

## Verification Steps

1. Run in console:
```ruby
MAX_UPLOAD_SIZE
# => 10485760 (10 megabytes)
```

2. Check cache store:
```ruby
Rails.cache.class.name
# Dev: ActiveSupport::Cache::MemoryStore
# Prod: ActiveSupport::Cache::RedisCacheStore
```

3. Access credential:
```ruby
Rails.application.credentials.sendgrid_api_key
# => "SG.abc123..."
```

## Setup Code

### Step 1: Add Custom Autoload Path

Edit `config/application.rb`:
```ruby
module MyApp
  class Application < Rails::Application
    config.load_defaults 7.0
    config.autoload_paths += %W[#{config.root}/app/services]
    config.time_zone = "Pacific Time (US & Canada)"
  end
end
```

### Step 2: Create Initializer

Create `config/initializers/constants.rb`:
```ruby
MAX_UPLOAD_SIZE = 10.megabytes
SUPPORT_EMAIL = "support@example.com"
ALLOWED_FILE_TYPES = %w[jpg png pdf]

Rails.logger.info "Loaded constants: MAX_UPLOAD_SIZE=#{MAX_UPLOAD_SIZE}"
```

### Step 3: Configure Caching by Environment

Edit `config/environments/development.rb`:
```ruby
Rails.application.configure do
  # ... existing config
  config.cache_store = :memory_store, { size: 64.megabytes }
  config.action_controller.perform_caching = true  # enable to test
end
```

Edit `config/environments/production.rb`:
```ruby
Rails.application.configure do
  # ... existing config
  config.cache_store = :redis_cache_store, {
    url: ENV['REDIS_URL'] || 'redis://localhost:6379/0',
    expires_in: 1.hour
  }
end
```

### Step 4: Add Credentials

```bash
# Edit credentials (will create if not exists)
EDITOR=nano bin/rails credentials:edit
```

Add:
```yaml
sendgrid_api_key: SG.abc123example
aws:
  access_key_id: AKIAIOSFODNN7EXAMPLE
  secret_access_key: wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY
```

Save and exit. The file is encrypted; master key is in `config/master.key` (gitignored).

Access in code:
```ruby
# config/initializers/sendgrid.rb
if Rails.application.credentials.sendgrid_api_key
  SendGrid.api_key = Rails.application.credentials.sendgrid_api_key
end
```

### Step 5: Test in Console

```bash
bin/rails console
```

```ruby
# Check constants
MAX_UPLOAD_SIZE  # => 10485760
SUPPORT_EMAIL    # => "support@example.com"

# Check cache store
Rails.cache.class.name
# => "ActiveSupport::Cache::MemoryStore" (development)

# Check credentials
Rails.application.credentials.sendgrid_api_key
# => "SG.abc123example"

Rails.application.credentials.aws[:access_key_id]
# => "AKIAIOSFODNN7EXAMPLE"

# Test caching
Rails.cache.write('test_key', 'hello')
Rails.cache.read('test_key')  # => "hello"
```

### Step 6: Create a Service Object

Create `app/services/uploader.rb`:
```ruby
class Uploader
  def self.max_size
    MAX_UPLOAD_SIZE
  end

  def self.allowed_types
    ALLOWED_FILE_TYPES
  end
end
```

Test:
```ruby
Uploader.max_size  # => 10485760
Uploader.allowed_types  # => ["jpg", "png", "pdf"]
```

## Stretch (Optional)

1. Create environment-specific credentials:
```bash
bin/rails credentials:edit --environment production
```

Add production-specific secrets (different API keys, DB passwords).

2. Add an initializer with dependencies:

`config/initializers/01_redis.rb`:
```ruby
REDIS = Redis.new(url: ENV['REDIS_URL'] || 'redis://localhost:6379/0')
```

`config/initializers/02_sidekiq.rb`:
```ruby
# Depends on Redis being initialized
Sidekiq.configure_server do |config|
  config.redis = { url: ENV['REDIS_URL'] }
end
```

3. Profile initializer load time:

Edit `config/initializers/constants.rb`:
```ruby
start = Time.now
MAX_UPLOAD_SIZE = 10.megabytes
SUPPORT_EMAIL = "support@example.com"
puts "Constants loaded in #{(Time.now - start) * 1000}ms"
```

Run `bin/rails runner 'puts "Ready"'` and check output.

## Time Estimate
15 minutes
