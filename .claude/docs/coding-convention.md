# Project Coding Convention

## Purpose
Document the project's coding standards, naming conventions, and architectural patterns to serve as the authoritative reference during code reviews. Seed version derived from Epic 0 (`epics/epic-1-backend-project-foundation.md`); `/dev-onboard` refreshes it from the code.

## Core Development Principles
- DRY (Don't Repeat Yourself): Extract common functionality into shared modules, concerns or value objects
- Single Responsibility Principle: Each class or method has one well-defined purpose; one service object per use case
- KISS (Keep It Simple, Stupid): Favor simple, readable solutions over clever metaprogramming
- Separation of Concerns: Controllers shape HTTP, services orchestrate, domain objects decide, models persist, serializers format

## Naming Conventions
- Files and directories: `snake_case.rb`, matching the Zeitwerk constant (`app/queries/availability/free_bays.rb` → `Availability::FreeBays`)
- Classes and modules: `PascalCase`
- Methods and variables: `snake_case`; predicates end in `?`, mutating or raising methods end in `!`
- Constants: `UPPER_SNAKE_CASE`, frozen
- Services: verb inside a plural namespace (`Appointments::Book`, `Appointments::Reschedule`), public entry point `call`
- Query objects: noun inside a namespace (`Availability::FreeTechnicians`, `Appointments::ListQuery`)
- Form objects: request noun (`BookingRequest`)
- Serializers: `<Model>Serializer` (`AppointmentSerializer`)
- Domain value objects: plain nouns under `Scheduling::` (`TimeInterval`, `SlotTime`)
- Namespaces may span autoload roots: `Appointments::` appears in both `app/services/` and `app/queries/`
- Database: plural `snake_case` tables, `<singular>_id` foreign keys, explicit names for check and exclusion constraints
- JSON keys: `snake_case` (`start_at`, `customer_id`)

## File Structure & Organization
```
app/
├── controllers/api/v1/        # thin controllers, BaseController
├── domain/scheduling/         # pure Ruby rules
│   └── assignment_strategies/
├── forms/                     # ActiveModel form objects
├── jobs/                      # Active Job (Solid Queue)
├── models/                    # Active Record aggregates
├── queries/                   # query objects
├── serializers/               # Alba resources
└── services/                  # use cases
config/initializers/           # lograge, cors, rack_attack, opentelemetry, yabeda, events
db/migrate/  db/seeds/  db/structure.sql
lib/tasks/                     # scheduler:* rake tasks
spec/                          # mirrors app/, plus concurrency/ and support/
docs/                          # system design, error catalogue, ERD, AI log
```

## Architectural Patterns
- Layered Rails with a pure-Ruby domain core; `app/domain` never references Active Record or `Rails.`
- Service objects: `call` returns `Dry::Monads::Result`; collaborators injected as keyword arguments with defaults
- Query objects and named scopes hold SQL; the range overlap predicate is `time_range && tstzrange(?, ?, '[)')`
- Value objects are immutable `Data.define` types that validate on construction
- Aggregates: `Appointment` owns its status transitions by delegating to `Scheduling::StatusMachine`
- Domain events: `ActiveSupport::Notifications.instrument`, fired by the service after commit
- Double-booking: availability check and insert in one transaction; the exclusion constraint is the source of truth

## Language Specific Syntax
- Ruby 3.4: use keyword arguments for anything beyond one positional parameter
- Use `Data.define` for value objects, not `Struct`
- Use pattern matching (`case ... in`) to unpack `Result` values where it reads more clearly than `.success?` chains
- Prefer `freeze`d constants and immutable objects in `app/domain`

## Imports & Dependencies
- Rely on Zeitwerk autoloading in `app/`; never `require` application files
- `require` is needed only for gems outside Bundler's auto-require and in `spec/domain` setup
- Pin gems with pessimistic constraints in `Gemfile`; commit `Gemfile.lock`

## Logging Standards
- Lograge JSON lines with `request_id`, `method`, `path`, `status`, `duration`, and `appointment_id` when relevant
- Use `Rails.logger` outside `app/domain`; never `puts` or `p`
- Levels: `info` for confirmed bookings, `warn` for conflicts, `error` for unexpected failures
- Never log request bodies; add sensitive keys to `config.filter_parameters`

## Constants Management
- Error codes live in the `ErrorCatalogue` module and `docs/error-catalogue.md`
- Tunables come from `ENV` with defaults (`SLOT_MINUTES`, `ALTERNATIVE_SLOTS_COUNT`); use `ENV.fetch` for required production values
- Domain constants live on the domain class that owns them

## Shared Code & Common Modules
- Controller helpers (envelope, pagination) live in `Api::V1::BaseController`
- `Current` (`ActiveSupport::CurrentAttributes`) carries `request_id`
- `Clock` is the injectable time source

## Utilities & Helper Functions
- Prefer a value object or a domain method over a generic helper module
- Put cross-cutting Ruby utilities in `lib/` only when they have no domain meaning

## Error Handling
- Expected business outcomes: `Failure(:code, details)` from services; no exceptions
- Programmer errors: raise (`ArgumentError` for invalid value-object construction)
- `Api::V1::BaseController` `rescue_from`: `RecordNotFound` → 404, `ParameterMissing` and `RecordInvalid` → 400/422, `StaleObjectError` → 409, catch-all → 500 with no stack trace
- Overlap conflicts: rescue `ActiveRecord::ExclusionViolation` inside a savepoint, retry with the next candidate (bounded), then `409`
- Error body: envelope `{ success, data, error, message }` with an RFC 7807-style `error` `{ type, title, status, code, detail, errors? }`
- Every code returned must exist in the error catalogue

## Code Comments
- No code comments, docstrings, or TODO/FIXME markers
- Exceptions: required magic comments, and a one-line justification next to a `strong_migrations` `safety_assured` block
- Code must be self-documenting through clear naming and structure
- rswag specs serve as API documentation, not code comments

## Framework Best Practices

### Rails (API-only)
- Routes under `namespace :api { namespace :v1 { ... } }`
- Controllers inherit from `Api::V1::BaseController < ActionController::API`
- Use Strong Parameters (`params.expect` or `require/permit`) or a form object for every write
- Avoid N+1 queries with `includes`; Bullet raises in test

### Active Record
- UUID primary keys; `timestamptz` for all times
- Enforce invariants with database constraints first (foreign keys, check, exclusion), then model validations
- `enum :status` with explicit string or integer mapping; scopes `active`, `for_vehicle`, `for_technician`, `overlapping`
- Optimistic locking with `lock_version` on `appointments`
- Bulk methods (`insert_all`, `update_all`, `upsert_all`) only in seeds and load tasks

### PostgreSQL
- `btree_gist` enabled; GiST indexes on `(resource_id, time_range)`
- Exclusion constraints are partial on `status IN ('confirmed','in_progress')` so cancelled rows never block
- READ COMMITTED isolation plus constraints; no table locks

### dry-monads
- `include Dry::Monads[:result]` in services; return `Success(value)` or `Failure(code, details)`
- Controllers translate `Failure` codes to HTTP through the catalogue

### Alba and Pagy
- All JSON shaping in serializers; models stay free of presentation logic
- Paginate list endpoints with Pagy and put metadata in the envelope; cap `per_page` at 100

### Time zones
- `config.time_zone = "UTC"`; convert with `ActiveSupport::TimeZone[dealership.time_zone]` at the edges only
- Parse input with `Time.iso8601`

## Build Commands & Tooling

### Development
- `bin/setup` - Install gems and prepare the database
- `bin/dev` or `bin/rails server` - Start the server with code reloading

### Testing
- `bundle exec rspec` - Full suite
- `bundle exec rspec spec/domain` - Pure domain specs, no database

### Code Quality
- `bundle exec rubocop` - Lint (`rubocop-rails-omakase`)
- `bin/brakeman` - Security scan
- `bundle exec bundler-audit check --update` - Gem vulnerabilities
- `bin/rails zeitwerk:check` - Autoload check
- `.claude/scripts/verify.sh` - The gate (zeitwerk, lint, security, test)

### Database
- `bin/rails db:migrate` / `bin/rails db:rollback`
- `bin/rails db:seed` / `bin/rails db:seed:replant`
- `bin/rails db:test:prepare`

### Docker
- `docker compose up` - App and PostgreSQL (verified once a container runtime is chosen; local PostgreSQL 16 is used meanwhile)

### Git Hooks (via Lefthook)
- Pre-commit: RuboCop on staged files

### Environment Variables Required
- `DATABASE_URL` or `DB_*`, `RAILS_MAX_THREADS`, `WEB_CONCURRENCY`, `LOG_LEVEL`, `CORS_ORIGINS`, `DOCS_ENABLED`; documented in `.env.example`
