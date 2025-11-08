# Config & Secrets Management

## What It Is

Configuration and secrets management is the practice of securely storing, accessing, and rotating sensitive credentials and environment-specific settings in Rails applications. Modern Rails (5.2+) provides encrypted credentials via `Rails.application.credentials`, which uses symmetric encryption to store API keys, database passwords, and service tokens in version control safely. The 12-factor app methodology dictates strict separation between code and config—environment variables for deployment-specific values, encrypted files for shared secrets. Secret rotation involves systematically updating credentials to limit exposure windows when keys are compromised.

## Why It Matters

Hardcoded secrets are the #1 cause of data breaches. A leaked AWS key can cost thousands in minutes; exposed database credentials enable full data exfiltration. Rails credentials solve this by encrypting secrets with a master key that never touches version control. Environment variables provide deployment flexibility—same codebase runs in dev, staging, and production with different configs. Secret rotation limits blast radius: if a key leaks, regular rotation means it expires quickly. Production deployments require multi-environment credentials (staging vs production secrets), zero-downtime rotation, and audit trails for compliance (SOC 2, GDPR).

## When to Use

- **Production deployments:** Store API keys, database URLs, JWT secrets encrypted
- **Multi-environment apps:** Separate staging/production credentials using environment-specific files
- **Third-party integrations:** Safely store Stripe, SendGrid, AWS keys in credentials
- **Team collaboration:** Share secrets in version control without exposing plaintext
- **Compliance requirements:** Audit trails and rotation policies for SOC 2/PCI-DSS
- **Secret rotation:** Scheduled updates to database passwords, API tokens, signing keys
- **Local development:** Use ENV variables or credentials.yml.enc for consistent config

## Three Common Pitfalls

1. **Committing master.key to version control:** The master key decrypts all secrets. Committing it to git exposes every credential. Fix: Add `config/master.key` to `.gitignore`; distribute via secure channels (1Password, Vault).
2. **ENV variable sprawl:** 50+ environment variables become unmaintainable. Fix: Use credentials for shared secrets, ENV for deployment-specific config (database host, Redis URL). Store credentials in encrypted files, ENV in deployment configs.
3. **Zero-downtime rotation failures:** Rotating a database password instantly breaks all running instances. Fix: Multi-step rotation—add new key, deploy with dual support, remove old key. Use credential versioning and rolling deployments.

---

## Rails Credentials System

### How Rails.application.credentials Works

Rails 5.2+ encrypts credentials using a 32-byte master key:

```bash
# Generate credentials (creates master.key automatically)
bin/rails credentials:edit

# Opens encrypted file in editor
# Stored in config/credentials.yml.enc (safe to commit)
```

Structure inside credentials:

```yaml
aws:
  access_key_id: AKIAIOSFODNN7EXAMPLE
  secret_access_key: wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY

stripe:
  publishable_key: pk_live_123
  secret_key: sk_live_456

secret_key_base: 64_character_hex_string_for_sessions
```

Access in code:

```ruby
# config/initializers/stripe.rb
Stripe.api_key = Rails.application.credentials.stripe[:secret_key]

# In controller
aws_key = Rails.application.credentials.dig(:aws, :access_key_id)
```

**Key benefits:**
- Encrypted file is safe to commit to git
- Master key is `.gitignore`d and distributed separately
- Single source of truth for secrets
- Editor integration for easy updates

---

## Per-Environment Credentials

Rails 6+ supports environment-specific credential files:

```bash
# Edit production credentials
bin/rails credentials:edit --environment production
# Creates: config/credentials/production.key
# Creates: config/credentials/production.yml.enc

# Edit staging credentials
bin/rails credentials:edit --environment staging
# Creates: config/credentials/staging.key
# Creates: config/credentials/staging.yml.enc
```

**Directory structure:**

```
config/
├── credentials.yml.enc           # Shared/development credentials
├── master.key                     # Decrypts shared credentials
└── credentials/
    ├── production.yml.enc         # Production-only secrets
    ├── production.key             # Production master key
    ├── staging.yml.enc
    └── staging.key
```

**Access pattern:**

```ruby
# Rails automatically loads environment-specific credentials
# In production, loads config/credentials/production.yml.enc

Rails.application.credentials.database_password
# => Uses production.yml.enc in production, staging.yml.enc in staging
```

**Deployment:**

```bash
# Production server
export RAILS_MASTER_KEY=$(cat config/credentials/production.key)

# Or use platform-specific secrets
# Heroku: heroku config:set RAILS_MASTER_KEY=abc123
# AWS ECS: Store in Secrets Manager, inject as env var
```

