# Content Moderation & Classification with LLMs

## What It Is
Content moderation with LLMs uses large language models to automatically classify, filter, and flag user-generated content for policy violations, toxicity, spam, or inappropriate material. Unlike traditional keyword-based filters or rule-based systems, LLMs understand context, nuance, and intent. They can perform zero-shot classification (categorizing content without training examples), sentiment analysis, multi-label tagging, and safety filtering using natural language prompts instead of manually crafted rules.

## Why It Matters
Manual moderation doesn't scale. A platform with 100,000 daily posts needs automated first-pass filtering to prioritize human review. Traditional ML models require thousands of labeled examples and retraining for new categories. LLMs perform zero-shot classification with simple prompt changes, reducing development time from weeks to hours. They catch subtle violations that keyword filters miss (e.g., "unalive" instead of violent terms) and reduce false positives by understanding context. Poor moderation leads to legal liability, toxic communities, and user churn.

## When to Use
- **User-generated content platforms:** Filter comments, reviews, posts, messages for policy violations
- **Zero-shot classification needs:** Categorize content without training data for new categories
- **Context-aware filtering:** Detect toxic content that evades keyword filters through misspellings or euphemisms
- **Multi-label tagging:** Assign multiple categories to content (e.g., "spam + promotional + low-quality")
- **Sentiment analysis at scale:** Classify customer feedback, support tickets, product reviews
- **Safety layers:** Add pre-submission checks or post-moderation queues with confidence scores

## Three Common Pitfalls
1. **Treating LLM scores as binary decisions:** LLMs return confidence scores, not absolute truth. A 0.7 "toxic" score needs human review, not auto-deletion. Build moderation queues with score thresholds (0-0.4 approve, 0.4-0.7 review, 0.7+ block) instead of hard cutoffs.
2. **Not caching or batching moderation calls:** Every moderation call costs money and latency. Cache results for identical content, batch requests where possible, and use async background jobs for non-blocking moderation to avoid slowing down user submissions.
3. **Over-relying on LLMs without feedback loops:** LLMs have biases and make mistakes. Track false positives (approved content flagged) and false negatives (violations missed) by sampling moderated content for human review. Use this data to tune prompts, adjust thresholds, or switch to fine-tuned models.

---

## Zero-Shot Classification Basics

LLMs can classify content into categories without training examples:

```ruby
# Classify support ticket priority
def classify_ticket_priority(message)
  prompt = <<~PROMPT
    Classify the following support ticket as one of: urgent, high, medium, low.

    Urgent: service down, security breach, data loss
    High: major feature broken, billing issue, many users affected
    Medium: minor bug, feature request, single user issue
    Low: general question, documentation request, feedback

    Ticket: #{message}

    Classification:
  PROMPT

  response = openai_client.chat(
    model: "gpt-4o-mini",
    messages: [{ role: "user", content: prompt }],
    max_tokens: 10,
    temperature: 0
  )

  response.dig("choices", 0, "message", "content").strip.downcase
end

# Usage
classify_ticket_priority("Our production database is down!")
# => "urgent"

classify_ticket_priority("Can you add dark mode?")
# => "low"

```

**Key details:**
- Temperature 0 for consistent classifications
- Clear category definitions in the prompt reduce ambiguity
- Low max_tokens saves costs for simple outputs
- No training data required; change categories by editing prompt

---

## Structured Content Moderation

Use structured outputs with function calling or JSON mode:

