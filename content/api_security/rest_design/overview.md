# REST Design Patterns

## What It Is

REST (Representational State Transfer) is an architectural style for APIs that treats everything as a resource accessed via HTTP verbs. Resources are nouns (users, orders) identified by URLs, manipulated through standard methods (GET, POST, PUT, DELETE), and return predictable status codes.

## Why It Matters

RESTful design creates predictable, cacheable APIs that clients can navigate without custom documentation. Consistent verb usage prevents confusion (POST for creation, PUT for full updates, PATCH for partials). Proper status codes (201 for creation, 404 for missing resources) enable generic error handling in frontend code.

## When to Use

- Building public or partner-facing APIs that need documentation
- Creating mobile backends where bandwidth and caching matter
- Designing microservices that communicate via HTTP
- Replacing legacy SOAP or RPC-style endpoints
- Supporting browser-based single-page applications

## Three Common Pitfalls

1. **Using verbs in URLs:** `/api/get_user/123` breaks REST conventions. Use `/api/users/123` with GET verb instead, so HTTP method conveys intent.
2. **Returning 200 for errors:** Sending `{error: "not found"}` with 200 OK forces clients to parse bodies. Use 404 status so HTTP-level tools (proxies, browsers) handle it correctly.
3. **Deep nesting beyond two levels:** `/api/companies/5/departments/12/teams/8/users` becomes unmaintainable. Stop at two levels (`/api/teams/8/users`) and use query params for filtering.

---

## Resource-Based URLs

Design URLs around nouns, not verbs. Use plural names and HTTP methods to convey actions.

```ruby
# routes.rb
namespace :api do
  resources :users do
    resources :posts, only: [:index, :create]
  end
end
```

This generates `/api/users` (GET for list, POST for create), `/api/users/:id` (GET for show, PUT/PATCH for update, DELETE for destroy), and `/api/users/:user_id/posts` for nested resources.

## HTTP Verbs and Idempotency

Match verbs to operations. GET and HEAD are safe (no state change). PUT and DELETE are idempotent (repeating has same effect). POST is neither.

```ruby
# UsersController
def create
  user = User.create!(user_params)
  render json: user, status: :created, location: api_user_url(user)
end

def update
  @user.update!(user_params)
  render json: @user
end
```

Return 201 Created with a `Location` header for POST. Return 200 OK for PUT/PATCH. Return 204 No Content for DELETE if no body is needed.

## Status Codes as Contracts

Choose codes that clients can handle generically.

```ruby
# Success codes
render json: @user, status: :ok                     # 200
render json: @user, status: :created                # 201
head :no_content                                    # 204

# Client error codes
render json: {error: "Not found"}, status: :not_found              # 404
render json: {errors: @user.errors}, status: :unprocessable_entity # 422
head :unauthorized                                                 # 401
head :forbidden                                                    # 403

# Server error codes
render json: {error: "Internal error"}, status: :internal_server_error # 500
```

Use 400 for malformed requests, 422 for validation failures, 401 for missing auth, 403 for insufficient permissions.

## JSON Response Conventions

Pick a format and enforce it. JSON:API provides standards for pagination, includes, and errors. Custom formats work if documented.

```ruby
# Custom format
{
  "data": {
    "id": 123,
    "type": "user",
    "attributes": {
      "email": "user@example.com",
      "created_at": "2025-01-15T10:30:00Z"
    }
  }
}

# JSON:API format
{
  "data": {
    "id": "123",
    "type": "users",
    "attributes": {
      "email": "user@example.com"
    },
    "links": {
      "self": "/api/users/123"
    }
  }
}
```

Wrap responses in a top-level `data` or `user` key. Use ISO8601 timestamps. Include links for discoverability (HATEOAS).

## Documentation with OpenAPI

OpenAPI (Swagger) specs enable auto-generated docs and client SDKs.

```yaml
# openapi.yml
openapi: 3.0.0
paths:
  /api/users:
    get:
      summary: List users
      responses:
        200:
          description: Success
          content:
            application/json:
              schema:
                type: array
                items:
                  $ref: '#/components/schemas/User'
```

Use `rswag` or `rspec-openapi` to generate specs from tests. Host docs with Swagger UI or ReDoc.

---

## Trade-offs Box

- **Advantage:** REST's uniformity reduces onboarding time and enables caching at the HTTP layer.
- **Cost:** Strict resource modeling can be awkward for operations like "send password reset" or "bulk approve."
- **When to skip:** For real-time websockets, GraphQL explorability, or internal microservices where RPC is simpler.

---

## Debugging Checklist

When REST APIs misbehave, check:

1. Confirm verb and URL match routes: `bin/rails routes | grep users`
2. Verify status code matches operation: 201 for create, 404 for missing, 422 for invalid
3. Check `Content-Type: application/json` header in request and response
4. Inspect body structure: does `data` key exist? Are timestamps ISO8601?
5. Test with `curl -v` to see raw headers and detect redirect loops
6. Review API docs (OpenAPI) for required fields and valid values

---

## One-Minute Recap

- Design URLs as resources (nouns) and use HTTP verbs for actions
- Return status codes that clients can handle generically (201, 404, 422)
- Keep nesting to two levels; use query params for deeper filtering
- Choose JSON:API for standards or document your custom format clearly
- Generate OpenAPI specs from tests to keep docs current
