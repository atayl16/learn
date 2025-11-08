# Exercise: APM Basics and Flamegraphs

## Objective
Set up rack-mini-profiler for local performance analysis, create a controller with an N+1 query, and use profiling to identify and fix the bottleneck.

## Task
In a Rails application:

1. Install rack-mini-profiler and dependencies
2. Create models and seed data to trigger N+1 queries
3. Build a controller action that exhibits N+1 behavior
4. Use rack-mini-profiler to identify the problem in the flamegraph
5. Fix the N+1 with eager loading and verify improvement

## Acceptance Criteria
- [ ] rack-mini-profiler installed and showing performance badge
- [ ] Author and Book models with has_many/belongs_to relationship
- [ ] Index page displays authors and book counts (triggers N+1)
- [ ] Profiler shows multiple identical SELECT COUNT queries
- [ ] Fixed version uses includes or counter_cache
- [ ] Profiler confirms query reduction (from N+1 to 2-3 queries total)

## Verification Steps

### Step 1: Install rack-mini-profiler

```bash
# Add to Gemfile development group
bundle add rack-mini-profiler --group development
bundle add memory_profiler --group development
bundle add stackprof --group development

bundle install
```

### Step 2: Configure rack-mini-profiler

Create `config/initializers/rack_profiler.rb`:

```ruby
if Rails.env.development?
  require 'rack-mini-profiler'

  # Memory profiling
  Rack::MiniProfiler.config.enable_advanced_debugging_tools = true
end
```

### Step 3: Create Models

Generate Author and Book models:

```bash
bin/rails generate model Author name:string bio:text
bin/rails generate model Book title:string author:references published_year:integer
bin/rails db:migrate
```

Edit models:

`app/models/author.rb`:
```ruby
class Author < ApplicationRecord
  has_many :books

  validates :name, presence: true
end
```

`app/models/book.rb`:
```ruby
class Book < ApplicationRecord
  belongs_to :author

  validates :title, presence: true
end
```

### Step 4: Seed Test Data

Edit `db/seeds.rb`:

```ruby
puts "Creating authors and books..."

10.times do |i|
  author = Author.create!(
    name: "Author #{i + 1}",
    bio: "Biography of author #{i + 1}"
  )

  rand(5..15).times do |j|
    author.books.create!(
      title: "Book #{j + 1} by #{author.name}",
      published_year: rand(1990..2024)
    )
  end
end

puts "Created #{Author.count} authors with #{Book.count} books"
```

Run seeds:

```bash
bin/rails db:seed
```

### Step 5: Create Controller with N+1

Generate controller:

```bash
bin/rails generate controller Authors index
```

Edit `app/controllers/authors_controller.rb`:

```ruby
class AuthorsController < ApplicationController
  def index
    # N+1 version - intentionally inefficient
    @authors = Author.all
  end

  def index_optimized
    # Optimized version with eager loading
    @authors = Author.includes(:books).all
    render :index
  end
end
```

### Step 6: Create View

Edit `app/views/authors/index.html.erb`:

```erb
<h1>Authors and Their Books</h1>

<% @authors.each do |author| %>
  <div style="border: 1px solid #ccc; padding: 10px; margin: 10px 0;">
    <h2><%= author.name %></h2>
    <p><%= author.bio %></p>
    <p><strong>Books written:</strong> <%= author.books.count %></p>

    <ul>
      <% author.books.limit(3).each do |book| %>
        <li><%= book.title %> (<%= book.published_year %>)</li>
      <% end %>
    </ul>
  </div>
<% end %>

<hr>
<p>
  <strong>Performance hint:</strong> Check the rack-mini-profiler badge in the top-left corner!
</p>
<p>
  Compare this page to the <%= link_to 'optimized version', authors_optimized_path %>
</p>
```

### Step 7: Update Routes

Edit `config/routes.rb`:

```ruby
Rails.application.routes.draw do
  resources :authors, only: [:index]
  get 'authors_optimized', to: 'authors#index_optimized'
end
```

### Step 8: Test and Profile

Start Rails server:

```bash
bin/rails server
```

Visit http://localhost:3000/authors

**Observe rack-mini-profiler badge (top-left):**
- Total time (e.g., 250ms)
- SQL time (e.g., 180ms)
- Number of queries (e.g., 21 queries)

Click the badge to see detailed breakdown:

**Expected N+1 pattern:**
```
SQL (21 queries - 180ms)
├─ SELECT "authors".* FROM "authors"  (1.2ms)
├─ SELECT COUNT(*) FROM "books" WHERE "books"."author_id" = 1  (8.1ms)
├─ SELECT COUNT(*) FROM "books" WHERE "books"."author_id" = 2  (7.9ms)
├─ SELECT COUNT(*) FROM "books" WHERE "books"."author_id" = 3  (8.2ms)
... (repeated for each author)
├─ SELECT "books".* FROM "books" WHERE "books"."author_id" = 1 LIMIT 3  (2.1ms)
... (repeated for each author)
```

### Step 9: Compare with Optimized Version

Visit http://localhost:3000/authors_optimized

**rack-mini-profiler should show:**
```
SQL (2 queries - 15ms)
├─ SELECT "authors".* FROM "authors"  (1.2ms)
└─ SELECT "books".* FROM "books" WHERE "books"."author_id" IN (1,2,3,4,5...)  (13.8ms)
```

**Improvement:** 21 queries → 2 queries, ~170ms saved

### Step 10: View Flamegraph

Click the rack-mini-profiler badge, then click "flamegraph" tab.

You'll see:
- Wide bars for N+1 queries (bad version)
- Narrow bars for eager-loaded query (good version)

### Step 11: Verify in Rails Console

```ruby
# Enable SQL logging
ActiveRecord::Base.logger = Logger.new(STDOUT)

# N+1 version
authors = Author.all
authors.each { |a| puts a.books.count }
# Watch console - you'll see COUNT(*) query for each author

# Optimized version
authors = Author.includes(:books).all
authors.each { |a| puts a.books.size }  # Use size, not count!
# Only 2 queries total
```

## Stretch (Optional)

1. Add counter_cache to eliminate COUNT queries entirely:

```bash
bin/rails generate migration AddBooksCountToAuthors books_count:integer
bin/rails db:migrate
```

```ruby
# app/models/book.rb
belongs_to :author, counter_cache: true

# Reset counter cache for existing records
Author.find_each { |a| Author.reset_counters(a.id, :books) }
```

Now `author.books_count` requires zero queries.

2. Add custom profiling steps:

```ruby
def index_optimized
  Rack::MiniProfiler.step('Load authors') do
    @authors = Author.includes(:books).all
  end

  Rack::MiniProfiler.step('Render view') do
    render :index
  end
end
```

3. Profile memory usage (click "memory" in rack-mini-profiler):

```ruby
# In controller
def index
  MemoryProfiler.report do
    @authors = Author.includes(:books).all
  end.pretty_print
end
```

## Time Estimate
17 minutes
