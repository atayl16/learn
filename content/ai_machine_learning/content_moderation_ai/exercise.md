# Exercise: Build a Content Moderation System with LLMs

## Objective
Build a working content moderation system for a blog comment platform using OpenAI's API. Implement auto-moderation with confidence thresholds, async processing, caching, and a human review queue.

## Task
Create a Rails application that:

1. Accepts user comments with async moderation
2. Classifies comments using LLM with structured JSON output
3. Auto-approves safe content, auto-rejects violations, queues uncertain cases
4. Caches moderation results to avoid duplicate API calls
5. Provides a moderation dashboard for human review
6. Tracks accuracy metrics (false positives/negatives)

## Acceptance Criteria
- [ ] Comments are created with "pending" status and moderated in background job
- [ ] LLM returns structured JSON with safe, violations, confidence, and reason fields
- [ ] Auto-approve if safe=true and confidence > 0.8
- [ ] Auto-reject if safe=false and confidence > 0.9
- [ ] Queue for human review if confidence between 0.5-0.9
- [ ] Identical content uses cached moderation results (no redundant API calls)
- [ ] Moderation dashboard shows pending reviews sorted by risk score
- [ ] Track and display false positive/negative rates from human overrides
- [ ] All moderation decisions are logged with timestamps and AI reasoning

## Verification Steps

Test the moderation flow:

```bash
# Create test comments
rails console

# Safe comment (should auto-approve)
Comment.create(body: "Great article! Thanks for sharing this tutorial.", author: "Alice")
# Check: moderation_status should be "approved", confidence > 0.8

# Spam comment (should auto-reject)
Comment.create(body: "Buy cheap watches now! Visit my-store-link.com for deals!!!", author: "Spammer")
# Check: moderation_status should be "rejected", confidence > 0.9

# Borderline comment (should queue for review)
Comment.create(body: "This is stupid. What a waste of time.", author: "Bob")
# Check: moderation_status should be "pending_review", confidence 0.5-0.9

# Duplicate comment (should use cache)
Comment.create(body: "Great article! Thanks for sharing this tutorial.", author: "Charlie")
# Check: logs show cache hit, no API call made

```

Verify moderation dashboard:

```bash
# Visit http://localhost:3000/moderator/comments
# Should see pending reviews sorted by confidence score
# Approve/reject buttons should update status and record audit

```

Check metrics:

```ruby
ModerationMetrics.calculate
# Should return false_positive_rate, false_negative_rate, accuracy

```

## Setup Code

### Step 1: Create Rails App and Models

```bash
rails new content_moderator --skip-javascript
cd content_moderator

# Add dependencies
bundle add ruby-openai
bundle add sidekiq

# Create models
bin/rails generate model Comment body:text author:string moderation_status:integer moderation_score:float moderation_violations:jsonb moderation_reason:text moderated_at:datetime
bin/rails generate model ModerationAudit comment:references ai_decision:string human_decision:integer ai_confidence:float reviewer_id:integer reviewed_at:datetime

bin/rails db:migrate

```

### Step 2: Configure OpenAI

Create `.env` file:

```
OPENAI_API_KEY=your_api_key_here

```

Add to `config/application.rb`:

```ruby
config.before_initialize do
  require 'openai'
end

```

### Step 3: Implement Comment Model

`app/models/comment.rb`:

```ruby
class Comment < ApplicationRecord
  enum moderation_status: {
    pending: 0,
    approved: 1,
    rejected: 2,
    pending_review: 3
  }

  has_many :moderation_audits

  after_create_commit :queue_moderation

  scope :for_public_display, -> { approved }
  scope :needs_review, -> { pending_review.order(moderation_score: :desc) }

  def queue_moderation
    ModerateCommentJob.perform_later(id)
  end

  def cache_key_for_moderation
    "moderation/#{Digest::SHA256.hexdigest(body)}"
  end
end

```

### Step 4: Create Moderation Service

`app/services/content_moderator.rb`:

```ruby
class ContentModerator
  def initialize
    @client = OpenAI::Client.new(access_token: ENV["OPENAI_API_KEY"])
  end

  def moderate(content)
    # Check cache first
    cache_key = "moderation/#{Digest::SHA256.hexdigest(content)}"

    Rails.cache.fetch(cache_key, expires_in: 7.days) do
      perform_moderation(content)
    end
  end

  private

  def perform_moderation(content)
    response = @client.chat(
      parameters: {
        model: "gpt-4o-mini",
        messages: [
          {
            role: "system",
            content: moderation_system_prompt
          },
          {
            role: "user",
            content: "Analyze this comment: #{content}"
          }
        ],
        response_format: { type: "json_object" },
        temperature: 0,
        max_tokens: 300
      }
    )

    result = JSON.parse(response.dig("choices", 0, "message", "content"))
    Rails.logger.info("Moderation API called for content: #{content.truncate(50)}")
    result
  rescue => e
    Rails.logger.error("Moderation failed: #{e.message}")
    # Return safe default on error
    {
      "safe" => true,
      "violations" => [],
      "confidence" => 0.5,
      "reason" => "Error during moderation, defaulting to safe"
    }
  end

  def moderation_system_prompt
    <<~PROMPT
      You are a content moderation system for a blog comment platform.

      Analyze the comment and return JSON with these exact fields:
      {
        "safe": boolean (true if content meets all policies),
        "violations": array of strings (list policy violations, empty array if safe),
        "confidence": float between 0.0 and 1.0,
        "reason": string (brief explanation)
      }

      Policies:
      1. No hate speech, threats, harassment, or bullying
      2. No spam, commercial promotion, or unsolicited links
      3. No graphic violence, adult content, or illegal activity
      4. No misinformation about health, safety, or current events
      5. Constructive criticism is allowed, but personal attacks are not

      Examples:
      - "Great article!" -> safe=true, confidence=0.95
      - "This is dumb" -> safe=true, confidence=0.7 (rude but not violating)
      - "You're an idiot and should die" -> safe=false, violations=["threats", "harassment"], confidence=0.98
      - "Buy my product at sketchy-link.com" -> safe=false, violations=["spam"], confidence=0.95

      Return valid JSON only. No explanations outside JSON.
    PROMPT
  end
end

```

### Step 5: Create Background Job

`app/jobs/moderate_comment_job.rb`:

```ruby
class ModerateCommentJob < ApplicationJob
  queue_as :moderation

  def perform(comment_id)
    comment = Comment.find(comment_id)
    moderator = ContentModerator.new

    result = moderator.moderate(comment.body)

    comment.update(
      moderation_status: determine_status(result),
      moderation_score: result["confidence"],
      moderation_violations: result["violations"],
      moderation_reason: result["reason"],
      moderated_at: Time.current
    )

    Rails.logger.info("Comment #{comment_id}: #{comment.moderation_status}, confidence=#{result['confidence']}")
  end

  private

  def determine_status(result)
    if result["safe"] && result["confidence"] > 0.8
      "approved"
    elsif !result["safe"] && result["confidence"] > 0.9
      "rejected"
    else
      "pending_review"
    end
  end
end

```

### Step 6: Create Moderation Dashboard

`app/controllers/moderator/comments_controller.rb`:

```ruby
module Moderator
  class CommentsController < ApplicationController
    before_action :require_moderator # Implement your auth

    def index
      @comments = Comment.needs_review.page(params[:page]).per(20)
      @metrics = ModerationMetrics.calculate
    end

    def approve
      comment = Comment.find(params[:id])

      # Record audit before changing status
      ModerationAudit.create(
        comment: comment,
        ai_decision: comment.moderation_status,
        human_decision: "approved",
        ai_confidence: comment.moderation_score,
        reviewer_id: current_user.id,
        reviewed_at: Time.current
      )

      comment.update(moderation_status: "approved")
      redirect_to moderator_comments_path, notice: "Comment approved"
    end

    def reject
      comment = Comment.find(params[:id])

      ModerationAudit.create(
        comment: comment,
        ai_decision: comment.moderation_status,
        human_decision: "rejected",
        ai_confidence: comment.moderation_score,
        reviewer_id: current_user.id,
        reviewed_at: Time.current
      )

      comment.update(moderation_status: "rejected")
      redirect_to moderator_comments_path, notice: "Comment rejected"
    end

    private

    def require_moderator
      # Implement your authorization logic
      # redirect_to root_path unless current_user&.moderator?
    end
  end
end

```

### Step 7: Add Routes

`config/routes.rb`:

```ruby
Rails.application.routes.draw do
  resources :comments, only: [:index, :create]

  namespace :moderator do
    resources :comments, only: [:index] do
      member do
        post :approve
        post :reject
      end
    end
  end
end

```

### Step 8: Create Metrics Service

`app/services/moderation_metrics.rb`:

```ruby
class ModerationMetrics
  def self.calculate
    total = ModerationAudit.count
    return {} if total.zero?

    # False positive: AI rejected, human approved
    false_positives = ModerationAudit.where(
      ai_decision: "rejected",
      human_decision: "approved"
    ).count

    # False negative: AI approved, human rejected
    false_negatives = ModerationAudit.where(
      ai_decision: "approved",
      human_decision: "rejected"
    ).count

    # Agreement
    agreements = ModerationAudit.where(
      "ai_decision = CASE WHEN human_decision = 0 THEN 'approved' ELSE 'rejected' END"
    ).count

    {
      total_reviews: total,
      false_positive_rate: (false_positives.to_f / total * 100).round(2),
      false_negative_rate: (false_negatives.to_f / total * 100).round(2),
      accuracy: (agreements.to_f / total * 100).round(2),
      avg_ai_confidence: ModerationAudit.average(:ai_confidence).to_f.round(2)
    }
  end
end

```

