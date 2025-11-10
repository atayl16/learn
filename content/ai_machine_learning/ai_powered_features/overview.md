# AI-Powered Search & Recommendations

## What It Is
AI-powered search uses vector embeddings to find semantically similar content, not just exact keyword matches. Instead of traditional full-text search (PostgreSQL's `tsvector`, Elasticsearch), embeddings represent text as high-dimensional vectors (1536 floats for OpenAI's ada-002) where similar meanings cluster together. pgvector extends PostgreSQL with vector similarity operations, enabling semantic search, recommendation systems, and hybrid search (semantic + keyword) directly in your Rails app without external services.

## Why It Matters
Keyword search fails when users phrase queries differently than your content ("cheap flight" vs "affordable airfare"). Embeddings capture meaning, so "Rails performance optimization" matches "speeding up Ruby on Rails apps" even without shared words. This improves search relevance, enables "find similar" features, and powers personalized recommendations. Using pgvector keeps vector data in PostgreSQL, avoiding the complexity of syncing to separate vector databases like Pinecone or Weaviate.

## When to Use
- **Semantic search:** Find documents by meaning, not just keywords (e.g., search documentation, customer support tickets)
- **Similarity features:** "More like this" recommendations (similar products, articles, job postings)
- **Hybrid search:** Combine semantic similarity with keyword filters (e.g., semantic search + price range)
- **Content moderation:** Detect similar spam/abuse patterns by comparing embeddings
- **Personalization:** Recommend content based on user behavior embeddings
- **Duplicate detection:** Find near-duplicate records despite phrasing differences

## Three Common Pitfalls
1. **Re-generating embeddings on every query:** Embeddings are expensive (0.0001 per 1K tokens for OpenAI). Generate once on content create/update, store in `vector` column, and reuse for queries. Only generate query embeddings at search time.
2. **No hybrid search fallback:** Pure semantic search can miss exact matches (product SKUs, acronyms). Always combine with keyword search using `OR` clauses or weighted ranking.
3. **Missing indexes:** Without an IVFFlat or HNSW index, pgvector scans every row. On 100K+ vectors, queries take seconds. Add indexes and tune `lists`/`m` parameters for production datasets.

---

## Vector Embeddings Fundamentals

Embeddings convert text into arrays of floats that capture semantic meaning:

```ruby
# Input text
"Rails performance optimization"

# Embedding (simplified; real vectors have 1536 dimensions)
[0.023, -0.891, 0.445, ..., 0.129]

```

**Similar texts have similar vectors:**

```ruby
"Rails performance optimization"  → [0.02, -0.89, 0.44, ...]
"Speed up Ruby on Rails apps"     → [0.03, -0.87, 0.47, ...]  # Close in vector space

"Cat photos"                       → [0.76, 0.12, -0.34, ...] # Far away

```

**Distance metrics** (pgvector supports all three):

| Metric | Formula | Use Case |
|--------|---------|----------|
| Cosine Distance (`<=>`) | 1 - (A·B)/(‖A‖‖B‖) | Default for OpenAI embeddings; measures angle |
| L2 Distance (`<->`) | √Σ(A-B)² | Euclidean distance; magnitude matters |
| Inner Product (`<#>`) | -A·B | When vectors are normalized |

For OpenAI embeddings, use **cosine distance** (`<=>`).

---

## Setting Up pgvector

### Installation

Add to `Gemfile`:

```ruby
gem 'neighbor'  # Ruby interface for pgvector

```

Enable pgvector extension:

```bash
bin/rails generate migration EnablePgvectorExtension
# Edit migration file

```

```ruby
class EnablePgvectorExtension < ActiveRecord::Migration[7.1]
  def change
    enable_extension 'vector'
  end
end

```

```bash
bin/rails db:migrate

```

### Adding Vector Columns

```bash
bin/rails generate migration AddEmbeddingToArticles

```

```ruby
class AddEmbeddingToArticles < ActiveRecord::Migration[7.1]
  def change
    add_column :articles, :embedding, :vector, limit: 1536  # OpenAI ada-002 dimension
  end
end

```

**Model setup:**

```ruby
class Article < ApplicationRecord
  has_neighbors :embedding, dimensions: 1536, distance: 'cosine'

  after_save :generate_embedding, if: :content_changed?

  private

  def generate_embedding
    response = OpenAI::Client.new.embeddings(
      parameters: {
        model: 'text-embedding-ada-002',
        input: [title, body].join("\n")
      }
    )
    update_column(:embedding, response.dig('data', 0, 'embedding'))
  end
end

```

