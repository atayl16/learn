# LLM API Integration Basics

## What It Is
LLM API integration involves connecting your Rails application to Large Language Model services like OpenAI (GPT-4) or Anthropic (Claude) to add AI-powered features. This includes managing API calls, handling streaming responses, optimizing token usage, implementing retry logic, and tracking costs — all while maintaining production reliability.

## Why It Matters
AI features are becoming table stakes for modern applications. Teams that understand LLM integration can ship features like content generation, intelligent search, code review automation, and chatbots in days instead of months. Production LLM integration requires managing costs (a single uncached GPT-4 call can cost $0.10), handling rate limits (429 errors), and optimizing latency (streaming responses vs. waiting 30 seconds for completion). Senior engineers understand these trade-offs and build resilient systems.

## When to Use
- Adding AI features: content generation, summarization, question answering, code analysis
- Building chatbots or conversational interfaces with context tracking
- Processing user input that requires understanding (sentiment analysis, intent classification)
- Automating tasks that need reasoning (bug triage, code review, documentation)
- Acceptable to skip: when deterministic algorithms work, when latency must be <100ms, when cost per request exceeds value

## Three Common Pitfalls
1. **Ignoring token limits:** GPT-4 has a 128K token context window, but each token costs money and increases latency. Sending entire documents without truncation can cost $5 per request and timeout. Always count tokens before making API calls and implement truncation strategies.
2. **Missing retry logic:** LLM APIs return 429 (rate limit) and 500 (overload) errors frequently, especially during peak hours. Without exponential backoff, your features fail in production. Implement retries with jitter and circuit breakers.
3. **Exposing API keys in client-side code:** Never send API keys to browsers or mobile apps. Always proxy requests through your Rails backend with authentication and rate limiting to prevent abuse and cost overruns.

---

## Setting Up API Clients

Both OpenAI and Anthropic provide official Ruby gems for integration.

### OpenAI Setup

```ruby
# Gemfile
gem 'ruby-openai'

# config/initializers/openai.rb
OpenAI.configure do |config|
  config.access_token = Rails.application.credentials.dig(:openai, :api_key)
  config.request_timeout = 60 # seconds
end
```

Store your API key securely:

```bash
bin/rails credentials:edit
# Add: openai: { api_key: "sk-..." }
```

### Anthropic Setup

```ruby
# Gemfile
gem 'anthropic'

# config/initializers/anthropic.rb
Anthropic.configure do |config|
  config.access_token = Rails.application.credentials.dig(:anthropic, :api_key)
end
```

Both gems handle HTTPS connections, JSON serialization, and basic error handling.

---

## Making Your First API Call

### OpenAI Example

```ruby
class ContentGenerator
  def initialize
    @client = OpenAI::Client.new
  end

  def generate_summary(text)
    response = @client.chat(
      parameters: {
        model: "gpt-4o",
        messages: [
          { role: "system", content: "You are a helpful assistant that summarizes text." },
          { role: "user", content: "Summarize this: #{text}" }
        ],
        max_tokens: 150,
        temperature: 0.7
      }
    )

    response.dig("choices", 0, "message", "content")
  end
end
```

### Anthropic Example

```ruby
class ContentGenerator
  def initialize
    @client = Anthropic::Client.new
  end

  def generate_summary(text)
    response = @client.messages(
      parameters: {
        model: "claude-3-5-sonnet-20241022",
        max_tokens: 150,
        messages: [
          { role: "user", content: "Summarize this: #{text}" }
        ]
      }
    )

    response.dig("content", 0, "text")
  end
end
```

Both APIs return structured JSON responses with the generated text nested inside.

---

## Prompt Engineering Best Practices

Effective prompts follow a consistent structure:

```ruby
class SmartAssistant
  SYSTEM_PROMPT = <<~PROMPT
    You are a Rails code reviewer. Analyze code for:
    - Security vulnerabilities (SQL injection, XSS, CSRF)
    - Performance issues (N+1 queries, missing indexes)
    - Best practices violations

    Format your response as JSON with this structure:
    {
      "issues": [{"severity": "high|medium|low", "description": "...", "line": 10}],
      "summary": "Overall assessment"
    }
  PROMPT

  def review_code(code)
    response = @client.chat(
      parameters: {
        model: "gpt-4o",
        messages: [
          { role: "system", content: SYSTEM_PROMPT },
          { role: "user", content: code }
        ],
        temperature: 0.2, # Lower temperature for consistent formatting
        response_format: { type: "json_object" }
      }
    )

    JSON.parse(response.dig("choices", 0, "message", "content"))
  rescue JSON::ParserError
    { "issues" => [], "summary" => "Failed to parse response" }
  end
end
```

