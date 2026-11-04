# Taskflow Backend Technical Stack: Ruby on Rails

## Overview

This document specializes the generic Backend Technical Stack Selection Template to **Ruby on Rails**. The language, framework, ORM, and several conventions are fixed by the choice of Rails, so those sections now carry a decision instead of a menu. The remaining sections keep the select-one format, with a **Recommended** default marked in each.

The selected stack will be used to implement the Taskflow backend API: database operations, authentication, validation, and testing.

**Baseline assumption:** Rails 8.x on Ruby 3.3+, generated in API-only mode (`rails new taskflow-api --api -d postgresql`).

---

## 1. Runtime & Language

### Decision: Ruby + Ruby on Rails (fixed)

| Item | Choice | Notes |
| --- | --- | --- |
| Language | **Ruby 3.3+** | Pin the exact version in `.ruby-version` |
| Version manager | Select ONE below |  |
| Interpreter | **CRuby (MRI)** with YJIT enabled | YJIT gives a meaningful speedup at no code cost |

### Version manager - Select ONE:

| Option | Description | Pros | Cons |
| --- | --- | --- | --- |
| \[x\] **mise** (Recommended) | Polyglot version manager | One tool for Ruby, Node, etc.; fast | Newer than rbenv |
| \[ \] **rbenv** | Ruby-only version manager | Simple, widely used | Needs ruby-build plugin |
| \[ \] **asdf** | Polyglot version manager | Mature plugin ecosystem | Slower shims |
| \[ \] **RVM** | Ruby version manager | Gemsets, long history | Heavier, shell-intrusive |

---

## 2. Web Framework

### Select ONE:

| Option | Description | Pros | Cons |
| --- | --- | --- | --- |
| \[x\] **Rails (API-only mode)** (Recommended) | Full-stack framework trimmed to JSON APIs | Conventions, generators, migrations, mature ecosystem | Opinionated, heavier than micro-frameworks |
| \[ \] **Rails + Grape** | Rails with the Grape REST DSL | Explicit API versioning and params DSL | Two routing systems, extra learning |
| \[ \] **Sinatra** | Minimal Ruby web DSL | Tiny, simple | No batteries; rebuild what Rails gives |
| \[ \] **Hanami** | Modern, modular Ruby framework | Clean architecture, explicit boundaries | Smaller community and gem support |
| \[ \] **Roda** | Routing-tree framework | Very fast, lightweight | Small community, manual assembly |

### Rails-specific conventions for Taskflow

- Namespaced, versioned routes: `namespace :api { namespace :v1 { resources :projects } }` giving `/api/v1/...`
- Controllers live in `app/controllers/api/v1/`
- Base class `Api::V1::BaseController < ActionController::API`, with shared `rescue_from` error handling
- Use `config.api_only = true` to drop views, cookies, and asset pipeline middleware

---

## 3. Database

### Primary Database - Select ONE:

| Option | Description | Pros | Cons |
| --- | --- | --- | --- |
| \[x\] **PostgreSQL** (Recommended) | Advanced relational database | Recursive CTEs, `ltree`, `pg_trgm`, JSONB, best Rails support | More setup than SQLite |
| \[ \] **MySQL/MariaDB** | Popular relational database | Simple, widely hosted | Weaker fuzzy search and recursive query story |
| \[ \] **SQLite** | File-based database | Zero config; Rails 8 supports it well | Weak fit for concurrent production writes |
| \[ \] **SQL Server** | Microsoft's database | Enterprise features | Licensing, awkward Rails support |

**Why PostgreSQL fits Taskflow:** recursive subtask retrieval (recursive CTE or `ltree`), fuzzy search with relevance ranking (`pg_trgm` plus full-text search), and transactional bulk operations are all native.

### Recommended PostgreSQL extensions

- `pg_trgm`: trigram similarity for fuzzy search
- `unaccent`: accent-insensitive matching
- `ltree` (optional): materialized-path subtask hierarchies

---

## 4. ORM / Query Layer

### Decision: Active Record (fixed with Rails)

| Option | Description | Pros | Cons |
| --- | --- | --- | --- |
| \[x\] **Active Record** (Recommended) | Rails' built-in ORM | Migrations, associations, scopes, callbacks, `upsert_all` | Fat-model risk; callbacks can surprise |
| \[ \] **ROM-rb** | Data-mapper persistence | Explicit, no magic | Not Rails-native, steep curve |
| \[ \] **Sequel** | Standalone Ruby ORM | Powerful, fast, great SQL control | Loses Rails integrations |

