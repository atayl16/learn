# Exercise: LLM API Integration Basics

## Objective
Build a Rails API endpoint that integrates OpenAI's GPT-4 to generate article summaries with token tracking, error handling, and cost monitoring.

## Task
In a Rails app that manages articles:

1. Set up OpenAI API credentials securely using Rails encrypted credentials
2. Create a service object that calls GPT-4 to generate article summaries
3. Implement token counting and cost tracking in the database
4. Add retry logic with exponential backoff for rate limit errors
5. Build a controller endpoint that returns summaries with cost metadata
6. Test the integration with a real API call and verify cost tracking

## Acceptance Criteria
- [ ] OpenAI API key stored in `rails credentials:edit` and loaded in initializer
- [ ] `ArticleSummarizerService` generates summaries using GPT-4 API
- [ ] Token usage (input/output) tracked in `llm_calls` table for every request
- [ ] Retry logic handles 429 errors with exponential backoff (3 attempts max)
- [ ] `/api/articles/:id/summarize` endpoint returns summary and cost data
- [ ] Integration test proves end-to-end flow works with mock or real API
- [ ] Logs show token count, cost, and retry attempts

## Verification Steps

1. After setup, run the endpoint and check logs:

```
Started POST "/api/articles/1/summarize"
ArticleSummarizerService: Sending request to GPT-4 (2,450 input tokens)
ArticleSummarizerService: Received response (145 output tokens, cost: $0.0104)
LlmCall created: #<LlmCall id: 1, model: "gpt-4o", cost_usd: 0.0104>
Completed 200 OK in 3842ms
```

2. Verify database tracking:

```ruby
rails console
> LlmCall.last
=> #<LlmCall id: 1, model: "gpt-4o", input_tokens: 2450, output_tokens: 145, cost_usd: 0.0104>
> LlmCall.total_cost_today
=> 0.0104
```

3. Test retry logic by triggering a 429 error (simulate or wait for real rate limit):

```
ArticleSummarizerService: Rate limited, retrying in 1.3s (attempt 1/3)
ArticleSummarizerService: Rate limited, retrying in 2.7s (attempt 2/3)
ArticleSummarizerService: Success on attempt 3
```

## Setup Code

### Step 1: Create Rails App & Models

```bash
rails new llm_demo --api --database=postgresql
cd llm_demo
bin/rails generate model Article title:string body:text
bin/rails generate model LlmCall model:string input_tokens:integer output_tokens:integer cost_usd:decimal
bin/rails db:create db:migrate
```

Add sample data in `db/seeds.rb`:

```ruby
Article.create!(
  title: "The Future of Ruby on Rails",
  body: <<~TEXT
    Ruby on Rails continues to evolve in 2024 with major improvements in performance,
    developer experience, and modern infrastructure support. The framework now ships with
    import maps by default, eliminating the need for webpack in many applications.
    ActionCable has been enhanced to support modern real-time features without additional
    dependencies. Hotwire (Turbo and Stimulus) has become the recommended approach for
    building interactive user interfaces, replacing the older UJS approach. Rails 7.1
    introduced asynchronous query loading, which allows developers to run multiple database
    queries in parallel, significantly reducing page load times. The ActiveRecord query
    interface has been enhanced with new methods like `sole` and `in_order_of`. Docker
    support has been improved with official Dockerfiles generated for new projects. The
    community has embraced modern deployment patterns with tools like Kamal for zero-downtime
    deployments. Performance benchmarks show Rails 7.1 is 15% faster than previous versions
    for typical CRUD operations. The framework's stability and convention-over-configuration
    philosophy continue to make it a top choice for startups and enterprises alike.
  TEXT
)

puts "Created #{Article.count} article(s)"
```

Run seeds:

```bash
bin/rails db:seed
```

### Step 2: Install Dependencies

```bash
bundle add ruby-openai
bundle add tiktoken_ruby  # For token counting
```

### Step 3: Configure OpenAI API

Store API key securely:

```bash
bin/rails credentials:edit
```

Add this content:

```yaml
openai:
  api_key: sk-your-actual-api-key-here
```

Create initializer `config/initializers/openai.rb`:

```ruby
OpenAI.configure do |config|
  config.access_token = Rails.application.credentials.dig(:openai, :api_key)
  config.request_timeout = 60
  config.log_errors = true
end
```

### Step 4: Create LlmCall Model with Cost Tracking

