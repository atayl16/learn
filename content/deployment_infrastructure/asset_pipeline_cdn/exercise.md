# Exercise: Asset Pipeline & CDN

## Objective

Configure Propshaft asset pipeline, precompile assets with fingerprinting, upload to S3, and serve via CloudFront CDN with proper cache headers.

## Task

Build a complete asset delivery pipeline for a Rails 7 application:

1. Configure Propshaft with asset fingerprinting
2. Set up CSS/JS preprocessing with esbuild and Tailwind
3. Precompile assets and verify fingerprints
4. Create S3 bucket and upload assets
5. Configure CloudFront distribution as CDN
6. Update Rails to serve assets from CloudFront
7. Verify cache headers and CDN performance

## Acceptance Criteria

- [ ] Propshaft configured with asset fingerprinting enabled
- [ ] CSS built with Tailwind, JS bundled with esbuild
- [ ] `rails assets:precompile` generates fingerprinted files in `public/assets/`
- [ ] `.manifest.json` maps logical to fingerprinted paths
- [ ] S3 bucket created with public-read permissions
- [ ] All assets uploaded to S3 with correct `Cache-Control` headers
- [ ] CloudFront distribution serves assets from S3 origin
- [ ] `config.asset_host` points to CloudFront URL
- [ ] Asset URLs include CloudFront domain and fingerprints
- [ ] Browser receives `Cache-Control: public, max-age=31536000, immutable`

## Setup Code

### Step 1: Create Rails App with Propshaft

```bash
# Create new Rails 7 app (Propshaft is default)
rails new asset_cdn_demo --css=tailwind --javascript=esbuild
cd asset_cdn_demo

# Verify Gemfile includes propshaft
grep propshaft Gemfile
# Should see: gem "propshaft"
```

If using an existing app, add Propshaft:

```ruby
# Gemfile
gem "propshaft"

# Remove sprockets-rails if present
# gem "sprockets-rails"
```

```bash
bundle install
```

### Step 2: Configure Asset Paths

Edit `config/application.rb`:

```ruby
module AssetCdnDemo
  class Application < Rails::Application
    config.load_defaults 7.1

    # Add esbuild output directory to asset paths
    config.assets.paths << Rails.root.join("app/assets/builds")

    # Ensure fingerprinting is enabled (default in production)
    config.assets.digest = true
  end
end
```

### Step 3: Create Sample Assets

Generate a controller with views:

```bash
rails generate controller Pages home about
```

Edit `config/routes.rb`:

```ruby
Rails.application.routes.draw do
  root "pages#home"
  get "about", to: "pages#about"
end
```

Add CSS to `app/assets/stylesheets/application.tailwind.css`:

```css
/* Existing Tailwind imports */
@tailwind base;
@tailwind components;
@tailwind utilities;

/* Custom styles */
@layer components {
  .hero-section {
    @apply bg-gradient-to-r from-blue-500 to-purple-600 text-white py-20 px-6;
  }

  .card {
    @apply bg-white rounded-lg shadow-lg p-6 hover:shadow-xl transition-shadow;
  }
}
```

Add JavaScript to `app/javascript/application.js`:

```javascript
// Entry point for the build script in package.json
console.log("Asset CDN Demo - JavaScript loaded!")

// Simple interactive feature
document.addEventListener('turbo:load', () => {
  const cards = document.querySelectorAll('.card')

  cards.forEach(card => {
    card.addEventListener('click', () => {
      card.classList.toggle('border-4')
      card.classList.toggle('border-blue-500')
    })
  })
})
```

Edit `app/views/pages/home.html.erb`:

```erb
<div class="hero-section">
  <div class="max-w-4xl mx-auto text-center">
    <h1 class="text-5xl font-bold mb-4">Asset Pipeline & CDN Demo</h1>
    <p class="text-xl mb-8">Serving assets from CloudFront CDN</p>
  </div>
</div>

<div class="container mx-auto px-6 py-12">
  <div class="grid grid-cols-1 md:grid-cols-3 gap-6">
    <div class="card">
      <h2 class="text-2xl font-bold mb-2">Propshaft</h2>
      <p>Modern asset pipeline for Rails 7+</p>
    </div>

    <div class="card">
      <h2 class="text-2xl font-bold mb-2">CloudFront CDN</h2>
      <p>Global edge caching for low latency</p>
    </div>

    <div class="card">
      <h2 class="text-2xl font-bold mb-2">S3 Storage</h2>
      <p>Scalable static asset hosting</p>
    </div>
  </div>
</div>
```

Edit `app/views/layouts/application.html.erb` to verify asset helpers:

```erb
<!DOCTYPE html>
<html>
  <head>
    <title>AssetCdnDemo</title>
    <meta name="viewport" content="width=device-width,initial-scale=1">
    <%= csrf_meta_tags %>
    <%= csp_meta_tag %>

    <%= stylesheet_link_tag "application", "data-turbo-track": "reload" %>
    <%= javascript_include_tag "application", "data-turbo-track": "reload", defer: true %>
  </head>

  <body>
    <%= yield %>
  </body>
</html>
```

### Step 4: Test Development Assets

```bash
# Start CSS and JS build watchers (in separate terminals)
./bin/dev

# Or manually:
# Terminal 1
rails server

# Terminal 2
yarn build:css --watch

# Terminal 3
yarn build --watch
```

Visit http://localhost:3000 - verify styles and JavaScript work.

### Step 5: Precompile Assets

```bash
# Clean any previous assets
rm -rf public/assets

# Precompile for production
RAILS_ENV=production rails assets:precompile
```

**Verify fingerprinted files:**

```bash
ls -lh public/assets/

# Should see files like:
# application-9f8e7d6c5b4a3210.css
# application-a1b2c3d4e5f6a7b8.js
# .manifest.json
```

**Inspect manifest:**

```bash
cat public/assets/.manifest.json | jq
```

Output shows logical-to-fingerprinted mappings:

```json
{
  "application.css": "application-9f8e7d6c5b4a3210.css",
  "application.js": "application-a1b2c3d4e5f6a7b8.js"
}
```

### Step 6: Create S3 Bucket

**Prerequisites:** AWS CLI installed and configured (`aws configure`)

```bash
# Set variables
BUCKET_NAME="your-app-assets-$(date +%s)"
AWS_REGION="us-east-1"

# Create bucket
aws s3 mb s3://$BUCKET_NAME --region $AWS_REGION

# Configure bucket for public-read access
aws s3api put-public-access-block \
  --bucket $BUCKET_NAME \
  --public-access-block-configuration \
  "BlockPublicAcls=false,IgnorePublicAcls=false,BlockPublicPolicy=false,RestrictPublicBuckets=false"

# Add bucket policy for public read
cat > /tmp/bucket-policy.json <<'EOF'
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "PublicReadGetObject",
      "Effect": "Allow",
      "Principal": "*",
      "Action": "s3:GetObject",
      "Resource": "arn:aws:s3:::BUCKET_NAME/*"
    }
  ]
}
EOF

# Replace BUCKET_NAME in policy
sed -i "s/BUCKET_NAME/$BUCKET_NAME/g" /tmp/bucket-policy.json

# Apply policy
aws s3api put-bucket-policy \
  --bucket $BUCKET_NAME \
  --policy file:///tmp/bucket-policy.json
```

### Step 7: Upload Assets to S3

```bash
# Sync assets with proper cache headers
aws s3 sync public/assets s3://$BUCKET_NAME/assets \
  --acl public-read \
  --cache-control "public, max-age=31536000, immutable" \
  --exclude ".manifest.json"

# Upload manifest separately with shorter cache (for debugging)
aws s3 cp public/assets/.manifest.json s3://$BUCKET_NAME/assets/ \
  --acl public-read \
  --cache-control "public, max-age=3600"
```

**Verify upload:**

```bash
aws s3 ls s3://$BUCKET_NAME/assets/ --recursive

# Test public URL (replace with your bucket name and filename)
curl -I https://$BUCKET_NAME.s3.amazonaws.com/assets/application-<fingerprint>.css
```

