# Exercise: Config & Secrets Management

## Objective

Set up per-environment Rails credentials with separate staging and production secrets, implement zero-downtime secret rotation, and configure 12-factor app compliance with proper ENV variable usage.

## Task

Build a complete secrets management system:

1. Create per-environment credentials for development, staging, and production
2. Store third-party API keys (Stripe, AWS) in encrypted credentials
3. Configure ENV variables for infrastructure settings (database host, Redis URL)
4. Implement zero-downtime secret rotation for a database password
5. Verify credentials are properly encrypted and master keys are not committed

## Acceptance Criteria

- [ ] Per-environment credentials created: `config/credentials/{development,staging,production}.yml.enc`
- [ ] Master keys excluded from git: `config/credentials/*.key` in `.gitignore`
- [ ] Third-party API keys stored in credentials (Stripe, AWS S3)
- [ ] Infrastructure config uses ENV variables (database URL, Redis)
- [ ] Zero-downtime rotation implemented with dual-secret support
- [ ] Application successfully loads environment-specific credentials
- [ ] `bin/rails credentials:show` displays correct secrets for each environment
- [ ] Git history contains no plaintext secrets or master keys

## Verification Steps

1. Check credentials are encrypted:

```bash
# Verify credentials files are encrypted (binary gibberish)
cat config/credentials/production.yml.enc
# Should output encrypted binary data, not readable YAML

```

2. Verify master keys are gitignored:

```bash
git status config/credentials/
# Should show only .yml.enc files, not .key files

git check-ignore -v config/credentials/production.key
# Should output: .gitignore:XX:config/credentials/*.key

```

3. Test credential loading per environment:

```bash
# Development credentials
RAILS_ENV=development bin/rails runner "puts Rails.application.credentials.stripe[:publishable_key]"
# Should output: pk_test_dev123

# Production credentials
RAILS_ENV=production RAILS_MASTER_KEY=$(cat config/credentials/production.key) \
  bin/rails runner "puts Rails.application.credentials.stripe[:publishable_key]"
# Should output: pk_live_prod456

```

4. Verify ENV variables override credentials:

```bash
DATABASE_URL=postgres://custom:5432/db bin/rails runner "puts ENV['DATABASE_URL']"
# Should output: postgres://custom:5432/db

```

## Setup Code

### Step 1: Create Rails Application

```bash
# Create new Rails app
rails new secrets_demo --database=postgresql
cd secrets_demo

# Initialize git
git init
git add .
git commit -m "Initial commit"

```

### Step 2: Set Up Per-Environment Credentials

**Create development credentials:**

```bash
bin/rails credentials:edit --environment development

```

Add the following content:

```yaml
# config/credentials/development.yml.enc (decrypted view)
stripe:
  publishable_key: pk_test_dev123
  secret_key: sk_test_dev456

aws:
  access_key_id: AKIAIOSFODNN7DEVKEY
  secret_access_key: dev_secret_key_for_testing

database:
  password: dev_password_123

secret_key_base: <%= SecureRandom.hex(64) %>

```

**Create staging credentials:**

```bash
bin/rails credentials:edit --environment staging

```

Add:

```yaml
# config/credentials/staging.yml.enc (decrypted view)
stripe:
  publishable_key: pk_test_staging789
  secret_key: sk_test_staging012

aws:
  access_key_id: AKIAIOSFODNN7STAGKEY
  secret_access_key: staging_secret_key_aws

database:
  password: staging_password_456
  password_v2: staging_password_789  # For rotation demo

secret_key_base: <%= SecureRandom.hex(64) %>

```

**Create production credentials:**

```bash
bin/rails credentials:edit --environment production

```

Add:

```yaml
# config/credentials/production.yml.enc (decrypted view)
stripe:
  publishable_key: pk_live_prod456
  secret_key: sk_live_prod789

aws:
  access_key_id: AKIAIOSFODNN7PRODKEY
  secret_access_key: production_secret_key_aws_real

database:
  password: production_password_secure_123
  password_v2: production_password_secure_456  # Rotation example

secret_key_base: <%= SecureRandom.hex(64) %>

```

### Step 3: Update .gitignore

Edit `.gitignore` to ensure master keys are never committed:

```bash
# Add to .gitignore
echo "" >> .gitignore
echo "# Ignore all master keys" >> .gitignore
echo "/config/master.key" >> .gitignore
echo "/config/credentials/*.key" >> .gitignore

# Verify they're ignored
git check-ignore -v config/credentials/production.key

```

### Step 4: Configure Stripe Integration

Create `config/initializers/stripe.rb`:

```ruby
# config/initializers/stripe.rb
if defined?(Stripe)
  Stripe.api_key = Rails.application.credentials.dig(:stripe, :secret_key)

  Rails.configuration.stripe = {
    publishable_key: Rails.application.credentials.dig(:stripe, :publishable_key),
    secret_key: Rails.application.credentials.dig(:stripe, :secret_key)
  }
end

```

