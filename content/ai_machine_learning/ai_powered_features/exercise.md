# Exercise: Build Semantic Search with pgvector

## Objective
Implement semantic search for a blog platform using OpenAI embeddings and pgvector, then compare semantic vs keyword search quality.

## Task
Build a Rails app that:

1. Stores article embeddings in PostgreSQL using pgvector
2. Generates embeddings automatically when articles are created/updated
3. Implements semantic search that finds articles by meaning, not just keywords
4. Creates a hybrid search combining semantic similarity + keyword matching
5. Adds a "similar articles" recommendation feature
6. Benchmarks query performance with and without indexes

## Acceptance Criteria
- [ ] PostgreSQL has pgvector extension enabled
- [ ] Articles table has `embedding` vector column (1536 dimensions)
- [ ] Embeddings generate automatically on article save using OpenAI API
- [ ] Semantic search returns relevant results for queries like "Rails performance tips"
- [ ] Hybrid search combines semantic and keyword results with weighted scoring
- [ ] "Similar articles" feature shows content-based recommendations
- [ ] IVFFlat index improves query performance on 100+ articles
- [ ] Comparison shows semantic search finding relevant content that keyword search misses

## Verification Steps

Test semantic search vs keyword search:

```ruby
# Query: "Rails performance tips"
# Semantic search should find articles containing:
# - "Speed up Ruby on Rails applications"
# - "Optimizing ActiveRecord queries"
# - "Caching strategies for faster response times"

# Even if they don't contain exact words "Rails performance tips"

# Keyword search misses these but finds:
# - "10 Tips for Rails Performance"  # Exact keyword match only

```

Verify index improves performance:

```ruby
# Without index: 200-500ms on 1000 articles
# With IVFFlat index: 10-50ms on 1000 articles

```

## Setup Code

### Step 1: Create Rails App with PostgreSQL

```bash
rails new semantic_search_demo --database=postgresql
cd semantic_search_demo

```

**Enable pgvector:**

```bash
# Install pgvector extension on PostgreSQL
# macOS: brew install pgvector
# Linux: apt-get install postgresql-14-pgvector
# Or use Docker: postgres:16 with pgvector

```

Add gems to `Gemfile`:

```ruby
gem 'ruby-openai'
gem 'neighbor'
gem 'dotenv-rails'

```

```bash
bundle install

```

Create `.env`:

```env
OPENAI_API_KEY=sk-your-key-here

```

### Step 2: Enable pgvector Extension

```bash
bin/rails generate migration EnablePgvector

```

Edit `db/migrate/XXXXXX_enable_pgvector.rb`:

```ruby
class EnablePgvector < ActiveRecord::Migration[7.1]
  def change
    enable_extension 'vector'
  end
end

```

```bash
bin/rails db:create db:migrate

```

### Step 3: Create Articles Model

```bash
bin/rails generate model Article title:string body:text published_at:datetime

```

Edit the migration to add vector column:

```ruby
class CreateArticles < ActiveRecord::Migration[7.1]
  def change
    create_table :articles do |t|
      t.string :title, null: false
      t.text :body, null: false
      t.datetime :published_at
      t.vector :embedding, limit: 1536  # OpenAI ada-002 dimensions

      t.timestamps
    end
  end
end

```

```bash
bin/rails db:migrate

```

### Step 4: Configure Article Model

`app/models/article.rb`:

```ruby
class Article < ApplicationRecord
  has_neighbors :embedding, dimensions: 1536, distance: 'cosine'

  validates :title, :body, presence: true

  after_save :generate_embedding_async, if: :content_changed?

  # Semantic search
  def self.semantic_search(query, limit: 10)
    embedding = generate_query_embedding(query)
    return none if embedding.blank?

    nearest_neighbors(:embedding, embedding, distance: 'cosine')
      .limit(limit)
  end

  # Hybrid search (70% semantic, 30% keyword)
  def self.hybrid_search(query, limit: 10)
    embedding = generate_query_embedding(query)
    return keyword_search(query, limit: limit) if embedding.blank?

    select(<<~SQL.squish)
      articles.*,
      (
        0.7 * (1 - (embedding <=> '[#{embedding.join(',')}]')) +
        0.3 * ts_rank(
          to_tsvector('english', title || ' ' || body),
          plainto_tsquery('english', '#{sanitize_sql_like(query)}')
        )
      ) AS relevance_score
    SQL
      .where(
        "embedding <=> '[#{embedding.join(',')}]' < 0.8 OR " \
        "to_tsvector('english', title || ' ' || body) @@ plainto_tsquery('english', ?)",
        query
      )
      .order('relevance_score DESC')
      .limit(limit)
  end

  # Traditional keyword search
  def self.keyword_search(query, limit: 10)
    where(
      "to_tsvector('english', title || ' ' || body) @@ plainto_tsquery('english', ?)",
      query
    )
    .order("ts_rank(to_tsvector('english', title || ' ' || body), plainto_tsquery('english', ?)) DESC", query)
    .limit(limit)
  end

  # Similar articles
  def similar_articles(limit: 5)
    return Article.none if embedding.blank?

    Article.nearest_neighbors(:embedding, embedding, distance: 'cosine')
           .where.not(id: id)
           .limit(limit)
  end

  private

  def content_changed?
    saved_change_to_title? || saved_change_to_body?
  end

  def generate_embedding_async
    GenerateEmbeddingJob.perform_later(id)
  end

  def self.generate_query_embedding(query)
    Rails.cache.fetch("embedding:#{Digest::SHA256.hexdigest(query)}", expires_in: 1.week) do
      client = OpenAI::Client.new(access_token: ENV['OPENAI_API_KEY'])
      response = client.embeddings(
        parameters: {
          model: 'text-embedding-ada-002',
          input: query
        }
      )
      response.dig('data', 0, 'embedding')
    rescue StandardError => e
      Rails.logger.error("Failed to generate embedding: #{e.message}")
      nil
    end
  end
end

```

### Step 5: Create Background Job

```bash
bin/rails generate job GenerateEmbedding

```

`app/jobs/generate_embedding_job.rb`:

```ruby
class GenerateEmbeddingJob < ApplicationJob
  queue_as :default
  retry_on StandardError, wait: 5.seconds, attempts: 3

  def perform(article_id)
    article = Article.find(article_id)
    content = [article.title, article.body].join("\n")

    client = OpenAI::Client.new(access_token: ENV['OPENAI_API_KEY'])
    response = client.embeddings(
      parameters: {
        model: 'text-embedding-ada-002',
        input: content
      }
    )

    embedding = response.dig('data', 0, 'embedding')
    article.update_column(:embedding, embedding) if embedding.present?
  end
end

```

### Step 6: Seed Test Data

`db/seeds.rb`:

```ruby
# Create diverse articles to test semantic search
articles_data = [
  {
    title: "Speed Up Your Ruby on Rails Application",
    body: "Learn techniques for optimizing Rails performance including caching, eager loading, and database query optimization."
  },
  {
    title: "Understanding ActiveRecord N+1 Queries",
    body: "Discover how to identify and fix N+1 query problems using includes, preload, and eager_load methods."
  },
  {
    title: "Rails Caching Strategies for Faster Response Times",
    body: "Explore fragment caching, Russian doll caching, and low-level caching to dramatically reduce page load times."
  },
  {
    title: "Database Indexing Best Practices",
    body: "Master PostgreSQL indexes to accelerate query performance with B-tree, GiST, and partial indexes."
  },
  {
    title: "Introduction to React Hooks",
    body: "Learn how to use useState, useEffect, and custom hooks in React applications for better state management."
  },
  {
    title: "Building RESTful APIs in Rails",
    body: "Create robust JSON APIs using Rails API mode, serializers, and authentication with JWT tokens."
  },
  {
    title: "Docker for Ruby Developers",
    body: "Package your Rails apps in containers using Docker and Docker Compose for consistent development environments."
  },
  {
    title: "Machine Learning Basics with Python",
    body: "Introduction to supervised learning, neural networks, and scikit-learn for data science beginners."
  },
  {
    title: "PostgreSQL Full-Text Search",
    body: "Implement search functionality using tsvector, tsquery, and GIN indexes for text-based queries."
  },
  {
    title: "Deploying Rails to AWS",
    body: "Step-by-step guide to deploying Ruby on Rails applications on EC2, RDS, and S3 with automated backups."
  }
]

puts "Creating articles..."
articles_data.each do |data|
  Article.create!(
    title: data[:title],
    body: data[:body],
    published_at: rand(30).days.ago
  )
end

puts "Created #{Article.count} articles"
puts "Waiting for embeddings to generate..."
sleep 5  # Wait for background jobs
puts "Articles with embeddings: #{Article.where.not(embedding: nil).count}"

```

