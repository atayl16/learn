# Exercise: REST Design Patterns

## Objective

Design and implement a RESTful API endpoint for managing product reviews with correct routes, verbs, status codes, and JSON structure.

## Task

You're building an e-commerce API. Create a `ReviewsController` under `/api/products/:product_id/reviews` that supports listing, creating, and deleting reviews. Return proper status codes, include a `Location` header on creation, and wrap responses in a `data` key.

1. Generate the controller and define routes for nested reviews under products
2. Implement `index` to return all reviews for a product (200 OK)
3. Implement `create` to add a review with validation, returning 201 Created with a `Location` header
4. Implement `destroy` to delete a review, returning 204 No Content
5. Handle not-found products with 404 and validation errors with 422
6. Test all endpoints with curl or a REST client, verifying status codes

## Acceptance Criteria

- [ ] Routes defined: `GET /api/products/:product_id/reviews`, `POST /api/products/:product_id/reviews`, `DELETE /api/reviews/:id`
- [ ] `POST` returns 201 with `Location: /api/reviews/{id}` header
- [ ] `GET` returns 200 with JSON array wrapped in `{"data": [...]}`
- [ ] `DELETE` returns 204 with no body
- [ ] Missing product returns 404; invalid review returns 422 with errors
- [ ] All responses include `Content-Type: application/json` header

## Verification Steps

1. Run `bin/rails routes | grep reviews` and confirm nested routes appear
2. Execute `curl -X POST http://localhost:3000/api/products/1/reviews -H "Content-Type: application/json" -d '{"rating": 5, "comment": "Great!"}'` and verify `201 Created` response with `Location` header
3. Execute `curl http://localhost:3000/api/products/1/reviews` and verify `200 OK` with `{"data": [...]}`
4. Execute `curl -X DELETE http://localhost:3000/api/reviews/1` and verify `204 No Content`
5. Execute `curl http://localhost:3000/api/products/9999/reviews` and verify `404 Not Found`
6. Execute `curl -X POST http://localhost:3000/api/products/1/reviews -H "Content-Type: application/json" -d '{"rating": "invalid"}'` and verify `422 Unprocessable Entity` with error details

## Stretch (Optional)

Add a `PATCH /api/reviews/:id` endpoint that returns 200 OK on success and demonstrates idempotency by allowing repeated updates with the same payload.

## Time Estimate

22 minutes
