# Exercise: N+1 Query Detection & Resolution

## Objective
Detect and fix N+1 queries using Bullet gem and eager loading strategies.

## Task
In a Rails app with posts and authors:

1. Set up Bullet gem to detect N+1 queries
2. Create a controller action that triggers an N+1 problem
3. Observe Bullet warnings in logs and browser alerts
4. Fix the N+1 using `includes`, measure query count reduction
5. Test nested associations (posts → authors → companies)

## Acceptance Criteria
- [ ] Bullet gem installed and configured in `development.rb`
- [ ] Controller action triggers N+1 when accessing `post.author.name` in a loop
- [ ] Bullet alerts appear in browser and logs identifying the N+1
- [ ] After adding `includes(:author)`, query count drops from 1+N to 2
- [ ] Nested eager loading `includes(author: :company)` reduces queries to 3 total
- [ ] Logs show before/after query counts proving optimization

## Verification Steps

1. Run the unoptimized endpoint and check `log/development.log`:
```
Started GET "/posts"
Post Load (0.5ms)  SELECT "posts".* FROM "posts"
User Load (0.3ms)  SELECT "users".* FROM "users" WHERE "users"."id" = 1
User Load (0.3ms)  SELECT "users".* FROM "users" WHERE "users"."id" = 2
# ... repeated N times
Completed 200 OK in 150ms (51 queries)
```

2. Check browser for Bullet alert:
```
USE eager loading detected
  Post => [:author]
  Add to your query: .includes(:author)
```

3. After fix, verify logs show only 2 queries:
```
Post Load (0.5ms)  SELECT "posts".* FROM "posts"
User Load (1.2ms)  SELECT "users".* FROM "users" WHERE "users"."id" IN (1, 2, 3, ...)
Completed 200 OK in 25ms (2 queries)
```

## Setup Code

### Step 1: Create Rails App & Models

```bash
rails new n_plus_one_demo --skip-javascript
cd n_plus_one_demo
bin/rails generate model Company name:string
bin/rails generate model User name:string company:references
bin/rails generate model Post title:string user:references
bin/rails db:migrate
```

**Add associations in models:**

`app/models/company.rb`:
```ruby
class Company < ApplicationRecord
  has_many :users
end
```

`app/models/user.rb`:
```ruby
class User < ApplicationRecord
  belongs_to :company
  has_many :posts
end
```

`app/models/post.rb`:
```ruby
class Post < ApplicationRecord
  belongs_to :user
end
```

### Step 2: Install Bullet

```bash
bundle add bullet
```

Edit `config/environments/development.rb`:
```ruby
Rails.application.configure do
  # ... existing config

  config.after_initialize do
    Bullet.enable = true
    Bullet.alert = true           # Browser alert
    Bullet.console = true         # Terminal output
    Bullet.rails_logger = true    # Log file
  end
end
```

### Step 3: Seed Data

```bash
bin/rails console
```

In console:
```ruby
# Create sample data
3.times do |i|
  company = Company.create(name: "Company #{i}")
  5.times do |j|
    user = User.create(name: "User #{j}", company: company)
    10.times do |k|
      Post.create(title: "Post #{k}", user: user)
    end
  end
end

puts "Created #{Post.count} posts, #{User.count} users, #{Company.count} companies"
```

### Step 4: Create Controller with N+1

```bash
bin/rails generate controller Posts index
```

Edit `app/controllers/posts_controller.rb`:
```ruby
class PostsController < ApplicationController
  def index
    # BEFORE: triggers N+1
    @posts = Post.limit(50)

    # This will be used in the view
  end
end
```

Edit `app/views/posts/index.html.erb`:
```erb
<h1>Posts</h1>
<ul>
  <% @posts.each do |post| %>
    <li><%= post.title %> by <%= post.user.name %></li>
  <% end %>
</ul>
```

### Step 5: Trigger N+1 and Observe

```bash
bin/rails server
# Visit http://localhost:3000/posts
```

Check terminal for Bullet output:
```
USE eager loading detected
  Post => [:user]
  Add to your query: .includes(:user)
```

Check `log/development.log` for query count.

### Step 6: Fix with includes

Edit `app/controllers/posts_controller.rb`:
```ruby
class PostsController < ApplicationController
  def index
    # AFTER: fixed with includes
    @posts = Post.includes(:user).limit(50)
  end
end
```

Reload page and verify only 2 queries in logs.

### Step 7: Test Nested Associations

Update view to show company:
```erb
<% @posts.each do |post| %>
  <li>
    <%= post.title %>
    by <%= post.user.name %>
    at <%= post.user.company.name %>
  </li>
<% end %>
```

This triggers a new N+1 on companies. Fix it:
```ruby
@posts = Post.includes(user: :company).limit(50)
```

Verify 3 queries: posts, users, companies.

## Stretch (Optional)

1. Compare `includes` vs `eager_load` vs `preload`:
```ruby
# Log queries for each and observe SQL differences
Post.includes(:user).where(users: { name: "User 1" }).to_a
Post.eager_load(:user).where(users: { name: "User 1" }).to_a
Post.preload(:user).where(users: { name: "User 1" }).to_a
```

2. Test when N+1 is acceptable:
```ruby
# For first 3 posts only, is eager loading worth it?
Post.limit(3).each { |p| puts p.user.name }
```

Measure query time and decide if optimization is needed.

## Time Estimate
18 minutes
