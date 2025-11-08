# Structured Logging with Lograge

## What It Is
Structured logging formats log entries as JSON objects with consistent key-value pairs instead of plain text strings. Lograge is a Rails gem that replaces Rails' default verbose request logging with single-line JSON entries containing request method, path, status, duration, and custom fields. Log aggregation tools (ELK, Datadog, CloudWatch) parse JSON logs to enable filtering, searching, and analytics across millions of entries.

## Why It Matters
Plain text logs require regex parsing and break when formats change. Structured logs provide queryable fields out of the box, enabling fast searches like "all 500 errors for user_id 123" or "requests slower than 1 second on /api/orders." Adding custom fields (request_id, user_id, tenant_id) connects logs across services for distributed tracing. Production debugging becomes data analysis instead of grep archaeology.

## When to Use
- Sending logs to aggregation services (Datadog, CloudWatch, ELK)
- Searching logs by user, request, or custom business context
- Correlating requests across multiple services via request_id
- Building dashboards or alerts based on log metrics
- Debugging production issues without SSH access to servers

## Three Common Pitfalls
1. **Logging sensitive data:** Passwords, tokens, and credit card numbers in log params create security risks and compliance violations. Configure lograge to filter these fields explicitly using `config.lograge.ignore_custom`.
2. **Overwhelming log volume:** Logging every SQL query or external API call in JSON creates massive storage costs. Use log levels (info vs debug) and sample high-traffic endpoints instead of logging everything.
3. **Missing request_id correlation:** Without request_id, you cannot track a single request through middleware, controllers, jobs, and background tasks. Rails generates request_id by default; ensure your log aggregator indexes it.

---

## JSON Logging vs Plain Text

Rails default logs are verbose and inconsistent:

```
Started GET "/users/123" for 127.0.0.1 at 2025-01-15 10:23:45 -0800
Processing by UsersController#show as HTML
  Parameters: {"id"=>"123"}
  User Load (0.5ms)  SELECT "users".* FROM "users" WHERE "users"."id" = $1 LIMIT $2
Completed 200 OK in 45ms (Views: 32.1ms | ActiveRecord: 0.5ms)
```

Lograge condenses this to one JSON line:

```json
{"method":"GET","path":"/users/123","format":"html","controller":"UsersController","action":"show","status":200,"duration":45.2,"view":32.1,"db":0.5}
```

Queryable fields enable fast filtering: `status:500`, `duration:>1000`, `path:/api/*`.

---

## Lograge Setup

Install and configure lograge:

```ruby
# Gemfile
gem 'lograge'

# config/environments/production.rb
config.lograge.enabled = true
config.lograge.formatter = Lograge::Formatters::Json.new

# Include timestamp and request_id
config.lograge.custom_options = lambda do |event|
  {
    time: event.time.iso8601,
    request_id: event.payload[:headers]['action_dispatch.request_id']
  }
end
```

Every request now logs one JSON line with structured fields.

---

## Adding Custom Fields

Enhance logs with user_id and tenant_id:

```ruby
# config/environments/production.rb
config.lograge.custom_options = lambda do |event|
  payload = event.payload
  {
    time: event.time.iso8601,
    request_id: payload[:headers]['action_dispatch.request_id'],
    user_id: payload[:user_id],
    tenant_id: payload[:tenant_id],
    ip: payload[:ip]
  }
end

# app/controllers/application_controller.rb
def append_info_to_payload(payload)
  super
  payload[:user_id] = current_user&.id
  payload[:tenant_id] = current_tenant&.id
  payload[:ip] = request.remote_ip
end
```

Now search logs by `user_id:123` to see all requests from one user.

---

## Filtering Sensitive Data

Prevent passwords and tokens from appearing in logs:

```ruby
# config/initializers/filter_parameter_logging.rb
Rails.application.config.filter_parameters += [
  :password, :password_confirmation, :token, :api_key, :secret, :ssn, :credit_card
]

# config/environments/production.rb
config.lograge.ignore_custom = lambda do |event|
  # Skip logging health check requests
  event.payload[:path] == '/health'
end
```

Filtered params appear as `[FILTERED]` in logs. Health checks reduce log noise.

---

## Log Aggregation Integration

Ship JSON logs to centralized storage:

**CloudWatch Logs (AWS):**
```ruby
# Gemfile
gem 'aws-sdk-cloudwatchlogs'

# config/environments/production.rb
logger = ActiveSupport::Logger.new(STDOUT)
logger.formatter = ->(severity, time, progname, msg) { "#{msg}\n" }
config.logger = logger
```

**Datadog:**
```ruby
# Gemfile
gem 'ddtrace'

# config/initializers/datadog.rb
Datadog.configure do |c|
  c.tracing.instrument :rails
end
```

Both parse JSON logs automatically. Build dashboards with queries like `status:>=500` or `duration:>2000`.

---

## Trade-offs Box
- **Advantage:** JSON logs enable fast querying by any field (user_id, status, duration) in log aggregators without regex parsing.
- **Cost:** JSON increases log size by 20-30% compared to compact text; filtering sensitive data requires explicit configuration.
- **When to skip:** Single-server apps with direct log access can use grep on plain text logs; add lograge when scaling beyond one server or shipping to aggregators.

---

## Debugging Checklist

When logs are missing or incorrect:

1. Verify lograge is enabled: `Rails.configuration.lograge.enabled` returns `true`
2. Check formatter: `Rails.configuration.lograge.formatter` should be `Lograge::Formatters::Json`
3. Inspect custom_options: Ensure lambda doesn't raise exceptions
4. Test append_info_to_payload: Add `logger.info` to verify it runs
5. Check log destination: `STDOUT` for containers, `log/production.log` for VMs
6. Verify filtered parameters: `Rails.application.config.filter_parameters`
7. Search aggregator for request_id: Confirms logs are shipping correctly
8. Check log volume limits: Aggregators may throttle or drop logs

---

## One-Minute Recap
- Structured logs use JSON key-value pairs instead of plain text for queryable fields
- Lograge condenses Rails request logs to single-line JSON with method, path, status, duration
- Add custom fields (user_id, request_id) via append_info_to_payload for cross-service correlation
- Filter sensitive params (password, token) to prevent security leaks
- JSON logs integrate seamlessly with Datadog, CloudWatch, ELK for production debugging
