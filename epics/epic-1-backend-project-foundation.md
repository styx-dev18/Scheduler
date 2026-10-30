# Epic 0: Technical Stack Overview (Ruby on Rails)

## Architecture Approach

**Layered Rails API (API-only) with a pure-Ruby domain core**

The project follows Rails conventions while preserving the separation of concerns needed for a scheduling engine whose correctness depends on testable business rules:

- Thin controllers, one service object per use case, Active Record models with named scopes and query objects (Option A in the Rails stack document)
- Scheduling rules (interval overlap, slot grid, assignment, status machine) live in **plain Ruby objects** under `app/domain/scheduling/`, with no Active Record dependency, so they can be unit-tested without a database
- Active Record models act as the persistence-backed aggregates and enforce their own invariants; no separate persistence-mapping layer (that would fight the framework)
- The database is the final authority for correctness (exclusion constraints), not application code

> **Adaptation note:** a strict Clean Architecture "dependency rule" is relaxed for Active Record models. The rule that **is** enforced: `app/domain/` must never reference `ActiveRecord`, controllers, or `Rails.*` (checked by an architecture spec; see Epic 7).

## Selected Technology Stack

Baseline: **Rails 8.x on Ruby 3.3+** (pinned to 3.4.10), generated at the repository root with `rails new . --api -d postgresql --skip-test --name=scheduler_api` so the app sits next to `.claude/` and `epics/`.

### Runtime & Language

| Item | Choice | Notes |
|---|---|---|
| Language | Ruby 3.3+ | Pinned in `.ruby-version` |
| Interpreter | CRuby (MRI) with YJIT | YJIT is on by default in Rails 8 when available |
| Version manager | rbenv | `.ruby-version` committed at the repository root |

### Web Framework

- **Rails (API-only mode)**: `config.api_only = true`
- Versioned, namespaced routes: `namespace :api { namespace :v1 { ... } }` giving `/api/v1/...`
- Controllers in `app/controllers/api/v1/`; shared `Api::V1::BaseController < ActionController::API` with `rescue_from` error handling
- CORS via `rack-cors` (origins from `CORS_ORIGINS`)

### Database & Persistence

- **PostgreSQL** (required, not just recommended): range types (`tstzrange`), GiST indexes and **exclusion constraints** guarantee no double-booking at the database level
- Extensions: `btree_gist` (mandatory), `pgcrypto` / built-in `gen_random_uuid()` for UUID keys
- **ORM:** Active Record. UUID primary keys (`primary_key_type: :uuid` in generators)
- Schema format: **`db/structure.sql`** (`config.active_record.schema_format = :sql`), because the schema uses PG-specific features (virtual range column, GiST exclusion constraints)
- Companion gems: `strong_migrations` (unsafe-migration guard). Not used here: `ancestry`/`closure_tree`, `pg_search`, `positioning`, `discard` (no hierarchy, search, ordering, or soft delete in this domain; cancellation is a status)

### Validation

- **Active Record validations + Strong Parameters** for input shaping and invariants
- Business-rule validation (ownership, opening hours, availability) lives in service objects and returns `Failure` results, not exceptions
- Form objects (`ActiveModel::Model`) for request-shaped inputs such as the booking request

### Result Handling

- **dry-monads** (`Success` / `Failure`) for expected business outcomes in service objects. Controllers map failures to HTTP via the error catalogue.

### Authentication & Security

- **None for MVP (assumption A8).** Customer and vehicle are referenced by ID. `Api::V1::BaseController` keeps a `current_customer` seam so the Rails 8 authentication generator or `has_secure_password` + JWT can be added later.
- Security tooling: Brakeman, bundler-audit; `rack-attack` for rate limiting (Epic 6)

### Logging, Metrics & Tracing

- **Logging:** Lograge (JSON) with `config.log_tags = [:request_id]`, STDOUT in production
- **Metrics:** Yabeda (`yabeda-rails`, `yabeda-puma-plugin`, `yabeda-prometheus`) exposed at `/metrics`
- **Tracing:** OpenTelemetry Ruby (`opentelemetry-sdk`, `opentelemetry-exporter-otlp`, Rails / PG / Active Record instrumentation)

### Serialization & Pagination

- **Alba** serializers in `app/serializers/`
- **Pagy** for pagination

### Caching & Background Jobs