### Companion gems - Select any that apply:

| Gem | Purpose in Taskflow | Select |
| --- | --- | --- |
| **ancestry** or **closure\_tree** | Subtask hierarchy and recursive retrieval | \[x\] one of the two |
| **pg\_search** | Fuzzy search with relevance ranking (trigram + tsearch) | \[x\] |
| **positioning** or **ranked-model** | Single and batch task reordering | \[x\] one of the two |
| **discard** | Soft delete, enabling restore (undo delete) | \[x\] |
| **strong\_migrations** | Catches unsafe migrations | \[x\] |
| **annotaterb** | Schema annotations in models | \[ \] optional |

### Migrations and seeding

- Migrations: Active Record migrations (`db/migrate`), schema in `db/schema.rb` (or `structure.sql` if using PG-specific features such as `ltree`)
- Seeding: `db/seeds.rb`, with idempotent `find_or_create_by`

---

## 5. Validation

### Select ONE primary approach:

| Option | Description | Pros | Cons |
| --- | --- | --- | --- |
| \[x\] **Active Record validations + Strong Parameters** (Recommended) | Model-level rules plus controller param whitelisting | Built in, zero dependencies | Rules tied to models |
| \[ \] **dry-validation / dry-schema** | Schema-based contract validation | Explicit, composable, validates before the model | Extra dependency and syntax |
| \[ \] **Active Model form objects** | Request-specific objects with `ActiveModel::Model` | Good for bulk and multi-model requests | Hand-rolled structure |
| \[ \] **JSON Schema (json\_schemer)** | Validate payloads against OpenAPI-derived schema | Single source of truth with docs | More setup |

**Suggested split:** use Active Record validations for domain invariants, Strong Parameters for input shaping, and form objects or dry-validation for bulk endpoints (bulk delete, complete, assign project).

---

## 6. Authentication (Future Consideration)

### Select ONE or MORE:

| Option | Description | Pros | Cons |
| --- | --- | --- | --- |
| \[ \] **Rails 8 built-in authentication generator** | Session-based, generated into your app | Simple, no extra gem, fully owned code | Cookie sessions suit browser clients best |
| \[ \] **Devise + devise-jwt** | Full auth suite with JWT | Mature, feature-rich | Heavy, lots of defaults |
| \[ \] **has\_secure\_password + JWT (`jwt` gem)** | Roll-your-own token auth | Minimal, API-friendly | You own revocation and security details |
| \[ \] **Doorkeeper (OAuth 2.0 provider)** | OAuth 2.0 server | Standard, third-party clients | Complex |
| \[ \] **OmniAuth** | OAuth / SSO strategies | Many providers | Needs session handling |
| \[ \] **Auth0 / Clerk / Supabase Auth** | Third-party service | Quick setup | Vendor lock-in, cost |
| \[x\] **None (No auth for MVP)** | Skip authentication | Fastest MVP | Not production-ready |

**Recommendation when auth is added:** Rails 8 authentication generator for same-site web clients, or `has_secure_password` + short-lived JWT with refresh tokens for separate SPA or mobile clients. Add `rack-cors` and `rack-attack` (rate limiting) at that point.

---

## 7. Logging

### Select ONE:

| Option | Description | Pros | Cons |
| --- | --- | --- | --- |
| \[x\] **Lograge** (Recommended) | Collapses Rails request logs into one line, JSON formatter available | Structured JSON, minimal setup | Needs custom fields for full context |
| \[ \] **Semantic Logger** | Structured, multi-appender logger | Powerful, JSON, async | Heavier, more configuration |
| \[ \] **Rails.logger (default)** | Built-in `ActiveSupport::Logger` | No dependencies, tagged logging | Multi-line text by default |
| \[ \] **Rails 8 structured event reporting** | `Rails.event` structured events | First-party | Newer, fewer integrations |

**Notes:**

- Use `config.log_tags = [:request_id]` and log to STDOUT in production (12-factor)
- Add `config.filter_parameters` entries for any sensitive fields
- Pair with an error tracker later (Sentry, Honeybadger, Rollbar)

---

## 8. Testing

### Framework - Select ONE:

