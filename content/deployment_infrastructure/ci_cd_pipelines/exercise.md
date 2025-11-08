# Exercise: CI/CD Pipelines

## Objective
Build a production-ready GitHub Actions CI/CD pipeline for a Rails application with automated testing, linting, security scanning, and deployment workflows.

## Task
Set up comprehensive CI/CD automation for a Rails app:

1. Create GitHub Actions workflows for testing and linting
2. Configure service containers for Postgres and Redis
3. Implement dependency caching to speed up builds
4. Add security scanning with Bundler Audit and Brakeman
5. Set up deployment automation for staging and production
6. Configure secrets management for sensitive credentials

## Acceptance Criteria
- [ ] Workflow runs tests automatically on every pull request
- [ ] RuboCop linting runs in parallel with tests
- [ ] Bundler caching reduces dependency installation time by 90%+
- [ ] Postgres and Redis services configured and healthy before tests
- [ ] Security audits (Bundler Audit, Brakeman) run on every PR
- [ ] Staging deploys automatically on main branch merge
- [ ] Production deploys on git tag push (v*.*.*)
- [ ] Secrets stored in GitHub Secrets, not in workflow files
- [ ] Workflow completes in under 5 minutes for typical changes

## Verification Steps

1. Push code and verify workflow runs:

```bash
git add .
git commit -m "Add CI/CD pipeline"
git push origin feature-branch

# Navigate to GitHub Actions tab to see workflow running

```

2. Check caching effectiveness:

```bash
# First run should install all gems (3-5 minutes)
# Second run should use cache (10-30 seconds)

# View cache hits in workflow logs:
# "Cache restored from key: Linux-gems-abc123..."

```

3. Verify tests run with services:

```bash
# Workflow logs should show:
# ✓ Postgres health check passed
# ✓ Database schema loaded
# ✓ RSpec tests passed

```

4. Test deployment workflow:

```bash
# Create and push a tag to trigger production deployment
git tag v1.0.0
git push --tags

# Check Actions tab for deploy job

```

## Setup Code

### Step 1: Create Rails Application

```bash
# Create new Rails app with RSpec
rails new cicd_demo --database=postgresql --skip-test
cd cicd_demo

# Add testing and linting gems
cat >> Gemfile << 'EOF'

group :development, :test do
  gem 'rspec-rails', '~> 6.0'
  gem 'factory_bot_rails'
  gem 'faker'
  gem 'rubocop', require: false
  gem 'rubocop-rails', require: false
  gem 'rubocop-rspec', require: false
  gem 'brakeman', require: false
  gem 'bundler-audit', require: false
end

group :test do
  gem 'shoulda-matchers', '~> 5.0'
  gem 'database_cleaner-active_record'
  gem 'rspec_junit_formatter'
end
EOF

bundle install

# Initialize RSpec
rails generate rspec:install

```

### Step 2: Create Sample Model and Tests

```bash
# Generate a simple model to test
rails generate model Article title:string body:text published:boolean
rails db:migrate

```

Edit `spec/models/article_spec.rb`:

```ruby
require 'rails_helper'

RSpec.describe Article, type: :model do
  describe 'validations' do
    it { should validate_presence_of(:title) }
  end

  describe '#published?' do
    it 'returns true when published is true' do
      article = Article.create!(title: 'Test', body: 'Body', published: true)
      expect(article.published?).to be true
    end

    it 'returns false when published is false' do
      article = Article.create!(title: 'Test', body: 'Body', published: false)
      expect(article.published?).to be false
    end
  end
end

```

Edit `app/models/article.rb`:

```ruby
class Article < ApplicationRecord
  validates :title, presence: true
end

```

Configure Shoulda Matchers in `spec/rails_helper.rb`:

```ruby
# At the end of the file, add:
Shoulda::Matchers.configure do |config|
  config.integrate do |with|
    with.test_framework :rspec
    with.library :rails
  end
end

```

### Step 3: Configure RuboCop

Create `.rubocop.yml`:

```yaml
require:
  - rubocop-rails
  - rubocop-rspec

AllCops:
  NewCops: enable
  TargetRubyVersion: 3.2
  Exclude:
    - 'bin/**/*'
    - 'db/schema.rb'
    - 'node_modules/**/*'
    - 'vendor/**/*'

Style/Documentation:
  Enabled: false

Metrics/BlockLength:
  Exclude:
    - 'spec/**/*'
    - 'config/environments/*'

RSpec/ExampleLength:
  Max: 15

RSpec/MultipleExpectations:
  Max: 5

```

### Step 4: Create GitHub Actions CI Workflow

Create `.github/workflows/ci.yml`:

```yaml
name: CI

on:
  push:
    branches: [main, develop]
  pull_request:
    branches: [main]

jobs:
  lint:
    name: Lint (RuboCop)
    runs-on: ubuntu-latest

    steps:
      - name: Checkout code
        uses: actions/checkout@v4

      - name: Set up Ruby
        uses: ruby/setup-ruby@v1
        with:
          ruby-version: '3.2'
          bundler-cache: true

      - name: Run RuboCop
        run: bundle exec rubocop --parallel --format progress

  security:
    name: Security Audit
    runs-on: ubuntu-latest

    steps:
      - name: Checkout code
        uses: actions/checkout@v4

      - name: Set up Ruby
        uses: ruby/setup-ruby@v1
        with:
          ruby-version: '3.2'
          bundler-cache: true

      - name: Run Bundler Audit
        run: |
          bundle exec bundler-audit --update
          bundle exec bundler-audit check

      - name: Run Brakeman
        run: bundle exec brakeman --quiet --no-pager

  test:
    name: Test (RSpec)
    runs-on: ubuntu-latest

    services:
      postgres:
        image: postgres:15-alpine
        env:
          POSTGRES_USER: postgres
          POSTGRES_PASSWORD: postgres
          POSTGRES_DB: cicd_demo_test
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
        options: >-
          --health-cmd "redis-cli ping"
          --health-interval 10s
          --health-timeout 5s
          --health-retries 5

    env:
      RAILS_ENV: test
      DATABASE_URL: postgres://postgres:postgres@localhost:5432/cicd_demo_test
      REDIS_URL: redis://localhost:6379/0

    steps:
      - name: Checkout code
        uses: actions/checkout@v4

      - name: Set up Ruby
        uses: ruby/setup-ruby@v1
        with:
          ruby-version: '3.2'
          bundler-cache: true

      - name: Install system dependencies
        run: |
          sudo apt-get update
          sudo apt-get install -y postgresql-client libpq-dev

      - name: Setup database
        run: |
          bundle exec rails db:schema:load
          bundle exec rails db:migrate

      - name: Run RSpec tests
        run: |
          bundle exec rspec \
            --format progress \
            --format RspecJunitFormatter \
            --out tmp/rspec-results.xml

      - name: Upload test results
        if: always()
        uses: actions/upload-artifact@v4
        with:
          name: rspec-results
          path: tmp/rspec-results.xml
          retention-days: 7

      - name: Upload coverage
        if: always()
        uses: actions/upload-artifact@v4
        with:
          name: coverage
          path: coverage/
          retention-days: 7

```

### Step 5: Create Deployment Workflow

Create `.github/workflows/deploy.yml`:

```yaml
name: Deploy

on:
  push:
    branches:
      - main
    tags:
      - 'v*'

jobs:
  deploy-staging:
    name: Deploy to Staging
    runs-on: ubuntu-latest
    if: github.ref == 'refs/heads/main' && !startsWith(github.ref, 'refs/tags/')

    steps:
      - name: Checkout code
        uses: actions/checkout@v4

      - name: Deploy to staging
        env:
          STAGING_DEPLOY_KEY: ${{ secrets.STAGING_DEPLOY_KEY }}
        run: |
          echo "Deploying to staging environment..."
          # Example: Deploy to Heroku staging
          # git remote add staging https://heroku:$STAGING_DEPLOY_KEY@git.heroku.com/myapp-staging.git
          # git push staging main

  deploy-production:
    name: Deploy to Production
    runs-on: ubuntu-latest
    if: startsWith(github.ref, 'refs/tags/v')
    environment:
      name: production
      url: https://myapp.com

    steps:
      - name: Checkout code
        uses: actions/checkout@v4

      - name: Set up Ruby
        uses: ruby/setup-ruby@v1
        with:
          ruby-version: '3.2'
          bundler-cache: true

      - name: Deploy to production
        env:
          PRODUCTION_DEPLOY_KEY: ${{ secrets.PRODUCTION_DEPLOY_KEY }}
          RAILS_MASTER_KEY: ${{ secrets.RAILS_MASTER_KEY }}
        run: |
          echo "Deploying version ${{ github.ref_name }} to production..."
          # Example: Deploy with Capistrano
          # bundle exec cap production deploy

      - name: Create GitHub Release
        uses: actions/create-release@v1
        env:
          GITHUB_TOKEN: ${{ secrets.GITHUB_TOKEN }}
        with:
          tag_name: ${{ github.ref_name }}
          release_name: Release ${{ github.ref_name }}
          body: |
            Production deployment of ${{ github.ref_name }}
            Deployed at: ${{ github.event.head_commit.timestamp }}
          draft: false
          prerelease: false

```