- **Solid Cache** (cache store) and **Solid Queue** (Active Job backend), both Rails 8 defaults and database-backed, so no Redis is needed
- Jobs are used for idempotency-key cleanup and, later, event relay (outbox)

### Testing

- **RSpec** with `factory_bot_rails`, `faker`, `shoulda-matchers`, `rswag`, `SimpleCov`
- `prop_check` (optional) for property-based interval tests
- Real PostgreSQL for all DB-backed specs (local compose DB, CI service container); no mocks for the exclusion constraints
- Test layout: `spec/domain`, `spec/models`, `spec/services`, `spec/queries`, `spec/requests`, `spec/concurrency`, `spec/support`

### API Documentation

- **OpenAPI via rswag**: request specs generate the OpenAPI document and Swagger UI

### Dependency Management & Code Quality

- Bundler (`Gemfile.lock` committed), `bundler-audit` in CI
- RuboCop (`rubocop-rails-omakase`), Brakeman, Bullet (N+1 detection in development and test)
- Lefthook for pre-commit hooks (RuboCop on staged files)

### Containerization

- Local development and tests use a host PostgreSQL 16 server until a container runtime is chosen (Docker is not installed on the build machine; Podman is available). The compose and Dockerfile stories stay in scope and are verified once a runtime is set up.
- Docker Compose (Rails + PostgreSQL) for local development; Rails 8's generated production `Dockerfile` (multi-stage, non-root, Thruster in front of Puma); Kamal available for deployment

## Project Structure

```
app/
├── controllers/api/v1/        # Thin controllers (params in, serializer out)
│   ├── base_controller.rb     # Envelope, rescue_from, pagination helpers
│   ├── appointments_controller.rb
│   ├── availability_controller.rb
│   ├── dealerships_controller.rb
│   ├── service_types_controller.rb
│   └── health_controller.rb
├── domain/scheduling/         # Pure Ruby (no ActiveRecord): TimeInterval, SlotTime,
│   │                          # OpeningHoursPolicy, StatusMachine
│   └── assignment_strategies/ # LeastLoaded, ...
├── models/                    # Aggregates and persistence: Appointment, Dealership,
│                              # ServiceBay, Technician, ServiceType, Vehicle, ...
├── queries/                   # Query objects: Availability::FreeBays, FreeTechnicians, DaySlots
├── services/                  # Use cases: Appointments::Book, Cancel, Reschedule ...
├── serializers/               # Alba resources
├── forms/                     # ActiveModel form objects (BookingRequest)
├── jobs/                      # Active Job (Solid Queue)
config/
├── initializers/              # lograge, cors, rack_attack, opentelemetry, yabeda, events
├── routes.rb
db/
├── migrate/
├── seeds.rb  seeds/           # Idempotent seeds
└── structure.sql
lib/tasks/                     # scheduler:load_data, etc.
spec/                          # domain, models, services, queries, requests, concurrency
docs/                          # system-design.md, error-catalogue.md, erd, openapi
```

## Design Patterns & Principles

- **Aggregates:** `Appointment` (Active Record) owns its status transitions via `Scheduling::StatusMachine`
- **Value Objects:** `Scheduling::TimeInterval` and `SlotTime` as immutable `Data.define` objects
- **Service Objects:** one per use case, `call` returns a `Result`; collaborators injected via keyword arguments with defaults (`clock:`, `strategy:`) for testability
- **Query Objects & Scopes:** availability queries encapsulate SQL range logic (`&&`)
- **Domain Events:** `ActiveSupport::Notifications`, published after commit
- **Callbacks:** only for simple data integrity; business rules stay in services

## Documented Assumptions (carry into the System Design Document)

| # | Ambiguity | Assumption |
|---|-----------|------------|
| A1 | Service duration | Fixed `duration_minutes` per ServiceType |
| A2 | "Qualified" technician | Technician holds a set of qualifications; ServiceType requires one |
| A3 | Technician/bay selection | System auto-assigns; the user does not choose |
| A4 | Bay differences | Bays have a type; ServiceType requires a bay type |
| A5 | Resources per appointment | Exactly one bay and one technician for the full duration |
| A6 | Time handling | Stored in UTC; dealership has an IANA time zone and opening hours; intervals are half-open `[start, end)` |
| A7 | Slot granularity | 15-minute grid |
| A8 | Auth / customer management | Out of scope; customer and vehicle are pre-seeded and referenced by ID |
| A9 | Vehicle ownership | A vehicle belongs to one customer; bookings are validated against it |
| A10 | Same-vehicle overlap | Not allowed |
| A11 | Payments, notifications | Out of scope (stretch) |

