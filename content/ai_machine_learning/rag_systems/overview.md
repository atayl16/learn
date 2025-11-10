# RAG Systems in Rails

## What It Is
Retrieval-Augmented Generation (RAG) combines semantic search with large language models to answer questions using your own data. Instead of relying solely on an LLM's training data, RAG fetches relevant documents from a knowledge base, then feeds them as context to the LLM for generating accurate, grounded responses. The pipeline includes document ingestion, text chunking, vector embedding generation, similarity search, and context-aware generation.

## Why It Matters
RAG systems let you build AI features that answer questions about your specific domain—product documentation, customer support tickets, internal wikis—without fine-tuning expensive models. Vector search replaces keyword matching with semantic similarity, finding relevant content even when exact terms don't match. Production RAG systems power chatbots, documentation assistants, and AI-driven search features that scale to millions of documents while maintaining sub-second response times.

## When to Use
- Build a documentation chatbot that answers questions using your knowledge base
- Create AI-powered search that understands intent, not just keywords
- Implement customer support assistants that retrieve relevant help articles
- Generate summaries grounded in specific documents or data sets
- Augment LLM responses with real-time or proprietary data not in training sets

## Three Common Pitfalls
1. **Chunking documents too large or too small:** 2000-token chunks lose coherence; 50-token chunks lose context. Optimal size is 200-500 tokens with 10-20% overlap. Test retrieval accuracy with your actual data before scaling.
2. **Ignoring metadata filtering:** Searching all documents when users only need recent ones wastes compute and returns irrelevant results. Combine vector similarity with metadata filters (date, category, access control) in your queries.
3. **Skipping re-ranking:** Top-5 vector matches aren't always the best context. Use a cross-encoder or keyword hybrid to re-rank results before sending to the LLM, improving answer quality by 20-40%.

---

## RAG Architecture Overview

A production RAG system has two pipelines:

**Indexing Pipeline (offline):**
1. Ingest documents (PDFs, Markdown, HTML)
2. Split into chunks (paragraphs, sections)
3. Generate embeddings (vector representations)
4. Store in vector database with metadata

**Query Pipeline (online):**
1. User submits question
2. Generate query embedding
3. Search vector database for similar chunks
4. Retrieve top-k most relevant contexts
5. Construct prompt with context + question
6. Send to LLM, return generated answer

Rails handles both pipelines: background jobs for indexing, controllers/services for queries.

---

## Document Ingestion and Processing

Process various document types into plain text:

```ruby
# app/services/document_processor.rb
class DocumentProcessor
  def self.process(file_path)
    case File.extname(file_path)
    when '.pdf'
      extract_pdf_text(file_path)
    when '.md', '.markdown'
      File.read(file_path)
    when '.html'
      extract_html_text(file_path)
    else
      raise "Unsupported file type: #{File.extname(file_path)}"
    end
  end

  def self.extract_pdf_text(file_path)
    # Using pdf-reader gem
    require 'pdf-reader'
    reader = PDF::Reader.new(file_path)
    reader.pages.map(&:text).join("\n\n")
  end

  def self.extract_html_text(file_path)
    # Using nokogiri gem
    require 'nokogiri'
    doc = Nokogiri::HTML(File.read(file_path))
    doc.xpath('//text()').map(&:text).join(' ').gsub(/\s+/, ' ')
  end
end
```

Store documents with metadata:

```ruby
# app/models/document.rb
class Document < ApplicationRecord
  # Columns: title, content, source_url, category, indexed_at
  has_many :chunks, dependent: :destroy

  def self.ingest(file_path, metadata = {})
    content = DocumentProcessor.process(file_path)
    create!(
      title: metadata[:title] || File.basename(file_path),
      content: content,
      source_url: metadata[:url],
      category: metadata[:category]
    )
  end
end
```

---

## Text Chunking Strategies

Split long documents into retrievable chunks:

```ruby
# app/services/text_chunker.rb
class TextChunker
  DEFAULT_CHUNK_SIZE = 400  # tokens
  DEFAULT_OVERLAP = 50      # tokens

  def initialize(chunk_size: DEFAULT_CHUNK_SIZE, overlap: DEFAULT_OVERLAP)
    @chunk_size = chunk_size
    @overlap = overlap
  end

  def chunk(text)
    # Simple sentence-based chunking
    sentences = text.split(/(?<=[.!?])\s+/)
    chunks = []
    current_chunk = []
    current_size = 0

    sentences.each do |sentence|
      sentence_tokens = estimate_tokens(sentence)

      if current_size + sentence_tokens > @chunk_size && current_chunk.any?
        chunks << current_chunk.join(' ')

        # Keep overlap: retain last few sentences
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
    # Rough estimate: 1 token ≈ 4 characters for English
    (text.length / 4.0).ceil
  end
end
```

Create chunk records with embeddings:

