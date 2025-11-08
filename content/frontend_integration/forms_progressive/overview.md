# Forms & progressive enhancement

## What It Is

Progressive enhancement builds forms that work without JavaScript, then layers on client-side features for better UX. The base layer submits to Rails controllers via HTTP POST. Enhanced layers add inline validation, optimistic UI updates, and real-time feedback using Stimulus and Turbo, degrading gracefully if scripts fail.

## Why It Matters

JavaScript can fail: slow networks, browser extensions, disabled scripts. Forms that require client-side code to function break for users in these scenarios. Progressive enhancement ensures core workflows (create, update, delete) always work. Enhanced features like live validation and instant feedback improve UX for most users without making the app fragile. This approach also simplifies testing since server-side logic already validates and persists data.

## When to Use

- Registration and checkout forms where submission must succeed even if JavaScript fails
- Admin dashboards where accessibility and keyboard navigation are critical
- Public-facing forms where diverse browsers and assistive technologies are common
- Forms with complex validation rules that exist on the server and shouldn't be duplicated in JavaScript
- Multi-step wizards where partial progress should save server-side, not just in local state

## Three Common Pitfalls

1. **Duplicating validation logic:** Writing validation in both JavaScript and Rails models creates drift. Use server-side validation as the source of truth and fetch it via AJAX for inline feedback, or use Rails to render error messages client-side.
2. **Optimistic updates without rollback:** Showing success immediately feels fast but breaks trust if the server rejects the change. Always handle failure by reverting the UI or re-rendering the form with errors.
3. **Inaccessible error messages:** Adding errors to the DOM without announcing them to screen readers hides failures from assistive technology users. Use ARIA live regions or focus management to make errors discoverable.

---

## Forms Without JavaScript: The Foundation

Every form should post to a Rails controller and handle the full lifecycle:

```erb
<%= form_with model: @user, url: users_path do |f| %>
  <%= f.label :email %>
  <%= f.text_field :email %>
  <%= f.submit "Sign Up" %>
<% end %>

```

On success, redirect with a flash message. On failure, re-render with errors:

```ruby
# app/controllers/users_controller.rb
def create
  @user = User.new(user_params)
  if @user.save
    redirect_to @user, notice: "Account created."
  else
    render :new, status: :unprocessable_entity
  end
end

```

This works in every browser, with or without JavaScript. Everything else is an enhancement.

---

## Turbo Form Submissions

Turbo intercepts form submissions and sends them via AJAX, replacing the page content without a full reload:

```erb
<%= form_with model: @post, data: { turbo_frame: "post_form" } do |f| %>
  <%= f.text_field :title %>
  <%= f.submit %>
<% end %>

```

On success, return a Turbo Stream to update the UI. On failure, return the form with errors:

```ruby
def create
  @post = Post.new(post_params)
  respond_to do |format|
    if @post.save
      format.turbo_stream { render turbo_stream: turbo_stream.prepend("posts", @post) }
    else
      format.html { render :new, status: :unprocessable_entity }
    end
  end
end

```

If Turbo fails to load, the form submits normally. No JavaScript required for basic functionality.

---

## Inline Validation with Stimulus

Validate fields on blur and show errors without submitting the form:

```javascript
// app/javascript/controllers/validation_controller.js
export default class extends Controller {
  static targets = ["email", "error"]

  async validateEmail() {
    const response = await fetch(`/users/validate_email?email=${this.emailTarget.value}`)
    const { valid, message } = await response.json()

    if (!valid) {
      this.errorTarget.textContent = message
      this.errorTarget.classList.remove("hidden")
    } else {
      this.errorTarget.classList.add("hidden")
    }
  }
}

```

HTML:

```erb
<div data-controller="validation">
  <%= f.text_field :email, data: { validation_target: "email", action: "blur->validation#validateEmail" } %>
  <span data-validation-target="error" class="hidden" role="alert"></span>
</div>

```

The server endpoint validates using the same model rules:

```ruby
# app/controllers/users_controller.rb
def validate_email
  user = User.new(email: params[:email])
  user.valid?
  render json: { valid: user.errors[:email].empty?, message: user.errors[:email].first }
end

```

---

## Optimistic UI Updates

Show success immediately, then revert if the server fails:

```javascript
// app/javascript/controllers/like_controller.js
export default class extends Controller {
  static targets = ["count", "button"]
  static values = { postId: Number }

  async toggle() {
    const previousCount = parseInt(this.countTarget.textContent)
    this.countTarget.textContent = previousCount + 1
    this.buttonTarget.disabled = true

    try {
      const response = await fetch(`/posts/${this.postIdValue}/like`, { method: "POST" })
      if (!response.ok) throw new Error("Failed")
      const { count } = await response.json()
      this.countTarget.textContent = count
    } catch (error) {
      this.countTarget.textContent = previousCount // Rollback
      alert("Like failed. Please try again.")
    } finally {
      this.buttonTarget.disabled = false
    }
  }
}

```

Always store the previous state and revert on error. Never leave the UI in a broken state.

---

## Handling Failures Gracefully

Display server errors inline without losing form data:

```ruby
# app/controllers/posts_controller.rb
def create
  @post = Post.new(post_params)
  respond_to do |format|
    if @post.save
      format.turbo_stream
    else
      format.turbo_stream do
        render turbo_stream: turbo_stream.replace("post_form", partial: "form", locals: { post: @post })
      end
    end
  end
end

```

The partial includes error messages:

```erb
<%= form_with model: post, id: "post_form" do |f| %>
  <% if post.errors.any? %>
    <div role="alert">
      <ul>
        <% post.errors.full_messages.each do |msg| %>
          <li><%= msg %></li>
        <% end %>
      </ul>
    </div>
  <% end %>
  <%= f.text_field :title %>
<% end %>

```

---

## Accessibility: ARIA and Focus Management

Announce errors to screen readers with ARIA live regions:

```erb
<div aria-live="polite" aria-atomic="true">
  <% if @user.errors[:email].any? %>
    <span role="alert"><%= @user.errors[:email].first %></span>
  <% end %>
</div>

```

Focus the first invalid field after submission:

```javascript
// app/javascript/controllers/form_controller.js
export default class extends Controller {
  handleError() {
    const firstError = this.element.querySelector("[aria-invalid='true']")
    if (firstError) firstError.focus()
  }
}

```

---

## Trade-offs Box

- **Advantage:** Forms work for all users regardless of JavaScript availability, reducing risk and improving accessibility.
- **Cost:** Requires maintaining server-side rendering logic alongside client enhancements; slightly more code than a pure SPA approach.
- **When to skip:** Internal tools with controlled environments where JavaScript is guaranteed might prioritize speed of development over graceful degradation.

---

## Debugging Checklist

When things go wrong, check:

1. Test with JavaScript disabled: open DevTools, disable JavaScript in settings, and verify the form submits and shows errors
2. Inspect Network tab for failed AJAX requests; confirm the server returns the correct status code (422 for validation errors)
3. Check for missing CSRF tokens: ensure `form_with` includes `authenticity_token` or Turbo handles it automatically
4. Verify error messages appear in the DOM: use Elements tab to confirm error spans render and ARIA attributes are present
5. Test with a screen reader (VoiceOver on Mac, NVDA on Windows) to confirm error announcements
6. Look for JavaScript errors in Console that might break Stimulus controllers or Turbo interceptors

---

## One-Minute Recap

- Progressive enhancement starts with HTML forms that work without JavaScript, then adds client-side features
- Turbo intercepts form submissions for AJAX updates while degrading gracefully to standard POSTs
- Inline validation with Stimulus calls server endpoints to avoid duplicating validation logic
- Optimistic updates improve perceived speed but must roll back on server errors
- Accessibility requires ARIA live regions, focus management, and semantic HTML for screen reader users