| Option | Description | Pros | Cons |
| --- | --- | --- | --- |
| \[x\] **RSpec** (Recommended) | Behavior-driven testing framework | Expressive, rich ecosystem, request specs | Extra gem, DSL to learn |
| \[ \] **Minitest** | Rails default test framework | Built in, fast, simple | More verbose, smaller ecosystem |

### Supporting libraries - Select any that apply:

| Gem | Purpose | Select |
| --- | --- | --- |
| **factory\_bot\_rails** | Test data factories | \[x\] |
| **faker** | Realistic fake data | \[x\] |
| **shoulda-matchers** | One-line model validation and association tests | \[x\] |
| **rswag** | Request specs that generate OpenAPI docs | \[x\] if using OpenAPI |
| **database\_cleaner** | Usually unnecessary (transactional tests suffice) | \[ \] |
| **SimpleCov** | Coverage reporting | \[x\] |
| **WebMock / VCR** | Stub external HTTP | \[ \] when integrations appear |

**Test layout mapping:** unit tests for models and service objects, request specs for `/api/v1` endpoints (integration), `spec/support` for shared helpers.

---

## 9. API Documentation

### Select ONE:

| Option | Description | Pros | Cons |
| --- | --- | --- | --- |
| \[x\] **OpenAPI via rswag** (Recommended) | Specs generate the OpenAPI document and Swagger UI | Docs verified by tests, always in sync | Spec syntax is verbose |
| \[ \] **OpenAPI hand-written + committee** | Maintain YAML, validate requests/responses against it | Contract-first | Manual maintenance |
| \[ \] **apipie-rails** | DSL-based documentation | Inline with controllers | Less standard than OpenAPI |
| \[ \] **Postman Collections** | Exported collections | Interactive, team sharing | Not self-hosted |
| \[ \] **Custom Markdown** | Manual docs | Simple | Drifts out of date |

---

## 10. Caching & Background Jobs (Optional)

### Cache store - Select ONE:

| Option | Description | Pros | Cons |
| --- | --- | --- | --- |
| \[x\] **Solid Cache** (Rails 8 default) | Database-backed cache | No extra infrastructure | Slower than in-memory |
| \[ \] **Redis (`redis_cache_store`)** | In-memory data store | Very fast, versatile | Additional infrastructure |
| \[ \] **Memcached (Dalli)** | Distributed cache | Simple, fast | Fewer features than Redis |
| \[ \] **Memory store** | Per-process cache | Simple, no dependencies | Not shared across processes |
| \[ \] **None** | No caching for MVP | Simplest | Performance limits |

### Background jobs (Active Job backend) - Select ONE:

| Option | Description | Pros | Cons |
| --- | --- | --- | --- |
| \[x\] **Solid Queue** (Rails 8 default) | Database-backed queue | No Redis needed, first-party | Lower throughput than Redis queues |
| \[ \] **Sidekiq** | Redis-backed job processor | Fast, battle-tested | Redis required, paid tiers for some features |
| \[ \] **GoodJob** | Postgres-backed queue | Reliable, dashboard | Postgres load |
| \[ \] **None** | Run work inline | Simplest | No async processing |

Taskflow's current requirements (CRUD, search, bulk operations) do not strictly need background jobs; add one if bulk operations become large.

---

## 11. Dependency Management

### Decision: Bundler (fixed with Rails)

| Item | Choice |
| --- | --- |
| \[x\] **Bundler** | `Gemfile` and `Gemfile.lock`, committed to version control |
| Gem groups | `:development, :test` for RSpec, FactoryBot, RuboCop, Brakeman; default group for runtime gems |
| Security | `bundler-audit` in CI to flag vulnerable gems |

---

## 12. Code Quality Tools

### Linting and formatting - Select ONE:

| Option | Description | Pros | Cons |
| --- | --- | --- | --- |
| \[x\] **RuboCop (via rubocop-rails-omakase)** (Recommended) | Linter and formatter with Rails' omakase style | Default in Rails 8, minimal config | Opinionated, fewer rules |
| \[ \] **RuboCop + rubocop-rails + rubocop-rspec** | Fully configurable linting | Rich rule set, RSpec cops | Config effort |
| \[ \] **StandardRB** | Zero-config RuboCop wrapper | No style debates | Not customizable |

Rubyfmt is not needed: RuboCop's autocorrect handles formatting.

