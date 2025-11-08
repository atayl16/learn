# CI/CD Pipelines

## What It Is
CI/CD (Continuous Integration/Continuous Deployment) automates testing and deployment of Rails apps through pipelines that run on every commit. GitHub Actions is GitHub's built-in automation platform that executes workflows defined in `.github/workflows/*.yml` files. A typical Rails workflow runs RSpec tests, lints code with RuboCop, checks dependencies with Bundler Audit, and deploys to production on merge. Workflows consist of jobs that run in parallel or sequence, each containing steps that execute shell commands or reusable actions.

## Why It Matters
Manual testing and deployments are error-prone and slow. CI catches regressions within minutes—before code reaches production. Matrix testing runs tests across multiple Ruby versions (3.1, 3.2, 3.3) simultaneously, ensuring compatibility. Automated deployments eliminate "Friday fear" and enable multiple daily releases. Caching gems and bundler dependencies cuts build times from 5 minutes to 30 seconds. Poor CI configuration costs dev time: a 10-minute pipeline run 50 times daily wastes 8 hours of team time waiting for feedback.

## When to Use
- **Every commit:** Run tests, linting, security checks on pull requests
- **Main branch merges:** Deploy to staging automatically
- **Tagged releases:** Deploy to production with `git tag v1.2.3`
- **Scheduled jobs:** Run nightly dependency updates, database backups
- **Matrix testing:** Verify compatibility across Ruby 3.1, 3.2, 3.3 and Rails 7.0, 7.1
- **Pre-deployment checks:** Validate migrations, asset compilation, secrets

## Three Common Pitfalls
1. **Uncached dependencies waste time:** Running `bundle install` without caching installs 200+ gems on every run, taking 3-5 minutes. Fix: Use `actions/cache` to persist `vendor/bundle` between runs, reducing install time to 10 seconds.
2. **Running tests serially instead of parallel:** RSpec with 1000 tests takes 8 minutes serially but 2 minutes across 4 parallel jobs. Fix: Use `ci-queue` or RSpec's `--split` to distribute tests across matrix runners.
3. **Secrets in workflow files or logs:** Hardcoding `DATABASE_URL` in workflows leaks credentials. Fix: Use GitHub Secrets and never echo secret values in steps.

---

## GitHub Actions Workflow Basics

### Workflow File Structure

Workflows live in `.github/workflows/` and trigger on events (push, pull_request, schedule):

```yaml
# .github/workflows/ci.yml
name: CI

on:
  push:
    branches: [main]
  pull_request:
    branches: [main]

jobs:
  test:
    runs-on: ubuntu-latest

    steps:
      - uses: actions/checkout@v4
      - name: Set up Ruby
        uses: ruby/setup-ruby@v1
        with:
          ruby-version: 3.2
          bundler-cache: true

      - name: Run tests
        run: bundle exec rspec

```

**Key concepts:**
- `on:` defines triggers (push, pull_request, schedule)
- `jobs:` defines what to run (test, lint, deploy)
- `runs-on:` selects runner OS (ubuntu-latest, macos-latest)
- `steps:` sequence of actions or shell commands

---

## Rails CI Pipeline Example

### Complete Workflow with Tests, Linting, and Security