Should return:

```
HTTP/1.1 200 OK
Cache-Control: public, max-age=31536000, immutable
Content-Type: text/css
```

### Step 8: Create CloudFront Distribution

```bash
# Create distribution config
cat > /tmp/cloudfront-config.json <<EOF
{
  "CallerReference": "asset-cdn-$(date +%s)",
  "Comment": "Asset CDN for Rails app",
  "Enabled": true,
  "Origins": {
    "Quantity": 1,
    "Items": [
      {
        "Id": "S3-$BUCKET_NAME",
        "DomainName": "$BUCKET_NAME.s3.amazonaws.com",
        "OriginPath": "/assets",
        "S3OriginConfig": {
          "OriginAccessIdentity": ""
        }
      }
    ]
  },
  "DefaultCacheBehavior": {
    "TargetOriginId": "S3-$BUCKET_NAME",
    "ViewerProtocolPolicy": "redirect-to-https",
    "AllowedMethods": {
      "Quantity": 2,
      "Items": ["GET", "HEAD"],
      "CachedMethods": {
        "Quantity": 2,
        "Items": ["GET", "HEAD"]
      }
    },
    "Compress": true,
    "MinTTL": 0,
    "DefaultTTL": 31536000,
    "MaxTTL": 31536000,
    "ForwardedValues": {
      "QueryString": false,
      "Cookies": {"Forward": "none"}
    }
  }
}
EOF

# Create distribution
aws cloudfront create-distribution --distribution-config file:///tmp/cloudfront-config.json

# Get distribution domain name (takes ~15 minutes to deploy)
aws cloudfront list-distributions --query 'DistributionList.Items[0].DomainName' --output text
```

**Note:** CloudFront deployment takes 10-20 minutes. Save the domain name (e.g., `d111111abcdef8.cloudfront.net`).

**Alternative: Use AWS Console**

1. Go to CloudFront → Create Distribution
2. Origin domain: `your-bucket.s3.amazonaws.com`
3. Origin path: `/assets`
4. Viewer protocol policy: Redirect HTTP to HTTPS
5. Compress objects automatically: Yes
6. Cache policy: CachingOptimized
7. Create distribution

### Step 9: Configure Rails for CloudFront

Edit `config/environments/production.rb`:

```ruby
Rails.application.configure do
  # ... existing config ...

  # Serve assets from CloudFront
  config.asset_host = ENV.fetch("ASSET_HOST", "https://d111111abcdef8.cloudfront.net")

  # Disable Rails static file serving (CDN serves assets)
  config.public_file_server.enabled = false

  # Don't fallback to assets pipeline if a precompiled asset is missed
  config.assets.compile = false

  # Enable serving of images, stylesheets, and JavaScripts from an asset server
  # (Already set via config.asset_host)
end
```

**For development testing, create `.env`:**

```bash
echo 'ASSET_HOST=https://d111111abcdef8.cloudfront.net' > .env
```

### Step 10: Test Asset URLs

Start Rails in production mode locally:

```bash
# Set secret key for production
export SECRET_KEY_BASE=$(rails secret)
export ASSET_HOST=https://d111111abcdef8.cloudfront.net

# Run production server
RAILS_ENV=production rails server -e production
```

Visit http://localhost:3000, view page source:

```html
<!-- Should see CloudFront URLs -->
<link rel="stylesheet" href="https://d111111abcdef8.cloudfront.net/assets/application-9f8e7d6c.css" />
<script src="https://d111111abcdef8.cloudfront.net/assets/application-a1b2c3d4.js" defer></script>
```

**Test in console:**

```ruby
rails console -e production

# Test asset path helpers
ActionController::Base.helpers.asset_path("application.css")
# => "https://d111111abcdef8.cloudfront.net/assets/application-9f8e7d6c.css"

ActionController::Base.helpers.stylesheet_link_tag("application")
# => <link rel="stylesheet" href="https://d111111abcdef8.cloudfront.net/assets/application-9f8e7d6c.css" />
```