## Pitfalls to Watch For (from the Rails stack document, adapted)

- **N+1 queries** in schedule/list endpoints: use `includes`, keep Bullet enabled in development and test
- **Callbacks hiding business logic:** keep booking rules in service objects
- **Bulk methods skip validations and callbacks:** `insert_all`, `update_all`, `upsert_all` are used only in seeds and load scripts
- **Exclusion constraints and soft state:** constraints are partial (`WHERE status IN ('confirmed','in_progress')`) so cancelled appointments never block
- **Aborted transactions:** after a PostgreSQL error the transaction is unusable; retries must use a savepoint (`transaction(requires_new: true)`)

## Development Workflow

### Key Commands (to be implemented)

- `bundle install` / `bin/setup` - Install dependencies and prepare the database
- `bin/dev` (or `bin/rails server`) - Start the development server with code reloading
- `bundle exec rspec` - Run the full test suite
- `bundle exec rspec spec/domain` - Run pure domain specs (no database)
- `bundle exec rubocop` - Lint
- `bin/brakeman` - Security scan
- `bundle exec bundler-audit check --update` - Gem vulnerability check
- `bin/rails db:migrate` / `bin/rails db:rollback` - Run / revert migrations
- `bin/rails db:seed` / `bin/rails db:seed:replant` - Seed / reset seed data
- `bin/rails rswag:specs:swaggerize` - Regenerate the OpenAPI document
- `docker compose up` - Start the app and PostgreSQL

---

# Epic 1: Backend Project Foundation

## Description

Set up the Rails API foundation: application generation, PostgreSQL configuration, the scheduling domain schema and seed data, API architecture patterns, development tooling, and Docker deployment. This epic establishes the technical foundation for all subsequent feature epics.

## Acceptance Criteria

- Rails API-only application is generated with the documented folder structure
- Database is configured and the application connects on startup
- The relational schema for the scheduling domain exists as migrations and can be seeded
- A consistent API response format and error handling pattern is established
- Development environment can be started with a single command
- Application and its dependent services (database) are containerized with Docker
- Interactive API documentation is available for developer reference

---

### User Story 1: Initialize the Rails API Project

#### Description

- Generate the Rails API-only application with the layered folder structure, versioned routing, and base configuration.

#### Requirements

- Generate at the repository root with `rails new . --api -d postgresql --skip-test --name=scheduler_api` and add RSpec
- Pin Ruby in `.ruby-version` (rbenv)
- Create `app/domain/scheduling`, `app/services`, `app/queries`, `app/serializers`, `app/forms`
- Define `namespace :api { namespace :v1 }` routes and `Api::V1::BaseController`
- Environment configuration via Rails credentials plus `ENV`; `dotenv-rails` in development/test only
- Add `GET /health` (alias of the liveness check); Rails' built-in `GET /up` remains available
- Add `.env.example` documenting every variable (`DATABASE_URL` or `DB_*`, `RAILS_MAX_THREADS`, `WEB_CONCURRENCY`, `LOG_LEVEL`, `CORS_ORIGINS`, `DOCS_ENABLED`)

#### Notes

- Fail fast in production if required variables are missing (`ENV.fetch` in an initializer)
- Add `bin/rails zeitwerk:check` to CI to catch autoloading mistakes
- Liveness/readiness endpoints are expanded in Epic 6

#### Acceptance Criteria

- `bin/rails server` starts without errors
- `GET /health` returns a success response
- Folder structure matches the documented layers
- App fails fast with a clear message when required production variables are missing

---

### User Story 2: Configure Database Connection

#### Description

- Set up the PostgreSQL connection, migration tooling, and schema format so the application can persist and retrieve data.

#### Requirements

- Configure `config/database.yml` from environment variables; pool size equals `RAILS_MAX_THREADS`
- Set `config.active_record.schema_format = :sql` and commit `db/structure.sql`
- Add `strong_migrations`
- Create a baseline migration: `enable_extension "btree_gist"` (and `pgcrypto` if needed)
- Configure the Solid Cache / Solid Queue databases per the Rails 8 multi-database setup

#### Notes

- Migrations run via `bin/rails db:migrate` and revert via `bin/rails db:rollback`
- Domain logic must not call Active Record directly from `app/domain`

