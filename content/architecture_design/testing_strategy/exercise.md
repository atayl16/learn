# Exercise: Testing Strategy

## Objective

Build a test suite with balanced unit, request, and system tests using FactoryBot, VCR, and Capybara.

## Task

You're testing a `BookingService` that validates availability, charges a credit card via Stripe, and sends a confirmation email. Create three test files:

1. **Unit test** for `BookingService` logic: test availability calculation without hitting the database or network
2. **Request test** for `POST /bookings`: verify the endpoint creates a booking and returns JSON, using FactoryBot for test data
3. **System test** for the booking flow: use Capybara to fill the form, submit, and verify the confirmation page loads
4. Add VCR to record Stripe API calls in the request test
5. Use WebMock to stub a timeout error from Stripe and verify the service handles it gracefully

Run SimpleCov and confirm you have 80%+ coverage on the `BookingService` class.

## Acceptance Criteria

- [ ] Unit test runs in under 10ms and requires no database or HTTP setup
- [ ] Request test uses FactoryBot to create a user and room, hits `/bookings`, and checks JSON response
- [ ] System test uses Capybara to interact with form elements and verify success message
- [ ] VCR cassette is created in `spec/fixtures/vcr_cassettes/` after first run
- [ ] WebMock stub triggers a timeout and the test confirms error handling
- [ ] SimpleCov report shows 80%+ coverage for `BookingService`

## Verification Steps

1. Run `rspec spec/services/booking_service_spec.rb --profile` and confirm unit test is under 10ms
2. Check `spec/fixtures/vcr_cassettes/` for a cassette named after the request test
3. Run `DISABLE_VCR=true rspec` and confirm WebMock stub is used instead
4. Open `coverage/index.html` and find `BookingService` in the report

## Stretch (Optional)

Add a test that runs the entire suite and fails if average test time exceeds 100ms per example (use RSpec metadata to tag slow tests and exclude them from CI).

## Time Estimate

24 minutes