Add Stripe gem:

```ruby
# Gemfile
gem 'stripe'

```

```bash
bundle install

```

### Step 5: Configure AWS S3 Integration

Create `config/initializers/aws.rb`:

```ruby
# config/initializers/aws.rb
require 'aws-sdk-s3'

Aws.config.update({
  region: ENV.fetch('AWS_REGION', 'us-east-1'),  # ENV for region
  credentials: Aws::Credentials.new(
    Rails.application.credentials.dig(:aws, :access_key_id),
    Rails.application.credentials.dig(:aws, :secret_access_key)
  )
})

```

Add AWS SDK:

```ruby
# Gemfile
gem 'aws-sdk-s3'

```

```bash
bundle install

```

### Step 6: Configure Database with ENV and Credentials

Edit `config/database.yml`:

```yaml
default: &default
  adapter: postgresql
  encoding: unicode
  pool: <%= ENV.fetch("RAILS_MAX_THREADS") { 5 } %>
  host: <%= ENV.fetch("DATABASE_HOST", "localhost") %>  # ENV for host

development:
  <<: *default
  database: secrets_demo_development
  username: postgres
  password: <%= Rails.application.credentials.dig(:database, :password) || 'postgres' %>

staging:
  <<: *default
  database: secrets_demo_staging
  username: <%= ENV.fetch("DATABASE_USERNAME", "postgres") %>
  # Zero-downtime rotation: try v2 first, fallback to v1
  password: <%= Rails.application.credentials.dig(:database, :password_v2) ||
               Rails.application.credentials.dig(:database, :password) %>

production:
  <<: *default
  url: <%= ENV['DATABASE_URL'] %>  # ENV for full URL if available
  username: <%= ENV.fetch("DATABASE_USERNAME") { "app_user" } %>
  # Zero-downtime rotation: try v2 first, fallback to v1
  password: <%= Rails.application.credentials.dig(:database, :password_v2) ||
               Rails.application.credentials.dig(:database, :password) %>

```

### Step 7: Configure Redis with ENV Variables

Create `config/initializers/redis.rb`:

```ruby
# config/initializers/redis.rb
REDIS_URL = ENV.fetch("REDIS_URL") do
  if Rails.env.production?
    raise "REDIS_URL environment variable must be set in production"
  else
    "redis://localhost:6379/0"  # Default for development
  end
end

# Example Redis connection
# $redis = Redis.new(url: REDIS_URL)

```

### Step 8: Test Credential Access in Rails Console

Create a test controller to verify credential loading:

```bash
bin/rails generate controller Secrets test

```

Edit `app/controllers/secrets_controller.rb`:

```ruby
class SecretsController < ApplicationController
  def test
    @credentials_info = {
      environment: Rails.env,
      stripe_publishable: Rails.application.credentials.dig(:stripe, :publishable_key)&.first(10),
      aws_access_key: Rails.application.credentials.dig(:aws, :access_key_id)&.first(10),
      database_password_present: Rails.application.credentials.dig(:database, :password).present?,
      secret_key_base_present: Rails.application.credentials.secret_key_base.present?,
      redis_url: REDIS_URL
    }

    render json: @credentials_info
  end
end

```

Edit `config/routes.rb`:

```ruby
Rails.application.routes.draw do
  get 'secrets/test', to: 'secrets#test'
end

```

### Step 9: Test Different Environments

**Development:**

```bash
bin/rails server

# Visit http://localhost:3000/secrets/test
# Should show development Stripe keys (pk_test_dev123...)

```

**Staging:**

```bash
RAILS_ENV=staging RAILS_MASTER_KEY=$(cat config/credentials/staging.key) bin/rails server

# Visit http://localhost:3000/secrets/test
# Should show staging Stripe keys (pk_test_staging789...)

```

**Production (simulated):**

```bash
RAILS_ENV=production \
RAILS_MASTER_KEY=$(cat config/credentials/production.key) \
DATABASE_URL=postgres://localhost/secrets_demo_production \
REDIS_URL=redis://localhost:6379/1 \
SECRET_KEY_BASE=$(bin/rails secret) \
bin/rails runner "puts Rails.application.credentials.dig(:stripe, :publishable_key)"

# Should output: pk_live_prod456

```

### Step 10: Implement Secret Rotation Workflow

**Scenario:** Rotate production database password without downtime.

**Phase 1: Add new password to credentials**

Already added as `password_v2` in production credentials above.

**Phase 2: Deploy with dual-password support**

The `config/database.yml` already tries `password_v2` first, then falls back to `password`.

**Phase 3: Verify dual-password support**

