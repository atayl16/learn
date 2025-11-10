# Rails Seniority Coach — Content Library

A comprehensive, content-first learning curriculum that takes mid-level Rails+React developers to senior-level expertise across 13 tracks and 64 topics.

## Overview

This repository contains **YAML metadata** and **Markdown content** organized into skill tracks. Each topic includes:

- **Overview** (600-900 words): Concise teaching with examples
- **Exercise** (15-25 minutes): Hands-on practice with acceptance criteria
- **Checkpoint** (6-10 questions): Auto-gradable quiz with explanations
- **References** (6-7 sources): Curated official docs, books, and talks

## Quick Start

### Option 1: GitHub Pages (Recommended)

Browse the curriculum online with a fully-featured web interface:

**[https://atayl16.github.io/learn/](https://atayl16.github.io/learn/)**

**Features:**
- Browse all tracks and topics with a clean, responsive interface
- Read content in tabbed views (Overview, Exercise, Checkpoint, References)
- Take checkpoint quizzes with instant client-side scoring
- Full-text search across all topics
- Dark mode support
- Progress tracking (saved in browser)
- Markdown rendering with syntax highlighting
- No login required

### Option 2: Local Development Server

Run the Sinatra viewer locally for development or offline use:

```bash
cd viewer
bundle install
bundle exec ruby app.rb

# Visit http://localhost:4567
```

See **[viewer/README.md](viewer/README.md)** for full documentation.

### Option 3: Browse Content Locally

**Markdown Preview**
```bash
# Open any topic overview in your editor
open content/rails_internals/request_lifecycle/overview.md

# Or use a Markdown viewer
npm install -g marked
marked content/rails_internals/request_lifecycle/overview.md
```

**File Explorer**
```bash
# List all tracks
ls content/

# List all topics in a track
ls content/rails_internals/

# Read a topic
cat content/rails_internals/request_lifecycle/overview.md
```

### Recommended Study Routes

See **[meta/_study_routes.md](meta/_study_routes.md)** for three prebuilt learning paths:

1. **12-Week Standard** (3-4 hours/week) - Steady progression
2. **6-Week Fast Track** (6-8 hours/week) - Interview prep
3. **Weekends-Only** (4-5 hours/weekend) - Deeper practice

## Content Structure

```
.
├── README.md                 # This file
├── meta/
│   ├── coverage_index.yml    # Complete topic list with depth targets
│   ├── _style_guide.md       # Content authoring standards
│   ├── _rubric.md            # Mastery levels (Exposure/Working/Strong/Expert)
│   └── _study_routes.md      # Three prebuilt learning paths
├── config/
│   └── skills/
│       ├── tracks.yml        # Track metadata (13 tracks)
│       └── {track}/          # Per-track YAML configs (64 topics)
│           └── {topic}.yml
└── content/
    └── {track}/{topic}/      # 64 topics × 4 files = 256 content files
        ├── overview.md       # Teaching content (600-900 words)
        ├── exercise.md       # Hands-on task (15-25 min)
        ├── checkpoint.yml    # Quiz (6-10 questions)
        └── references.yml    # Curated sources (6-7 links)
```

## Coverage: 13 Tracks, 64 Topics

### 1. Rails Internals (6 topics, Strong depth)
- `request_lifecycle` - Request lifecycle & middleware
- `autoloading_boot` - Zeitwerk/autoloading & boot sequence
- `ar_relations` - Active Record relations & query interface
- `validations_callbacks` - Validations, callbacks & concerns
- `routing_middleware` - Routing & middleware patterns
- `config_initializers` - Configuration & initializers

### 2. SQL & PostgreSQL (6 topics, Strong depth)
- `modeling_constraints` - Modeling & constraints (FKs, uniques, check)
- `indexing` - Indexing strategies
- `explain_analyze` - EXPLAIN/ANALYZE & query plans
- `transactions_locks` - Transactions, isolation & locks
- `zero_downtime_migrations` - Zero-downtime migrations
- `ctes_windows` - CTEs & window functions

### 3. Background Jobs & Redis (4 topics, Strong depth)
- `sidekiq_basics` - ActiveJob vs Sidekiq fundamentals
- `idempotency_retries` - Idempotency patterns & retries
- `scheduling` - Job scheduling & deduplication
- `job_instrumentation` - Job instrumentation & backoff

### 4. Caching & Performance (5 topics, Strong depth)
- `n_plus_one` - N+1 detection & resolution
- `eager_preload` - Eager loading vs preloading
- `fragment_caching` - Fragment & low-level caching
- `cache_keys_invalidations` - Cache keys & invalidation strategies
- `memory_gc_basics` - Memory & GC awareness

### 5. Observability (4 topics, Working→Strong)
- `structured_logging` - Structured logging with lograge (Strong)
- `error_tracking_model` - Error tracking mental model (Working)
- `apm_traces` - APM basics & flamegraphs (Working)
- `metrics_slos` - Metrics & SLO thinking (Working)

### 6. API Design & Security (7 topics, Strong depth)
- `rest_design` - REST design patterns
- `pagination_filtering` - Pagination, filtering & sorting
- `error_shapes` - API error shapes & standards
- `authn_authz` - AuthN/AuthZ with Pundit
- `idempotency_rate_limits` - Idempotency keys & rate limiting
- `versioning` - API versioning strategies
- `csrf_cors` - CSRF, CORS & input validation

### 7. Frontend Integration (4 topics)
- `hotwire_frames_streams` - Hotwire: Frames & Streams (Strong)
- `stimulus_patterns` - Stimulus patterns & best practices (Strong)
- `forms_progressive` - Forms & progressive enhancement (Strong)
- `react_working_fundamentals` - React: Working fundamentals (Working)

### 8. Architecture & Design (5 topics)
- `layering_services` - Layering & boundaries (Strong)
- `testing_strategy` - Testing strategy (unit/request/system) (Strong)
- `feature_flags_rollouts` - Feature flags & safe rollouts (Strong)
- `adrs` - ADRs & lightweight documentation (Strong)
- `microservices_when_not` - When NOT to microservice (Working)

### 9. Deployment & Infrastructure (6 topics, Working→Strong depth)
- `docker_containerization` - Docker & containerization basics (Strong)
- `ci_cd_pipelines` - CI/CD pipelines (Strong)
- `deployment_strategies` - Deployment strategies (Strong)
- `asset_pipeline_cdn` - Asset pipeline & CDN (Working)
- `config_secrets` - Config & secrets management (Strong)
- `health_checks_graceful` - Health checks & graceful shutdowns (Strong)

### 10. Advanced Ruby Internals (4 topics, Working depth)
- `metaprogramming_patterns` - Metaprogramming patterns (Working)
- `memory_model` - Ruby memory model & object allocation (Working)
- `concurrency_primitives` - Concurrency primitives (Ractor, Fiber, Thread) (Working)
- `dsl_design` - DSL design patterns (Working)

### 11. Code Quality & Refactoring (4 topics, Strong depth)
- `refactoring_patterns` - Refactoring patterns in Rails (Strong)
- `legacy_code` - Working with legacy code (Strong)
- `technical_debt` - Technical debt assessment & management (Strong)
- `code_review` - Code review techniques (Strong)

### 12. Data & Analytics (4 topics, Working depth)
- `etl_patterns` - ETL patterns in Rails (Working)
- `event_tracking` - Event tracking & analytics (Working)
- `report_generation` - Report generation strategies (Working)
- `data_warehouses` - Working with data warehouses (Working)

### 13. AI & Machine Learning (5 topics, Working depth)
- `llm_api_integration` - LLM API integration basics (Working)
- `ai_powered_features` - AI-powered search & recommendations (Working)
- `content_moderation_ai` - Content moderation & classification (Working)
- `ai_dev_tools` - AI development workflows (Working)
- `rag_systems` - RAG systems in Rails (Working)

## Depth Targets

See **[meta/_rubric.md](meta/_rubric.md)** for detailed explanations.

- **Exposure** - Can define the term; knows when it might apply
- **Working** - Can implement with notes; can debug common issues
- **Strong** - Can design, debug in prod, and teach others ⭐ (Target for 48/64 topics)
- **Expert** - Can choose trade-offs, optimize, extend patterns safely

## Suggested Weekly Plan (12-Week Standard)

| Week | Topics | Focus Area |
|------|--------|------------|
| 1-2 | Rails Internals (6 topics) | Request flow, AR, autoloading |
| 3-4 | SQL/Postgres (6 topics) | Schema, indexes, query plans |
| 5 | Background Jobs (3 topics) | Sidekiq, idempotency, scheduling |
| 6 | Caching/Performance (2 topics + 1 job) | N+1, eager loading, job instrumentation |
| 7 | Caching/Performance (3 topics) | Fragment caching, invalidation, memory |
| 8 | Observability (4 topics) | Logging, errors, APM, metrics |
| 9-10 | API & Security (7 topics) | REST, auth, rate limits, CORS |
| 11 | Frontend Integration (4 topics) | Hotwire, Stimulus, React basics |
| 12 | Architecture & Design (5 topics) | Layering, testing, flags, ADRs |

**Weekly rhythm:**
- **Monday**: Read 1 overview (10-15 min)
- **Wednesday**: Read 1 overview + do 1 exercise (30-40 min)
- **Friday**: Read 1 overview, take 1 checkpoint quiz (20-30 min)
- **Weekend**: Finish exercises + review weak spots (60-90 min)

See **[meta/_study_routes.md](meta/_study_routes.md)** for 6-week fast track and weekends-only routes.

## How to Use This Content

### 1. Self-Paced Learning

```bash
# Pick a topic
cd content/rails_internals/request_lifecycle/

# Read overview
cat overview.md

# Do exercise
cat exercise.md
# (Follow setup code, verify acceptance criteria)

# Take quiz
cat checkpoint.yml
# (Answer questions, check score, read explanations)

# Dive deeper
cat references.yml
# (Click through 5-7 curated sources)
```

### 2. Track Progress

Use the checklist in **[meta/_study_routes.md](meta/_study_routes.md)**:

```markdown
### Rails Internals (6 topics)
- [x] request_lifecycle
- [ ] autoloading_boot
- [ ] ar_relations
...
```

### 3. Study Tips

**Before starting:**
1. Self-assess using **[meta/_rubric.md](meta/_rubric.md)**
2. Pick a route or customize based on your gaps
3. Set calendar reminders for study blocks

**During study:**
1. Type out code samples (no passive reading)
2. Do exercises in a real Rails app
3. Take checkpoint quizzes immediately after overview
4. Revisit wrong answers — read the "why" explanations

**After each topic:**
1. Write one-sentence summary
2. Flag for review if checkpoint score < 70%
3. Apply immediately in your work code

**Weekly reviews:**
1. Check checkpoint scores — aim for 80%+ on Strong topics
2. Revisit 1-2 weak topics from previous weeks
3. Update progress checklist

**Monthly reviews:**
1. Retake checkpoint quizzes for topics from 3-4 weeks ago
2. Scan references for deeper dives
3. Teach one topic to a peer or write a blog post

### 4. Completion Criteria

You've finished when you can:

- ✅ Explain any topic from memory (2-minute verbal summary)
- ✅ Implement core patterns without docs
- ✅ Debug production issues using checklists
- ✅ Score 80%+ on all checkpoint quizzes for Strong topics
- ✅ Complete all exercises + 50% of stretch goals

## Next Steps After Completion

1. **Apply** - Use these skills in real projects
2. **Mentor** - Guide a junior through 3-5 topics
3. **Contribute** - Contribute to Rails, Sidekiq, or Postgres extensions
4. **Share** - Write blog posts or give talks on 2-3 topics
5. **Interview** - Ready for senior IC Rails roles

## Time Estimates

- **Total topics**: 64
- **Total estimated hours**: 70-110 hours (reading + exercises + quizzes)
- **16-week plan**: 4-5 hours/week
- **8-week fast track**: 8-10 hours/week
- **Weekends-only**: 4-5 hours/weekend over 14 weeks

## Content Philosophy

This curriculum follows these principles:

1. **Concise, not chatty** - Every word earns its place
2. **Truth-only sources** - Official docs, canonical books, well-known talks
3. **Show trade-offs** - Costs and benefits, not just how
4. **Runnable code** - All examples work in isolation
5. **Working → Strong** - Get to production-ready skills fast

See **[meta/_style_guide.md](meta/_style_guide.md)** for full content standards.

## File Counts

- **13 tracks** (defined in `config/skills/tracks.yml`)
- **64 topics** (YAML config files in `config/skills/{track}/`)
- **256 content files** (64 topics × 4 files each)
- **5 meta files** (coverage, style guide, rubric, study routes, tracks)
- **Total: 326 files**

## Licensing & Usage

This content is provided as-is for learning purposes. All references point to publicly available official documentation, books, and resources.

## Questions?

- **What is this?** A content-first Rails learning curriculum with a web viewer
- **How do I browse it?** Visit https://atayl16.github.io/learn/ or run the local server
- **Can I use it offline?** Yes! Run the Sinatra viewer locally or browse markdown files directly
- **What order should I follow?** See **[meta/_study_routes.md](meta/_study_routes.md)**
- **How long will it take?** 12 weeks at 3-4 hours/week (standard pace)
- **Is this for beginners?** No, it assumes mid-level Rails experience
- **What's the end goal?** Senior IC-level skills across Rails, SQL, APIs, and architecture

---

**Ready to start?** Open **[meta/coverage_index.yml](meta/coverage_index.yml)** to see all 64 topics, then jump into your first overview:

```bash
cat content/rails_internals/request_lifecycle/overview.md
```

Happy learning! 🚀
