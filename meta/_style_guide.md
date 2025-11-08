# Rails Seniority Coach — Writing Style Guide

## Core Principles

**Concise, not chatty.** Every word earns its place.
**Truth-only sources.** Official docs, canonical books, well-known talks.
**Verbs and checklists** over prose.
**Show trade-offs** before celebrating a pattern.

---

## Content Structure (Enforce for every topic)

### 1. Overview.md Template

Every `overview.md` must follow this structure:

```markdown
# [Topic Name]

## What It Is
[2-3 sentences. Define the concept clearly.]

## Why It Matters
[2-3 sentences. Impact on production systems, debugging, or design.]

## When to Use
[Bullet list. 3-5 scenarios where this applies.]

## Three Common Pitfalls
1. **[Pitfall name]:** [1 sentence what goes wrong + 1 sentence how to avoid]
2. **[Pitfall name]:** [...]
3. **[Pitfall name]:** [...]

---

## [Core Concept Section 1]
[Explanation with tiny code samples. Max 150 words per section.]

```ruby
# Code must be runnable in isolation
User.where(active: true).order(created_at: :desc).limit(10)
```

[Brief explanation of what this shows.]

## [Core Concept Section 2]
[...]

---

## Trade-offs Box
- **Advantage:** [1 sentence]
- **Cost:** [1 sentence]
- **When to skip:** [1 sentence]

---

## Debugging Checklist
When things go wrong, check:
1. [Step 1 - be specific]
2. [Step 2]
3. [Step 3]
4. [Step 4]
5. [Step 5]

---

## One-Minute Recap
- [Key point 1]
- [Key point 2]
- [Key point 3]
- [Key point 4]
- [Key point 5]
```

**Length target:** 600–900 words total.

---

### 2. Exercise.md Template

```markdown
# Exercise: [Topic Name]

## Objective
[1 sentence. What skill you're practicing.]

## Task
[Clear, specific instructions. Single realistic scenario.]

## Acceptance Criteria
- [ ] [Criterion 1 - must be verifiable]
- [ ] [Criterion 2]
- [ ] [Criterion 3]
- [ ] [Criterion 4]

## Verification Steps
1. Run `[command]` and confirm `[expected output]`
2. Check `[file/log]` for `[specific line]`
3. Capture `[screenshot/output]` showing `[proof]`

## Stretch (Optional)
[One additional challenge if time permits.]

## Time Estimate
[X] minutes
```

**Length target:** One task, 10–20 minutes to complete.

---

### 3. Checkpoint.yml Template

```yaml
checkpoint:
  passing_score: 7  # out of 10 typical
  questions:
    # Mix 60% MCQ, 40% short-answer

    - kind: mcq
      points: 2
      prompt: "Which layer handles X before Y?"
      choices:
        - "Option A"
        - "Option B"
        - "Option C"
        - "Option D"
      correct: "Option B"
      why: "One sentence explaining why B is correct."

    - kind: short
      points: 3
      prompt: "Name two ways Rails does X and when they differ."
      sample_answer: "Sample concise answer showing key points."

# Total 6-10 questions, 10 points max
```

**MCQ explanations:** 1 sentence only. No fluff.

---

### 4. References.yml Template

```yaml
references:
  - title: "Exact Title from Source"
    url: "https://full.url.here"
    why: "One sentence: what you'll learn or why it's canonical."

  - title: "Rails Guides — Action Controller"
    url: "https://guides.rubyonrails.org/action_controller_overview.html"
    why: "Canonical overview of controller lifecycle and filters."

# 5-8 references per topic
# Only include: official docs, O'Reilly books, RailsConf/RubyConf talks, well-known blogs (thoughtbot, evilmartians, etc.)
```

---

## Writing Style Rules

### Tone
- **Direct and technical.** Assume mid-level Rails dev reading.
- **No cheerleading.** Avoid "amazing," "awesome," "powerful."
- **Neutral on trade-offs.** Present costs and benefits equally.
- **Action-oriented.** Use verbs: "Measure," "Identify," "Refactor," not "You can measure..."

### Code Samples
- **Runnable in isolation.** No implicit `current_user` or `@order` unless you show setup.
- **Tiny.** 3-10 lines max per snippet.
- **Realistic.** Use domain names like `User`, `Order`, `Product`, not `Foo`/`Bar`.
- **Commented sparingly.** Code should be self-evident; add comments only for "why" not "what."

### Examples

**Bad:**
> Active Record is an amazing ORM that makes database queries super powerful and easy!

**Good:**
> Active Record translates Ruby method chains into SQL. It simplifies common queries but can hide performance costs.