#### Acceptance Criteria

- Application connects to the database on boot (verified by the readiness check and a boot log line)
- Migrations run from scratch and roll back cleanly
- `btree_gist` is enabled after migration and present in `structure.sql`

---

### User Story 3: Define Scheduling Domain Schema and Initial Migrations

#### Description

- Create the relational schema for the scheduling domain as Active Record migrations, with the indexes needed for time-range queries.

#### Requirements

- Create tables with UUID primary keys: `dealerships` (IANA `time_zone`), `dealership_opening_hours` (day_of_week, opens_at, closes_at), `dealership_holidays`, `service_bays` (dealership, bay_type), `qualifications`, `technicians`, `technician_qualifications`, `technician_shifts` (weekly pattern in dealership-local time), `technician_time_off`, `bay_blocks` (maintenance), `service_types` (duration_minutes, required qualification, required bay_type), `customers`, `vehicles` (owner customer), `appointments`, `appointment_status_histories`, `idempotency_keys`
- `appointments`: `start_at`, `end_at` (`timestamptz`, UTC), `status`, `lock_version` (optimistic locking), foreign keys to customer, vehicle, technician, service bay, service type, dealership, plus timestamps
- Add a stored virtual column `time_range` of type `tstzrange` defined as `tstzrange(start_at, end_at, '[)')`
- Add indexes: GiST on `(service_bay_id, time_range)` and `(technician_id, time_range)`, B-tree on `(vehicle_id, start_at)`, `(dealership_id, start_at)`, `(customer_id, start_at)`
- Add check constraints (`end_at > start_at`, valid status values) via `add_check_constraint`
- Model the Active Record classes with associations, `enum :status`, and validations
- Produce an ERD (`rails-erd` or Mermaid) for the System Design Document

#### Notes

- Exclusion constraints are added in Epic 3 (User Story 8) so they ship with the concurrency tests
- Store durations in minutes and times in UTC (`config.time_zone = "UTC"`); convert to dealership time zone only at the edges
- `strong_migrations` may flag index creation; use `algorithm: :concurrently` or `safety_assured` with a comment where appropriate

#### Acceptance Criteria

- Migrations run from scratch on an empty database and roll back cleanly
- Foreign keys, indexes, and check constraints are present in `structure.sql`
- Model specs (shoulda-matchers) cover associations and validations
- ERD is committed under `docs/`

---

### User Story 4: Provide Seed Data

#### Description

- Provide idempotent seeds so developers and testers can demo and test quickly.

#### Requirements

- Implement `db/seeds.rb` loading files from `db/seeds/` using `find_or_create_by!` with stable UUIDs
- Seed two dealerships in different time zones with opening hours and a holiday
- Seed bays of multiple types (`general`, `lift`, `alignment`)
- Seed technicians with varied qualifications and shifts
- Seed service types with different durations and requirements (e.g. Oil Change 30 min, Full Service 120 min, Wheel Alignment 60 min)
- Seed customers and vehicles (each vehicle owned by one customer)
- Support `bin/rails db:seed` and `bin/rails db:seed:replant`

#### Notes

- Stable UUIDs keep the README cURL examples working
- Include one scarce-capacity scenario (a single lift bay) to demo conflicts

#### Acceptance Criteria

- Running the seed repeatedly creates no duplicates
- Seed data covers every table the booking flow needs
- Seeded data demonstrates both a successful booking and a no-capacity conflict

---

### User Story 5: Establish API Architecture and Error Handling

#### Description

- Define a consistent API response format, centralized error handling, and request validation pattern used across all endpoints.

#### Requirements

- Define the response envelope `{ success, data, error, message }` with helpers `render_success` / `render_failure` in `Api::V1::BaseController`
- The `error` object uses an RFC 7807-style shape: `{ type, title, status, code, detail, errors? }`; `code` is stable and machine-readable, `errors` holds field-level detail
- Use `rescue_from` for `ActiveRecord::RecordNotFound` (404), `ActionController::ParameterMissing` and `ActiveRecord::RecordInvalid` (400/422), `ActiveRecord::StaleObjectError` (409), and a catch-all (500, no stack trace in the body)
- Services return `Dry::Monads::Result`; the controller maps `Failure` codes to HTTP statuses via the error catalogue
- Use Strong Parameters and form objects for input shaping
- Configure `rack-cors`
- Serialize with Alba; paginate with Pagy and include pagination metadata in the envelope