```yaml
# .github/workflows/ci.yml
name: Rails CI

on:
  push:
    branches: [main, develop]
  pull_request:
    branches: [main]

jobs:
  lint:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - name: Set up Ruby
        uses: ruby/setup-ruby@v1
        with:
          ruby-version: 3.2
          bundler-cache: true

      - name: Run RuboCop
        run: bundle exec rubocop --parallel

      - name: Security audit
        run: |
          bundle exec bundler-audit --update
          bundle exec brakeman -q -w2

  test:
    runs-on: ubuntu-latest

    services:
      postgres:
        image: postgres:15
        env:
          POSTGRES_USER: postgres
          POSTGRES_PASSWORD: postgres
          POSTGRES_DB: test_db
        ports:
          - 5432:5432
        options: >-
          --health-cmd pg_isready
          --health-interval 10s
          --health-timeout 5s
          --health-retries 5

      redis:
        image: redis:7-alpine
        ports:
          - 6379:6379

    env:
      RAILS_ENV: test
      DATABASE_URL: postgres://postgres:postgres@localhost:5432/test_db
      REDIS_URL: redis://localhost:6379/0

    steps:
      - uses: actions/checkout@v4

      - name: Set up Ruby
        uses: ruby/setup-ruby@v1
        with:
          ruby-version: 3.2
          bundler-cache: true

      - name: Install dependencies
        run: |
          sudo apt-get update
          sudo apt-get install -y postgresql-client libpq-dev

      - name: Setup database
        run: |
          bundle exec rails db:schema:load
          bundle exec rails db:seed

      - name: Precompile assets
        run: bundle exec rails assets:precompile

      - name: Run tests
        run: bundle exec rspec --format progress --format RspecJunitFormatter --out tmp/rspec-results.xml

      - name: Upload test results
        if: always()
        uses: actions/upload-artifact@v4
        with:
          name: rspec-results
          path: tmp/rspec-results.xml

```

**Key features:**
- **Services:** Postgres and Redis run as Docker containers
- **Health checks:** Wait for Postgres to be ready before running tests
- **Database setup:** Load schema instead of running migrations (faster)
- **Test artifacts:** Upload results for debugging failed runs

---

## Matrix Testing Across Ruby Versions

Run tests against multiple Ruby and Rails versions in parallel:

```yaml
jobs:
  test:
    runs-on: ubuntu-latest

    strategy:
      fail-fast: false
      matrix:
        ruby: ['3.1', '3.2', '3.3']
        rails: ['7.0', '7.1']
        exclude:
          - ruby: '3.1'
            rails: '7.1'

    env:
      BUNDLE_GEMFILE: gemfiles/rails_${{ matrix.rails }}.gemfile

    steps:
      - uses: actions/checkout@v4

      - name: Set up Ruby ${{ matrix.ruby }}
        uses: ruby/setup-ruby@v1
        with:
          ruby-version: ${{ matrix.ruby }}
          bundler-cache: true

      - name: Run tests (Ruby ${{ matrix.ruby }}, Rails ${{ matrix.rails }})
        run: bundle exec rspec

```

**Result:** 5 parallel jobs testing Ruby 3.1/3.2/3.3 against Rails 7.0/7.1 (excluding incompatible Ruby 3.1 + Rails 7.1).

---

## Caching Dependencies

### Bundle Caching with setup-ruby

The `ruby/setup-ruby` action includes built-in caching:

```yaml
- name: Set up Ruby
  uses: ruby/setup-ruby@v1
  with:
    ruby-version: 3.2
    bundler-cache: true  # Caches vendor/bundle automatically

```

**Cache key:** Based on `Gemfile.lock`, OS, and Ruby version. Cache invalidates when dependencies change.

### Manual Caching for Custom Setups

```yaml
- name: Cache gems
  uses: actions/cache@v4
  with:
    path: vendor/bundle
    key: ${{ runner.os }}-gems-${{ hashFiles('**/Gemfile.lock') }}
    restore-keys: |
      ${{ runner.os }}-gems-

- name: Install dependencies
  run: |
    bundle config path vendor/bundle
    bundle install --jobs 4 --retry 3

```

**Performance impact:** First run 4m 20s → subsequent runs 12s.

---

## Secrets Management

### GitHub Secrets

Store sensitive values in Settings → Secrets and variables → Actions:

```yaml
jobs:
  deploy:
    runs-on: ubuntu-latest
    steps:
      - name: Deploy to production
        env:
          DEPLOY_KEY: ${{ secrets.SSH_PRIVATE_KEY }}
          DATABASE_URL: ${{ secrets.PRODUCTION_DATABASE_URL }}
          SECRET_KEY_BASE: ${{ secrets.RAILS_SECRET_KEY_BASE }}
        run: |
          bundle exec cap production deploy

```

**Best practices:**
- Never log secret values: `echo ${{ secrets.API_KEY }}` redacts output
- Use environment-specific secrets: `STAGING_DATABASE_URL`, `PRODUCTION_DATABASE_URL`
- Rotate secrets regularly and use least-privilege access

### Encrypted Credentials

