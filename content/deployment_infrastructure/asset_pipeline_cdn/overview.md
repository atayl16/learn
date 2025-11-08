# Asset Pipeline & CDN

## What It Is

The Rails asset pipeline manages static assets (JavaScript, CSS, images). Rails 7+ defaults to **Propshaft**, a streamlined alternative to legacy **Sprockets**. Propshaft compiles assets with digest fingerprints (e.g., `application-a1b2c3d4.css`) and serves them via CDN. CDNs like CloudFront or Cloudflare cache assets globally, reducing latency and offloading bandwidth. S3 integration enables stateless deployments by storing compiled assets separately from application servers.

## Why It Matters

Production Rails apps serve millions of asset requests. Without a CDN, every CSS/JS request hits your servers, wasting CPU and bandwidth. A well-configured asset pipeline with CDN reduces page load times by 60-80%, improves SEO, and cuts hosting costs. Asset fingerprinting ensures cache invalidation works—users get the latest version after deploys without manual cache purges. Propshaft simplifies configuration compared to Sprockets. Understanding cache headers (`Cache-Control`, `ETag`) prevents stale asset bugs in production.

## When to Use

- **Production deployments:** Serve assets from CloudFront/Cloudflare to reduce server load
- **High-traffic apps:** Offload 80%+ of requests to edge caches
- **Multi-region apps:** CDN edge locations reduce latency globally
- **Stateless containers:** Store assets in S3 instead of container filesystems
- **Zero-downtime deploys:** Fingerprinted assets allow multiple app versions to coexist

## Three Common Pitfalls

1. **Missing fingerprinted assets in production:** Forgetting `rails assets:precompile` before deployment causes 404 errors. Precompile assets during Docker builds, not at container runtime. Propshaft requires explicit precompilation.

2. **Incorrect cache headers cause stale assets:** Setting long cache TTLs on HTML pages breaks deployments. HTML should have `no-cache` or short TTLs; only fingerprinted assets get immutable caching. Misconfigured CDN behaviors serve old CSS to new HTML.

3. **S3 upload missing files or permissions:** Uploading only changed files breaks when old assets are purged. Always upload the full `public/assets/` directory. S3 bucket policies must allow public `GetObject`. Missing CORS headers break font/image requests.

---

## Propshaft vs Sprockets

**Sprockets (Legacy):** Rails 3.1-6.x default. Uses `//= require` directives, compiles Sass/CoffeeScript, manages dependencies. Complex but feature-rich.

**Propshaft (Rails 7+):** Minimal pipeline focusing on fingerprinting only. Delegates JS/CSS bundling to esbuild/Vite/Tailwind. Faster, simpler configuration.

```ruby
# Gemfile (Rails 7+)
gem "propshaft"

# config/application.rb
config.assets.paths << Rails.root.join("app/assets/builds")
```

**Key difference:** Propshaft delegates preprocessing to external tools. Sprockets does everything internally.

---

## Asset Fingerprinting

Fingerprinting appends a content hash to filenames: `application.css` → `application-9f8e7d6c.css`. When you deploy updated CSS, the filename changes, forcing browsers to fetch the new version instead of using stale cache.

Rails computes SHA256 hash of file contents and stores mappings in `.manifest.json`:

```json
{
  "application.css": "application-9f8e7d6c5b4a3.css"
}
```

Helpers like `asset_path()` and `stylesheet_link_tag()` consult this manifest to generate correct URLs.

---

## Precompilation

Production requires pre-built assets. Run `rails assets:precompile` to compile Sass/JS, generate fingerprinted files in `public/assets/`, and create `.manifest.json`.

```bash
RAILS_ENV=production rails assets:precompile
```

**Docker integration:** Precompile in builder stage, copy `public/assets/` to final image:

```dockerfile
FROM ruby:3.2-alpine AS builder
RUN SECRET_KEY_BASE=dummy rails assets:precompile

FROM ruby:3.2-alpine
COPY --from=builder /app/public/assets /app/public/assets
```

**Critical config:** Set `config.assets.compile = false` in production to prevent on-the-fly compilation (security risk).

---

## CDN Integration

**CloudFront:** Create S3 bucket → upload assets → create CloudFront distribution with S3 origin → set TTL to 1 year → configure Rails:

```ruby
# config/environments/production.rb
config.asset_host = "https://d111111abcdef8.cloudfront.net"
```

**Cloudflare:** Add domain → create page rule for `/assets/*` with max TTL → configure Rails:

```ruby
config.asset_host = "https://assets.myapp.com"
```

Cloudflare auto-caches assets without requiring S3. CloudFront requires S3 origin but offers more control.

---

## Cache Headers

**Fingerprinted assets:** Set `Cache-Control: public, max-age=31536000, immutable` for 1-year caching. The `immutable` directive prevents unnecessary revalidation.

```ruby
# config/environments/production.rb
config.public_file_server.headers = {
  "Cache-Control" => "public, max-age=31536000, immutable"
}
```

**HTML pages:** Use `Cache-Control: no-cache` or short TTLs. HTML references fingerprinted assets, so it must always fetch the latest version to get new asset URLs.

**ETags:** Rails sets `ETag` headers for conditional requests. Use `fresh_when(@resource)` in controllers to return `304 Not Modified` when content hasn't changed.

---

## Serving Assets from S3

**Using asset_sync gem:** Automatically uploads assets after precompilation. Configure with AWS credentials, bucket name, and enable gzip compression.

**Manual upload:**

```bash
aws s3 sync public/assets s3://myapp-assets/assets \
  --acl public-read \
  --cache-control "public, max-age=31536000, immutable"
```

**CORS setup (for fonts/images):** Add CORS policy to S3 bucket allowing GET requests from your domain.

---

## Best Practices

- Use Propshaft for new apps; precompile assets in CI/CD before deployment
- Set `config.assets.compile = false` in production to catch missing assets early
- Use CloudFront/Cloudflare for multi-region apps; direct S3 for simple deployments
- Set `Cache-Control: immutable` on fingerprinted assets, short TTLs on HTML
- Upload full `public/assets/` to S3 on every deploy to handle deletions
- Monitor CDN cache hit rates (target >95%)

---

## Key Terms

- **Propshaft** - Rails 7+ asset pipeline (simpler than Sprockets)
- **Asset fingerprinting** - Appending content hash to filenames for cache invalidation
- **Precompilation** - Building production assets via `rails assets:precompile`
- **CDN** - Global edge caches (CloudFront, Cloudflare)
- **Cache-Control** - HTTP header controlling caching behavior
- **Immutable** - Cache directive indicating file will never change
- **Asset host** - Domain serving static assets

---

## Summary

Rails asset pipelines (Propshaft/Sprockets) compile and fingerprint static assets for production. Propshaft delegates JS bundling to external tools for simpler configuration. Fingerprinting ensures cache invalidation—new deploys change filenames, forcing cache misses. Precompile assets during deployment (Docker/CI/CD), never at runtime. Use CloudFront or Cloudflare to serve assets from global edge caches, reducing latency by 60-80%. Set `Cache-Control: immutable` on fingerprinted files, short TTLs on HTML to prevent stale asset bugs.

**Next steps:** Complete the exercise to configure Propshaft and deploy assets to CloudFront.