```ruby
class ContentModerator
  def initialize
    @client = OpenAI::Client.new(access_token: ENV["OPENAI_API_KEY"])
  end

  def moderate(content)
    response = @client.chat(
      parameters: {
        model: "gpt-4o-mini",
        messages: [
          {
            role: "system",
            content: "You are a content moderation system. Analyze content for policy violations."
          },
          {
            role: "user",
            content: moderation_prompt(content)
          }
        ],
        response_format: { type: "json_object" },
        temperature: 0
      }
    )

    JSON.parse(response.dig("choices", 0, "message", "content"))
  end

  private

  def moderation_prompt(content)
    <<~PROMPT
      Analyze this content and return JSON with these fields:
      - safe (boolean): true if content meets all policies
      - violations (array): list of policy violations (empty if safe)
      - confidence (float): 0.0-1.0 confidence in assessment
      - reason (string): explanation of decision

      Policies:
      1. No hate speech, threats, or harassment
      2. No spam or commercial promotion
      3. No graphic violence or adult content
      4. No misinformation about health/safety

      Content to analyze:
      #{content}

      Return valid JSON only.
    PROMPT
  end
end

# Usage
moderator = ContentModerator.new
result = moderator.moderate("Check out my store at sketchy-link.com for cheap watches!")

# => {
#   "safe" => false,
#   "violations" => ["spam", "commercial promotion"],
#   "confidence" => 0.95,
#   "reason" => "Content contains unsolicited commercial link"
# }

```

Store results with the content for auditing:

```ruby
class Comment < ApplicationRecord
  before_create :moderate_content

  def moderate_content
    result = ContentModerator.new.moderate(body)

    self.moderation_score = result["confidence"]
    self.moderation_status = determine_status(result)
    self.moderation_violations = result["violations"]
    self.moderation_reason = result["reason"]
  end

  def determine_status(result)
    return "approved" if result["safe"] && result["confidence"] > 0.8
    return "rejected" if !result["safe"] && result["confidence"] > 0.8
    "pending_review" # Low confidence needs human review
  end
end

```

---

## Multi-Label Classification

Assign multiple categories to content:

```ruby
def categorize_article(text)
  prompt = <<~PROMPT
    Categorize this article with ALL applicable labels from this list:
    - technical, business, opinion, tutorial, news, research
    - beginner, intermediate, advanced
    - rails, ruby, javascript, database, devops

    Return JSON array of labels: ["label1", "label2", ...]

    Article: #{text.truncate(500)}
  PROMPT

  response = openai_client.chat(
    model: "gpt-4o-mini",
    messages: [{ role: "user", content: prompt }],
    response_format: { type: "json_object" },
    temperature: 0
  )

  JSON.parse(response.dig("choices", 0, "message", "content"))["labels"]
end

# Usage
article = "This tutorial covers advanced Rails performance optimization techniques..."
categorize_article(article)
# => ["technical", "tutorial", "advanced", "rails"]

```

Store as JSON or separate tags table:

```ruby
class Article < ApplicationRecord
  # Option 1: JSON column
  # add_column :articles, :ai_tags, :jsonb, default: []

  # Option 2: Tagging system
  has_many :article_tags
  has_many :tags, through: :article_tags

  after_create_commit :auto_tag

  def auto_tag
    AutoTagJob.perform_later(id)
  end
end

class AutoTagJob < ApplicationJob
  def perform(article_id)
    article = Article.find(article_id)
    labels = categorize_article(article.body)

    labels.each do |label_name|
      tag = Tag.find_or_create_by(name: label_name)
      article.tags << tag unless article.tags.include?(tag)
    end
  end
end

```

---

## Sentiment Analysis

Classify emotional tone and intensity:

```ruby
class SentimentAnalyzer
  def analyze(text)
    response = openai_client.chat(
      parameters: {
        model: "gpt-4o-mini",
        messages: [
          {
            role: "system",
            content: "Analyze sentiment. Return JSON: {sentiment: 'positive'|'negative'|'neutral', intensity: 0.0-1.0, emotion: string}"
          },
          {
            role: "user",
            content: text
          }
        ],
        response_format: { type: "json_object" },
        temperature: 0
      }
    )

    JSON.parse(response.dig("choices", 0, "message", "content"))
  end
end

# Usage in customer support
class SupportTicket < ApplicationRecord
  after_create :analyze_sentiment

  def analyze_sentiment
    result = SentimentAnalyzer.new.analyze(message)

    update(
      sentiment: result["sentiment"],
      sentiment_intensity: result["intensity"],
      detected_emotion: result["emotion"]
    )

    # Prioritize angry customers
    update(priority: "high") if result["emotion"] == "angry" && result["intensity"] > 0.7
  end
end

```

