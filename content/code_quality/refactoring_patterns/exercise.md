# Exercise: Refactoring Patterns in Rails

## Objective
Refactor a fat controller into a clean, testable architecture using Extract Service and Replace Conditional with Polymorphism patterns.

## Task
You have a bloated `ArticlesController` that handles publishing, scheduling, archiving, and notifications. Your job is to:

1. Extract the publishing workflow into a service object
2. Replace the conditional notification logic with polymorphism
3. Write tests to verify behavior remains unchanged

## Acceptance Criteria
- [ ] `ArticlePublishingService` extracts all publishing logic from controller
- [ ] Controller action is under 10 lines
- [ ] Notification logic uses strategy pattern (no conditionals)
- [ ] All tests pass before and after refactoring
- [ ] Service object is independently testable

## Starting Code

### Fat Controller (Before)

```ruby
# app/controllers/articles_controller.rb
class ArticlesController < ApplicationController
  def publish
    @article = Article.find(params[:id])

    # Validate
    unless @article.draft?
      flash[:error] = "Only drafts can be published"
      redirect_to @article and return
    end

    # Publish
    @article.status = "published"
    @article.published_at = Time.current
    @article.save!

    # Update search index
    SearchIndexer.index(@article)

    # Clear cache
    Rails.cache.delete("articles/#{@article.id}")
    Rails.cache.delete("articles/recent")

    # Send notifications based on subscription type
    subscribers = @article.author.subscribers
    subscribers.each do |subscriber|
      case subscriber.subscription_type
      when "premium"
        PremiumNotificationMailer.new_article(@article, subscriber).deliver_later
        PushNotificationService.send(subscriber, "New article: #{@article.title}")
      when "standard"
        StandardNotificationMailer.new_article(@article, subscriber).deliver_later
      when "digest"
        # Add to weekly digest queue
        DigestQueue.add(@article, subscriber)
      end
    end

    # Track analytics
    Analytics.track("article_published", {
      article_id: @article.id,
      author_id: @article.author_id,
      category: @article.category
    })

    redirect_to @article, notice: "Article published successfully!"
  end
end
```

### Models

```ruby
# app/models/article.rb
class Article < ApplicationRecord
  belongs_to :author

  enum status: { draft: 0, published: 1, archived: 2 }
end

# app/models/subscriber.rb
class Subscriber < ApplicationRecord
  belongs_to :author

  enum subscription_type: { standard: 0, premium: 1, digest: 2 }
end
```

## Refactoring Steps

### Step 1: Write Characterization Tests (5 minutes)

First, capture current behavior with tests:

```ruby
# spec/controllers/articles_controller_spec.rb
RSpec.describe ArticlesController, type: :controller do
  describe "#publish" do
    let(:author) { create(:author) }
    let(:article) { create(:article, :draft, author: author) }
    let!(:premium_sub) { create(:subscriber, author: author, subscription_type: :premium) }
    let!(:standard_sub) { create(:subscriber, author: author, subscription_type: :standard) }

    before do
      allow(SearchIndexer).to receive(:index)
      allow(Analytics).to receive(:track)
    end

    it "publishes article and sends notifications" do
      expect {
        post :publish, params: { id: article.id }
      }.to change { article.reload.status }.from("draft").to("published")

      expect(article.published_at).to be_present
      expect(SearchIndexer).to have_received(:index).with(article)
      expect(ActionMailer::Base.deliveries.size).to eq(2) # premium + standard
      expect(response).to redirect_to(article)
    end

    it "rejects non-draft articles" do
      article.update!(status: :published)

      post :publish, params: { id: article.id }

      expect(flash[:error]).to eq("Only drafts can be published")
    end
  end
end
```

### Step 2: Extract Service Object (10 minutes)

Create a service to handle publishing workflow:

```ruby
# app/services/article_publishing_service.rb
class ArticlePublishingService
  def initialize(article)
    @article = article
  end

  def call
    return failure("Only drafts can be published") unless @article.draft?

    publish_article
    update_search_index
    clear_cache
    notify_subscribers
    track_analytics

    success
  end

  private

  def publish_article
    @article.update!(status: :published, published_at: Time.current)
  end

  def update_search_index
    SearchIndexer.index(@article)
  end

  def clear_cache
    Rails.cache.delete("articles/#{@article.id}")
    Rails.cache.delete("articles/recent")
  end

  def notify_subscribers
    @article.author.subscribers.each do |subscriber|
      NotificationStrategy.for(subscriber).notify(@article, subscriber)
    end
  end

  def track_analytics
    Analytics.track("article_published", {
      article_id: @article.id,
      author_id: @article.author_id,
      category: @article.category
    })
  end

  def success
    ServiceResult.success(@article)
  end

  def failure(message)
    ServiceResult.failure(message)
  end
end

# app/services/service_result.rb
class ServiceResult
  attr_reader :value, :error

  def self.success(value)
    new(success: true, value: value)
  end

  def self.failure(error)
    new(success: false, error: error)
  end

  def initialize(success:, value: nil, error: nil)
    @success = success
    @value = value
    @error = error
  end

  def success?
    @success
  end

  def failure?
    !@success
  end
end
```