Edit `app/models/llm_call.rb`:

```ruby
class LlmCall < ApplicationRecord
  PRICING = {
    "gpt-4o" => { input: 0.0025 / 1000, output: 0.01 / 1000 },
    "gpt-4o-mini" => { input: 0.00015 / 1000, output: 0.0006 / 1000 }
  }.freeze

  validates :model, :input_tokens, :output_tokens, :cost_usd, presence: true

  def self.track(model:, input_tokens:, output_tokens:)
    pricing = PRICING[model] || { input: 0, output: 0 }
    cost = (input_tokens * pricing[:input]) + (output_tokens * pricing[:output])

    create!(
      model: model,
      input_tokens: input_tokens,
      output_tokens: output_tokens,
      cost_usd: cost.round(6)
    )
  end

  def self.total_cost_today
    where("created_at >= ?", Time.current.beginning_of_day).sum(:cost_usd)
  end

  def self.total_cost_this_month
    where("created_at >= ?", Time.current.beginning_of_month).sum(:cost_usd)
  end
end
```

### Step 5: Build ArticleSummarizerService

Create `app/services/article_summarizer_service.rb`:

```ruby
class ArticleSummarizerService
  MAX_RETRIES = 3
  BASE_DELAY = 1.0

  def initialize(article)
    @article = article
    @client = OpenAI::Client.new
    @encoder = Tiktoken.encoding_for_model("gpt-4")
  end

  def call
    input_text = build_prompt
    input_tokens = count_tokens(input_text)

    Rails.logger.info("ArticleSummarizerService: Sending request (#{input_tokens} input tokens)")

    response = call_with_retry(input_text)
    output_text = response.dig("choices", 0, "message", "content")
    output_tokens = response.dig("usage", "completion_tokens")

    # Track cost
    llm_call = LlmCall.track(
      model: "gpt-4o",
      input_tokens: input_tokens,
      output_tokens: output_tokens
    )

    Rails.logger.info("ArticleSummarizerService: Response received (#{output_tokens} tokens, $#{llm_call.cost_usd})")

    {
      summary: output_text,
      metadata: {
        input_tokens: input_tokens,
        output_tokens: output_tokens,
        cost_usd: llm_call.cost_usd,
        model: "gpt-4o"
      }
    }
  end

  private

  def build_prompt
    <<~PROMPT
      Summarize this article in 2-3 sentences. Focus on the main points and key takeaways.

      Title: #{@article.title}

      Body:
      #{@article.body}
    PROMPT
  end

  def count_tokens(text)
    @encoder.encode(text).length
  end

  def call_with_retry(input_text)
    attempt = 0

    begin
      attempt += 1

      @client.chat(
        parameters: {
          model: "gpt-4o",
          messages: [
            { role: "system", content: "You are a helpful assistant that creates concise summaries." },
            { role: "user", content: input_text }
          ],
          max_tokens: 200,
          temperature: 0.5
        }
      )
    rescue Faraday::TooManyRequestsError => e
      if attempt <= MAX_RETRIES
        delay = BASE_DELAY * (2 ** (attempt - 1)) + rand(0.0..1.0)
        Rails.logger.warn("ArticleSummarizerService: Rate limited, retrying in #{delay.round(1)}s (attempt #{attempt}/#{MAX_RETRIES})")
        sleep(delay)
        retry
      else
        Rails.logger.error("ArticleSummarizerService: Rate limit exceeded after #{MAX_RETRIES} retries")
        raise
      end
    rescue Faraday::ServerError => e
      if attempt <= MAX_RETRIES
        delay = BASE_DELAY * attempt
        Rails.logger.warn("ArticleSummarizerService: Server error, retrying in #{delay}s")
        sleep(delay)
        retry
      else
        Rails.logger.error("ArticleSummarizerService: Server error after #{MAX_RETRIES} retries")
        raise
      end
    end
  end
end
```

### Step 6: Create API Controller

```bash
bin/rails generate controller Api::Articles
```

Edit `app/controllers/api/articles_controller.rb`:

```ruby
module Api
  class ArticlesController < ApplicationController
    def summarize
      article = Article.find(params[:id])
      result = ArticleSummarizerService.new(article).call

      render json: {
        article: {
          id: article.id,
          title: article.title
        },
        summary: result[:summary],
        metadata: result[:metadata]
      }
    rescue ActiveRecord::RecordNotFound
      render json: { error: "Article not found" }, status: :not_found
    rescue StandardError => e
      Rails.logger.error("Summarization failed: #{e.message}")
      render json: { error: "Failed to generate summary" }, status: :internal_server_error
    end
  end
end
```

