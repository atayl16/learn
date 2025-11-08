# Exercise: Forms & progressive enhancement

## Objective

Build a user registration form with progressive enhancement: baseline HTML submission, inline email validation, optimistic UI feedback, and accessible error handling.

## Task

Create a registration form for `User` with email and password fields:

1. **Baseline functionality:** The form should POST to `/users` and work without JavaScript. On validation errors, re-render the form with error messages displayed above each field. On success, redirect to a welcome page.

2. **Turbo enhancement:** Intercept the form submission with Turbo. On success, append a welcome message to the page using Turbo Stream. On failure, replace the form with the error-annotated version without a full page reload.

3. **Inline email validation:** Add a Stimulus controller that validates the email field on blur. Send a GET request to `/users/validate_email?email=<value>` and display an error message below the field if invalid. Mark the field with `aria-invalid="true"` when errors exist.

4. **Optimistic UI feedback:** Disable the submit button immediately on click and show "Creating account..." text. If the server responds with errors, re-enable the button and restore the original "Sign Up" text.

5. **Accessible errors:** Wrap error messages in a `<div role="alert" aria-live="polite">` so screen readers announce them. After submission with errors, focus the first invalid field.

## Acceptance Criteria

- [ ] Disabling JavaScript in DevTools and submitting the form still creates a user or shows errors after a full page reload
- [ ] Blurring the email field with an invalid email (e.g., "test@") shows an inline error message without submitting
- [ ] Submitting with validation errors replaces the form content without reloading the page (check Network tab: no document reload)
- [ ] The submit button text changes to "Creating account..." when clicked and reverts if errors occur
- [ ] Error messages include `role="alert"` and screen reader testing confirms announcements (or inspect Elements tab for ARIA attributes)
- [ ] After form submission with errors, the first invalid field receives focus automatically

## Verification Steps

1. Run `rails server` and navigate to `/users/new`
2. Open DevTools, go to Settings, and check "Disable JavaScript"
3. Submit the form with blank fields and confirm errors appear after a full page reload
4. Re-enable JavaScript and reload the page
5. Type "invalid-email" in the email field, tab away, and verify an error appears inline
6. Fill the form correctly, click Submit, and confirm the button text changes and a success message appears without a page reload
7. Capture a screenshot of the Elements tab showing `role="alert"` on an error message

## Stretch (Optional)

Add password strength indicator using Stimulus: show weak/medium/strong feedback as the user types, using CSS classes to color the indicator red/yellow/green.

## Time Estimate

23 minutes