```bash
# Test that app can load with v2 password
RAILS_ENV=production RAILS_MASTER_KEY=$(cat config/credentials/production.key) \
  bin/rails runner "puts ActiveRecord::Base.connection.execute('SELECT 1').first"

```

**Phase 4: Update database to require new password**

```sql
-- Connect to database as admin
-- psql production_db

ALTER USER app_user WITH PASSWORD 'production_password_secure_456';

```

**Phase 5: Remove old password from credentials**

```bash
bin/rails credentials:edit --environment production

# Remove password_v2, rename to password:
# database:
#   password: production_password_secure_456

```

**Phase 6: Deploy and verify**

```bash
# Deploy to production
# Application now uses only the new password
# Rotation complete with zero downtime

```

### Step 11: Create Credential Audit Script

Create `bin/audit_credentials`:

```bash
#!/usr/bin/env ruby

require_relative '../config/environment'

puts "=== Credentials Audit ==="
puts "Environment: #{Rails.env}"
puts ""

def check_credential(path, name)
  value = Rails.application.credentials.dig(*path)
  if value.present?
    if value.is_a?(String) && value.length > 20
      puts "✓ #{name}: Present (#{value.first(10)}...)"
    else
      puts "✓ #{name}: Present"
    end
  else
    puts "✗ #{name}: MISSING"
  end
end

check_credential([:stripe, :publishable_key], "Stripe Publishable Key")
check_credential([:stripe, :secret_key], "Stripe Secret Key")
check_credential([:aws, :access_key_id], "AWS Access Key ID")
check_credential([:aws, :secret_access_key], "AWS Secret Access Key")
check_credential([:database, :password], "Database Password")
check_credential([:secret_key_base], "Secret Key Base")

puts ""
puts "ENV Variables:"
puts "DATABASE_URL: #{ENV['DATABASE_URL'] ? 'Set' : 'Not set'}"
puts "REDIS_URL: #{ENV.fetch('REDIS_URL', 'Using default')}"
puts "RAILS_MASTER_KEY: #{ENV['RAILS_MASTER_KEY'] ? 'Set' : 'Using file'}"

```

Make executable:

```bash
chmod +x bin/audit_credentials

```

Run audit:

```bash
# Development
bin/audit_credentials

# Production
RAILS_ENV=production RAILS_MASTER_KEY=$(cat config/credentials/production.key) \
  bin/audit_credentials

```

### Step 12: Commit and Verify Security

```bash
# Verify master keys are not staged
git status

# Should only show .yml.enc files, not .key files

# Commit encrypted credentials
git add config/credentials/
git commit -m "Add per-environment encrypted credentials"

# Double-check no secrets leaked
git log -p | grep -i "secret_key\|password\|access_key"
# Should only show references in code, not actual values

# Search history for master keys (should return nothing)
git log -p | grep -E "[a-f0-9]{32}"
# Should not show any 32-character hex keys

```

## Stretch Goals

- [ ] Integrate with 1Password CLI for master key distribution
- [ ] Set up AWS Secrets Manager integration for dynamic credential retrieval
- [ ] Create automated credential rotation script
- [ ] Add credential encryption at rest with additional layer
- [ ] Set up automated credential validation in CI
- [ ] Implement credential versioning with rollback capability

## Solution Notes

**Common Gotchas:**

1. **Master key not found error:** Ensure `RAILS_MASTER_KEY` environment variable is set or `config/credentials/{environment}.key` file exists.

2. **Credentials not loading:** Rails looks for environment-specific credentials first. If `config/credentials/production.yml.enc` exists, it uses that instead of `config/credentials.yml.enc`.

3. **Editor errors when editing credentials:** Set `EDITOR` environment variable:
   ```bash
   EDITOR=nano bin/rails credentials:edit
   ```

4. **Rotation breaks running instances:** Always add new secrets alongside old ones first, deploy with dual support, then remove old secrets in a second deployment.

5. **ENV variables not overriding:** Use `ENV.fetch` or `ENV[]` in config files. Rails.application.credentials values are cached and don't check ENV automatically.

**Best Practices:**

- Use credentials for secrets (API keys, passwords)
- Use ENV for infrastructure config (hostnames, ports, feature flags)
- Never commit master keys—distribute via secure channels
- Implement rotation in phases: add, deploy, remove
- Audit credentials regularly with automated scripts
- Test credential loading in CI with test-specific keys
- Document which secrets are required in README

**Production Deployment Checklist:**

- [ ] Master keys distributed to team via 1Password/Vault
- [ ] `RAILS_MASTER_KEY` set in production environment
- [ ] `.gitignore` excludes all `*.key` files
- [ ] No plaintext secrets in git history
- [ ] Rotation runbook documented
- [ ] Quarterly rotation scheduled
- [ ] Backup master keys stored securely
- [ ] Access to credentials logged and audited

## Time Estimate

25 minutes
