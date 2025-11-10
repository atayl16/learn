# Rails Seniority Coach — Study Routes

Three prebuilt learning paths tailored to different time commitments and goals. Choose one or mix topics based on your needs.

---

## Route 1: 12-Week Standard Track

**Target:** Mid → Senior (Strong depth across all core areas)
**Time:** 3-4 hours/week (3 topics/week)
**Best for:** Steady progression while working full-time

### Weekly Breakdown

#### Weeks 1-2: Rails Foundations
**Goal:** Understand request flow and core Active Record patterns

| Week | Topics | Hours |
|------|--------|-------|
| 1 | request_lifecycle, autoloading_boot, ar_relations | 3-4 |
| 2 | validations_callbacks, routing_middleware, config_initializers | 3-4 |

**Checkpoint:** Can trace a Rails request from Rack to view; can write complex AR queries.

---

#### Weeks 3-4: SQL Fundamentals
**Goal:** Design schemas and optimize queries

| Week | Topics | Hours |
|------|--------|-------|
| 3 | modeling_constraints, indexing, explain_analyze | 3-4 |
| 4 | transactions_locks, zero_downtime_migrations, ctes_windows | 3-4 |

**Checkpoint:** Can add indexes based on EXPLAIN; can write safe migrations for production.

---

#### Weeks 5-6: Jobs & Performance
**Goal:** Handle async work and eliminate N+1s

| Week | Topics | Hours |
|------|--------|-------|
| 5 | sidekiq_basics, idempotency_retries, scheduling | 3-4 |
| 6 | job_instrumentation, n_plus_one, eager_preload | 3-4 |

**Checkpoint:** Can write idempotent jobs; can fix N+1 queries using Bullet.

---

#### Weeks 7-8: Caching & Observability
**Goal:** Speed up apps and debug production issues

| Week | Topics | Hours |
|------|--------|-------|
| 7 | fragment_caching, cache_keys_invalidations, memory_gc_basics | 3-4 |
| 8 | structured_logging, error_tracking_model, apm_traces | 3-4 |

**Checkpoint:** Can implement Russian-doll caching; can read APM flamegraphs.

---

#### Weeks 9-10: API & Security
**Goal:** Design secure, scalable APIs

| Week | Topics | Hours |
|------|--------|-------|
| 9 | rest_design, pagination_filtering, error_shapes, authn_authz | 4 |
| 10 | idempotency_rate_limits, versioning, csrf_cors | 3 |

**Checkpoint:** Can design a paginated API with auth and rate limiting.

---

#### Weeks 11-12: Frontend & Architecture
**Goal:** Integrate frontend and design maintainable systems

| Week | Topics | Hours |
|------|--------|-------|
| 11 | hotwire_frames_streams, stimulus_patterns, forms_progressive, metrics_slos | 4 |
| 12 | layering_services, testing_strategy, feature_flags_rollouts, adrs, microservices_when_not | 4 |

**Checkpoint:** Can build a Hotwire feature; can design a service layer and write ADRs.

---

### Study Rhythm
- **Monday:** Read 1 overview (10-15 min)
- **Wednesday:** Read 1 overview + do 1 exercise (30-40 min)
- **Friday:** Read 1 overview, take 1 checkpoint quiz (20-30 min)
- **Weekend:** Finish exercises + review weak spots (60-90 min)

**Weekly reviews:** Spend 15 minutes on Friday reviewing your checkpoint scores and flagging topics to revisit.

---

## Route 2: 6-Week Fast Track

**Target:** Mid → Senior (accelerated, focus on Rails/SQL/Jobs/Observability)
**Time:** 6-8 hours/week (5-6 topics/week)
**Best for:** Preparing for interviews or stepping into a senior role soon

### Weekly Breakdown

#### Week 1: Rails Core
request_lifecycle, autoloading_boot, ar_relations, validations_callbacks, routing_middleware, config_initializers

**Checkpoint:** Can debug Rails boot issues; can write complex AR queries with scopes.

---

#### Week 2: SQL Mastery
modeling_constraints, indexing, explain_analyze, transactions_locks, zero_downtime_migrations, ctes_windows

**Checkpoint:** Can tune slow queries; can write zero-downtime migrations.

---

#### Week 3: Jobs & Caching
sidekiq_basics, idempotency_retries, scheduling, job_instrumentation, n_plus_one, eager_preload

**Checkpoint:** Can write idempotent jobs; can eliminate N+1 queries.

---

#### Week 4: Performance & Observability
fragment_caching, cache_keys_invalidations, memory_gc_basics, structured_logging, error_tracking_model, apm_traces

**Checkpoint:** Can implement caching strategies; can debug prod issues with logs/traces.

---

#### Week 5: API Design & Security
rest_design, pagination_filtering, error_shapes, authn_authz, idempotency_rate_limits, versioning, csrf_cors

**Checkpoint:** Can design a production-ready API with auth and rate limiting.

---

#### Week 6: Frontend & Architecture
hotwire_frames_streams, stimulus_patterns, forms_progressive, react_working_fundamentals, layering_services, testing_strategy, feature_flags_rollouts, adrs, metrics_slos