```bash
bin/rails db:seed

```

### Step 7: Create Search Interface

```bash
bin/rails generate controller Articles index search show

```

`app/controllers/articles_controller.rb`:

```ruby
class ArticlesController < ApplicationController
  def index
    @articles = Article.order(published_at: :desc).limit(10)
  end

  def show
    @article = Article.find(params[:id])
    @similar = @article.similar_articles(limit: 3)
  end

  def search
    @query = params[:q]
    @search_type = params[:type] || 'hybrid'

    if @query.present?
      @results = case @search_type
                 when 'semantic'
                   Article.semantic_search(@query)
                 when 'keyword'
                   Article.keyword_search(@query)
                 when 'hybrid'
                   Article.hybrid_search(@query)
                 end
    else
      @results = Article.none
    end
  end
end

```

`config/routes.rb`:

```ruby
Rails.application.routes.draw do
  resources :articles, only: [:index, :show] do
    collection do
      get :search
    end
  end

  root 'articles#index'
end

```

### Step 8: Create Views

`app/views/articles/index.html.erb`:

```erb
<h1>Articles</h1>

<%= form_with(url: search_articles_path, method: :get, local: true) do |f| %>
  <%= f.text_field :q, placeholder: "Search articles...", value: params[:q] %>
  <%= f.select :type, [['Hybrid', 'hybrid'], ['Semantic', 'semantic'], ['Keyword', 'keyword']], {}, { selected: params[:type] } %>
  <%= f.submit "Search" %>
<% end %>

<ul>
  <% @articles.each do |article| %>
    <li>
      <%= link_to article.title, article_path(article) %>
      <p><%= truncate(article.body, length: 200) %></p>
    </li>
  <% end %>
</ul>

```

`app/views/articles/show.html.erb`:

```erb
<h1><%= @article.title %></h1>
<p><%= @article.body %></p>

<h2>Similar Articles</h2>
<ul>
  <% @similar.each do |similar| %>
    <li><%= link_to similar.title, article_path(similar) %></li>
  <% end %>
</ul>

<%= link_to "Back", articles_path %>

```

`app/views/articles/search.html.erb`:

```erb
<h1>Search Results: <%= @query %></h1>
<p>Search type: <%= @search_type %></p>

<%= form_with(url: search_articles_path, method: :get, local: true) do |f| %>
  <%= f.text_field :q, placeholder: "Search articles...", value: @query %>
  <%= f.select :type, [['Hybrid', 'hybrid'], ['Semantic', 'semantic'], ['Keyword', 'keyword']], {}, { selected: @search_type } %>
  <%= f.submit "Search" %>
<% end %>

<% if @results.any? %>
  <ul>
    <% @results.each do |article| %>
      <li>
        <%= link_to article.title, article_path(article) %>
        <% if article.respond_to?(:relevance_score) %>
          <small>(Score: <%= article.relevance_score.round(3) %>)</small>
        <% end %>
        <p><%= truncate(article.body, length: 200) %></p>
      </li>
    <% end %>
  </ul>
<% else %>
  <p>No results found.</p>
<% end %>

<%= link_to "Back", articles_path %>

```