### Step 3: Replace Conditional with Polymorphism (10 minutes)

Replace the case statement with strategy pattern:

```ruby
# app/services/notification_strategy.rb
class NotificationStrategy
  def self.for(subscriber)
    case subscriber.subscription_type
    when "premium" then PremiumNotification.new
    when "standard" then StandardNotification.new
    when "digest" then DigestNotification.new
    else raise "Unknown subscription type"
    end
  end
end

# app/services/premium_notification.rb
class PremiumNotification
  def notify(article, subscriber)
    PremiumNotificationMailer.new_article(article, subscriber).deliver_later
    PushNotificationService.send(subscriber, "New article: #{article.title}")
  end
end

# app/services/standard_notification.rb
class StandardNotification
  def notify(article, subscriber)
    StandardNotificationMailer.new_article(article, subscriber).deliver_later
  end
end

# app/services/digest_notification.rb
class DigestNotification
  def notify(article, subscriber)
    DigestQueue.add(article, subscriber)
  end
end
```

### Step 4: Update Controller (5 minutes)

Simplify the controller to use the service:

```ruby
# app/controllers/articles_controller.rb
class ArticlesController < ApplicationController
  def publish
    @article = Article.find(params[:id])
    result = ArticlePublishingService.new(@article).call

    if result.success?
      redirect_to @article, notice: "Article published successfully!"
    else
      flash[:error] = result.error
      redirect_to @article
    end
  end
end
```

### Step 5: Test the Service in Isolation (5 minutes)

Now write focused unit tests:

```ruby
# spec/services/article_publishing_service_spec.rb
RSpec.describe ArticlePublishingService do
  let(:article) { create(:article, :draft) }
  let(:service) { ArticlePublishingService.new(article) }

  before do
    allow(SearchIndexer).to receive(:index)
    allow(Analytics).to receive(:track)
  end

  describe "#call" do
    it "publishes the article" do
      result = service.call

      expect(result).to be_success
      expect(article.reload.status).to eq("published")
      expect(article.published_at).to be_present
    end

    it "updates search index" do
      service.call
      expect(SearchIndexer).to have_received(:index).with(article)
    end

    it "clears cache" do
      expect(Rails.cache).to receive(:delete).with("articles/#{article.id}")
      expect(Rails.cache).to receive(:delete).with("articles/recent")
      service.call
    end

    it "rejects non-draft articles" do
      article.update!(status: :published)
      result = service.call

      expect(result).to be_failure
      expect(result.error).to eq("Only drafts can be published")
    end
  end
end

# spec/services/notification_strategy_spec.rb
RSpec.describe NotificationStrategy do
  let(:article) { create(:article) }

  it "sends premium notifications" do
    subscriber = create(:subscriber, subscription_type: :premium)

    expect(PremiumNotificationMailer).to receive_message_chain(:new_article, :deliver_later)
    expect(PushNotificationService).to receive(:send)

    NotificationStrategy.for(subscriber).notify(article, subscriber)
  end

  it "sends standard notifications" do
    subscriber = create(:subscriber, subscription_type: :standard)

    expect(StandardNotificationMailer).to receive_message_chain(:new_article, :deliver_later)

    NotificationStrategy.for(subscriber).notify(article, subscriber)
  end
end
```

## Verification Steps

1. Run original tests: `rspec spec/controllers/articles_controller_spec.rb`
2. Extract service and re-run tests (should still pass)
3. Replace conditional with polymorphism and re-run tests
4. Run new service specs: `rspec spec/services/`
5. Verify controller action is under 10 lines

## Stretch Goals

- [ ] Add rollback logic if any step fails (wrap in transaction)
- [ ] Extract cache clearing into a separate concern
- [ ] Add logging to track each step of the publishing workflow
- [ ] Create a base `NotificationStrategy` class with shared behavior
- [ ] Add metrics tracking for notification delivery

## Time Estimate
25-30 minutes

## Key Takeaways

After completing this exercise, you should understand:
- How to identify code smells in controllers (multiple responsibilities, long methods)
- When and how to extract service objects
- How to replace conditionals with polymorphism
- The importance of tests when refactoring
- How to test services in isolation