#### Notes

- Validation errors return `400` with field-level detail; business-rule failures return `409` / `422`
- The full error code catalogue is defined in Epic 6 (User Story 6)
- Public JSON uses snake_case keys (`start_at`, `customer_id`), following Rails convention

#### Acceptance Criteria

- All successful responses follow the envelope
- Unhandled errors return a structured error with the right status and no stack trace leakage
- Validation errors include field-level detail
- CORS headers are present on all responses

---

### User Story 6: Set Up Development Environment

#### Description

- Configure local tooling for code reloading, linting, security scanning, and the test runner.

#### Requirements

- `bin/setup` installs gems and prepares the database; `bin/dev` (or `bin/rails server`) starts the app with Zeitwerk code reloading
- Configure RuboCop (`rubocop-rails-omakase`), Brakeman, bundler-audit, and Bullet (raise in test, log in development)
- Configure RSpec (`rspec-rails`, FactoryBot, Faker, shoulda-matchers, SimpleCov with branch coverage)
- Add a sample model spec and a sample request spec
- Configure Lefthook pre-commit (RuboCop on staged files)
- Optional `Makefile` aliases (`make up`, `make test`, `make reset-db`)

#### Notes

- Rails reloads code automatically in development; no extra watcher is needed
- The Rails-generated GitHub Actions CI is extended in Epic 7

#### Acceptance Criteria

- `bin/dev` starts the server with code reloading
- RuboCop and Brakeman run clean on the initial codebase
- Sample specs run and pass
- All common commands are documented in the README

---

### User Story 7: Create Dockerfile

#### Description

- Containerize the application for consistent deployment using Rails 8's production Dockerfile as the base.

#### Requirements

- Use the generated multi-stage `Dockerfile` (build stage with build tools, final stage with runtime gems only)
- Run as the non-root `rails` user; Thruster in front of Puma
- Expose the application port and set production environment defaults
- Keep `bin/docker-entrypoint` running `db:prepare`
- Maintain `.dockerignore`

#### Notes

- Bundle without `development test` groups in the final image
- Add a `HEALTHCHECK` using the health endpoint

#### Acceptance Criteria

- Docker image builds successfully
- Container starts and the health endpoint responds
- No development/test gems or unnecessary files in the final image

---

### User Story 8: Create Docker Compose Configuration

#### Description

- Create a `docker-compose.yml` that runs the Rails app and PostgreSQL together for local development.

#### Requirements

- Services: `web` (Rails) and `db` (PostgreSQL 16+)
- Shared network, named volume for DB persistence, environment mapping from `.env`
- `db` healthcheck (`pg_isready`); `web` uses `depends_on: condition: service_healthy`
- Run `db:prepare` and seed on startup (entrypoint or one-shot service)
- Optional `docker-compose.override.yml` mounting source code for development

#### Notes

- A fresh clone must work with `docker compose up`
- Ensure Solid Cache / Solid Queue databases are created (`db:prepare` handles multi-database setups)

#### Acceptance Criteria

- `docker compose up` starts both services
- Application connects to the database within the compose network
- Data persists across container restarts
- Stopping and restarting the stack causes no data loss

---

### User Story 9: Set Up API Documentation Foundation

#### Description

- Configure OpenAPI documentation with rswag so consumers have a live reference that is verified by tests (also the client-side contract for the backend-only submission).

#### Requirements

- Install `rswag-api`, `rswag-ui`, `rswag-specs`; configure `spec/swagger_helper.rb` with title, version, description, and server URL
- Serve Swagger UI at `/api-docs` and the raw OpenAPI JSON at `/api-docs/v1/openapi.json`
- Define the response envelope and error schemas as reusable `components/schemas`
- Document `GET /health` through an rswag spec as the reference example
- Include example payloads in schemas

#### Notes

- Mount the docs routes only when `DOCS_ENABLED=true`; disabled by default in production
- Generate with `bin/rails rswag:specs:swaggerize` and commit the output

#### Acceptance Criteria

- Interactive documentation is accessible at the configured route
- Raw spec endpoint returns valid OpenAPI 3.0+ JSON
- `GET /health` appears in the documentation
- Envelope and error schemas are reusable components
- Documentation updates when specs are added and the generate task is re-run (CI fails on drift; see Epic 7)

---
