# Exercise: Docker & Containerization Basics

## Objective
Build a production-ready Rails Dockerfile with multi-stage builds, layer caching optimization, and security best practices.

## Task
Create an optimized Docker container for a Rails application:

1. Create a multi-stage Dockerfile using Alpine Linux base image
2. Implement layer caching strategies to minimize rebuild times
3. Configure asset precompilation in the build stage
4. Set up a non-root user for security
5. Build and run the container, measuring image sizes and build times

## Acceptance Criteria
- [ ] Multi-stage Dockerfile with separate `builder` and `runner` stages
- [ ] Alpine-based images reducing final size to under 200MB
- [ ] Non-root user `rails` runs the application (not root)
- [ ] Assets precompiled in build stage, not at runtime
- [ ] Layer caching optimized: dependencies installed before copying source code
- [ ] `.dockerignore` excludes unnecessary files (log/, tmp/, .git/)
- [ ] Container runs and serves HTTP traffic on port 3000
- [ ] Build time under 5 minutes on clean build, under 30 seconds on cached builds

## Verification Steps

1. Build the image and check size:

```bash
docker build -t rails-demo:optimized .

# Check image size (should be < 200MB)
docker images rails-demo:optimized

```

2. Verify non-root user:

```bash
docker run --rm rails-demo:optimized id
# Should output: uid=1000(rails) gid=1000(rails) groups=1000(rails)

```

3. Run container and test HTTP access:

```bash
docker run -p 3000:3000 --rm rails-demo:optimized

# In another terminal
curl http://localhost:3000
# Should return Rails welcome page or app homepage

```

4. Test layer caching - change app code and rebuild:

```bash
# Edit app/controllers/application_controller.rb
# Add a comment, then rebuild

docker build -t rails-demo:optimized .
# Should skip dependency layers and complete in ~30 seconds

```

## Setup Code

### Step 1: Create Rails Application

```bash
# Create new Rails app with minimal setup
rails new docker_demo --skip-test --skip-javascript --database=postgresql
cd docker_demo

# Generate a simple controller to test
bin/rails generate controller Pages home

```

Edit `config/routes.rb`:

```ruby
Rails.application.routes.draw do
  root 'pages#home'
end

```

Edit `app/views/pages/home.html.erb`:

```erb
<h1>Docker Containerization Demo</h1>
<p>This Rails app is running in a Docker container!</p>
<p>Time: <%= Time.current %></p>

```

### Step 2: Create .dockerignore

Create `.dockerignore` at project root:

```
# Ignore bundler config
.bundle

# Ignore all logfiles and tempfiles
log/*
tmp/*

# Ignore uploaded files in development
storage/*

# Ignore master key for decrypting credentials
config/master.key

# Ignore assets that will be compiled
public/assets/*
public/packs/*

# Ignore git and CI files
.git
.gitignore
.github
.dockerignore

# Ignore local development files
.env
.env.local

# Ignore node_modules
node_modules

# Ignore test files
spec
test

# Ignore documentation
README.md
doc

```

### Step 3: Create Multi-Stage Dockerfile

Create `Dockerfile` at project root:

