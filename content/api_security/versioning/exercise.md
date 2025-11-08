# Exercise: API Versioning Strategies

## Objective

Implement path-based API versioning with v1 and v2 endpoints, add a Sunset header to deprecate v1, and ensure backward compatibility for new fields.

## Task

You're evolving a product catalog API. Create v1 returning `{id, name, price}` and v2 returning `{id, name, price, description}`. Add a `Sunset` header to v1 indicating deprecation in 6 months. Ensure v2 is backward-compatible by making `description` optional and documenting the change.

1. Create `Api::V1::ProductsController` returning products with `id`, `name`, `price` fields only
2. Create `Api::V2::ProductsController` adding `description` field to response
3. Configure routes under `/api/v1/products` and `/api/v2/products`
4. Add a `before_action` to v1 controller setting `Sunset` header to 6 months from now
5. Test both versions with curl, verifying v1 has Sunset header and v2 includes description
6. Write a migration guide documenting the new field

## Acceptance Criteria

- [ ] `GET /api/v1/products` returns `{data: [{id, name, price}]}` with Sunset header
- [ ] `GET /api/v2/products` returns `{data: [{id, name, price, description}]}`
- [ ] Sunset header format: `Sat, 31 Dec 2025 23:59:59 GMT` (6 months from now)
- [ ] v2 response is backward-compatible: old clients ignore `description` field
- [ ] Both versions use shared model and query logic (no duplication)
- [ ] Migration guide exists at `docs/api_v2_migration.md`

## Verification Steps

1. Execute `curl http://localhost:3000/api/v1/products` and verify response has `id`, `name`, `price` only
2. Check response headers: `curl -I http://localhost:3000/api/v1/products` and verify `Sunset` header present
3. Execute `curl http://localhost:3000/api/v2/products` and verify response includes `description` field
4. Execute `curl http://localhost:3000/api/v2/products` with old client parser (ignores unknown fields) and confirm no errors
5. Run `bin/rails routes | grep products` and verify both `/api/v1/products` and `/api/v2/products` exist
6. Read `docs/api_v2_migration.md` and confirm it documents the new field and backward compatibility

## Stretch (Optional)

Implement header-based versioning using `Accept: application/vnd.myapp.v1+json` and `Accept: application/vnd.myapp.v2+json`, routing to the same controllers based on header parsing.

## Time Estimate

21 minutes