### Step 6: Add Caching Optimization

Create `.github/workflows/ci-optimized.yml` for comparison:

```yaml
name: CI (Optimized with Manual Caching)

on:
  workflow_dispatch:  # Manual trigger for testing

jobs:
  test-with-cache:
    runs-on: ubuntu-latest

    services:
      postgres:
        image: postgres:15-alpine
        env:
          POSTGRES_USER: postgres
          POSTGRES_PASSWORD: postgres
          POSTGRES_DB: test
        ports:
          - 5432:5432
        options: >-
          --health-cmd pg_isready
          --health-interval 10s
          --health-timeout 5s
          --health-retries 5

    steps:
      - uses: actions/checkout@v4

      - name: Set up Ruby
        uses: ruby/setup-ruby@v1
        with:
          ruby-version: '3.2'

      - name: Cache gems
        uses: actions/cache@v4
        with:
          path: vendor/bundle
          key: ${{ runner.os }}-gems-${{ hashFiles('**/Gemfile.lock') }}
          restore-keys: |
            ${{ runner.os }}-gems-

      - name: Cache node modules
        uses: actions/cache@v4
        with:
          path: node_modules
          key: ${{ runner.os }}-node-${{ hashFiles('**/yarn.lock') }}
          restore-keys: |
            ${{ runner.os }}-node-

      - name: Install dependencies
        run: |
          bundle config path vendor/bundle
          bundle install --jobs 4 --retry 3

      - name: Setup database
        env:
          DATABASE_URL: postgres://postgres:postgres@localhost:5432/test
          RAILS_ENV: test
        run: bundle exec rails db:schema:load

      - name: Run tests
        env:
          DATABASE_URL: postgres://postgres:postgres@localhost:5432/test
          RAILS_ENV: test
        run: bundle exec rspec

```

### Step 7: Configure GitHub Secrets

In your GitHub repository, go to Settings → Secrets and variables → Actions, and add:

```
STAGING_DEPLOY_KEY=<your-staging-deploy-key>
PRODUCTION_DEPLOY_KEY=<your-production-deploy-key>
RAILS_MASTER_KEY=<contents-of-config/master.key>
```

**For testing locally without real deployment:**
You can add placeholder values:

```bash
# These won't actually deploy but will test the workflow structure
STAGING_DEPLOY_KEY=placeholder_staging_key
PRODUCTION_DEPLOY_KEY=placeholder_production_key
RAILS_MASTER_KEY=placeholder_master_key

```

### Step 8: Test the Workflow

```bash
# Initialize git repository
git init
git add .
git commit -m "Initial commit with CI/CD pipeline"

# Create GitHub repo and push
gh repo create cicd-demo --public --source=. --remote=origin --push

# Create a feature branch and PR
git checkout -b add-feature
echo "# New feature" >> README.md
git add README.md
git commit -m "Add feature documentation"
git push origin add-feature

# Create pull request
gh pr create --title "Add feature" --body "Testing CI pipeline"

```

Navigate to GitHub Actions tab to watch the workflow run.

### Step 9: Verify Caching Performance

```bash
# First workflow run (no cache):
# Expected time: 3-5 minutes

# Make a small change and push again
git commit --allow-empty -m "Trigger CI again"
git push origin add-feature

# Second run (with cache):
# Expected time: 1-2 minutes (60-70% faster)

```