---

## Semantic Search Implementation

### Basic Similarity Search

Find articles similar to a query:

```ruby
class ArticlesController < ApplicationController
  def search
    query = params[:q]
    return if query.blank?

    # Generate query embedding
    response = OpenAI::Client.new.embeddings(
      parameters: { model: 'text-embedding-ada-002', input: query }
    )
    query_embedding = response.dig('data', 0, 'embedding')

    # Find nearest neighbors
    @articles = Article.nearest_neighbors(
      :embedding, query_embedding,
      distance: 'cosine'
    ).limit(10)
  end
end

```

### Using Raw SQL

```ruby
# Find articles with cosine distance < 0.5
query_embedding = [0.123, -0.456, ...] # 1536 dimensions

Article.select("*, embedding <=> '[#{query_embedding.join(',')}]' AS distance")
       .where("embedding <=> '[#{query_embedding.join(',')}]' < ?", 0.5)
       .order("distance")
       .limit(10)

```

---

## Hybrid Search: Semantic + Keyword

Combine semantic similarity with keyword matching:

```ruby
class Article < ApplicationRecord
  def self.hybrid_search(query, limit: 10)
    # Generate embedding for semantic search
    response = OpenAI::Client.new.embeddings(
      parameters: { model: 'text-embedding-ada-002', input: query }
    )
    embedding = response.dig('data', 0, 'embedding')

    # Combine semantic and keyword search with weighted ranking
    Article.select(<<~SQL)
      *,
      (
        0.7 * (1 - (embedding <=> '[#{embedding.join(',')}]')) +
        0.3 * ts_rank(to_tsvector('english', title || ' ' || body), plainto_tsquery('#{query}'))
      ) AS hybrid_score
    SQL
      .where("embedding <=> '[#{embedding.join(',')}]' < 0.8 OR to_tsvector('english', title || ' ' || body) @@ plainto_tsquery(?)", query)
      .order("hybrid_score DESC")
      .limit(limit)
  end
end

```

**Weighting strategies:**
- 70% semantic, 30% keyword: Good default for natural language queries
- 50/50: Balanced for product search with SKUs/part numbers
- 90% semantic, 10% keyword: Exploratory "find similar" features

---

## Recommendation Systems

### Content-Based Recommendations

Recommend articles similar to what a user read:

```ruby
class Article < ApplicationRecord
  def similar_articles(limit: 5)
    Article.nearest_neighbors(:embedding, embedding, distance: 'cosine')
           .where.not(id: id)
           .limit(limit)
  end
end

# Usage
@article = Article.find(params[:id])
@recommended = @article.similar_articles

```

### User-Based Recommendations

Aggregate user interaction embeddings:

```ruby
class User < ApplicationRecord
  has_many :article_views

  def recommended_articles(limit: 10)
    # Average embeddings of viewed articles
    viewed_embeddings = article_views.joins(:article).pluck('articles.embedding')
    return Article.none if viewed_embeddings.empty?

    avg_embedding = viewed_embeddings.transpose.map { |col| col.sum / viewed_embeddings.size }

    # Find articles similar to user's interests
    Article.nearest_neighbors(:embedding, avg_embedding, distance: 'cosine')
           .where.not(id: article_views.pluck(:article_id))  # Exclude already viewed
           .limit(limit)
  end
end

```

---

## Indexing for Performance

Without indexes, pgvector performs exhaustive search (slow on large datasets).

### IVFFlat Index (Fast, Less Accurate)

```ruby
class AddIvfIndexToArticles < ActiveRecord::Migration[7.1]
  def change
    # Tune lists = rows / 1000 (100 lists for 100K rows)
    add_index :articles, :embedding,
              using: :ivfflat,
              opclass: :vector_cosine_ops,
              options: 'WITH (lists = 100)'
  end
end

```

**Trade-off:** Faster queries, but may miss some nearest neighbors. Increase `lists` for accuracy, decrease for speed.

### HNSW Index (More Accurate, Requires pgvector 0.5+)

```ruby
add_index :articles, :embedding,
          using: :hnsw,
          opclass: :vector_cosine_ops,
          options: 'WITH (m = 16, ef_construction = 64)'

```

**Parameters:**
- `m`: Max connections per layer (higher = more accurate, slower writes)
- `ef_construction`: Build-time search depth (higher = better index quality)

**Query-time tuning:**