### Step 9: Add Performance Index

```bash
bin/rails generate migration AddIndexToArticlesEmbedding

```

Edit migration:

```ruby
class AddIndexToArticlesEmbedding < ActiveRecord::Migration[7.1]
  def change
    # IVFFlat index for faster similarity search
    # lists = rows / 1000 (use 10 for small datasets)
    add_index :articles, :embedding,
              using: :ivfflat,
              opclass: :vector_cosine_ops,
              options: 'WITH (lists = 10)'
  end
end

```

```bash
bin/rails db:migrate

```

### Step 10: Test and Compare

Start server:

```bash
bin/rails server

```

Visit `http://localhost:3000` and test searches:

**Test Case 1: Semantic Understanding**
- Query: "Rails performance tips"
- Semantic/Hybrid: Should return articles about caching, N+1 queries, optimization
- Keyword: May only find exact "performance" matches

**Test Case 2: Synonym Matching**
- Query: "speeding up Ruby applications"
- Semantic: Finds "optimize", "faster", "performance" articles
- Keyword: Misses these due to different wording

**Test Case 3: Similar Articles**
- Click any article
- Verify "Similar Articles" shows related content

### Step 11: Benchmark Performance

Create `lib/tasks/benchmark_search.rake`:

```ruby
namespace :search do
  desc "Benchmark semantic vs keyword search"
  task benchmark: :environment do
    require 'benchmark'

    queries = [
      "Rails performance tips",
      "caching strategies",
      "database optimization",
      "API development"
    ]

    puts "\n=== Search Performance Comparison ==="
    queries.each do |query|
      puts "\nQuery: #{query}"

      Benchmark.bm(15) do |x|
        x.report("Semantic") { Article.semantic_search(query).to_a }
        x.report("Keyword") { Article.keyword_search(query).to_a }
        x.report("Hybrid") { Article.hybrid_search(query).to_a }
      end
    end

    puts "\n=== Index Impact ==="
    Article.connection.execute("DROP INDEX IF EXISTS index_articles_on_embedding")
    Benchmark.bm(15) do |x|
      x.report("Without index") { Article.semantic_search("Rails").to_a }
    end

    # Recreate index
    Article.connection.execute(<<~SQL)
      CREATE INDEX index_articles_on_embedding ON articles
      USING ivfflat (embedding vector_cosine_ops)
      WITH (lists = 10)
    SQL

    Benchmark.bm(15) do |x|
      x.report("With index") { Article.semantic_search("Rails").to_a }
    end
  end
end

```

Run benchmark:

```bash
bin/rails search:benchmark

```

## Stretch (Optional)

1. **Implement Relevance Feedback:**

```ruby
# Track which results users click
class SearchLog < ApplicationRecord
  belongs_to :article

  scope :positive_signals, -> { where(clicked: true) }
end

# Boost similar content in future searches
Article.semantic_search(query).reorder(
  Arel.sql("CASE WHEN id IN (SELECT article_id FROM search_logs WHERE clicked = true) THEN 0.5 ELSE 1 END * (embedding <=> '[...]')")
)

```

2. **Add Multi-Field Embeddings:**

```ruby
# Separate embeddings for title vs body for weighted search
add_column :articles, :title_embedding, :vector, limit: 1536
add_column :articles, :body_embedding, :vector, limit: 1536

# Search with field-specific weights
Article.select(<<~SQL)
  *, (0.4 * (title_embedding <=> '[...]') + 0.6 * (body_embedding <=> '[...]')) AS score
SQL

```

3. **Implement HNSW Index (pgvector 0.5+):**

```ruby
add_index :articles, :embedding,
          using: :hnsw,
          opclass: :vector_cosine_ops,
          options: 'WITH (m = 16, ef_construction = 64)'

# Query-time tuning
Article.connection.execute("SET hnsw.ef_search = 100")

```

## Time Estimate
30 minutes