Check workflow logs for cache hit messages:
```
Cache restored from key: Linux-gems-abc123def456...
```

### Step 10: Test Deployment Workflow

```bash
# Merge PR to main (triggers staging deployment)
gh pr merge --squash

# Wait for staging deployment to complete

# Create production release tag
git checkout main
git pull origin main
git tag v1.0.0
git push origin v1.0.0

# Check Actions tab for production deployment

```

## Stretch (Optional)

1. **Add matrix testing for multiple Ruby versions:**

```yaml
jobs:
  test:
    strategy:
      fail-fast: false
      matrix:
        ruby: ['3.1', '3.2', '3.3']
    steps:
      - name: Set up Ruby ${{ matrix.ruby }}
        uses: ruby/setup-ruby@v1
        with:
          ruby-version: ${{ matrix.ruby }}

```

2. **Implement parallel test execution:**

```yaml
strategy:
  matrix:
    ci_node_total: [4]
    ci_node_index: [0, 1, 2, 3]

steps:
  - name: Run parallel tests
    run: |
      bundle exec rspec $(bundle exec rspec --dry-run spec | \
        grep _spec.rb | \
        awk "NR % ${{ matrix.ci_node_total }} == ${{ matrix.ci_node_index }}")

```

3. **Add code coverage reporting:**

```bash
# Add to Gemfile
gem 'simplecov', require: false

```

Edit `spec/spec_helper.rb`:

```ruby
require 'simplecov'
SimpleCov.start 'rails'

```

Update workflow to upload coverage:

```yaml
- name: Upload coverage to Codecov
  uses: codecov/codecov-action@v3
  with:
    files: ./coverage/.resultset.json

```

4. **Add scheduled dependency updates:**

Create `.github/workflows/scheduled.yml`:

```yaml
name: Scheduled Tasks

on:
  schedule:
    - cron: '0 2 * * 1'  # Every Monday at 2am UTC

jobs:
  dependency-check:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - name: Set up Ruby
        uses: ruby/setup-ruby@v1
        with:
          ruby-version: '3.2'

      - name: Check for outdated gems
        run: |
          bundle outdated --strict
          bundle exec bundler-audit check --update

```

5. **Add workflow status badge to README:**

```markdown
# CI/CD Demo

![CI](https://github.com/yourusername/cicd-demo/workflows/CI/badge.svg)

```

6. **Implement manual approval for production deployments:**

```yaml
deploy-production:
  environment:
    name: production
    # Requires manual approval in GitHub UI

```

## Solution Notes

**Common Gotchas:**

1. **Services not ready:** If tests fail with "connection refused", add health checks and increase health check intervals.

2. **Cache not working:** Ensure `Gemfile.lock` is committed. Cache key uses its hash to determine when to invalidate.

3. **Secrets not available:** GitHub Secrets are only available in workflows triggered by repository events, not forked PRs (security feature).

4. **Database connection errors:** Ensure `DATABASE_URL` matches the service configuration exactly, including port 5432.

5. **Asset precompilation fails:** Set `SECRET_KEY_BASE=dummy` in env or skip asset compilation in test environment.

**Performance Optimization Tips:**

- Use `bundler-cache: true` instead of manual caching for simplicity
- Run lint jobs before test jobs (faster feedback on style issues)
- Use `fail-fast: false` in matrix to see all failures, not just first
- Set `timeout-minutes: 15` to prevent runaway jobs
- Use `if: always()` for artifact uploads to capture results even on failure

**Security Best Practices:**

- Never commit secrets to workflow files or code
- Use environment protection rules for production deployments
- Rotate secrets regularly
- Use least-privilege access for deploy keys
- Enable branch protection to require CI before merge
- Use Dependabot to automate dependency updates

**Debugging Failed Workflows:**

1. Check "Set up job" step for service startup issues
2. Review database setup logs for migration errors
3. Use `run: env | sort` to inspect environment variables
4. Add debug statements: `run: echo "::debug::Variable value is $VAR"`
5. Enable step debugging: Settings → Secrets → Add `ACTIONS_STEP_DEBUG=true`

## Time Estimate
24 minutes