**Key techniques:**
- **System prompts** define behavior and output format
- **Low temperature** (0-0.3) for consistent, factual responses
- **High temperature** (0.7-1.0) for creative, varied outputs
- **JSON mode** (`response_format: { type: "json_object" }`) ensures structured data
- **Few-shot examples** in system prompts improve accuracy

---

## Token Management & Cost Optimization

Tokens are the currency of LLM APIs. GPT-4 costs ~$0.01 per 1K input tokens and ~$0.03 per 1K output tokens.

### Counting Tokens

```ruby
# Gemfile
gem 'tiktoken_ruby'

class TokenCounter
  def initialize(model: "gpt-4")
    @encoder = Tiktoken.encoding_for_model(model)
  end

  def count(text)
    @encoder.encode(text).length
  end

  def truncate(text, max_tokens:)
    tokens = @encoder.encode(text)
    return text if tokens.length <= max_tokens

    truncated_tokens = tokens[0...max_tokens]
    @encoder.decode(truncated_tokens)
  end
end

# Usage
counter = TokenCounter.new
text = File.read("large_document.txt")
puts "Tokens: #{counter.count(text)}"

# Truncate to fit in context window
truncated = counter.truncate(text, max_tokens: 8000)
```

### Cost Tracking

```ruby
class LlmCall < ApplicationRecord
  # Schema: model, input_tokens, output_tokens, cost_usd, created_at

  PRICING = {
    "gpt-4o" => { input: 0.0025 / 1000, output: 0.01 / 1000 },
    "gpt-4o-mini" => { input: 0.00015 / 1000, output: 0.0006 / 1000 },
    "claude-3-5-sonnet-20241022" => { input: 0.003 / 1000, output: 0.015 / 1000 }
  }.freeze

  def self.track(model:, input_tokens:, output_tokens:)
    pricing = PRICING[model]
    cost = (input_tokens * pricing[:input]) + (output_tokens * pricing[:output])

    create!(
      model: model,
      input_tokens: input_tokens,
      output_tokens: output_tokens,
      cost_usd: cost
    )
  end

  def self.total_cost_today
    where("created_at >= ?", Time.current.beginning_of_day).sum(:cost_usd)
  end
end

# Track every API call
response = @client.chat(parameters: {...})
LlmCall.track(
  model: "gpt-4o",
  input_tokens: response.dig("usage", "prompt_tokens"),
  output_tokens: response.dig("usage", "completion_tokens")
)
```

### Caching Strategies

Cache expensive LLM calls to avoid repeat costs:

```ruby
class CachedLlmService
  def generate_summary(text)
    cache_key = "llm_summary:#{Digest::SHA256.hexdigest(text)}"

    Rails.cache.fetch(cache_key, expires_in: 24.hours) do
      raw_generate_summary(text)
    end
  end

  private

  def raw_generate_summary(text)
    # Actual API call
  end
end
```

---

## Error Handling & Retry Logic

LLM APIs are unreliable. Implement robust error handling:

```ruby
class ResilientLlmClient
  MAX_RETRIES = 3
  BASE_DELAY = 1 # second

  def call_with_retry(parameters)
    attempt = 0

    begin
      attempt += 1
      OpenAI::Client.new.chat(parameters: parameters)
    rescue Faraday::TooManyRequestsError => e
      # 429 Rate limit
      if attempt <= MAX_RETRIES
        delay = BASE_DELAY * (2 ** (attempt - 1)) + rand(0.0..1.0) # Exponential backoff with jitter
        Rails.logger.warn("Rate limited, retrying in #{delay}s (attempt #{attempt}/#{MAX_RETRIES})")
        sleep(delay)
        retry
      else
        Rails.logger.error("Rate limit exceeded after #{MAX_RETRIES} retries")
        raise
      end
    rescue Faraday::ServerError => e
      # 500-level errors
      if attempt <= MAX_RETRIES
        delay = BASE_DELAY * attempt
        Rails.logger.warn("Server error, retrying in #{delay}s")
        sleep(delay)
        retry
      else
        raise
      end
    rescue Faraday::TimeoutError => e
      Rails.logger.error("LLM request timed out: #{e.message}")
      raise
    end
  end
end
```