```ruby
# Increase recall at query time
Article.connection.execute("SET hnsw.ef_search = 100")

```

---

## Measuring Similarity Quality

### Embedding Quality Check

```ruby
# Check embedding distribution
Article.select("AVG(array_length(embedding, 1)) as avg_dimensions").first
# Should return 1536 for OpenAI ada-002

# Check for null embeddings
Article.where(embedding: nil).count

```

### Distance Distribution Analysis

```ruby
# Find distance range for tuning thresholds
article = Article.first
Article.select("embedding <=> '[#{article.embedding.join(',')}]' AS distance")
       .order("distance")
       .limit(100)
       .pluck(:distance)
# Distances typically range 0.0-1.0 for cosine

```

### A/B Test Relevance

```ruby
# Compare semantic vs keyword search CTR
class SearchLog < ApplicationRecord
  scope :semantic_searches, -> { where(search_type: 'semantic') }
  scope :keyword_searches, -> { where(search_type: 'keyword') }

  def self.click_through_rate
    where(clicked: true).count.to_f / count
  end
end

SearchLog.semantic_searches.click_through_rate
# vs
SearchLog.keyword_searches.click_through_rate

```

---

## Caching Strategies

### Cache Query Embeddings

```ruby
class ArticlesController < ApplicationController
  def search
    query = params[:q]
    cache_key = "query_embedding:#{Digest::SHA256.hexdigest(query)}"

    query_embedding = Rails.cache.fetch(cache_key, expires_in: 1.week) do
      response = OpenAI::Client.new.embeddings(
        parameters: { model: 'text-embedding-ada-002', input: query }
      )
      response.dig('data', 0, 'embedding')
    end

    @articles = Article.nearest_neighbors(:embedding, query_embedding).limit(10)
  end
end

```

### Async Embedding Generation

```ruby
class Article < ApplicationRecord
  after_commit :regenerate_embedding_async, if: :content_changed?

  private

  def regenerate_embedding_async
    GenerateEmbeddingJob.perform_later(self)
  end
end

class GenerateEmbeddingJob < ApplicationJob
  def perform(article)
    response = OpenAI::Client.new.embeddings(
      parameters: {
        model: 'text-embedding-ada-002',
        input: [article.title, article.body].join("\n")
      }
    )
    article.update_column(:embedding, response.dig('data', 0, 'embedding'))
  end
end

```

---

## Trade-offs Box
- **Advantage:** Semantic search understands meaning, improving relevance 2-5x over keyword search for natural language queries. pgvector keeps embeddings in PostgreSQL, avoiding external vector DB sync complexity.
- **Cost:** Embedding generation costs money (0.0001/1K tokens OpenAI) and adds latency (50-200ms per request). Indexes consume disk space (1536 floats × 4 bytes × row count). HNSW indexes slow down writes.
- **When to skip:** When exact keyword matching suffices (product SKUs, codes), datasets under 1,000 rows (full table scan is fast enough), or when embedding API costs exceed search value.

---

## Debugging Checklist

When implementing semantic search:

1. Verify pgvector extension: `SELECT * FROM pg_extension WHERE extname = 'vector'`
2. Check embedding dimensions: `SELECT array_length(embedding, 1) FROM articles LIMIT 1` should return 1536
3. Test distance calculation: Query with known similar content and verify distance < 0.5
4. Validate index usage: `EXPLAIN ANALYZE` should show "Index Scan using articles_embedding_idx"
5. Monitor embedding generation: Log API response times and error rates
6. Compare semantic vs keyword: A/B test CTR or relevance scores
7. Audit null embeddings: `Article.where(embedding: nil).count` should be zero in production
8. Check index parameters: Increase `lists` (IVFFlat) or `ef_search` (HNSW) if recall is low
9. Profile query performance: Semantic queries should complete in <100ms with indexes
10. Validate hybrid search weights: Adjust semantic vs keyword ratio based on user feedback

---

## One-Minute Recap
- Vector embeddings represent text as high-dimensional arrays capturing semantic meaning
- pgvector adds vector similarity search to PostgreSQL without external databases
- Use cosine distance (`<=>`) for OpenAI embeddings; L2 for custom models
- Generate embeddings once on create/update; cache query embeddings
- Hybrid search combines semantic similarity with keyword matching for best results
- Add IVFFlat or HNSW indexes for 10-100x faster queries on large datasets
- Recommendations: find similar content or aggregate user interest embeddings
- Cost: 0.0001 per 1K tokens; generate async to avoid blocking requests