```ruby
# app/models/chunk.rb
class Chunk < ApplicationRecord
  # Columns: document_id, content, embedding (vector), position
  belongs_to :document

  # Using pgvector for vector storage
  # Migration: add_column :chunks, :embedding, :vector, limit: 1536
end
```

---

## Generating Embeddings

Use OpenAI's embedding API (or alternatives like Cohere, Voyage):

```ruby
# app/services/embedding_service.rb
class EmbeddingService
  EMBEDDING_MODEL = 'text-embedding-3-small'  # 1536 dimensions
  BATCH_SIZE = 100

  def initialize(api_key: ENV['OPENAI_API_KEY'])
    @client = OpenAI::Client.new(access_token: api_key)
  end

  def generate_embedding(text)
    response = @client.embeddings(
      parameters: {
        model: EMBEDDING_MODEL,
        input: text
      }
    )
    response.dig('data', 0, 'embedding')
  end

  def generate_batch(texts)
    response = @client.embeddings(
      parameters: {
        model: EMBEDDING_MODEL,
        input: texts.first(BATCH_SIZE)
      }
    )
    response['data'].map { |d| d['embedding'] }
  end
end
```

Background job for indexing documents:

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

---

## Vector Search with pgvector

Install and configure pgvector in PostgreSQL:

```ruby
# db/migrate/20240101000001_enable_pgvector.rb
class EnablePgvector < ActiveRecord::Migration[7.1]
  def change
    enable_extension 'vector'
  end
end

# db/migrate/20240101000002_add_vector_to_chunks.rb
class AddVectorToChunks < ActiveRecord::Migration[7.1]
  def change
    add_column :chunks, :embedding, :vector, limit: 1536
    add_index :chunks, :embedding, using: :ivfflat, opclass: :vector_cosine_ops
  end
end
```

Implement similarity search:

```ruby
# app/models/chunk.rb
class Chunk < ApplicationRecord
  belongs_to :document

  # Find similar chunks using cosine similarity
  def self.search(query_embedding, limit: 5, metadata_filters: {})
    relation = all

    # Apply metadata filters
    if metadata_filters[:category].present?
      relation = relation.joins(:document).where(documents: { category: metadata_filters[:category] })
    end

    if metadata_filters[:after].present?
      relation = relation.joins(:document).where('documents.created_at > ?', metadata_filters[:after])
    end

    # Vector similarity search using cosine distance
    relation
      .select("chunks.*, (embedding <=> '#{query_embedding}') AS distance")
      .order('distance ASC')
      .limit(limit)
  end

  # Alternative: using L2 distance (Euclidean)
  def self.search_l2(query_embedding, limit: 5)
    select("chunks.*, (embedding <-> '#{query_embedding}') AS distance")
      .order('distance ASC')
      .limit(limit)
  end
end
```

---

## Query Pipeline

Retrieve relevant chunks for a user question:

```ruby
# app/services/rag_retriever.rb
class RagRetriever
  def initialize(embedding_service: EmbeddingService.new)
    @embedding_service = embedding_service
  end

  def retrieve(query, top_k: 5, filters: {})
    # Generate query embedding
    query_embedding = @embedding_service.generate_embedding(query)

    # Search for similar chunks
    results = Chunk.search(query_embedding, limit: top_k, metadata_filters: filters)

    # Return chunks with similarity scores
    results.map do |chunk|
      {
        content: chunk.content,
        document_title: chunk.document.title,
        similarity: 1 - chunk.distance,  # Convert distance to similarity
        metadata: {
          source_url: chunk.document.source_url,
          category: chunk.document.category
        }
      }
    end
  end
end
```

---

## Combining Retrieval with Generation

Build prompts with retrieved context and send to LLM:

```ruby
# app/services/rag_service.rb
class RagService
  def initialize(
    retriever: RagRetriever.new,
    llm_client: OpenAI::Client.new(access_token: ENV['OPENAI_API_KEY'])
  )
    @retriever = retriever
    @llm_client = llm_client
  end

  def answer(question, filters: {})
    # Retrieve relevant chunks
    contexts = @retriever.retrieve(question, top_k: 5, filters: filters)

    # Build prompt with context
    prompt = build_prompt(question, contexts)

    # Generate answer
    response = @llm_client.chat(
      parameters: {
        model: 'gpt-4-turbo-preview',
        messages: [
          { role: 'system', content: system_prompt },
          { role: 'user', content: prompt }
        ],
        temperature: 0.3  # Lower temperature for factual responses
      }
    )

    {
      answer: response.dig('choices', 0, 'message', 'content'),
      sources: contexts.map { |c| c[:metadata] }.uniq
    }
  end

  private

  def system_prompt
    <<~PROMPT
      You are a helpful assistant that answers questions based on the provided context.
      Use only the information from the context to answer questions.
      If the context doesn't contain enough information, say so clearly.
      Cite sources when possible by mentioning the document title.
    PROMPT
  end

  def build_prompt(question, contexts)
    context_text = contexts.map.with_index do |ctx, i|
      "Source #{i + 1} (#{ctx[:document_title]}):\n#{ctx[:content]}"
    end.join("\n\n---\n\n")

    <<~PROMPT
      Context:
      #{context_text}

      Question: #{question}

      Please provide a clear, accurate answer based on the context above.
    PROMPT
  end
end
```