**Error categories:**
- **429 Rate Limit:** Exponential backoff with jitter (1s, 2s, 4s + random)
- **500 Server Error:** Retry up to 3 times with linear backoff
- **Timeout:** Fail fast and log for monitoring
- **Invalid Request:** Don't retry (400, 401, 403, 404)

---

## Rate Limiting & Circuit Breakers

Protect your app from cascading failures:

```ruby
# Gemfile
gem 'redis'
gem 'connection_pool'

class LlmRateLimiter
  def initialize(redis: Redis.new)
    @redis = redis
  end

  def check_and_increment(user_id, limit: 100, period: 3600)
    key = "llm_rate_limit:#{user_id}:#{Time.current.to_i / period}"
    count = @redis.incr(key)
    @redis.expire(key, period) if count == 1

    if count > limit
      raise RateLimitError, "User #{user_id} exceeded #{limit} requests per hour"
    end

    count
  end
end

# In controller
class AiController < ApplicationController
  before_action :check_rate_limit

  private

  def check_rate_limit
    LlmRateLimiter.new.check_and_increment(current_user.id, limit: 50)
  rescue RateLimitError => e
    render json: { error: e.message }, status: 429
  end
end
```

---

## Streaming Responses

For long-form content, stream responses to improve perceived latency:

```ruby
class StreamingController < ApplicationController
  include ActionController::Live

  def generate
    response.headers['Content-Type'] = 'text/event-stream'
    response.headers['Cache-Control'] = 'no-cache'

    client = OpenAI::Client.new

    client.chat(
      parameters: {
        model: "gpt-4o",
        messages: [{ role: "user", content: params[:prompt] }],
        stream: proc do |chunk, _bytesize|
          content = chunk.dig("choices", 0, "delta", "content")
          if content
            response.stream.write("data: #{content}\n\n")
          end
        end
      }
    )

    response.stream.write("data: [DONE]\n\n")
  ensure
    response.stream.close
  end
end
```

**Note:** Streaming requires Puma or Unicorn with sufficient workers to avoid blocking other requests.

---

## Trade-offs Box
- **Advantage:** LLM APIs unlock sophisticated AI features without training models, handling infrastructure, or hiring ML engineers. Integration takes days, not months.
- **Cost:** API calls are expensive ($0.01-$0.10 per request for GPT-4), unpredictable (token usage varies), and add latency (2-30 seconds). Requires careful budgeting and optimization.
- **When to skip:** When deterministic logic works (regex, rules engines), when you need <100ms response times, or when cost per user exceeds LTV.

---

## Debugging Checklist

When troubleshooting LLM integrations:

1. Log all API requests/responses during development (redact sensitive data in production)
2. Track token usage per endpoint to identify cost hotspots
3. Monitor error rates: 429s indicate rate limiting, 500s indicate provider issues
4. Test prompt quality: use LLM playground (OpenAI/Anthropic web UIs) before coding
5. Implement timeouts: set `request_timeout` to avoid hanging requests (30-60s max)
6. Validate responses: LLMs can return invalid JSON or unexpected formats
7. Cache aggressively: identical prompts should hit cache, not API
8. Set up alerts: track daily cost, error rate, p95 latency

---

## One-Minute Recap
- LLM APIs (OpenAI, Anthropic) add AI features to Rails apps via HTTP calls
- Prompt engineering: use system prompts, temperature control, and JSON mode for consistent outputs
- Token management: count tokens with tiktoken_ruby, truncate inputs, track costs per request
- Error handling: retry 429s with exponential backoff, fail fast on timeouts
- Rate limiting: protect your budget with per-user limits and circuit breakers
- Stream responses for better UX on long-form content generation
- Cache expensive calls and monitor costs daily to avoid budget overruns