### Security and quality add-ons - Select any that apply:

| Tool | Purpose | Select |
| --- | --- | --- |
| **Brakeman** | Static security scanner for Rails | \[x\] |
| **bundler-audit** | Known-vulnerability check for gems | \[x\] |
| **Bullet** | N+1 query detection in development/test | \[x\] |
| **Reek / Flog** | Code smell and complexity | \[ \] optional |

---

## 13. Containerization (Optional)

### Select ONE:

| Option | Description | Pros | Cons |
| --- | --- | --- | --- |
| \[ \] **Docker** | Container platform | Rails 8 ships a production Dockerfile | Learning curve |
| \[x\] **Docker Compose** (Recommended) | Rails + PostgreSQL for local dev | One-command local setup | Compose-specific |
| \[ \] **Dev Containers** | Rails' devcontainer generator | Consistent editor environment | VS Code-centric |
| \[ \] **Podman** | Docker alternative | Rootless, daemonless | Less tooling |
| \[ \] **None** | No containerization | Simplest | Environment inconsistency |

**Deployment note:** Rails 8 includes **Kamal** for deploying containers to your own servers, and Thruster in front of Puma.

---

## 14. Architecture Mapping (Rails-specific)

The requirements call for a layered architecture of Controllers, Services, and Repositories. Rails does not have a repository layer by default; the choices below keep the layering without fighting the framework.

| Required layer | Rails implementation | Location |
| --- | --- | --- |
| Controllers | Thin `ActionController::API` controllers: params in, serializer out | `app/controllers/api/v1/` |
| Services | Plain Ruby service objects, one per use case (for example `Tasks::Complete`, `Tasks::Restore`) | `app/services/` |
| Repositories | **Option A (Recommended):** Active Record models with named scopes and query objects. **Option B:** explicit repository classes wrapping Active Record | `app/models/`, `app/queries/` |
| Serialization | JSON serializers | `app/serializers/` |
| Error handling | `rescue_from` in the base controller, mapped to a consistent JSON error shape | `Api::V1::BaseController` |
| Configuration | `config/credentials.yml.enc` plus environment variables, per-environment files | `config/` |

### Serializer - Select ONE:

| Option | Description | Pros | Cons |
| --- | --- | --- | --- |
| \[x\] **Alba** (Recommended) | Fast, flexible serializer | Fast, simple DSL, active development | Smaller community |
| \[ \] **jsonapi-serializer** | JSON:API spec serializer | Standard output, caching | Imposes JSON:API format |
| \[ \] **Blueprinter** | Declarative serializer | Views, simple | Fewer features |
| \[ \] **ActiveModelSerializers** | Classic serializer | Familiar | Poor maintenance momentum |
| \[ \] **Jbuilder** | Template-based JSON | Built in to Rails | Slow, template overhead |

### Pagination - Select ONE:

| Option | Description | Pros | Cons |
| --- | --- | --- | --- |
| \[x\] **Pagy** (Recommended) | Fast, lightweight pagination | Very fast, low memory | Different API from others |
| \[ \] **Kaminari** | Popular pagination gem | Familiar, flexible | Slower |
| \[ \] **will\_paginate** | Older pagination gem | Simple | Less active |

---

## Recommended Stack Combinations

### 1. Standard Rails API Stack (Recommended for Taskflow)

| Category | Selection |
| --- | --- |
| Runtime & Language | Ruby 3.3+ (YJIT) |
| Web Framework | Rails 8, API-only |
| Database | PostgreSQL (`pg_trgm`, `unaccent`) |
| ORM / Query Layer | Active Record + ancestry/closure\_tree, pg\_search, discard, positioning |
| Validation | Active Record validations + Strong Parameters (form objects for bulk) |
| Authentication | None for MVP; Rails 8 auth generator or JWT later |
| Logging | Lograge (JSON) |
| Testing | RSpec + FactoryBot + shoulda-matchers |
| API Documentation | OpenAPI via rswag |
| Caching / Jobs | Solid Cache / Solid Queue |
| Dependency Management | Bundler + bundler-audit |
| Linting & Formatting | RuboCop (omakase) + Brakeman |
| Serializer / Pagination | Alba / Pagy |
| Containerization | Docker Compose |

### 2. Lean MVP Rails Stack (For quick prototyping)