```dockerfile
# syntax=docker/dockerfile:1

# ==================================
# Stage 1: Builder
# ==================================
FROM ruby:3.2.2-alpine AS builder

# Install build dependencies
RUN apk add --no-cache \
  build-base \
  postgresql-dev \
  git \
  nodejs \
  yarn \
  tzdata

# Set working directory
WORKDIR /app

# Copy dependency files first (for layer caching)
COPY Gemfile Gemfile.lock ./

# Install gems to system (not vendor/bundle for smaller image)
RUN bundle config set --local deployment 'true' && \
    bundle config set --local without 'development test' && \
    bundle install --jobs 4 --retry 3 && \
    rm -rf /usr/local/bundle/cache/*.gem && \
    find /usr/local/bundle/gems/ -name "*.c" -delete && \
    find /usr/local/bundle/gems/ -name "*.o" -delete

# Copy application code
COPY . .

# Precompile assets (if using asset pipeline)
# This runs in the builder stage to keep runner slim
RUN SECRET_KEY_BASE=dummy bundle exec rails assets:precompile

# Remove development/test files
RUN rm -rf spec test tmp/cache

# ==================================
# Stage 2: Runner
# ==================================
FROM ruby:3.2.2-alpine AS runner

# Install runtime dependencies only
RUN apk add --no-cache \
  postgresql-client \
  tzdata \
  curl

# Create non-root user
RUN addgroup -g 1000 rails && \
    adduser -D -u 1000 -G rails rails

# Set working directory
WORKDIR /app

# Copy bundled gems from builder
COPY --from=builder /usr/local/bundle /usr/local/bundle

# Copy application from builder
COPY --from=builder --chown=rails:rails /app /app

# Switch to non-root user
USER rails

# Expose port
EXPOSE 3000

# Set production environment
ENV RAILS_ENV=production \
    RAILS_LOG_TO_STDOUT=true \
    RAILS_SERVE_STATIC_FILES=true

# Health check
HEALTHCHECK --interval=30s --timeout=3s --start-period=40s --retries=3 \
  CMD curl -f http://localhost:3000 || exit 1

# Start Rails server
CMD ["bundle", "exec", "rails", "server", "-b", "0.0.0.0"]

```

### Step 4: Create docker-compose.yml for Development

Create `docker-compose.yml`:

```yaml
version: '3.8'

services:
  db:
    image: postgres:15-alpine
    environment:
      POSTGRES_USER: postgres
      POSTGRES_PASSWORD: postgres
    volumes:
      - postgres_data:/var/lib/postgresql/data
    ports:
      - "5432:5432"

  web:
    build:
      context: .
      dockerfile: Dockerfile
    command: bundle exec rails server -b 0.0.0.0
    environment:
      DATABASE_URL: postgresql://postgres:postgres@db:5432/docker_demo_production
      RAILS_ENV: production
      SECRET_KEY_BASE: insecure_secret_for_demo_only_change_in_production
    ports:
      - "3000:3000"
    depends_on:
      - db
    volumes:
      - ./:/app

volumes:
  postgres_data:

```

### Step 5: Configure Database

Edit `config/database.yml` to support DATABASE_URL:

```yaml
production:
  <<: *default
  url: <%= ENV['DATABASE_URL'] %>

```

### Step 6: Build and Run

```bash
# Build the image
docker build -t rails-demo:optimized .

# Check image size
docker images rails-demo:optimized

# Run with docker-compose (includes database)
docker-compose up --build

# In another terminal, create database
docker-compose exec web bundle exec rails db:create db:migrate

```

Visit http://localhost:3000 - you should see your homepage.

### Step 7: Test Layer Caching

Make a small code change:

```bash
# Edit app/views/pages/home.html.erb
# Add: <p>Updated at: <%= Time.current.to_s(:long) %></p>

# Rebuild - notice cached layers
time docker build -t rails-demo:optimized .

```

Output should show:

```
 => CACHED [builder 2/8] RUN apk add --no-cache ...
 => CACHED [builder 4/8] COPY Gemfile Gemfile.lock ./
 => CACHED [builder 5/8] RUN bundle config ...
```

Build time should be under 1 minute.

### Step 8: Verify Security - Non-Root User

```bash
# Check what user runs the process
docker run --rm rails-demo:optimized whoami
# Output: rails

docker run --rm rails-demo:optimized id
# Output: uid=1000(rails) gid=1000(rails) groups=1000(rails)

# Try to write to protected directory (should fail)
docker run --rm rails-demo:optimized sh -c "touch /etc/test"
# Output: touch: /etc/test: Permission denied

```

### Step 9: Measure Optimization Impact

Create an unoptimized Dockerfile for comparison:

Create `Dockerfile.unoptimized`:

