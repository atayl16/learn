# API Versioning Strategies

## What It Is

API versioning lets you evolve endpoints without breaking existing clients. Path versioning embeds the version in the URL (`/api/v1/users`). Header versioning uses `Accept` or custom headers (`API-Version: 2`). Deprecation strategies signal upcoming changes via Sunset headers or changelogs.

## Why It Matters

Breaking changes to live APIs crash mobile apps and third-party integrations. Versioning isolates changes, letting old clients stay on v1 while new ones adopt v2. Sunset headers give clients time to migrate before shutting down legacy versions.

## When to Use

- Changing response structures (adding/removing fields)
- Modifying validation rules or required parameters
- Renaming resources or endpoints
- Supporting multiple client generations (web, iOS v1, iOS v2)
- Deprecating legacy endpoints while maintaining uptime

## Three Common Pitfalls

1. **Over-versioning for minor changes:** Adding v2 for a new optional field is overkill. Use backward-compatible changes (new fields ignored by old clients) to avoid version sprawl.
2. **No deprecation timeline:** Shutting down v1 without warning breaks clients. Announce deprecation 6-12 months early with Sunset headers and docs.
3. **Duplicating all code across versions:** Copy-pasting controllers for v1 and v2 creates maintenance debt. Share common logic; version only what differs.

---

## Path-Based Versioning

Embed version in the URL. Simple and visible in logs.

```ruby
# config/routes.rb
namespace :api do
  namespace :v1 do
    resources :users
  end

  namespace :v2 do
    resources :users
  end
end

# app/controllers/api/v1/users_controller.rb
class Api::V1::UsersController < ApplicationController
  def index
    render json: User.all.select(:id, :email)
  end
end

# app/controllers/api/v2/users_controller.rb
class Api::V2::UsersController < ApplicationController
  def index
    render json: User.all.select(:id, :email, :full_name)  # New field
  end
end
```

Pros: Easy to test (just change URL). Cons: Pollutes URL space; caching treats v1 and v2 as separate resources.

## Header-Based Versioning

Version via `Accept` header or custom header. Cleaner URLs.

```ruby
# config/routes.rb
namespace :api do
  scope module: :v1, constraints: ApiVersion.new(1, default: true) do
    resources :users
  end

  scope module: :v2, constraints: ApiVersion.new(2) do
    resources :users
  end
end

# lib/api_version.rb
class ApiVersion
  def initialize(version, default: false)
    @version = version
    @default = default
  end

  def matches?(request)
    @default || request.headers['API-Version'] == @version.to_s
  end
end
```

Clients send `API-Version: 2`. Requires custom routing logic.

## Backward Compatibility

Add fields instead of removing. Ignore unknown params.

```ruby
# V1: {id, email}
# V2: {id, email, full_name}  ← Backward compatible

# V1: {id, email, name}
# V2: {id, email, full_name}  ← Breaking (renamed field)

# Workaround: alias old field names
def as_json(options = {})
  super.merge(name: full_name)  # Maintain 'name' for v1 clients
end
```

Use feature flags or serializers to conditionally include fields.

## Sunset Header for Deprecation

Signal when an endpoint will be removed.

```ruby
# Api::V1::UsersController
before_action :set_sunset_header

def set_sunset_header
  response.set_header('Sunset', 'Sat, 31 Dec 2025 23:59:59 GMT')
  response.set_header('Link', '<https://api.example.com/docs/migration>; rel="sunset"')
end
```

Clients parse `Sunset` to know the shutdown date. `Link` points to migration docs.

## Deprecation Warnings

Return custom headers to warn clients.

```ruby
# ApplicationController
after_action :deprecation_warning, if: -> { request.path.start_with?('/api/v1') }

def deprecation_warning
  response.set_header('Warning', '299 - "API v1 is deprecated. Migrate to v2 by 2025-12-31."')
end
```

Log which clients hit deprecated endpoints to prioritize migration outreach.

## When to Version

Introduce a new version only for breaking changes:

- Removing or renaming fields
- Changing data types (string → integer)
- Altering validation (email now required)
- Restructuring nested objects

Skip versioning for:

- Adding optional fields
- Adding new endpoints
- Improving performance
- Fixing bugs

---

## Trade-offs Box

- **Advantage:** Versioning prevents breaking existing clients; deprecation timelines enable graceful migrations.
- **Cost:** Maintaining multiple versions increases code complexity and testing surface; sunset enforcement requires tracking client adoption.
- **When to skip:** For internal APIs with tightly coupled clients or alpha/beta products where breaking changes are expected.

---

## Debugging Checklist

When versioning or deprecation issues arise, check:

1. Confirm routing constraints: `bin/rails routes | grep v2`
2. Verify header parsing: log `request.headers['API-Version']` in controller
3. Check Sunset header format: must be HTTP-date (RFC 7231)
4. Test both versions with curl: `curl -H "API-Version: 1"` vs `curl -H "API-Version: 2"`
5. Review logs for deprecated endpoint usage: `grep '/api/v1' log/production.log`
6. Validate backward compatibility: ensure old clients ignore new fields

---

## One-Minute Recap

- Use path versioning (`/api/v1`) for simplicity; header versioning for cleaner URLs
- Avoid versioning for backward-compatible changes like adding optional fields
- Signal deprecation with Sunset header and 6-12 month migration timelines
- Share common logic across versions; duplicate only what differs
- Version only for breaking changes: removing fields, renaming, or changing types