### Step 11: Verify Cache Headers

Use curl to check CloudFront cache headers:

```bash
curl -I https://d111111abcdef8.cloudfront.net/assets/application-9f8e7d6c.css
```

Expected headers:

```
HTTP/2 200
content-type: text/css
cache-control: public, max-age=31536000, immutable
x-cache: Hit from cloudfront
age: 3600
```

**`x-cache: Hit from cloudfront`** means CDN is serving cached asset (not hitting S3).

**On first request:**

```
x-cache: Miss from cloudfront
```

**Second request:**

```
x-cache: Hit from cloudfront
age: 10  # seconds since cached
```

### Step 12: Deployment Automation Script

Create `bin/deploy-assets.sh`:

```bash
#!/bin/bash
set -e

echo "==> Precompiling assets..."
RAILS_ENV=production rails assets:precompile

echo "==> Uploading to S3..."
aws s3 sync public/assets s3://$BUCKET_NAME/assets \
  --acl public-read \
  --cache-control "public, max-age=31536000, immutable" \
  --delete \
  --exclude ".manifest.json"

aws s3 cp public/assets/.manifest.json s3://$BUCKET_NAME/assets/ \
  --acl public-read \
  --cache-control "public, max-age=3600"

echo "==> Invalidating CloudFront cache..."
DISTRIBUTION_ID=$(aws cloudfront list-distributions --query 'DistributionList.Items[0].Id' --output text)
aws cloudfront create-invalidation \
  --distribution-id $DISTRIBUTION_ID \
  --paths "/assets/*"

echo "==> Assets deployed successfully!"
```

Make executable:

```bash
chmod +x bin/deploy-assets.sh

# Set bucket name
export BUCKET_NAME=your-app-assets-1234567890

# Run deployment
./bin/deploy-assets.sh
```

## Verification Steps

### 1. Verify Fingerprinting Works

Make a CSS change:

```css
/* app/assets/stylesheets/application.tailwind.css */
.hero-section {
  @apply bg-gradient-to-r from-green-500 to-blue-600 text-white py-20 px-6;
}
```

Recompile:

```bash
RAILS_ENV=production rails assets:precompile
```

Check new fingerprint:

```bash
ls public/assets/application-*.css

# Should see NEW fingerprint
# application-xyz789newHash.css
```

### 2. Verify CDN Cache Hit Rate

```bash
# Make multiple requests
for i in {1..10}; do
  curl -I https://d111111abcdef8.cloudfront.net/assets/application-9f8e7d6c.css | grep x-cache
done

# Should see:
# x-cache: Miss from cloudfront  (first request)
# x-cache: Hit from cloudfront   (subsequent 9 requests)
```

### 3. Test Immutable Cache Directive

```bash
curl -I https://d111111abcdef8.cloudfront.net/assets/application-9f8e7d6c.css | grep -i cache-control

# Expected:
# cache-control: public, max-age=31536000, immutable
```

### 4. Performance Comparison

Test CloudFront vs direct S3:

```bash
# CloudFront (with edge caching)
time curl -so /dev/null https://d111111abcdef8.cloudfront.net/assets/application-9f8e7d6c.css
# Real: ~50ms (from edge location)

# Direct S3 (no edge caching)
time curl -so /dev/null https://$BUCKET_NAME.s3.amazonaws.com/assets/application-9f8e7d6c.css
# Real: ~200ms (from us-east-1)
```

CloudFront should be 3-4x faster for global users.

## Stretch Goals

### 1. Implement asset_sync Gem

Automate S3 uploads:

```ruby
# Gemfile
gem "asset_sync"

# config/initializers/asset_sync.rb
if defined?(AssetSync)
  AssetSync.configure do |config|
    config.fog_provider = "AWS"
    config.aws_access_key_id = ENV["AWS_ACCESS_KEY_ID"]
    config.aws_secret_access_key = ENV["AWS_SECRET_ACCESS_KEY"]
    config.fog_directory = ENV["S3_BUCKET_NAME"]
    config.fog_region = ENV["AWS_REGION"]
    config.gzip_compression = true
    config.manifest = true
    config.existing_remote_files = "keep"
  end
end
```