---

## Controller Integration

Expose RAG as an API endpoint:

```ruby
# app/controllers/api/v1/rag_controller.rb
module Api
  module V1
    class RagController < ApplicationController
      def query
        question = params[:question]
        filters = {
          category: params[:category],
          after: params[:after_date]
        }

        rag_service = RagService.new
        result = rag_service.answer(question, filters: filters)

        render json: {
          answer: result[:answer],
          sources: result[:sources]
        }
      rescue StandardError => e
        render json: { error: e.message }, status: :unprocessable_entity
      end
    end
  end
end

# config/routes.rb
namespace :api do
  namespace :v1 do
    post 'rag/query', to: 'rag#query'
  end
end
```

---

## Advanced: Hybrid Search

Combine vector similarity with keyword search:

```ruby
# app/services/hybrid_retriever.rb
class HybridRetriever
  def retrieve(query, top_k: 5)
    # Vector search
    embedding = EmbeddingService.new.generate_embedding(query)
    vector_results = Chunk.search(embedding, limit: top_k * 2)

    # Keyword search (full-text)
    keyword_results = Chunk
      .joins(:document)
      .where("chunks.content ILIKE ? OR documents.title ILIKE ?", "%#{query}%", "%#{query}%")
      .limit(top_k * 2)

    # Combine and re-rank using RRF (Reciprocal Rank Fusion)
    combined = reciprocal_rank_fusion(
      vector_results.to_a,
      keyword_results.to_a,
      k: 60
    )

    combined.first(top_k)
  end

  private

  def reciprocal_rank_fusion(list1, list2, k: 60)
    scores = Hash.new(0)

    list1.each_with_index do |chunk, rank|
      scores[chunk.id] += 1.0 / (k + rank + 1)
    end

    list2.each_with_index do |chunk, rank|
      scores[chunk.id] += 1.0 / (k + rank + 1)
    end

    # Sort by combined score
    all_chunks = (list1 + list2).uniq(&:id)
    all_chunks.sort_by { |chunk| -scores[chunk.id] }
  end
end
```

---

## Monitoring and Optimization

Track retrieval quality and performance:

```ruby
# app/models/rag_query_log.rb
class RagQueryLog < ApplicationRecord
  # Columns: query, answer, contexts_count, response_time_ms, user_feedback

  def self.track(query, answer, contexts, duration)
    create!(
      query: query,
      answer: answer,
      contexts_count: contexts.size,
      response_time_ms: (duration * 1000).round
    )
  end
end

# In RagService
def answer(question, filters: {})
  start_time = Time.current

  # ... existing logic ...

  result = {
    answer: answer_text,
    sources: contexts.map { |c| c[:metadata] }.uniq
  }

  RagQueryLog.track(question, answer_text, contexts, Time.current - start_time)

  result
end
```

---

## Trade-offs Box
- **Advantage:** RAG grounds LLM responses in your data without fine-tuning; updates are instant (re-index documents); vector search finds semantic matches that keyword search misses.
- **Cost:** Requires vector database infrastructure (pgvector, Pinecone); embedding API costs scale with document count; query latency increases with retrieval overhead (embedding generation + search).
- **When to skip:** For simple keyword search, use PostgreSQL full-text search; for questions not needing external context, skip retrieval and use LLM directly.

---

## Debugging Checklist

When RAG answers are poor:

1. Check chunk retrieval: Are returned chunks actually relevant?
2. Verify embedding quality: Test query embedding similarity to known good chunks
3. Review chunk size: Too large = loss of precision; too small = loss of context
4. Inspect prompt construction: Is context being passed correctly to LLM?
5. Test with different top-k values: More context isn't always better
6. Monitor token limits: Ensure context + question fit within model's context window
7. Check metadata filters: Overly restrictive filters may exclude good results
8. Measure end-to-end latency: Optimize slowest component (embedding, search, LLM)

---

## One-Minute Recap
- RAG combines vector search and LLMs to answer questions using your knowledge base
- Pipeline: chunk documents, generate embeddings, store vectors, retrieve similar chunks, generate answer
- Use pgvector for vector storage in PostgreSQL with cosine similarity search
- Chunk size of 200-500 tokens with 10-20% overlap balances context and precision
- Combine retrieval with metadata filtering for better accuracy and access control
- Hybrid search (vector + keyword) outperforms pure vector search for many use cases