### Step 9: Create Dashboard View

`app/views/moderator/comments/index.html.erb`:

```erb
<h1>Moderation Queue</h1>

<div class="metrics">
  <h2>Accuracy Metrics</h2>
  <ul>
    <li>Total Reviews: <%= @metrics[:total_reviews] %></li>
    <li>False Positive Rate: <%= @metrics[:false_positive_rate] %>%</li>
    <li>False Negative Rate: <%= @metrics[:false_negative_rate] %>%</li>
    <li>Accuracy: <%= @metrics[:accuracy] %>%</li>
    <li>Avg AI Confidence: <%= @metrics[:avg_ai_confidence] %></li>
  </ul>
</div>

<table>
  <thead>
    <tr>
      <th>Author</th>
      <th>Comment</th>
      <th>AI Decision</th>
      <th>Confidence</th>
      <th>Violations</th>
      <th>Reason</th>
      <th>Actions</th>
    </tr>
  </thead>
  <tbody>
    <% @comments.each do |comment| %>
      <tr>
        <td><%= comment.author %></td>
        <td><%= comment.body.truncate(100) %></td>
        <td><%= comment.moderation_status %></td>
        <td><%= (comment.moderation_score * 100).round %>%</td>
        <td><%= comment.moderation_violations.join(", ") %></td>
        <td><%= comment.moderation_reason %></td>
        <td>
          <%= button_to "Approve", approve_moderator_comment_path(comment) %>
          <%= button_to "Reject", reject_moderator_comment_path(comment) %>
        </td>
      </tr>
    <% end %>
  </tbody>
</table>

<%= paginate @comments %>

```

### Step 10: Run and Test

Start Sidekiq for background jobs:

```bash
bundle exec sidekiq

```

Start Rails server:

```bash
bin/rails server

```

Test in console:

```bash
bin/rails console

# Create test comments
Comment.create(body: "Great article! Very helpful.", author: "Alice")
Comment.create(body: "Visit buy-now-cheap.com for amazing deals!!!", author: "Spammer")
Comment.create(body: "This is kind of dumb.", author: "Bob")

# Check statuses
Comment.all.each do |c|
  puts "#{c.author}: #{c.moderation_status} (#{c.moderation_score})"
end

# Create duplicate (should use cache)
Comment.create(body: "Great article! Very helpful.", author: "Charlie")
# Check logs for cache hit

# View metrics
ModerationMetrics.calculate

```

Visit dashboard:
```
http://localhost:3000/moderator/comments
```

## Stretch (Optional)

1. **Add batch moderation:** Process multiple comments in a single API call to reduce latency and costs.

```ruby
class BatchContentModerator
  def moderate_batch(comments)
    prompt = build_batch_prompt(comments)
    # Send single API call, parse JSON array response
  end
end

```

2. **Implement appeal system:** Allow users to contest rejected comments, triggering human review.

3. **Add severity scoring:** Instead of binary safe/unsafe, use severity levels (low, medium, high, critical).

4. **Custom policies:** Allow admins to configure custom moderation rules via UI.

5. **Rate limiting:** Prevent abuse by limiting comments per user per hour.

```ruby
class Comment < ApplicationRecord
  before_create :check_rate_limit

  def check_rate_limit
    recent_count = Comment.where(author: author)
                          .where("created_at > ?", 1.hour.ago)
                          .count
    errors.add(:base, "Too many comments") if recent_count > 10
  end
end

```

6. **A/B test prompts:** Try different moderation prompts and compare accuracy.

## Time Estimate
25 minutes

## Common Issues

**API errors:** Ensure `OPENAI_API_KEY` is set correctly in `.env` and loaded.

**Sidekiq not processing:** Make sure Sidekiq is running in a separate terminal.

**Cache not working:** Check Rails cache is configured (default: file store in development).

**JSON parsing errors:** LLM occasionally returns invalid JSON. Add error handling and retry logic.

```ruby
def perform_moderation(content)
  retries ||= 0
  # ... API call ...
  JSON.parse(response.dig("choices", 0, "message", "content"))
rescue JSON::ParserError => e
  if (retries += 1) < 3
    Rails.logger.warn("JSON parse failed, retrying...")
    retry
  else
    # Return safe default after retries
    return default_safe_response
  end
end

```
