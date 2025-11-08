# Exercise: Pagination, Filtering & Sorting

## Objective

Implement cursor-based pagination, filtering, and sorting for an API endpoint, ensuring database indexes support performance.

## Task

You're building an API for a blog platform. Extend the `GET /api/posts` endpoint to support cursor pagination (by `id`), filtering by `status` (draft, published), sorting by `created_at` or `updated_at`, and returning pagination metadata. Add appropriate database indexes.

1. Implement cursor pagination using `?cursor=` param, fetching 20 posts per page
2. Add filtering: `?status=published` or `?status=draft`
3. Add sorting: `?sort=created_at` (ascending) or `?sort=-created_at` (descending)
4. Return JSON with `data` and `meta.next_cursor`
5. Create database indexes on `status` and `created_at` columns
6. Test with curl, verifying performance with `EXPLAIN ANALYZE`

## Acceptance Criteria

- [ ] `GET /api/posts` returns 20 posts ordered by `id` descending with `next_cursor` in meta
- [ ] `GET /api/posts?cursor=12345` returns posts with `id < 12345`
- [ ] `GET /api/posts?status=published` filters to only published posts
- [ ] `GET /api/posts?sort=-created_at` orders by creation date descending
- [ ] Database has indexes on `status` and `created_at` columns
- [ ] Response includes `{"data": [...], "meta": {"next_cursor": 12300}}`

## Verification Steps

1. Run `bin/rails db:migrate:status` and confirm migration adding indexes exists
2. Execute `curl http://localhost:3000/api/posts` and verify 20 posts with `next_cursor`
3. Execute `curl "http://localhost:3000/api/posts?cursor=12345"` and verify posts have `id < 12345`
4. Execute `curl "http://localhost:3000/api/posts?status=published"` and verify only published posts returned
5. Execute `curl "http://localhost:3000/api/posts?sort=-created_at"` and verify posts ordered by `created_at` descending
6. Run `bin/rails db` and execute `EXPLAIN ANALYZE SELECT * FROM posts WHERE status = 'published' ORDER BY created_at DESC LIMIT 20;` to confirm index usage

## Stretch (Optional)

Combine cursor pagination with filtering and sorting: implement `?cursor=12345&status=published&sort=-created_at` ensuring the cursor works correctly with the filter and sort.

## Time Estimate

24 minutes
