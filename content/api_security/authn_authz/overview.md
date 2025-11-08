# Authentication & Authorization with Pundit

## What It Is

Authentication (AuthN) verifies identity (who you are) via tokens, sessions, or credentials. Authorization (AuthZ) enforces permissions (what you can do) using policies. Pundit is a Rails gem that defines authorization rules in plain Ruby classes, separating policy logic from controllers.

## Why It Matters

Missing authorization causes Insecure Direct Object Reference (IDOR) attacks where users access others' data by changing IDs. Hardcoding `if current_user.admin?` in controllers creates scattered, untestable logic. Pundit centralizes rules, making them auditable and testable in isolation.

## When to Use

- Building APIs where users have different permission levels
- Protecting resources so users can only access their own records
- Implementing role-based access (admin, member, guest)
- Replacing controller-level authorization checks with policies
- Auditing authorization logic for security compliance

## Three Common Pitfalls

1. **Authenticating but not authorizing:** Verifying a user is logged in doesn't check if they own the resource. Always call `authorize @post` after `@post = Post.find(params[:id])`.
2. **Forgetting to scope index actions:** `Post.all` returns all posts, including others' private ones. Use `policy_scope(Post)` to filter by ownership or visibility.
3. **Testing only controller behavior:** Authorization bugs hide if you test as an admin. Write policy specs testing each role (guest, member, admin) separately.

---

## Token-Based Authentication

APIs use tokens instead of sessions. Clients send tokens in the `Authorization` header.

```ruby
# ApplicationController
class ApplicationController < ActionController::API
  before_action :authenticate_user!

  private

  def authenticate_user!
    token = request.headers['Authorization']&.split(' ')&.last
    payload = decode_token(token)
    @current_user = User.find_by(id: payload['user_id']) if payload
    render json: {error: 'Unauthorized'}, status: :unauthorized unless @current_user
  end

  def decode_token(token)
    JWT.decode(token, Rails.application.secret_key_base, true, algorithm: 'HS256')[0]
  rescue JWT::DecodeError
    nil
  end

  attr_reader :current_user
end
```

Generate tokens with `JWT.encode({user_id: user.id}, secret, 'HS256')`. Send them as `Authorization: Bearer <token>`.

## Pundit Policies

Define a policy class per model. Each method corresponds to a controller action.

```ruby
# app/policies/post_policy.rb
class PostPolicy < ApplicationPolicy
  def show?
    record.published? || record.user_id == user.id
  end

  def update?
    record.user_id == user.id
  end

  def destroy?
    record.user_id == user.id || user.admin?
  end
end

# PostsController
def update
  @post = Post.find(params[:id])
  authorize @post  # calls PostPolicy#update?
  @post.update!(post_params)
  render json: @post
end
```

`authorize @post` raises `Pundit::NotAuthorizedError` if `update?` returns false. Rescue and render 403.

## Policy Scopes

Scopes filter records users are allowed to see.

```ruby
# app/policies/post_policy.rb
class PostPolicy < ApplicationPolicy
  class Scope < Scope
    def resolve
      if user.admin?
        scope.all
      else
        scope.where(published: true).or(scope.where(user_id: user.id))
      end
    end
  end
end

# PostsController
def index
  @posts = policy_scope(Post)
  render json: @posts
end
```

Guests see only published posts; owners see their drafts; admins see all.

## Handling Authorization Errors

Rescue `Pundit::NotAuthorizedError` to return 403.

```ruby
# ApplicationController
include Pundit::Authorization

rescue_from Pundit::NotAuthorizedError, with: :user_not_authorized

private

def user_not_authorized
  render json: {error: 'Forbidden'}, status: :forbidden
end
```

Optionally log the attempt for audit trails.

## Testing Policies

Test policies in isolation using RSpec.

```ruby
# spec/policies/post_policy_spec.rb
RSpec.describe PostPolicy do
  subject { described_class.new(user, post) }

  let(:post) { create(:post, user: owner) }
  let(:owner) { create(:user) }

  context 'as owner' do
    let(:user) { owner }

    it { is_expected.to permit_action(:update) }
    it { is_expected.to permit_action(:destroy) }
  end

  context 'as guest' do
    let(:user) { create(:user) }

    it { is_expected.not_to permit_action(:update) }
    it { is_expected.not_to permit_action(:destroy) }
  end
end
```

Use `pundit-matchers` gem for `permit_action` matcher.

## Preventing IDOR Attacks

IDOR (Insecure Direct Object Reference) lets users change IDs to access others' data.

```ruby
# Vulnerable
def show
  @post = Post.find(params[:id])  # No authorization check
  render json: @post
end

# Secure
def show
  @post = Post.find(params[:id])
  authorize @post  # Calls PostPolicy#show?
  render json: @post
end
```

Attacker changes `/api/posts/123` to `/api/posts/124` and sees another user's draft. `authorize` prevents this.

---

## Trade-offs Box

- **Advantage:** Pundit centralizes authorization logic, making it testable and auditable.
- **Cost:** Requires policy classes for each model; scopes add query complexity.
- **When to skip:** For simple apps with one permission level or internal admin tools where all users are trusted.

---

## Debugging Checklist

When authorization fails unexpectedly, check:

1. Confirm `current_user` is set: `puts current_user.inspect` in controller
2. Verify policy class exists: `PostPolicy` for `Post` model
3. Check policy method matches action: `update?` for `update` action
4. Inspect record attributes: `puts @post.user_id` vs `current_user.id`
5. Test policy in console: `PostPolicy.new(user, post).update?`
6. Review scope logic: run `policy_scope(Post).to_sql` to see generated query

---

## One-Minute Recap

- Authentication verifies identity (JWT tokens); authorization enforces permissions (Pundit policies)
- Call `authorize @resource` in every controller action to prevent IDOR attacks
- Use `policy_scope(Model)` in index actions to filter by ownership or visibility
- Rescue `Pundit::NotAuthorizedError` to return 403 Forbidden
- Test policies in isolation with RSpec, covering guest, member, and admin roles