Deploy:

```bash
rails assets:precompile
# Automatically uploads to S3 after precompile
```

### 2. Add Brotli Compression

Generate compressed versions:

```bash
# Install brotli
brew install brotli  # macOS
# apt-get install brotli  # Ubuntu

# Compress CSS and JS
find public/assets -type f \( -name "*.css" -o -name "*.js" \) -exec brotli {} \;

# Upload with Content-Encoding
aws s3 sync public/assets s3://$BUCKET_NAME/assets \
  --exclude "*" \
  --include "*.br" \
  --content-encoding "br" \
  --cache-control "public, max-age=31536000, immutable"
```

### 3. Implement Subresource Integrity (SRI)

```ruby
# config/initializers/propshaft.rb
Rails.application.config.assets.unknown_asset_fallback = false

# Generate SRI hashes
Rails.application.config.assets.resolve_with << Propshaft::Resolver::Integrity.new
```

Update layout:

```erb
<%= stylesheet_link_tag "application", integrity: true %>
<%= javascript_include_tag "application", integrity: true %>
```

Generates:

```html
<link rel="stylesheet" href="https://cdn.example.com/assets/app.css"
  integrity="sha384-oqVuAfXRKap7fdgcCY5uykM6+R9GqQ8K/uxECu1E2XPmcrpVvWSLpU2kEGSq4R9B" />
```

### 4. Configure Multiple Asset Hosts (Sharding)

For parallelizing downloads:

```ruby
# config/environments/production.rb
config.action_controller.asset_host = Proc.new { |source|
  "https://assets#{Digest::MD5.hexdigest(source).to_i(16) % 4}.example.com"
}
```

Distributes assets across:
- `assets0.example.com`
- `assets1.example.com`
- `assets2.example.com`
- `assets3.example.com`

### 5. Monitor CloudFront with CloudWatch

```bash
# Get metrics
aws cloudwatch get-metric-statistics \
  --namespace AWS/CloudFront \
  --metric-name Requests \
  --dimensions Name=DistributionId,Value=$DISTRIBUTION_ID \
  --start-time 2024-01-01T00:00:00Z \
  --end-time 2024-01-02T00:00:00Z \
  --period 3600 \
  --statistics Sum
```

Track:
- Cache hit rate (target >95%)
- 4xx/5xx error rates
- Data transfer out
- Request count

## Solution Notes

**Common Gotchas:**

1. **Assets return 403 Forbidden:** S3 bucket policy not set correctly. Verify `s3:GetObject` is public.

2. **404 on asset URLs:** Fingerprint changed but CloudFront has old cached version. Invalidate CloudFront cache:
   ```bash
   aws cloudfront create-invalidation --distribution-id $DIST_ID --paths "/*"
   ```

3. **CSS not loading from CDN:** Check CORS headers if using fonts. Add CORS policy to S3 bucket.

4. **Assets recompile every time:** `.manifest.json` is being deleted. Ensure it's preserved during deploys.

5. **CloudFront serves stale assets:** Check TTL settings. Fingerprints should change on content updates.

**Cache Invalidation Best Practices:**

- Avoid frequent invalidations (costs money after 1000/month)
- Use fingerprinting instead of invalidations
- Only invalidate if you must fix a critical bug in deployed assets
- Invalidate specific paths, not `/*`

**Production Checklist:**

- [ ] `config.assets.compile = false` (no runtime compilation)
- [ ] `config.assets.digest = true` (fingerprinting enabled)
- [ ] CloudFront distribution uses HTTPS
- [ ] S3 bucket has public-read policy
- [ ] Cache-Control headers set to `max-age=31536000, immutable`
- [ ] HTML pages have `no-cache` to avoid stale references
- [ ] Asset URLs include CloudFront domain
- [ ] CI/CD runs `rails assets:precompile` before deploy
- [ ] Assets uploaded to S3 after every deploy

## Time Estimate

28 minutes
