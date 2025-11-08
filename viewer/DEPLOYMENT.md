# Deploying to GitHub Pages

This guide explains how to deploy the Rails Seniority Coach static site to GitHub Pages.

## Build the Static Site

```bash
cd viewer
ruby build_static.rb
```

This generates all HTML files in the `dist/` directory (50 files: 1 index + 8 tracks + 41 topics).

## Deployment Option 1: GitHub Pages from Branch

### Step 1: Create `gh-pages` branch

```bash
# From the root of your repository
git checkout -b gh-pages
```

### Step 2: Copy dist files to root

```bash
# Copy generated files to root
cp -r viewer/dist/* .

# Add .nojekyll to prevent Jekyll processing
touch .nojekyll

# Commit
git add .
git commit -m "Deploy static site to GitHub Pages"
git push -u origin gh-pages
```

### Step 3: Configure GitHub Pages

1. Go to your repository on GitHub
2. Navigate to **Settings** → **Pages**
3. Under "Source", select:
   - **Branch**: `gh-pages`
   - **Folder**: `/ (root)`
4. Click **Save**

Your site will be available at: `https://<username>.github.io/<repo-name>/`

## Deployment Option 2: GitHub Pages from docs/ folder

### Step 1: Copy dist to docs/

```bash
# From repository root
mkdir -p docs
cp -r viewer/dist/* docs/
git add docs/
git commit -m "Add static site to docs folder"
git push
```

### Step 2: Configure GitHub Pages

1. Go to **Settings** → **Pages**
2. Under "Source", select:
   - **Branch**: `main` (or your default branch)
   - **Folder**: `/docs`
3. Click **Save**

## Deployment Option 3: Deploy subtree

This method keeps the static files in `viewer/dist` but deploys only that folder to `gh-pages`:

```bash
# Build the site
cd viewer && ruby build_static.rb && cd ..

# Deploy dist folder to gh-pages branch
git subtree push --prefix viewer/dist origin gh-pages
```

Then configure GitHub Pages to use the `gh-pages` branch (root folder).

## Updating the Site

Whenever you update content:

1. **Rebuild**: `ruby viewer/build_static.rb`
2. **Commit and push** the updated files
3. GitHub Pages will automatically redeploy

## Custom Domain (Optional)

To use a custom domain:

1. Add a `CNAME` file to `viewer/dist/` with your domain name
2. Configure DNS to point to GitHub Pages
3. Enable custom domain in GitHub Pages settings

See: https://docs.github.com/en/pages/configuring-a-custom-domain-for-your-github-pages-site

## Troubleshooting

### Files not loading (404)

- Ensure `.nojekyll` file exists in the root of your deployment
- Check that paths in HTML use relative URLs (not absolute paths starting with `/`)

### Styles/JS not working

- Verify all CSS and JavaScript is embedded in the HTML (no external files)
- Check browser console for errors

### Build errors

- Ensure Ruby 3.0+ is installed
- Run `bundle install` in the `viewer/` directory
- Check that all content files (YAML/Markdown) are valid

## Development vs Production

- **Development**: Run `bundle exec rackup` in `viewer/` for live server with hot reload
- **Production**: Build static site with `ruby build_static.rb` and deploy `dist/` folder

---

**Note**: The static site generator embeds all CSS and JavaScript inline, so there are no external dependencies. The `dist/` folder is completely self-contained and ready for deployment.
