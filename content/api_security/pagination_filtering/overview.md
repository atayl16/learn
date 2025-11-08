# Pagination, Filtering & Sorting

## What It Is

Pagination limits result sets to manageable chunks, returning metadata (page numbers, cursors, totals) so clients can fetch subsequent pages. Filtering uses query parameters to narrow results (`?status=active`). Sorting orders results by one or more columns (`?sort=-created_at`).

## Why It Matters

Unpaginated endpoints loading thousands of records cause memory bloat and timeouts. Cursor pagination prevents data skipping when new records are inserted mid-iteration. Proper indexing on filtered and sorted columns keeps queries fast as tables grow to millions of rows.

## When to Use

- Listing resources that grow unbounded (users, orders, logs)
- Supporting mobile clients with bandwidth constraints
- Building infinite-scroll UIs that fetch pages on demand
- Exposing real-time feeds where new items appear frequently
- Replacing legacy endpoints that return entire tables

## Three Common Pitfalls

1. **Missing indexes on filter columns:** Filtering by `?status=active` without an index on `status` causes full table scans. Add indexes to all filterable columns.
2. **Using offset pagination for real-time feeds:** `OFFSET 100 LIMIT 20` skips records if new items are inserted. Use cursor pagination (keyset pagination) with `WHERE id > last_seen_id` instead.
3. **Returning total_count on every request:** `COUNT(*)` queries are slow on large tables. Cache counts, estimate them, or omit entirely for cursor pagination.

---

## Offset Pagination

Simplest approach using `LIMIT` and `OFFSET`. Works well for small, stable datasets.

```ruby
# UsersController
def index
  page = params[:page]&.to_i || 1
  per_page = 20

  @users = User.limit(per_page).offset((page - 1) * per_page)
  total = User.count

  render json: {
    data: @users,
    meta: {
      current_page: page,
      per_page: per_page,
      total_count: total,
      total_pages: (total / per_page.to_f).ceil
    }
  }
end
```

Use the `kaminari` or `pagy` gem for helpers. Offset pagination degrades with large offsets because the database still scans skipped rows.

## Cursor Pagination

Uses a cursor (last seen ID or timestamp) to fetch the next page. Stable for real-time data.

```ruby
# PostsController
def index
  per_page = 20
  cursor = params[:cursor]&.to_i

  scope = Post.order(id: :desc).limit(per_page + 1)
  scope = scope.where('id < ?', cursor) if cursor

  posts = scope.to_a
  has_next = posts.size > per_page
  posts = posts.first(per_page) if has_next

  render json: {
    data: posts,
    meta: {
      next_cursor: has_next ? posts.last.id : nil
    }
  }
end
```

Client passes `?cursor=12345` to fetch posts older than ID 12345. No total count or page numbers, just `next_cursor`.

## Filtering with Query Params

Map query params to scopes or WHERE clauses. Validate allowed filters to prevent SQL injection.

```ruby
# ProductsController
ALLOWED_FILTERS = %w[category status in_stock].freeze

def index
  @products = Product.all

  if params[:category].present?
    @products = @products.where(category: params[:category])
  end

  if params[:status].present?
    @products = @products.where(status: params[:status])
  end

  render json: { data: @products }
end
```

Use strong params or a gem like `ransack` (carefully scoped) or `filterrific`. Always whitelist allowed filters.

## Sorting

Parse `sort` param to allow multi-column ordering. Prefix with `-` for descending.

```ruby
# OrdersController
def index
  sort = params[:sort] || 'created_at'
  direction = sort.starts_with?('-') ? :desc : :asc
  column = sort.delete_prefix('-')

  allowed = %w[created_at updated_at total]
  column = 'created_at' unless allowed.include?(column)

  @orders = Order.order(column => direction)
  render json: { data: @orders }
end
```

Add indexes on sortable columns. For composite sorts, create multi-column indexes.

## Pagination Meta Fields

Return enough metadata for clients to build navigation UI.

```ruby
{
  "data": [...],
  "meta": {
    "current_page": 2,
    "per_page": 20,
    "total_count": 1543,
    "total_pages": 78,
    "next_page": 3,
    "prev_page": 1
  },
  "links": {
    "first": "/api/users?page=1",
    "prev": "/api/users?page=1",
    "next": "/api/users?page=3",
    "last": "/api/users?page=78"
  }
}
```

Include `links` for HATEOAS. Omit `total_count` for cursor pagination.

---

## Trade-offs Box

- **Advantage:** Pagination reduces memory usage and response times; filtering limits data transfer to what's needed.
- **Cost:** Cursor pagination complicates UI (no page numbers); offset pagination degrades with large offsets; counts are expensive on big tables.
- **When to skip:** For admin dashboards with small datasets or when exporting entire tables to CSV.

---

## Debugging Checklist

When pagination or filtering breaks, check:

1. Confirm indexes exist on filter and sort columns: `\d table_name` in psql or check `schema.rb`
2. Run `EXPLAIN ANALYZE` on the query to detect full table scans
3. Verify `per_page` doesn't exceed a safe limit (100-200 max)
4. Check cursor logic: ensure `id` or timestamp is indexed and unique
5. Test filter params for SQL injection: pass `'; DROP TABLE users--` and verify sanitization
6. Validate `total_count` is cached or omitted for large tables

---

## One-Minute Recap

- Use offset pagination for small datasets; cursor pagination for real-time feeds
- Filter via query params with whitelisted columns to prevent SQL injection
- Sort using `?sort=column` or `?sort=-column` for descending; index sort columns
- Return `meta` with `current_page`, `total_count`, and `next_cursor` as appropriate
- Always add database indexes to columns used in WHERE and ORDER BY clauses