Add route in `config/routes.rb`:

```ruby
Rails.application.routes.draw do
  namespace :api do
    resources :articles, only: [] do
      member do
        post :summarize
      end
    end
  end
end
```

### Step 7: Test the Integration

Start the server:

```bash
bin/rails server
```

Make a request:

```bash
curl -X POST http://localhost:3000/api/articles/1/summarize
```

Expected response:

```json
{
  "article": {
    "id": 1,
    "title": "The Future of Ruby on Rails"
  },
  "summary": "Ruby on Rails in 2024 has significantly improved with Hotwire becoming the standard for interactive UIs, import maps replacing webpack, and Rails 7.1 introducing asynchronous query loading for faster performance. The framework now offers better Docker support, modern deployment tools like Kamal, and is 15% faster than previous versions. Rails continues to be a top choice for both startups and enterprises due to its stability and convention-over-configuration approach.",
  "metadata": {
    "input_tokens": 245,
    "output_tokens": 89,
    "cost_usd": 0.001503,
    "model": "gpt-4o"
  }
}
```

### Step 8: Verify Cost Tracking

```bash
bin/rails console
```

In console:

```ruby
# Check latest call
puts LlmCall.last.attributes

# Check total costs
puts "Today's cost: $#{LlmCall.total_cost_today}"
puts "This month: $#{LlmCall.total_cost_this_month}"

# Analyze token usage
puts "Average input tokens: #{LlmCall.average(:input_tokens).round(0)}"
puts "Average output tokens: #{LlmCall.average(:output_tokens).round(0)}"
```

### Step 9: Write Integration Test

Create `test/integration/article_summarization_test.rb`:

```ruby
require 'test_helper'

class ArticleSummarizationTest < ActionDispatch::IntegrationTest
  test "summarize article returns summary with metadata" do
    article = Article.create!(
      title: "Test Article",
      body: "This is a test article body with some content to summarize."
    )

    # Mock OpenAI response to avoid real API calls in tests
    mock_response = {
      "choices" => [
        { "message" => { "content" => "This is a test summary." } }
      ],
      "usage" => {
        "prompt_tokens" => 50,
        "completion_tokens" => 10
      }
    }

    OpenAI::Client.any_instance.stubs(:chat).returns(mock_response)

    post api_article_summarize_path(article)

    assert_response :success

    json = JSON.parse(response.body)
    assert_equal "This is a test summary.", json["summary"]
    assert_equal 50, json["metadata"]["input_tokens"]
    assert_equal 10, json["metadata"]["output_tokens"]
    assert json["metadata"]["cost_usd"].positive?
  end

  test "returns error when article not found" do
    post api_article_summarize_path(id: 9999)

    assert_response :not_found
    assert_equal "Article not found", JSON.parse(response.body)["error"]
  end
end
```

Run tests:

```bash
bin/rails test test/integration/article_summarization_test.rb
```

## Stretch (Optional)

1. **Add caching to avoid repeat API calls:**

```ruby
def call
  cache_key = "article_summary:#{@article.id}:#{@article.updated_at.to_i}"

  Rails.cache.fetch(cache_key, expires_in: 24.hours) do
    generate_summary
  end
end
```

2. **Implement streaming for real-time summary generation:**

```ruby
# In controller
def summarize_stream
  response.headers['Content-Type'] = 'text/event-stream'

  @client.chat(
    parameters: {
      model: "gpt-4o",
      messages: [...],
      stream: proc do |chunk, _bytesize|
        content = chunk.dig("choices", 0, "delta", "content")
        response.stream.write("data: #{content}\n\n") if content
      end
    }
  )
ensure
  response.stream.close
end
```

3. **Add per-user rate limiting:**

```ruby
class RateLimitMiddleware
  def initialize(app)
    @app = app
    @redis = Redis.new
  end

  def call(env)
    user_id = extract_user_id(env)
    key = "llm_rate_limit:#{user_id}:#{Time.current.hour}"

    count = @redis.incr(key)
    @redis.expire(key, 3600) if count == 1

    if count > 10
      return [429, {}, ["Rate limit exceeded"]]
    end

    @app.call(env)
  end
end
```

## Time Estimate
25 minutes