---

## 12-Factor Config Principles

### Strict Separation of Config from Code

**Rule:** Never hardcode environment-specific values.

**Bad:**

```ruby
# Hardcoded—breaks in production
REDIS_URL = "redis://localhost:6379"
```

**Good (credentials):**

```yaml
# config/credentials.yml.enc
redis_url: redis://production.example.com:6379
```

**Good (ENV):**

```ruby
# config/initializers/redis.rb
REDIS_URL = ENV.fetch("REDIS_URL") { "redis://localhost:6379" }
```

### When to Use ENV vs Credentials

| Type | Use ENV | Use Credentials |
|------|---------|-----------------|
| Database host | ✓ (varies per deploy) | |
| Database password | | ✓ (secret) |
| Redis URL | ✓ (infrastructure) | |
| API keys | | ✓ (secret) |
| Feature flags | ✓ (config) | |
| JWT signing key | | ✓ (secret) |

**Pattern:**

```ruby
# config/database.yml
production:
  url: <%= ENV['DATABASE_URL'] %>  # ENV for URL
  password: <%= Rails.application.credentials.dig(:database, :password) %>  # Credentials for secret
```

---

## Secret Rotation

### Zero-Downtime Rotation Strategy

**Problem:** Rotating a secret instantly breaks running instances.

**Solution:** Multi-phase rotation.

**Phase 1: Add new secret**

```yaml
# config/credentials/production.yml.enc
database:
  password: old_password
  password_v2: new_password  # Add without removing old
```

**Phase 2: Support both secrets**

```ruby
# config/database.yml
production:
  url: <%= ENV['DATABASE_URL'] %>
  password: <%= Rails.application.credentials.dig(:database, :password_v2) ||
               Rails.application.credentials.dig(:database, :password) %>
```

Deploy—now app accepts both passwords.

**Phase 3: Update database to require new password**

```sql
ALTER USER app_user WITH PASSWORD 'new_password';
```

**Phase 4: Remove old secret**

```yaml
# config/credentials/production.yml.enc
database:
  password: new_password  # Old password removed
```

Deploy—rotation complete.

### Automated Rotation

**AWS Secrets Manager rotation:**

```ruby
# config/initializers/database.rb
if Rails.env.production?
  require 'aws-sdk-secretsmanager'

  client = Aws::SecretsManager::Client.new
  secret = client.get_secret_value(secret_id: 'production/database')

  # Override credentials with rotated secret
  parsed = JSON.parse(secret.secret_string)
  ENV['DATABASE_PASSWORD'] = parsed['password']
end
```

---

## Best Practices

- Use per-environment credentials for staging vs production separation
- Never commit `config/master.key` or `config/credentials/*.key` to git
- Distribute master keys via 1Password, AWS Secrets Manager, or secure channels
- Set `RAILS_MASTER_KEY` environment variable in production deployments
- Use ENV variables for infrastructure config (hosts, ports), credentials for secrets
- Rotate secrets quarterly or after suspected compromise
- Implement multi-phase rotation for zero-downtime updates
- Audit credential access in production (CloudTrail, application logs)
- Use `credentials:diff` to track changes in encrypted files
- Test credential loading in CI with test-specific master keys
- Document which secrets are in credentials vs ENV in README

---

## Key Terms

- **Rails credentials** - Encrypted YAML files storing secrets, decrypted via master key
- **Master key** - 32-byte key decrypting credentials.yml.enc, never committed to version control
- **12-factor app** - Methodology requiring strict config/code separation via environment variables
- **Secret rotation** - Systematic process of updating credentials to limit exposure windows
- **Per-environment credentials** - Rails 6+ feature for separate staging/production credential files
- **ENV variables** - OS-level configuration injected at runtime, used for deployment-specific settings
- **RAILS_MASTER_KEY** - Environment variable providing master key for decrypting credentials

---

## Summary

Rails credentials provide encrypted storage for secrets using symmetric encryption and a master key that never touches version control. Per-environment credentials (Rails 6+) separate staging and production secrets into isolated files. Follow 12-factor principles: use ENV for infrastructure config, credentials for secrets. Secret rotation requires multi-phase deployments to avoid downtime—add new key, support both, remove old. Never commit master keys; distribute via secure channels and inject as RAILS_MASTER_KEY in production.

**Next steps:** Complete the exercise to set up per-environment credentials with rotation.
