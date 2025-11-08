# Docker & Containerization Basics

## What It Is
Docker is a platform for packaging applications and their dependencies into isolated containers—lightweight, portable units that run consistently across environments. A container bundles your Rails app, Ruby runtime, system libraries, and dependencies into a single image. Unlike virtual machines, containers share the host OS kernel, making them faster to start and lighter on resources. Multi-stage Dockerfiles optimize images by separating build-time tools from runtime dependencies.

## Why It Matters
Production Rails deployments require reproducibility. "Works on my machine" bugs disappear when dev and prod run identical containers. Docker simplifies deploying to Kubernetes, AWS ECS, or any cloud platform. Rails-specific challenges—precompiling assets, managing database migrations, handling secrets—require careful Dockerfile design. A poorly optimized image (2GB+) wastes bandwidth and slows deployments; a well-crafted multi-stage build produces 200-500MB images. Understanding layer caching cuts build times from 10 minutes to 30 seconds.

## When to Use
- **Production deployment:** Ship to Kubernetes, ECS, or any container orchestrator
- **Development parity:** Run the same environment locally and in production
- **CI/CD pipelines:** Build once, test in container, deploy the same image
- **Microservices:** Isolate services (Rails API, background workers, frontend)
- **Debugging production issues:** Reproduce exact production environment locally
- **Legacy dependencies:** Isolate old Ruby versions or system libraries

## Three Common Pitfalls
1. **Layer caching breaks on Gemfile changes:** Copying the entire app before `bundle install` invalidates cache on every code change. Fix: copy `Gemfile` first, run `bundle install`, then copy app code.
2. **Asset compilation in production containers:** Running `rails assets:precompile` at runtime wastes startup time. Fix: Precompile in multi-stage build, copy compiled assets to final image.
3. **Bloated images with build tools:** Including gcc, make, and node in production images adds 500MB+. Fix: Use multi-stage builds to separate build dependencies from runtime.

---

## Docker Core Concepts

### Images vs Containers

**Image:** A read-only template with your app and dependencies. Built from a Dockerfile.

**Container:** A running instance of an image. Writable, ephemeral.

```bash
docker build -t myapp:latest .       # Creates image
docker run -p 3000:3000 myapp:latest # Runs container from image
```

### Layers & Caching

Each Dockerfile instruction creates a layer. Docker caches unchanged layers:

```dockerfile
FROM ruby:3.2-alpine         # Layer 1: base image
RUN apk add --no-cache build-base  # Layer 2: dependencies
COPY Gemfile* ./             # Layer 3: gem files
RUN bundle install           # Layer 4: installed gems (cached if Gemfile unchanged)
COPY . .                     # Layer 5: app code (changes frequently)
```

**Optimization:** Order instructions from least to most frequently changed. Place `COPY . .` last so code changes don't invalidate gem cache.

---

## Multi-Stage Builds for Rails

Multi-stage builds use multiple `FROM` statements. Early stages build assets and install gems; the final stage copies only runtime artifacts:

```dockerfile
# Stage 1: Build environment
FROM ruby:3.2-alpine AS builder

RUN apk add --no-cache build-base nodejs yarn postgresql-dev

WORKDIR /app

COPY Gemfile Gemfile.lock ./
RUN bundle config set --local deployment 'true' && \
    bundle config set --local without 'development test' && \
    bundle install --jobs 4

COPY package.json yarn.lock ./
RUN yarn install --frozen-lockfile

COPY . .

# Precompile assets
RUN SECRET_KEY_BASE=placeholder rails assets:precompile

# Stage 2: Runtime environment
FROM ruby:3.2-alpine

RUN apk add --no-cache postgresql-client tzdata

WORKDIR /app

# Copy only runtime dependencies
COPY --from=builder /usr/local/bundle /usr/local/bundle
COPY --from=builder /app /app

EXPOSE 3000

CMD ["rails", "server", "-b", "0.0.0.0"]
```

**Key benefits:**
- Builder stage has gcc, make, node (build tools)
- Final image has only runtime dependencies
- Image size: 1.2GB → 350MB

---

## Rails-Specific Dockerfile Concerns

### 1. Asset Compilation

**Problem:** Assets need to be precompiled before the app starts.

**Solution:** Precompile during image build:

```dockerfile
# In builder stage
ENV RAILS_ENV=production
ENV NODE_ENV=production
RUN SECRET_KEY_BASE=placeholder rails assets:precompile
```

**Why placeholder key?** Assets:precompile doesn't need the real secret; it just needs a non-empty value.

### 2. Database Setup

**Problem:** `rails db:migrate` shouldn't run in the Dockerfile (database may not exist yet).

**Solution:** Run migrations in a separate step (init container, deploy script):

```bash
# Deploy script
docker run myapp:latest rails db:migrate
docker run -d myapp:latest rails server
```

