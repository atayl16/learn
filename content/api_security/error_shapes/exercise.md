# Exercise: API Error Shapes & Standards

## Objective

Implement a consistent error response format following RFC 7807 conventions, with field-level validation errors and unique error IDs for server exceptions.

## Task

You're standardizing error handling in your Rails API. Create an `ApplicationController` concern called `ApiErrors` that provides methods to render RFC 7807-style errors, validation errors with field details, and 500 errors with unique IDs. Apply it to a `UsersController` endpoint.

1. Create `app/controllers/concerns/api_errors.rb` with methods: `render_problem`, `render_validation_errors`, `render_server_error`
2. Implement `render_problem` to return RFC 7807 structure (`type`, `title`, `status`, `detail`)
3. Implement `render_validation_errors` to map ActiveRecord errors to `{field, message}` array
4. Implement `render_server_error` to generate unique error ID, log exception, and return generic message
5. Use the concern in `UsersController#create` to handle validation failures
6. Test with curl, verifying 422 validation errors and 500 with error ID

## Acceptance Criteria

- [ ] `render_problem` returns `{type, title, status, detail}` matching RFC 7807
- [ ] `render_validation_errors` returns `{errors: [{field: "email", message: "..."}]}` with 422 status
- [ ] `render_server_error` generates UUID, logs full exception, returns `{error, error_id}` with 500 status
- [ ] `POST /api/users` with invalid data returns 422 with field-level errors
- [ ] Triggering an exception returns 500 with error ID and generic message
- [ ] Logs include error ID and full stack trace

## Verification Steps

1. Run `curl -X POST http://localhost:3000/api/users -H "Content-Type: application/json" -d '{"email": "invalid"}'` and verify `422` with `{errors: [{field: "email", message: "is invalid"}]}`
2. Execute `curl -X POST http://localhost:3000/api/users -H "Content-Type: application/json" -d '{}'` and verify 422 with multiple field errors
3. Modify controller to raise `StandardError` and execute `curl http://localhost:3000/api/users/1`, verifying `500` with `error_id` in response
4. Check `log/development.log` for the error ID and full stack trace
5. Execute `curl http://localhost:3000/api/users/99999` and verify `404` with RFC 7807 format
6. Verify no stack traces appear in response JSON, only in logs

## Stretch (Optional)

Add internationalization support using `I18n.t` for error messages, allowing clients to pass `Accept-Language` header for localized errors.

## Time Estimate

21 minutes
