# Exercise: RAG Systems in Rails

## Objective
Build a complete RAG system that ingests markdown documentation, generates embeddings, stores vectors in PostgreSQL with pgvector, and answers questions using retrieved context with an LLM.

## Task
In a Rails app with PostgreSQL and OpenAI API access:

1. Set up pgvector extension for vector storage
2. Create models for documents and chunks with embeddings
3. Implement document chunking and embedding generation
4. Build a retrieval service using cosine similarity search
5. Create a RAG service that combines retrieval with GPT-4
6. Test with sample documentation and queries

## Acceptance Criteria
- [ ] PostgreSQL pgvector extension enabled
- [ ] `Document` and `Chunk` models with vector column
- [ ] Text chunker splits documents into 300-token chunks with 50-token overlap
- [ ] Embedding service generates OpenAI embeddings (1536 dimensions)
- [ ] Vector search returns top-5 similar chunks using cosine distance
- [ ] RAG service builds prompts with context and queries GPT-4
- [ ] API endpoint `/api/v1/rag/query` accepts questions and returns answers with sources

## Verification Steps

1. Create and index a sample document:

```ruby
# In Rails console
doc = Document.create!(
  title: "Rails Caching Guide",
  content: File.read("docs/caching.md"),
  category: "documentation"
)

IndexDocumentJob.perform_now(doc.id)

# Verify chunks created
doc.chunks.count  # Should be > 0
doc.chunks.first.embedding.present?  # Should be true
```

2. Test vector search:

```ruby
# Generate query embedding
service = EmbeddingService.new
query_embedding = service.generate_embedding("How does fragment caching work?")

# Search for similar chunks
results = Chunk.search(query_embedding, limit: 5)
results.each do |chunk|
  puts "Distance: #{chunk.distance.round(4)}"
  puts chunk.content[0..100]
  puts "---"
end
```

3. Test RAG query:

```bash
curl -X POST http://localhost:3000/api/v1/rag/query \
  -H "Content-Type: application/json" \
  -d '{
    "question": "What are the benefits of fragment caching in Rails?"
  }'
```

Expected response:

```json
{
  "answer": "Fragment caching in Rails provides several benefits...",
  "sources": [
    {
      "source_url": "https://guides.rubyonrails.org/caching",
      "category": "documentation"
    }
  ]
}
```

## Setup Code

### Step 1: Install Dependencies

```bash
# Gemfile
bundle add pgvector
bundle add ruby-openai
bundle add pdf-reader  # For PDF processing (optional)

bundle install
```

### Step 2: Enable pgvector Extension

```bash
bin/rails generate migration EnablePgvector
```

```ruby
# db/migrate/XXXXXX_enable_pgvector.rb
class EnablePgvector < ActiveRecord::Migration[7.1]
  def change
    enable_extension 'vector'
  end
end
```

### Step 3: Create Models

```bash
bin/rails generate model Document title:string content:text source_url:string category:string indexed_at:datetime
bin/rails generate model Chunk document:references content:text position:integer
```

Add vector column:

```bash
bin/rails generate migration AddEmbeddingToChunks
```

```ruby
# db/migrate/XXXXXX_add_embedding_to_chunks.rb
class AddEmbeddingToChunks < ActiveRecord::Migration[7.1]
  def change
    add_column :chunks, :embedding, :vector, limit: 1536
    add_index :chunks, :embedding, using: :ivfflat, opclass: :vector_cosine_ops
  end
end
```

Run migrations:

```bash
bin/rails db:migrate
```

### Step 4: Implement Models

```ruby
# app/models/document.rb
class Document < ApplicationRecord
  has_many :chunks, dependent: :destroy

  validates :title, presence: true
  validates :content, presence: true
end

# app/models/chunk.rb
class Chunk < ApplicationRecord
  belongs_to :document

  def self.search(query_embedding, limit: 5, metadata_filters: {})
    relation = all

    if metadata_filters[:category].present?
      relation = relation.joins(:document)
        .where(documents: { category: metadata_filters[:category] })
    end

    relation
      .select("chunks.*, (embedding <=> '[#{query_embedding.join(',')}]') AS distance")
      .order('distance ASC')
      .limit(limit)
  end
end
```

### Step 5: Create Services