```dockerfile
FROM ruby:3.2.2

WORKDIR /app

# No layer optimization - copy everything first
COPY . .

# Install dependencies after copying code
RUN bundle install

# Run as root (insecure)
# No multi-stage build (larger image)

EXPOSE 3000

CMD ["bundle", "exec", "rails", "server", "-b", "0.0.0.0"]

```

Compare:

```bash
# Build unoptimized version
docker build -f Dockerfile.unoptimized -t rails-demo:unoptimized .

# Compare sizes
docker images | grep rails-demo

# Optimized: ~150MB
# Unoptimized: ~900MB

```

## Stretch (Optional)

1. **Add BuildKit caching with mount cache:**

Edit Dockerfile builder stage:

```dockerfile
# Install gems with mount cache
RUN --mount=type=cache,target=/usr/local/bundle/cache \
    bundle config set --local deployment 'true' && \
    bundle install --jobs 4 --retry 3

```

Build with BuildKit:

```bash
DOCKER_BUILDKIT=1 docker build -t rails-demo:buildkit .

```

2. **Implement .dockerignore optimization check:**

```bash
# See what files Docker sends to build context
docker build --no-cache -t rails-demo . 2>&1 | grep "Sending build context"

# Should be under 10MB if .dockerignore works

```

3. **Add multi-platform builds:**

```bash
# Build for AMD64 and ARM64
docker buildx create --use
docker buildx build --platform linux/amd64,linux/arm64 -t rails-demo:multi .

```

4. **Scan for vulnerabilities:**

```bash
# Install trivy
# On macOS: brew install aquasecurity/trivy/trivy
# On Linux: see https://github.com/aquasecurity/trivy

trivy image rails-demo:optimized

```

5. **Optimize for faster startup:**

Add bootsnap configuration in Dockerfile:

```dockerfile
# In runner stage, precompile bootsnap cache
RUN bundle exec bootsnap precompile --gemfile app/ lib/

```

6. **Implement Docker secrets for production:**

```bash
# Create a secret
echo "my-secret-key" | docker secret create rails_secret_key_base -

# Use in docker-compose.yml
services:
  web:
    secrets:
      - rails_secret_key_base
    environment:
      SECRET_KEY_BASE_FILE: /run/secrets/rails_secret_key_base

secrets:
  rails_secret_key_base:
    external: true

```

## Solution Notes

**Common Gotchas:**

1. **Assets not found:** If you see asset 404s, ensure `RAILS_SERVE_STATIC_FILES=true` is set and assets are precompiled in builder stage.

2. **Permission errors:** If the container can't write to `tmp/` or `log/`, ensure those directories have correct ownership:
   ```dockerfile
   RUN mkdir -p tmp/pids log && \
       chown -R rails:rails tmp log
   ```

3. **Database connection errors:** Use `DATABASE_URL` environment variable instead of hardcoded config. Wait for database to be ready:
   ```bash
   docker-compose exec web bundle exec rails db:create
   ```

4. **Slow builds:** Ensure Gemfile/Gemfile.lock are copied BEFORE application code. Check .dockerignore excludes large directories.

5. **Large image size:** Verify multi-stage build is working. Check `docker history rails-demo:optimized` to see layer sizes. Remove build dependencies from runner stage.

**Layer Caching Best Practices:**

- Copy dependency files (Gemfile) before source code
- Install dependencies before copying application
- Use `.dockerignore` to exclude unnecessary files
- Group RUN commands that change together with `&&`
- Put frequently changing steps (COPY app code) last

**Production Readiness Checklist:**

- [ ] Non-root user configured
- [ ] Multi-stage build reduces image size
- [ ] Secrets managed via environment or Docker secrets
- [ ] Health check endpoint configured
- [ ] Logs sent to STDOUT for container logging
- [ ] Static files served efficiently
- [ ] Alpine base image for minimal attack surface
- [ ] No development dependencies in final image

## Time Estimate
22 minutes
