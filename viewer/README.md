# Rails Seniority Coach - Web Viewer

A lightweight Sinatra-based web application to browse the Rails Seniority Coach content library.

## Features

- **Browse all 8 tracks** with topic listings
- **Read topic content** with tabbed interface (Overview, Exercise, Checkpoint, References)
- **Take checkpoint quizzes** with instant scoring (client-side, no auth required)
- **Search functionality** - real-time search across all topics
- **Progress tracking** - mark topics complete with localStorage persistence
- **Dark mode** - toggle with persistent preference
- **Keyboard shortcuts** - navigate with arrow keys, search with `/`
- **Prev/Next navigation** - seamless topic browsing
- **Code copy buttons** - one-click copying of code samples
- **Markdown rendering** with syntax highlighting for code samples
- **Responsive design** works on desktop and mobile
- **No database** - reads directly from YAML/Markdown files
- **Static site generation** - export to GitHub Pages-ready HTML

## Installation

```bash
cd viewer

# Install dependencies
bundle install
```

## Running the Viewer

```bash
# Development mode (with auto-reload)
bundle exec ruby app.rb

# Or using rackup
bundle exec rackup -p 4567

# Production mode
RACK_ENV=production bundle exec puma -p 4567
```

Then visit: **http://localhost:4567**

## Architecture

### Files

- `app.rb` - Main Sinatra application
- `build_static.rb` - Static site generator for GitHub Pages
- `views/layout.erb` - HTML layout with CSS and JavaScript
- `views/index.erb` - Track listing page
- `views/track.erb` - Topic listing for a track
- `views/topic.erb` - Full topic view with tabs
- `Gemfile` - Ruby dependencies
- `config.ru` - Rack configuration
- `DEPLOYMENT.md` - GitHub Pages deployment guide

### How It Works

1. **Loads content** from `../config/skills/` (YAML metadata) and `../content/` (Markdown)
2. **Renders Markdown** using Redcarpet with Rouge syntax highlighting
3. **Client-side quiz** scoring using vanilla JavaScript (no frameworks)
4. **No authentication** - content is publicly browsable
5. **No database** - stateless, reads from files

## Dependencies

- **sinatra** - Lightweight web framework
- **redcarpet** - Markdown rendering
- **rouge** - Syntax highlighting for code blocks
- **puma** - Web server

## Usage

### Browsing Content

1. **Home page** (`/`) - Lists all 8 tracks
2. **Track page** (`/tracks/:track_key`) - Lists topics in the track
3. **Topic page** (`/tracks/:track_key/topics/:topic_key`) - Full content with 4 tabs:
   - **Overview** - Teaching content (600-900 words)
   - **Exercise** - Hands-on task with acceptance criteria
   - **Checkpoint** - Quiz with MCQ and short-answer questions
   - **References** - Curated sources (official docs, books, talks)

### Taking Quizzes

1. Navigate to a topic's **Checkpoint** tab
2. Select answers for multiple-choice questions
3. Click **Check Answers** to see your score
4. Review explanations for correct/incorrect answers
5. Click **Reset** to try again

Short-answer questions show sample answers for self-assessment.

## Deployment

### Heroku

```bash
# Create Heroku app
heroku create rails-seniority-coach

# Deploy
git subtree push --prefix viewer heroku main

# Or: git push heroku main (if viewer is root)
```

### Docker

```dockerfile
FROM ruby:3.2

WORKDIR /app
COPY Gemfile* ./
RUN bundle install

COPY . .

EXPOSE 4567
CMD ["bundle", "exec", "puma", "-p", "4567"]
```

### GitHub Pages (Static Site)

Generate a static HTML version for GitHub Pages:

```bash
cd viewer
ruby build_static.rb
```

This creates a `dist/` folder with 50 self-contained HTML files (1 index + 8 tracks + 41 topics).

See **[DEPLOYMENT.md](DEPLOYMENT.md)** for detailed deployment instructions including:
- Deploying to `gh-pages` branch
- Using `/docs` folder
- Custom domain setup

The static site includes ALL features (search, dark mode, progress tracking, quizzes) with no backend required.

## Customization

### Styling

Edit the `<style>` block in `views/layout.erb`:
- Change `#CC0000` to your brand color
- Modify fonts, spacing, or layout
- Add custom CSS for dark mode

### Content Location

By default, reads from `../config/skills/` and `../content/`. To change:

Edit `app.rb` and update paths in:
- `load_tracks()`
- `load_track_topics(track_key)`
- `load_topic_content(track_key, topic_key)`

## Performance

- **No database queries** - reads files on demand
- **In-memory caching** - could add Rails.cache for production
- **Lightweight** - ~5 MB RAM footprint
- **Fast** - <50ms response times for most pages

## Browser Support

- Chrome, Firefox, Safari, Edge (modern versions)
- Mobile browsers (iOS Safari, Chrome Mobile)
- Requires JavaScript for quiz functionality

## License

Same as parent content repository.

## Contributing

To add new content:
1. Add YAML config to `config/skills/{track}/{topic}.yml`
2. Add content files to `content/{track}/{topic}/`
3. Viewer automatically picks up new files

No code changes needed!