```ruby
# app/services/text_chunker.rb
class TextChunker
  def initialize(chunk_size: 300, overlap: 50)
    @chunk_size = chunk_size
    @overlap = overlap
  end

  def chunk(text)
    sentences = text.split(/(?<=[.!?])\s+/)
    chunks = []
    current_chunk = []
    current_size = 0

    sentences.each do |sentence|
      sentence_tokens = estimate_tokens(sentence)

      if current_size + sentence_tokens > @chunk_size && current_chunk.any?
        chunks << current_chunk.join(' ')

        # Keep overlap
        overlap_sentences = []
        overlap_size = 0
        current_chunk.reverse.each do |s|
          s_tokens = estimate_tokens(s)
          break if overlap_size + s_tokens > @overlap
          overlap_sentences.unshift(s)
          overlap_size += s_tokens
        end

        current_chunk = overlap_sentences
        current_size = overlap_size
      end

      current_chunk << sentence
      current_size += sentence_tokens
    end

    chunks << current_chunk.join(' ') if current_chunk.any?
    chunks
  end

  private

  def estimate_tokens(text)
    (text.length / 4.0).ceil
  end
end

# app/services/embedding_service.rb
class EmbeddingService
  def initialize
    @client = OpenAI::Client.new(access_token: ENV['OPENAI_API_KEY'])
  end

  def generate_embedding(text)
    response = @client.embeddings(
      parameters: {
        model: 'text-embedding-3-small',
        input: text
      }
    )
    response.dig('data', 0, 'embedding')
  end
end

# app/services/rag_retriever.rb
class RagRetriever
  def initialize(embedding_service: EmbeddingService.new)
    @embedding_service = embedding_service
  end

  def retrieve(query, top_k: 5, filters: {})
    query_embedding = @embedding_service.generate_embedding(query)

    results = Chunk.search(query_embedding, limit: top_k, metadata_filters: filters)

    results.map do |chunk|
      {
        content: chunk.content,
        document_title: chunk.document.title,
        similarity: 1 - chunk.distance,
        metadata: {
          source_url: chunk.document.source_url,
          category: chunk.document.category
        }
      }
    end
  end
end

# app/services/rag_service.rb
class RagService
  def initialize
    @retriever = RagRetriever.new
    @llm_client = OpenAI::Client.new(access_token: ENV['OPENAI_API_KEY'])
  end

  def answer(question, filters: {})
    contexts = @retriever.retrieve(question, top_k: 5, filters: filters)
    prompt = build_prompt(question, contexts)

    response = @llm_client.chat(
      parameters: {
        model: 'gpt-4-turbo-preview',
        messages: [
          { role: 'system', content: system_prompt },
          { role: 'user', content: prompt }
        ],
        temperature: 0.3
      }
    )

    {
      answer: response.dig('choices', 0, 'message', 'content'),
      sources: contexts.map { |c| c[:metadata] }.uniq
    }
  end

  private

  def system_prompt
    "You are a helpful assistant that answers questions based on provided context. "\
    "Use only the information from the context. If insufficient information is available, say so."
  end

  def build_prompt(question, contexts)
    context_text = contexts.map.with_index do |ctx, i|
      "Source #{i + 1} (#{ctx[:document_title]}):\n#{ctx[:content]}"
    end.join("\n\n---\n\n")

    "Context:\n#{context_text}\n\nQuestion: #{question}\n\n"\
    "Please provide a clear answer based on the context above."
  end
end
```

### Step 6: Create Background Job

```ruby
# app/jobs/index_document_job.rb
class IndexDocumentJob < ApplicationJob
  queue_as :default

  def perform(document_id)
    document = Document.find(document_id)
    chunker = TextChunker.new
    embedding_service = EmbeddingService.new

    chunks = chunker.chunk(document.content)

    chunks.each_with_index do |chunk_text, index|
      embedding = embedding_service.generate_embedding(chunk_text)

      document.chunks.create!(
        content: chunk_text,
        embedding: embedding,
        position: index
      )
    end

    document.update!(indexed_at: Time.current)
  end
end
```

### Step 7: Create Controller and Routes

```ruby
# app/controllers/api/v1/rag_controller.rb
module Api
  module V1
    class RagController < ApplicationController
      skip_before_action :verify_authenticity_token

      def query
        question = params[:question]

        return render json: { error: 'Question required' }, status: :bad_request if question.blank?

        filters = {
          category: params[:category]
        }.compact

        rag_service = RagService.new
        result = rag_service.answer(question, filters: filters)

        render json: result
      rescue StandardError => e
        render json: { error: e.message }, status: :unprocessable_entity
      end
    end
  end
end

# config/routes.rb
Rails.application.routes.draw do
  namespace :api do
    namespace :v1 do
      post 'rag/query', to: 'rag#query'
    end
  end
end
```

### Step 8: Set Environment Variables

```bash
# .env (or set in your environment)
export OPENAI_API_KEY=sk-your-api-key-here
```

### Step 9: Create Sample Data

Create `docs/caching.md`:

```markdown
# Rails Caching Guide

Fragment caching is a powerful Rails feature that caches portions of views.
Unlike page caching, fragment caching allows you to cache specific parts while
keeping other sections dynamic.

## Benefits

Fragment caching reduces database queries and view rendering time. It's especially
useful for expensive computations or complex partials that don't change frequently.

## Example

```erb
<% cache @product do %>
  <%= render @product %>
<% end %>
```

This caches the product partial. Rails automatically expires the cache when
the product updates using the cache key.
```

Index the document:

```ruby
# Rails console
doc = Document.create!(
  title: "Rails Caching Guide",
  content: File.read("docs/caching.md"),
  category: "documentation",
  source_url: "https://guides.rubyonrails.org/caching"
)

IndexDocumentJob.perform_now(doc.id)
```

## Stretch (Optional)

1. **Add metadata filtering by date:**

```ruby
def query
  filters = {
    category: params[:category],
    after: params[:after_date] ? Date.parse(params[:after_date]) : nil
  }.compact

  # In Chunk.search, add:
  # relation = relation.where('documents.created_at > ?', metadata_filters[:after]) if metadata_filters[:after]
end
```

2. **Implement hybrid search (vector + keyword):**

```ruby
# In Chunk model
def self.hybrid_search(query_embedding, query_text, limit: 5)
  vector_results = search(query_embedding, limit: limit * 2)
  keyword_results = where("content ILIKE ?", "%#{query_text}%").limit(limit * 2)

  # Combine using Reciprocal Rank Fusion
  # ... implementation from overview.md
end
```

3. **Add query logging and analytics:**

```bash
bin/rails generate model RagQueryLog query:text answer:text contexts_count:integer response_time_ms:integer user_feedback:integer
```

Track each query for analysis and improvement.

## Time Estimate
28 minutes