Rails encrypted credentials work in CI with the master key:

```yaml
- name: Decrypt credentials
  env:
    RAILS_MASTER_KEY: ${{ secrets.RAILS_MASTER_KEY }}
  run: bundle exec rails credentials:show

```

Store `config/master.key` content as a GitHub secret.

---

## Deployment Workflows

### Continuous Deployment on Main Merge

```yaml
name: Deploy

on:
  push:
    branches: [main]

jobs:
  deploy:
    runs-on: ubuntu-latest
    if: github.ref == 'refs/heads/main'

    steps:
      - uses: actions/checkout@v4

      - name: Deploy to Heroku
        env:
          HEROKU_API_KEY: ${{ secrets.HEROKU_API_KEY }}
        run: |
          git remote add heroku https://heroku:$HEROKU_API_KEY@git.heroku.com/myapp.git
          git push heroku main

```

### Tag-Based Production Releases

```yaml
on:
  push:
    tags:
      - 'v*'

jobs:
  deploy:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - name: Deploy to production
        run: |
          bundle exec cap production deploy

```

Trigger with: `git tag v1.2.3 && git push --tags`

---

## Parallel Test Execution

### RSpec Parallel with CI Node Index

```yaml
strategy:
  matrix:
    ci_node_total: [4]
    ci_node_index: [0, 1, 2, 3]

steps:
  - name: Run tests
    run: |
      bundle exec rspec --tag ~slow \
        --only-failures \
        $(bundle exec rspec --dry-run spec | \
          awk "NR % ${{ matrix.ci_node_total }} == ${{ matrix.ci_node_index }}")

```

**Result:** 8-minute test suite runs in 2 minutes across 4 parallel jobs.

---

## Best Practices

- Use `bundler-cache: true` for automatic gem caching
- Run fast jobs (lint) before slow jobs (tests) to fail fast
- Use matrix testing to verify Ruby/Rails version compatibility
- Store all secrets in GitHub Secrets, never in code
- Enable branch protection: require CI to pass before merge
- Set reasonable timeouts: `timeout-minutes: 15` prevents runaway jobs
- Use `services:` for Postgres/Redis instead of installing manually
- Cache `node_modules` for JavaScript asset compilation
- Run security audits (Bundler Audit, Brakeman) on every PR
- Deploy staging automatically on main merge, production on tags

---

## Debugging Failed Workflows

**View logs:** Click failed job → expand step to see output

**Re-run with debug logging:**

```yaml
- name: Debug workflow
  run: echo "::debug::Database URL is $DATABASE_URL"

```

Enable debug logging: Settings → Secrets → Add `ACTIONS_STEP_DEBUG=true`

**SSH into runner (for debugging):**

```yaml
- name: Setup tmate session
  uses: mxschmitt/action-tmate@v3
  if: failure()

```

**Check service health:**

```yaml
- name: Test Postgres connection
  run: pg_isready -h localhost -p 5432

```

---

## Key Terms

- **Workflow** - YAML file defining automation (`.github/workflows/ci.yml`)
- **Job** - Set of steps running on the same runner
- **Step** - Individual task (checkout code, run tests)
- **Action** - Reusable step (e.g., `actions/checkout@v4`)
- **Runner** - VM executing jobs (ubuntu-latest, macos-latest)
- **Matrix** - Run job multiple times with different configurations
- **Service** - Docker container (Postgres, Redis) for job
- **Secret** - Encrypted environment variable for sensitive data
- **Artifact** - File uploaded from workflow (test reports, logs)

---

## Summary

CI/CD automates testing and deployment through GitHub Actions workflows triggered on every commit. Workflows define jobs (test, lint, deploy) that run in parallel, with steps executing shell commands or reusable actions. Caching gems with `bundler-cache: true` reduces install time from minutes to seconds. Matrix testing verifies compatibility across Ruby/Rails versions. Store secrets in GitHub Secrets, never in code. Continuous deployment merges to main deploy staging automatically; production deploys on tagged releases. Parallel test execution splits specs across runners, cutting feedback time by 75%.

**Next steps:** Complete the exercise to build a production-ready GitHub Actions workflow for a Rails app.