**Checkpoint:** Can build Hotwire features; can design layered architecture with tests.

---

### Study Rhythm
- **Weekdays:** 1 topic/day (overview + exercise, 60-90 min)
- **Weekends:** 2-3 topics (overview + exercise + checkpoint, 3-4 hours)
- **Daily reviews:** 15 minutes to revisit previous day's topic

**Weekly reviews:** Spend 30 minutes on Sunday reviewing checkpoint scores and weak spots.

---

## Route 3: Weekends-Only Track (10 Weeks)

**Target:** Mid → Senior (deeper exercises, spaced repetition)
**Time:** 4-5 hours/weekend (2 topics/week)
**Best for:** Busy schedules; prefer depth over speed

### Weekly Breakdown

#### Weeks 1-2: Rails Core
| Week | Topics | Hours |
|------|--------|-------|
| 1 | request_lifecycle, autoloading_boot | 4 |
| 2 | ar_relations, validations_callbacks | 4 |

---

#### Weeks 3-4: Rails + SQL
| Week | Topics | Hours |
|------|--------|-------|
| 3 | routing_middleware, config_initializers | 4 |
| 4 | modeling_constraints, indexing | 4 |

---

#### Weeks 5-6: SQL Deep Dive
| Week | Topics | Hours |
|------|--------|-------|
| 5 | explain_analyze, transactions_locks | 5 |
| 6 | zero_downtime_migrations, ctes_windows | 5 |

---

#### Weeks 7-8: Jobs & Caching
| Week | Topics | Hours |
|------|--------|-------|
| 7 | sidekiq_basics, idempotency_retries | 4 |
| 8 | scheduling, job_instrumentation | 4 |

---

#### Week 9: Performance
n_plus_one, eager_preload (4 hours)

---

#### Week 10: Caching
fragment_caching, cache_keys_invalidations (4 hours)

---

#### Weeks 11-12: Observability & API
| Week | Topics | Hours |
|------|--------|-------|
| 11 | memory_gc_basics, structured_logging | 4 |
| 12 | error_tracking_model, apm_traces | 4 |

---

#### Weeks 13-14: API Design
| Week | Topics | Hours |
|------|--------|-------|
| 13 | rest_design, pagination_filtering | 4 |
| 14 | error_shapes, authn_authz | 5 |

---

#### Weeks 15-16: Security & Frontend
| Week | Topics | Hours |
|------|--------|-------|
| 15 | idempotency_rate_limits, versioning, csrf_cors | 5 |
| 16 | metrics_slos, hotwire_frames_streams | 4 |

---

#### Weeks 17-18: Frontend & Architecture
| Week | Topics | Hours |
|------|--------|-------|
| 17 | stimulus_patterns, forms_progressive | 4 |
| 18 | react_working_fundamentals, layering_services | 5 |

---

#### Weeks 19-20: Architecture & Testing
| Week | Topics | Hours |
|------|--------|-------|
| 19 | testing_strategy, feature_flags_rollouts | 5 |
| 20 | adrs, microservices_when_not | 4 |

---

### Study Rhythm
- **Saturday morning:** Read 1 overview, start exercise (2 hours)
- **Saturday afternoon:** Finish exercise, do stretch goal (1 hour)
- **Sunday morning:** Read 2nd overview, do exercise (2-3 hours)
- **Sunday afternoon:** Take 2 checkpoint quizzes, review (1 hour)

**Monthly reviews:** Spend 1 hour at the end of each month reviewing weak checkpoint scores.

---

## Custom Route: Topic-by-Priority

If none of the above fit, prioritize based on your **current gaps**:

### Priority 1 (Critical for seniors)
- request_lifecycle, ar_relations, indexing, explain_analyze
- n_plus_one, eager_preload, sidekiq_basics, idempotency_retries
- rest_design, authn_authz, testing_strategy
- docker_containerization, ci_cd_pipelines, deployment_strategies

### Priority 2 (Needed for production work)
- validations_callbacks, transactions_locks, zero_downtime_migrations
- fragment_caching, cache_keys_invalidations, structured_logging
- pagination_filtering, error_shapes, hotwire_frames_streams
- config_secrets, health_checks_graceful, refactoring_patterns, legacy_code

### Priority 3 (Rounding out skills)
- autoloading_boot, routing_middleware, config_initializers
- ctes_windows, scheduling, job_instrumentation, memory_gc_basics
- error_tracking_model, apm_traces, metrics_slos, versioning, csrf_cors
- stimulus_patterns, forms_progressive, layering_services, feature_flags_rollouts, adrs
- asset_pipeline_cdn, technical_debt, code_review

### Priority 4 (Nice to have)
- react_working_fundamentals, microservices_when_not
- metaprogramming_patterns, memory_model, concurrency_primitives, dsl_design
- etl_patterns, event_tracking, report_generation, data_warehouses

**Custom study plan:** Pick 2-3 from Priority 1 each week until complete, then move to Priority 2.

---

## Progress Tracking

Use this checklist to track completion:

### Rails Internals (6 topics)
- [ ] request_lifecycle
- [ ] autoloading_boot
- [ ] ar_relations
- [ ] validations_callbacks
- [ ] routing_middleware
- [ ] config_initializers

### SQL/Postgres (6 topics)
- [ ] modeling_constraints
- [ ] indexing
- [ ] explain_analyze
- [ ] transactions_locks
- [ ] zero_downtime_migrations
- [ ] ctes_windows

### Background Jobs (4 topics)
- [ ] sidekiq_basics
- [ ] idempotency_retries
- [ ] scheduling
- [ ] job_instrumentation

### Caching/Performance (5 topics)
- [ ] n_plus_one
- [ ] eager_preload
- [ ] fragment_caching
- [ ] cache_keys_invalidations
- [ ] memory_gc_basics

### Observability (4 topics)
- [ ] structured_logging
- [ ] error_tracking_model
- [ ] apm_traces
- [ ] metrics_slos

### API & Security (7 topics)
- [ ] rest_design
- [ ] pagination_filtering
- [ ] error_shapes
- [ ] authn_authz
- [ ] idempotency_rate_limits
- [ ] versioning
- [ ] csrf_cors

### Frontend Integration (4 topics)
- [ ] hotwire_frames_streams
- [ ] stimulus_patterns
- [ ] forms_progressive
- [ ] react_working_fundamentals

### Architecture & Design (5 topics)
- [ ] layering_services
- [ ] testing_strategy
- [ ] feature_flags_rollouts
- [ ] adrs
- [ ] microservices_when_not

### Deployment & Infrastructure (6 topics)
- [ ] docker_containerization
- [ ] ci_cd_pipelines
- [ ] deployment_strategies
- [ ] asset_pipeline_cdn
- [ ] config_secrets
- [ ] health_checks_graceful

### Advanced Ruby Internals (4 topics)
- [ ] metaprogramming_patterns
- [ ] memory_model
- [ ] concurrency_primitives
- [ ] dsl_design

### Code Quality & Refactoring (4 topics)
- [ ] refactoring_patterns
- [ ] legacy_code
- [ ] technical_debt
- [ ] code_review

### Data & Analytics (4 topics)
- [ ] etl_patterns
- [ ] event_tracking
- [ ] report_generation
- [ ] data_warehouses

### AI & Machine Learning (5 topics)
- [ ] llm_api_integration
- [ ] ai_powered_features
- [ ] content_moderation_ai
- [ ] ai_dev_tools
- [ ] rag_systems

---

## Study Tips

### Before Starting
1. **Self-assess** using the rubric (meta/_rubric.md)
2. **Pick a route** or customize based on your gaps
3. **Set a calendar reminder** for study blocks
4. **Clone a Rails app** or use an existing project for exercises

### During Study
1. **No passive reading.** Type out code samples.
2. **Do exercises in a real Rails app,** not isolated scripts.
3. **Take checkpoint quizzes immediately** after finishing the overview.
4. **Revisit wrong answers** — read the "why" explanations.

### After Each Topic
1. **One-sentence summary:** Write what you learned.
2. **Flag for review:** If checkpoint score < 70%, revisit in 1 week.
3. **Apply immediately:** Find a place in your work code to use it.

### Weekly Reviews
1. **Check checkpoint scores** — aim for 80%+ on Strong topics.
2. **Revisit 1-2 weak topics** from previous weeks.
3. **Update progress checklist** — track momentum.

### Monthly Reviews
1. **Retake checkpoint quizzes** for topics from 3-4 weeks ago (spaced repetition).
2. **Scan references** for deeper dives on weak areas.
3. **Teach one topic** to a peer or write a blog post.

---

## Completion Criteria

You've finished when you can:

✅ **Explain** any topic from memory (2-minute verbal summary)
✅ **Implement** core patterns without docs
✅ **Debug** production issues using checklists
✅ **Score 80%+** on all checkpoint quizzes for Strong topics
✅ **Complete** all exercises + 50% of stretch goals

**Next steps:**
- Apply these skills in real projects
- Mentor a junior through 3-5 topics
- Contribute to open source (Rails, Sidekiq, Postgres extensions)
- Write blog posts or give talks on 2-3 topics

---

## FAQs

**Q: Can I skip topics I already know?**
A: Yes, but take the checkpoint quiz first. If you score 80%+, skip it. If not, skim the overview and do the exercise.

**Q: What if I fall behind?**
A: Adjust your route. Switch from 12-week to weekends-only, or focus on Priority 1 topics only.

**Q: Should I do all 64 topics?**
A: For senior IC roles, aim for all Priority 1 + Priority 2 topics (40+ total). Priority 3/4 are optional but recommended for well-rounded expertise.

**Q: Can I use this for interview prep?**
A: Yes. Focus on Priority 1 topics + rest_design + testing_strategy. 4-6 weeks is enough for most senior Rails interviews.

**Q: How do I know if I'm senior-ready?**
A: If you can complete 80% of exercises without docs and score 80%+ on checkpoint quizzes for all Priority 1 topics, you're ready.