Or use an entrypoint script:

```dockerfile
COPY docker-entrypoint.sh /usr/local/bin/
RUN chmod +x /usr/local/bin/docker-entrypoint.sh
ENTRYPOINT ["docker-entrypoint.sh"]
```

```bash
#!/bin/sh
# docker-entrypoint.sh
bundle exec rails db:migrate
exec "$@"
```

### 3. Secrets Management

**Problem:** Don't bake secrets into images.

**Solution:** Use environment variables or mounted secrets:

```dockerfile
# Don't do this:
# ENV DATABASE_PASSWORD=secret123

# Do this:
# Pass at runtime
docker run -e DATABASE_URL=postgres://... myapp:latest
```

Or use Docker secrets (Swarm/Kubernetes) or AWS Secrets Manager.

### 4. Gem Native Extensions

**Problem:** Gems like `pg`, `nokogiri` need system libraries.

**Solution:** Install dev packages in builder, runtime libraries in final stage:

```dockerfile
# Builder
RUN apk add --no-cache build-base postgresql-dev libxml2-dev

# Runtime
RUN apk add --no-cache postgresql-client libxml2
```

---

## Optimizing Image Size

### Alpine vs Debian

| Base Image | Size | Pros | Cons |
|------------|------|------|------|
| `ruby:3.2` (Debian) | ~900MB | Full compatibility | Large |
| `ruby:3.2-alpine` | ~150MB | Small, fast | Some gems need tweaks |

**Recommendation:** Start with Alpine; fall back to Debian if gems fail to compile.

### Layer Minimization

Combine `RUN` commands to reduce layers:

```dockerfile
# Bad: 3 layers
RUN apk add build-base
RUN apk add postgresql-dev
RUN apk add nodejs

# Good: 1 layer
RUN apk add --no-cache build-base postgresql-dev nodejs
```

### .dockerignore

Exclude unnecessary files from build context:

```
# .dockerignore
.git
log/*
tmp/*
node_modules
coverage
*.swp
.env
```

**Impact:** Reduces context size from 500MB to 50MB, speeds up `COPY . .`.

---

## Debugging Containers

### Inspecting a Running Container

```bash
docker ps                          # List running containers
docker exec -it <container_id> sh  # Open shell inside container
```

### Viewing Logs

```bash
docker logs <container_id>         # View stdout/stderr
docker logs -f <container_id>      # Follow logs
```

### Debugging Build Failures

```bash
docker build --no-cache -t myapp .  # Force rebuild all layers
docker build --target builder -t myapp-builder .  # Build only builder stage
docker run -it myapp-builder sh    # Inspect builder stage
```

### Common Errors

**Error:** `Gem::Ext::BuildError: ERROR: Failed to build gem native extension`

**Fix:** Install missing system libraries:

```dockerfile
RUN apk add --no-cache build-base postgresql-dev
```

**Error:** `ExecJS::RuntimeUnavailable: Could not find a JavaScript runtime`

**Fix:** Install Node.js:

```dockerfile
RUN apk add --no-cache nodejs
```

---

## Best Practices

- Use multi-stage builds to separate build and runtime dependencies
- Copy `Gemfile` before app code to leverage layer caching
- Precompile assets during build, not at runtime
- Use `.dockerignore` to exclude logs, tmp, node_modules
- Run as non-root user for security
- Pin base image versions (`ruby:3.2.2-alpine`, not `ruby:latest`)
- Set `RAILS_ENV=production` and `NODE_ENV=production`
- Use `bundle config set --local deployment 'true'` for production installs
- Avoid installing development/test gems in production
- Handle database migrations outside the image build

---

## Running as Non-Root User

**Problem:** Containers run as root by default (security risk).

**Solution:** Create a user:

```dockerfile
RUN addgroup -g 1000 rails && \
    adduser -D -u 1000 -G rails rails

USER rails

WORKDIR /app
```

---

## Key Terms

- **Image** - Read-only template with app and dependencies
- **Container** - Running instance of an image
- **Layer** - Each Dockerfile instruction creates a cached layer
- **Multi-stage build** - Use multiple FROM statements to optimize final image
- **Build context** - Files sent to Docker daemon (controlled by .dockerignore)
- **Layer caching** - Docker reuses unchanged layers to speed builds
- **Alpine** - Minimal Linux distribution (~5MB base)
- **Entrypoint** - Script that runs before CMD, useful for migrations

---

## Summary

Docker packages Rails apps into portable containers that run identically everywhere. Multi-stage builds separate build tools from production runtime, reducing image size by 60%+. Layer caching is critical: copy Gemfile before app code, order instructions least-to-most frequently changed. Precompile assets during build, run migrations outside the image. Use Alpine for small images, .dockerignore to exclude junk, non-root users for security.

**Next steps:** Complete the exercise to build a production-ready Dockerfile with multi-stage builds.