---

## Caching and Performance Optimization

Don't re-moderate identical content:

```ruby
class CachedContentModerator
  def moderate(content)
    # Use content hash as cache key
    cache_key = "moderation/#{Digest::SHA256.hexdigest(content)}"

    Rails.cache.fetch(cache_key, expires_in: 7.days) do
      perform_moderation(content)
    end
  end

  private

  def perform_moderation(content)
    # Actual API call only if not cached
    response = openai_client.chat(...)
    JSON.parse(response.dig("choices", 0, "message", "content"))
  end
end

```

Batch processing for efficiency:

```ruby
class BatchModerator
  def moderate_batch(contents)
    # Process multiple items in one API call
    prompt = <<~PROMPT
      Analyze each item and return JSON array with moderation results.
      Format: [{"index": 0, "safe": bool, "violations": [], "confidence": float}, ...]

      Items to moderate:
      #{contents.map.with_index { |c, i| "#{i}. #{c}" }.join("\n")}
    PROMPT

    response = openai_client.chat(
      model: "gpt-4o-mini",
      messages: [{ role: "user", content: prompt }],
      response_format: { type: "json_object" },
      temperature: 0
    )

    JSON.parse(response.dig("choices", 0, "message", "content"))["results"]
  end
end

# Usage
BatchModerator.new.moderate_batch([
  "Great product!",
  "Spam link here...",
  "Hate speech example"
])

```

---

## Async Moderation Workflows

Don't block user submissions:

```ruby
class Comment < ApplicationRecord
  # Allow submission, moderate in background
  after_create_commit :queue_moderation

  def queue_moderation
    ModerateCommentJob.perform_later(id)
  end

  scope :pending_moderation, -> { where(moderation_status: "pending") }
  scope :approved, -> { where(moderation_status: "approved") }
  scope :requires_review, -> { where(moderation_status: "pending_review") }
end

class ModerateCommentJob < ApplicationJob
  queue_as :moderation

  def perform(comment_id)
    comment = Comment.find(comment_id)
    result = ContentModerator.new.moderate(comment.body)

    comment.update(
      moderation_status: determine_status(result),
      moderation_data: result,
      moderated_at: Time.current
    )

    # Notify user if rejected
    UserMailer.content_rejected(comment.user).deliver_later if comment.rejected?
  end

  private

  def determine_status(result)
    return "approved" if result["safe"] && result["confidence"] > 0.8
    return "rejected" if !result["safe"] && result["confidence"] > 0.9
    "pending_review"
  end
end

```

Display content conditionally:

```ruby
# Controller
def index
  @comments = if current_user.moderator?
    Comment.all # Show all including pending
  else
    Comment.approved # Only show approved to users
  end
end

# View
<% @comments.each do |comment| %>
  <div class="comment <%= 'pending-review' if comment.pending_review? %>">
    <%= comment.body %>
    <% if current_user.moderator? && comment.pending_review? %>
      <%= link_to "Approve", approve_comment_path(comment), method: :post %>
      <%= link_to "Reject", reject_comment_path(comment), method: :post %>
    <% end %>
  </div>
<% end %>

```

---

## Building a Moderation Queue

Dashboard for human reviewers:

```ruby
# routes.rb
namespace :moderator do
  resources :comments, only: [:index] do
    member do
      post :approve
      post :reject
    end
  end
end

# app/controllers/moderator/comments_controller.rb
class Moderator::CommentsController < ApplicationController
  before_action :require_moderator

  def index
    @comments = Comment.requires_review
                       .order(moderation_score: :desc) # High-risk first
                       .page(params[:page])
  end

  def approve
    comment = Comment.find(params[:id])
    comment.update(
      moderation_status: "approved",
      reviewed_by: current_user.id,
      reviewed_at: Time.current
    )
    redirect_to moderator_comments_path, notice: "Approved"
  end

  def reject
    comment = Comment.find(params[:id])
    comment.update(
      moderation_status: "rejected",
      reviewed_by: current_user.id,
      reviewed_at: Time.current
    )
    UserMailer.content_rejected(comment.user).deliver_later
    redirect_to moderator_comments_path, notice: "Rejected"
  end
end

```

---

## Tracking Moderation Accuracy

Monitor false positives and negatives:

```ruby
class ModerationAudit < ApplicationRecord
  belongs_to :comment
  belongs_to :reviewer, class_name: "User"

  enum human_decision: { approved: 0, rejected: 1 }

  def self.calculate_metrics
    total = count

    # False positive: AI said unsafe, human approved
    false_positives = where(
      ai_decision: "rejected",
      human_decision: "approved"
    ).count

    # False negative: AI said safe, human rejected
    false_negatives = where(
      ai_decision: "approved",
      human_decision: "rejected"
    ).count

    {
      false_positive_rate: (false_positives.to_f / total * 100).round(2),
      false_negative_rate: (false_negatives.to_f / total * 100).round(2),
      accuracy: ((total - false_positives - false_negatives).to_f / total * 100).round(2)
    }
  end
end

# Record when human overrides AI
def approve
  comment = Comment.find(params[:id])

  ModerationAudit.create(
    comment: comment,
    reviewer: current_user,
    ai_decision: comment.moderation_status,
    human_decision: "approved",
    ai_confidence: comment.moderation_score
  )

  comment.update(moderation_status: "approved")
end

```

---

## Trade-offs Box
- **Advantage:** Zero-shot classification eliminates weeks of training data collection and model development. LLMs understand context better than keyword filters, reducing false positives by 40-60%. Adding new moderation categories takes minutes instead of retraining models.
- **Cost:** API calls cost $0.10-$1.00 per 1,000 moderations. Latency of 200-500ms per request can slow user submissions without async processing. LLMs still make mistakes; expect 5-15% error rates requiring human review.
- **When to skip:** For simple binary filters (profanity lists), use traditional pattern matching. For high-volume (millions/day) with stable categories, fine-tuned models are cheaper. For legal/regulated content, require human-in-the-loop regardless of AI confidence.

---

## Debugging Checklist

When implementing content moderation:

1. Log all moderation decisions with timestamps, content hash, model version, and prompt for debugging
2. Set up confidence score thresholds: auto-approve (>0.8 safe), auto-reject (>0.9 unsafe), human review (between)
3. Cache results by content hash to avoid re-moderating identical submissions
4. Monitor API costs: track requests/day, average tokens per request, monthly spend
5. Sample and review 5-10% of auto-approved and auto-rejected content for false positives/negatives
6. A/B test prompts and thresholds to optimize accuracy vs. review queue size
7. Implement rate limiting to prevent moderation API abuse from malicious bulk submissions
8. Track moderation latency and set async processing for any calls over 200ms
9. Store raw LLM responses for audit trails and prompt improvement
10. Build feedback loop: let moderators report bad AI decisions to tune prompts

---

## One-Minute Recap
- LLMs enable zero-shot classification without training data; change categories by editing prompts
- Use structured JSON outputs for consistent moderation results with confidence scores
- Cache results by content hash to avoid redundant API calls; batch requests when possible
- Implement async moderation to avoid blocking user submissions; show pending status
- Build moderation queues with thresholds: auto-approve high confidence, human review medium confidence
- Track false positives and false negatives to tune prompts and confidence thresholds
- Balance cost, latency, and accuracy by choosing appropriate models and caching strategies
