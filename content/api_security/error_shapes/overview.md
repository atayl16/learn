# API Error Shapes & Standards

## What It Is

Error shapes define the JSON structure returned when API requests fail. A consistent format includes status code, error type, human-readable message, and optionally field-level details (for validation) or error IDs (for support). Standards like RFC 7807 and JSON:API provide conventions.

## Why It Matters

Inconsistent errors force clients to parse arbitrary structures (`{error: "..."}` vs `{message: "..."}` vs `{errors: []}`). Generic messages like "Something went wrong" hide root causes. Structured errors enable frontend error handling, logging, and support ticket correlation.

## When to Use

- Building APIs consumed by multiple clients (mobile, web, partners)
- Returning validation errors with field-level details
- Logging errors with unique IDs for support teams to trace
- Migrating from legacy endpoints with inconsistent error formats
- Supporting internationalization of error messages

## Three Common Pitfalls

1. **Returning 200 OK with error payloads:** Sending `{success: false, error: "..."}` with 200 breaks HTTP semantics. Use 4xx or 5xx status codes so proxies and browsers recognize failures.
2. **Exposing stack traces in production:** Leaking traces reveals internal paths and gems, aiding attackers. Return generic messages to users; log details server-side.
3. **Missing field names in validation errors:** Returning `["Email is invalid"]` forces clients to guess which field failed. Include `{field: "email", message: "is invalid"}` for precise UI feedback.

---

## HTTP Status Codes for Errors

Match status to error type so clients can handle categories generically.

```ruby
# 4xx Client Errors
render json: {error: "Malformed JSON"}, status: :bad_request                  # 400
render json: {error: "Token missing or invalid"}, status: :unauthorized        # 401
render json: {error: "Insufficient permissions"}, status: :forbidden           # 403
render json: {error: "Resource not found"}, status: :not_found                 # 404
render json: {errors: @user.errors}, status: :unprocessable_entity             # 422
render json: {error: "Too many requests"}, status: :too_many_requests          # 429

# 5xx Server Errors
render json: {error: "Internal server error"}, status: :internal_server_error  # 500
```

Use 400 for malformed requests, 401 for missing auth, 403 for denied access, 422 for validation failures.

## RFC 7807 Problem Details

RFC 7807 defines a standard error format with `type`, `title`, `status`, `detail`, `instance`.

```ruby
# application_controller.rb
def render_error(type:, title:, status:, detail: nil, instance: nil)
  render json: {
    type: "https://api.example.com/errors/#{type}",
    title: title,
    status: Rack::Utils::SYMBOL_TO_STATUS_CODE[status],
    detail: detail,
    instance: instance
  }, status: status
end

# Usage
render_error(
  type: 'invalid-email',
  title: 'Invalid Email Address',
  status: :unprocessable_entity,
  detail: 'Email must be a valid format',
  instance: "/api/users/#{params[:id]}"
)
```

`type` is a URI identifying the error category. `instance` is the specific resource URL.

## JSON:API Error Format

JSON:API uses an `errors` array with `status`, `code`, `title`, `detail`, `source.pointer` for field paths.

```ruby
# Invalid params
{
  "errors": [
    {
      "status": "422",
      "code": "invalid_attribute",
      "title": "Invalid Attribute",
      "detail": "Email is not a valid email address",
      "source": {
        "pointer": "/data/attributes/email"
      }
    }
  ]
}
```

`source.pointer` uses JSON Pointer syntax (`/data/attributes/email`) to identify the exact field.

## Validation Error Shapes

Map ActiveRecord validation errors to structured responses.

```ruby
# UsersController
def create
  @user = User.new(user_params)
  if @user.save
    render json: @user, status: :created
  else
    render json: {
      errors: @user.errors.map do |error|
        {
          field: error.attribute,
          message: error.message,
          code: error.type
        }
      end
    }, status: :unprocessable_entity
  end
end
```

Returns `[{field: "email", message: "is invalid", code: "invalid"}]`. Clients can map to form fields.

## Error IDs for Support

Generate unique IDs to correlate user-reported errors with server logs.

```ruby
# ApplicationController
rescue_from StandardError do |exception|
  error_id = SecureRandom.uuid
  Rails.logger.error("Error #{error_id}: #{exception.class} - #{exception.message}")
  Rails.logger.error(exception.backtrace.join("\n"))

  render json: {
    error: "An unexpected error occurred",
    error_id: error_id,
    support_message: "Please contact support with ID: #{error_id}"
  }, status: :internal_server_error
end
```

Users report the `error_id`, support searches logs for the full trace.

## User-Facing vs Developer Messages

Separate public messages from internal details.

```ruby
# config/environments/production.rb
config.consider_all_requests_local = false

# ApplicationController
rescue_from ActiveRecord::RecordNotFound do |exception|
  if Rails.env.production?
    render json: {error: "Resource not found"}, status: :not_found
  else
    render json: {error: exception.message, backtrace: exception.backtrace.first(5)}, status: :not_found
  end
end
```

In production, return generic messages. In development, include traces for debugging.

---

## Trade-offs Box

- **Advantage:** Structured errors enable generic client handling and improve debuggability.
- **Cost:** Standardizing errors across legacy endpoints requires refactoring; verbose formats increase payload size slightly.
- **When to skip:** For internal microservices where both client and server control the contract.

---

## Debugging Checklist

When error responses misbehave, check:

1. Confirm status codes match error types: 401 for auth, 422 for validation, 500 for server errors
2. Verify error format is consistent: same keys (`error`, `errors`, `type`) across endpoints
3. Check production logs for stack traces: ensure they're logged but not returned to clients
4. Validate field-level errors include `field` or `source.pointer` for form mapping
5. Test with malformed JSON to ensure 400 is returned, not 500
6. Search logs for `error_id` to correlate user reports with server exceptions

---

## One-Minute Recap

- Use appropriate HTTP status codes: 400 for malformed, 401 for auth, 422 for validation, 500 for server errors
- Adopt RFC 7807 or JSON:API error formats for consistency across endpoints
- Return field-level details for validation errors so clients can map to forms
- Generate unique error IDs to correlate user reports with server logs
- Hide stack traces in production; return generic messages to clients, log details server-side