| Category | Selection |
| --- | --- |
| Runtime & Language | Ruby 3.3+ |
| Web Framework | Rails 8, API-only |
| Database | SQLite (dev) / PostgreSQL (prod) |
| ORM / Query Layer | Active Record + ancestry, discard |
| Validation | Active Record validations + Strong Parameters |
| Authentication | None |
| Logging | Rails.logger (default) |
| Testing | Minitest |
| API Documentation | Custom Markdown |
| Caching / Jobs | None |
| Dependency Management | Bundler |
| Linting & Formatting | RuboCop (omakase) |
| Serializer / Pagination | Jbuilder / Pagy |
| Containerization | None |

**Caveat:** fuzzy search with relevance ranking depends on PostgreSQL extensions, so SQLite in development means that feature cannot be exercised locally. Prefer PostgreSQL in both environments if search matters early.

### 3. Scalable / Enterprise Rails Stack (Larger teams, higher throughput)

| Category | Selection |
| --- | --- |
| Runtime & Language | Ruby 3.3+ (YJIT) |
| Web Framework | Rails 8, API-only, optionally with Grape |
| Database | PostgreSQL with read replicas |
| ORM / Query Layer | Active Record + closure\_tree, pg\_search, discard, ranked-model |
| Validation | dry-validation contracts + Active Record validations |
| Authentication | Devise + devise-jwt, or Doorkeeper for OAuth |
| Logging | Semantic Logger (JSON) + error tracker |
| Testing | RSpec + FactoryBot + SimpleCov + VCR |
| API Documentation | OpenAPI via rswag |
| Caching / Jobs | Redis cache + Sidekiq |
| Dependency Management | Bundler + bundler-audit |
| Linting & Formatting | RuboCop + rubocop-rails + rubocop-rspec, Brakeman |
| Serializer / Pagination | Alba / Pagy |
| Containerization | Docker + Kamal |

---

## Additional Notes

### Required Backend Features (from requirements) and Rails approach

| Requirement | Rails approach |
| --- | --- |
| RESTful API with versioned endpoints (`/api/v1/...`) | Nested `namespace :api / :v1` routes and `Api::V1` controllers |
| Layered architecture (Controllers, Services, Repositories) | See section 14: thin controllers, service objects, Active Record scopes/query objects |
| Database migrations and seeding | Active Record migrations, `db/seeds.rb`, `bin/rails db:setup` |
| Request validation and error handling | Strong Parameters, model validations, `rescue_from` returning a uniform JSON error body |
| Structured JSON logging | Lograge with JSON formatter, request ID tagging |
| Unit and integration testing | RSpec model/service specs plus request specs |
| Environment-based configuration | `config/environments/*.rb`, Rails credentials, `ENV` variables |

### API Endpoints to Implement and Rails approach

| Area | Scope | Rails approach |
| --- | --- | --- |
| **Projects** | CRUD, task count calculation | `resources :projects`; use `counter_cache` or a grouped count query for task counts |
| **Tasks** | CRUD, completion toggle, restore (undo delete) | `resources :tasks` with member routes `complete` and `restore`; soft delete via `discard` |
| **Subtasks** | Create, recursive retrieval, cascade operations | `ancestry` or `closure_tree` (or a recursive CTE); `dependent: :destroy` or discard cascade in a transaction |
| **Progress** | Overall and task-level progress calculation | Query object or service aggregating completed vs total, including descendants |
| **Search** | Fuzzy search with relevance ranking | `pg_search` (trigram + tsearch) with `ranked_by` |
| **Bulk Operations** | Bulk delete, complete, assign project | Collection routes, one transaction per request, `update_all` / `upsert_all` for efficiency (note these skip callbacks and validations) |
| **Reordering** | Single and batch task reordering | `positioning` or `ranked-model` for single moves; transactional batch update for bulk reorder |

### Pitfalls to watch for

- **N+1 queries** when loading subtask trees: use `includes` and keep Bullet enabled in development and test
- **Callbacks hiding business logic:** keep rules in service objects, and use callbacks only for simple data integrity
- **Bulk methods skip validations:** `update_all`, `delete_all`, and `upsert_all` bypass callbacks, so validate inputs explicitly
- **Deep recursion:** cap subtask depth or enforce it in validation to keep recursive queries predictable
- **Soft delete and uniqueness:** unique indexes need to account for discarded records (partial indexes)