**Bad:**
```ruby
# This is a user
user = User.find(1)
# Get the posts
posts = user.posts
```

**Good:**
```ruby
user = User.find(1)
posts = user.posts.where(published: true).order(created_at: :desc)
# Triggers: SELECT * FROM posts WHERE user_id = 1 AND published = true ORDER BY created_at DESC
```

---

## Section Length Guidelines

| Section | Target Words | Max Words |
|---------|--------------|-----------|
| What It Is | 30-50 | 80 |
| Why It Matters | 30-50 | 80 |
| When to Use | 40-60 | 100 |
| Pitfalls | 60-90 | 120 |
| Core Concept (each) | 100-150 | 200 |
| Trade-offs Box | 30-50 | 80 |
| Debugging Checklist | 50-80 | 120 |
| One-Minute Recap | 40-60 | 80 |
| **Total Overview** | **600-900** | **1200** |

---

## Formatting Conventions

### Headings
- `#` for topic title
- `##` for major sections (What It Is, Why It Matters, etc.)
- `###` for subsections (rare; prefer bullets)

### Lists
- **Bulleted lists:** Use `-` for consistency
- **Numbered lists:** Only for sequential steps (debugging, exercises)
- **Checklists:** Use `- [ ]` for exercise acceptance criteria

### Emphasis
- **Bold:** Key terms on first use, section labels in lists
- *Italic:* Rare; only for emphasis or book titles
- `Code:` Inline code, file names, commands, SQL keywords

### Code Blocks
Always specify language:
```ruby
# Ruby
User.includes(:posts).where(posts: { published: true })
```

```sql
-- SQL
SELECT users.*, posts.* FROM users
INNER JOIN posts ON posts.user_id = users.id
WHERE posts.published = true;
```

---

## Quality Checklist

Before shipping any content, verify:

- [ ] Overview is 600-900 words (use `wc -w overview.md`)
- [ ] All code samples run in isolation (or show setup)
- [ ] Each reference has title + URL + 1-line "why"
- [ ] Checkpoint has 6-10 questions totaling ~10 points
- [ ] Exercise has clear acceptance criteria (4-6 items)
- [ ] No words: "amazing," "awesome," "powerful," "simply," "just"
- [ ] Trade-offs box present and balanced
- [ ] Debugging checklist has 5-8 concrete steps
- [ ] One-minute recap has exactly 5 bullets

---

## Example Reference Set (Good)

```yaml
references:
  - title: "Rails Guides — Active Record Query Interface"
    url: "https://guides.rubyonrails.org/active_record_querying.html"
    why: "Canonical reference for relations, scopes, and eager loading."

  - title: "Use The Index, Luke"
    url: "https://use-the-index-luke.com/"
    why: "Deep dive into SQL indexing across databases, including Postgres."

  - title: "RailsConf 2018 — The Case of the Missing Method (Noel Rappin)"
    url: "https://www.youtube.com/watch?v=p8IzTThzAHg"
    why: "How Rails autoloading and method lookup work under the hood."

  - title: "Evil Martians — Postgres Query Plans"
    url: "https://evilmartians.com/chronicles/postgresql-query-planner"
    why: "Practical guide to reading EXPLAIN ANALYZE output."

  - title: "Practical Object-Oriented Design (Sandi Metz)"
    url: "https://www.poodr.com/"
    why: "Foundational OO patterns applicable to Rails service objects."
```

---

## Anti-Patterns to Avoid

### ❌ Vague Statements
> "Performance can be improved with caching."

### ✅ Specific Statements
> "Fragment caching reduces view rendering time by 40-80% when hitting cached keys."

---

### ❌ Opinion Without Evidence
> "Callbacks are bad and you should never use them."

### ✅ Balanced Trade-off
> "Callbacks couple behavior to model lifecycle. Use for audit logs or cache invalidation; avoid for business logic that belongs in services."

---

### ❌ Code Without Context
```ruby
@posts = Post.all
```

### ✅ Code With Purpose
```ruby
# N+1 problem: triggers 1 + N queries
@posts = Post.all
@posts.each { |post| puts post.author.name }

# Solution: eager load authors
@posts = Post.includes(:author)
@posts.each { |post| puts post.author.name }
```

---

## Final Notes

- **Revise ruthlessly.** Cut 20% of your first draft.
- **Test all code.** Open a Rails console and run it.
- **Verify references.** Click every URL before shipping.
- **Read aloud.** If you stumble, rewrite.

**Target: 5–12 minutes to read, 10–20 minutes to practice.**
