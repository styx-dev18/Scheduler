# Project Knowledge

> Derived from the code at `0f0af0b` (foundation, Epics 2 and 3 core, exclusion constraints) plus the settled decisions in Epic 0 (`epics/epic-1-backend-project-foundation.md`). Items marked **planned** are decided in an epic but have no code yet; check the cited epic before you build them.

## Coding

### System architecture
- One Rails 8.1.4 API-only app (`config.api_only = true`, Ruby 3.4.10, `.ruby-version`) at the repository root, module `SchedulerApi` (`config/application.rb`), backed by PostgreSQL 16 (`config/initializers/strong_migrations.rb` `target_version = 16`).
- Layered Rails with a pure-Ruby core. Autoload roots under `app/` are not namespaces: `app/errors/error_catalogue.rb` defines the top-level `ErrorCatalogue`, and `app/services/appointments/book.rb` would define `Appointments::Book`. `lib/` is autoloaded too, except `lib/assets` and `lib/tasks` (`config.autoload_lib(ignore: %w[assets tasks])`).
- Production splits Solid Cache, Solid Queue and Solid Cable into their own databases (`config/database.yml` `production.cache|queue|cable`, `db/*_schema.rb`); development and test use only the primary database.

### Layers
| Layer | Folder | Owns | State |
|---|---|---|---|
| controllers | `app/controllers/api/v1/` | Strong Parameters or a form in, one service call, a serializer out. `Api::V1::BaseController` holds the `rescue_from` map, `Pagy::Backend`, `pagination_meta` and the `current_customer` seam; `Envelope` (`app/controllers/concerns/envelope.rb`) renders every body | built |
| errors | `app/errors/` | `ErrorCatalogue`: code to HTTP status and title | built (8 codes incl. `UNAUTHORIZED`, `RATE_LIMITED`, `REQUEST_TIMEOUT`, `SERVICE_UNAVAILABLE`; catalogued in `docs/error-catalogue.md`) |
| models | `app/models/` | Associations, string enums, scopes, validations that mirror DB constraints | built |
| forms | `app/forms/` | `ActiveModel::Model` request objects, structural validation only (`BookingRequest`) | built |
| services | `app/services/<plural namespace>/` | One use case each, `call` returns a dry-monads `Result` (`Appointments::Book`) | built |
| queries | `app/queries/<namespace>/` | Multi-scope SQL and range logic (`Availability::FreeBays`, `FreeTechnicians`, `Finder`, `DaySlots`, `Alternatives`) | built |
| domain | `app/domain/scheduling/` | Plain Ruby value objects, policies, assignment strategies (`TimeInterval`, `SlotTime`, `OpeningHoursPolicy`, `LeastLoaded`) | built (status machine planned, Epic 5) |
| serializers | `app/serializers/` | Alba 3.11 resources; all JSON shaping | built for appointments, dealerships and availability slots |

### Design patterns and why
- **Pure domain core** (`app/domain/scheduling/`): scheduling rules must be unit-testable without a database (Epic 0 › Architecture Approach).
- **Active Record models as aggregates**, no separate persistence mapping: a mapper layer would fight the framework (Epic 0 › Architecture Approach).
- **Service objects returning `Result`** (dry-monads 1.11.0): expected business outcomes are values the controller maps to HTTP, so exceptions stay reserved for bugs and infrastructure faults (Epic 0 › Result Handling).
- **Keyword-injected collaborators with defaults** (`clock:`, `strategy:`, `availability:`): specs can swap fakes without stubbing globals (Epic 2 › Notes).
- **Query objects and named scopes** for range SQL: one place owns the `&&` overlap predicate; `Appointment.overlapping` (`app/models/appointment.rb`) is the first instance.
- **Database constraints as the final authority**: application checks give friendly errors, constraints guarantee correctness under races (Epic 3 › Chosen approach).
- **Domain events through `ActiveSupport::Notifications`**, published after commit, so subscribers never see rolled-back work (planned, Epic 5).

### Implementation patterns
- Every response goes through `render_success(data, status:, message:, meta:)` or `render_failure(code, detail:, errors:, status:)` (`app/controllers/concerns/envelope.rb`). `render_failure` looks the code up in `ErrorCatalogue`; an unknown code raises `ArgumentError` in test and falls back to `INTERNAL_ERROR` elsewhere.
- `rescue_from` handlers are declared generic-first (`StandardError` at the top of `app/controllers/api/v1/base_controller.rb`) because Rails tries the last-declared handler first.
- `status:` overrides the catalogue status where one code covers two HTTP statuses: `ParameterMissing` renders `VALIDATION_ERROR` with `400`, while `RecordInvalid` keeps the catalogue's `422`.
- Pagination: Pagy 9.4.0 with `Pagy::DEFAULT[:limit] = 25` (`config/initializers/pagy.rb`); pass `pagination_meta(pagy)` as `meta:` to `render_success`. Pagy 9 names the page size `limit`; the envelope exposes it as `per_page`.
- Seeds are idempotent and use stable UUIDs: `SeedSupport.upsert!(Model, SeedSupport.uuid(namespace, number), attrs)` (`db/seeds.rb`), one file per table group in `db/seeds/NN_name.rb`, loaded in sorted order. Namespaces in use: `0x10`, `0x20`, `0x30`, `0x31`, `0x40`, `0x50`, `0x60`, `0x61`, `0x62`, `0x70`, `0x71`.
- Booking concurrency (built, `app/services/appointments/book.rb`): availability check, assignment and insert in one transaction; each attempt in `transaction(requires_new: true)`. A `StatementInvalid` whose `cause` is a `PG::ExclusionViolation` is read for its constraint name (`appointments_no_bay_overlap` drops the bay, `appointments_no_technician_overlap` drops the technician, `appointments_no_vehicle_overlap` returns `VEHICLE_ALREADY_BOOKED`). After `MAX_ASSIGNMENT_ATTEMPTS = 3` attempts, or when a candidate list empties, the result is `NO_CAPACITY` (`409`).
- Availability endpoint (built): `GET /api/v1/availability?dealership_id=&service_type_id=&date=` validates through `AvailabilityRequest`, computes the day's bookable grid with `Availability::DaySlots` (in memory over at most 8 bulk queries) and caches the body in `Rails.cache` for 30 seconds without invalidation on booking. `Availability::Alternatives` reuses `DaySlots` to put up to `ALTERNATIVE_SLOTS_COUNT` (default 3) nearest same-day start times in `error.alternatives` of every `NO_*` failure from `Appointments::Book`.
- Load and design notes: `bin/rails "scheduler:load_data[N]"` (`lib/tasks/scheduler.rake`) recreates the "Load Test Motors" data set with N non-overlapping appointments. Query plans, measured p95 and the concurrency reasoning are in `docs/system-design.md`.

### Data architecture
- Persistence is Active Record on PostgreSQL with `schema_format = :sql`; `db/structure.sql` is the generated schema of record because the schema uses a stored generated `tstzrange` column and GiST indexes that `schema.rb` cannot express.
- Every table has a UUID primary key from `gen_random_uuid()` (generator default `primary_key_type: :uuid`, `config/application.rb`); every foreign key is `uuid`, `NOT NULL` unless optional, with a real FK constraint.
- Three time representations (`db/migrate/`): business instants are `timestamptz` (`start_at`/`end_at`); recurring wall-clock times are `time` interpreted in the dealership's IANA zone (`opens_at`/`closes_at`, `starts_at`/`ends_at`); calendar days are `date`. Rails `created_at`/`updated_at` are `timestamp(6) without time zone`.
- Appointment overlap uses a stored generated column `time_range = tstzrange(start_at, end_at, '[)')` with GiST indexes on `(service_bay_id, time_range)` and `(technician_id, time_range)` (`db/migrate/20260101000005_create_appointments.rb`). Three partial GiST exclusion constraints on the active statuses (`confirmed`, `in_progress`) are built (`db/migrate/20260301000001`): `appointments_no_bay_overlap`, `appointments_no_technician_overlap` and `appointments_no_vehicle_overlap`. They are the final guard against double-booking.
- Invariants are enforced twice: named check constraints (`<table>_<rule>_check`) and unique indexes in the database, mirrored by model validations so callers get `422` instead of a database error.
- Allowed-value sets are string columns with a check constraint plus a frozen constant or string-mapped `enum ... validate: true` on the model (`ServiceBay::BAY_TYPES`, `Appointment` `status`).
- Ownership: dealership configuration children use `dependent: :destroy`; anything an appointment references uses `dependent: :restrict_with_error` (`app/models/*.rb`). `appointments.lock_version` enables optimistic locking.
- Schema overview: `docs/erd.md` (Mermaid).

### API design
- REST JSON under `namespace :api { namespace :v1 }` (`config/routes.rb`); controllers live in `app/controllers/api/v1/` and inherit `Api::V1::BaseController`. Operational endpoints (`/health`, `/up`) sit outside the version namespace.
- Envelope `{ success, data, error, message }` plus optional `meta`; errors are RFC 7807-style `{ type, title, status, code, detail, errors? }` with `type` `https://httpstatuses.com/<status>` and `message` repeating `detail` (`app/controllers/concerns/envelope.rb`).
- JSON keys are `snake_case`, times are ISO 8601 UTC.
- OpenAPI 3.0.3 is generated by rswag into `swagger/v1/openapi.yaml` (`make docs`); `components/schemas` holds `Envelope` and `Error`. Swagger UI and the raw spec mount at `/api-docs` only when `DOCS_ENABLED=true`.
- CORS allows the comma-separated `CORS_ORIGINS` and exposes the `Location` header (`config/initializers/cors.rb`).

### Cross-cutting concerns
- **Auth:** none for the MVP (Epic 0 assumption A8). `current_customer` in `Api::V1::BaseController` returns `nil` and is the only seam for adding auth.
- **Validation:** Strong Parameters or form objects at the edge, model validations for invariants, business rules in services as `Failure` (Epic 0 › Validation).
- **Errors:** the catch-all `rescue_from StandardError` logs `"<class>: <message>"` and renders `INTERNAL_ERROR` with no stack trace. Error codes live in `ErrorCatalogue::ENTRIES`; `docs/error-catalogue.md` lists every code (built, Epic 6). New codes: `RATE_LIMITED` (429, rack-attack), `REQUEST_TIMEOUT` (504, rack-timeout), `SERVICE_UNAVAILABLE` (503), `UNAUTHORIZED` (401, `/metrics`).
- **Logging (built, Epic 6):** Lograge JSON (`config/initializers/lograge.rb`); `Current.request_id`, `trace_id` and `appointment_id` are attached to each line, and `ApplicationJob` propagates `request_id` to jobs. Production still logs to STDOUT, level from `RAILS_LOG_LEVEL` (default `info`).
- **Metrics (built, Epic 6):** Yabeda (`config/initializers/yabeda.rb`) subscribes to the `booking.scheduler` and `availability.scheduler` notifications. `/metrics` is mounted only when `METRICS_ENABLED=true` and requires a bearer token when `METRICS_TOKEN` is set (`UNAUTHORIZED` otherwise).
- **Tracing (built, Epic 6):** OpenTelemetry (`config/initializers/opentelemetry.rb`), active only when `OTEL_ENABLED=true`. Spans: `availability.free_bays`, `availability.free_technicians`, `booking.transaction`, `booking.assignment`.
- **Health and resilience (built, Epic 6):** `/health/live` and `/health/ready` (`HealthController`); rack-attack (`config/initializers/rack_attack.rb`) and rack-timeout (`config/initializers/rack_timeout.rb`); PostgreSQL `statement_timeout` from `DB_STATEMENT_TIMEOUT_MS` (default 5000, set to 0 for `db:prepare` in `bin/docker-entrypoint` so migrations are exempt). Rationale in the Scaling & Reliability section of `docs/system-design.md`; a local Prometheus/Grafana stack is in `docker-compose.observability.yml` and `config/observability/`.
- **Config:** everything comes from `ENV`, through `dotenv-rails` in development and test (`.env.example`). `config/initializers/required_env.rb` aborts boot in production without `DATABASE_URL` or `DB_HOST`, and without `CORS_ORIGINS`. The database pool is `RAILS_MAX_THREADS` (`config/database.yml`).
- **Background jobs:** Solid Queue in production (`config/environments/production.rb`); `ApplicationJob` is still the generated stub.
- **N+1:** Bullet is enabled in development (log only) and raises in test (`config/environments/*.rb`).

## Testing

### Test pyramid
- Wide base of fast unit specs: pure domain specs under `spec/domain` and shoulda-driven model specs under `spec/models` (`spec/models/*_spec.rb`).
- Middle: database-backed specs that prove PostgreSQL itself enforces the rules (check constraints, the generated `time_range` column, and the exclusion constraints). They run against the real database because the database is the source of truth (`spec/models/appointment_spec.rb`).
- Top: request specs for HTTP behaviour (envelope, error mapping, CORS) in `spec/requests/`, and rswag specs in `spec/integration/` that are also the source of the committed OpenAPI document `swagger/v1/openapi.yaml` (`spec/swagger_helper.rb`).
- Concurrency (race) specs live in `spec/concurrency/`, the only non-transactional layer.

### Isolation
- Two load paths: `spec/spec_helper.rb` alone, with a separate Zeitwerk loader for `app/domain` when only `spec/domain` paths are given, and `spec/rails_helper.rb`, which boots Rails, SimpleCov, shoulda-matchers, FactoryBot and `spec/support`. The domain loader isn't active in full-suite runs (see `testing-rules.md`, Critical don't-miss).
- Every Rails spec runs inside a transaction (`use_transactional_fixtures = true`). Examples run in random order with a reproducible seed.
- Request specs that need throwaway endpoints redraw the routes and restore them afterwards (`spec/requests/error_handling_spec.rb`).
- Bullet raises only for N+1 queries inside a request, so request specs double as the N+1 check (`config/environments/test.rb`).

### Test data
- FactoryBot is the only data source (`spec/factories/`). There are no YAML fixtures. Unique columns use sequences, and factories build consistent object graphs (same customer and dealership across an appointment's associations).
- Times are fixed UTC values on a far-future Monday that fits inside the default shift and opening hours, so specs never depend on the real clock (`spec/factories/appointments.rb`, `spec/factories/technician_shifts.rb`).

### Environments
- Test database `scheduler_api_test` (`DB_NAME_TEST`) on the local PostgreSQL 16 server. The schema loads from `db/structure.sql` and is kept in sync by `maintain_test_schema!`. The pool has at least 25 connections for thread specs (`config/database.yml`).
- `.claude/scripts/verify.sh` is the only place the suite gates changes, and it runs with `CI=true`, which eager-loads the app. GitHub Actions runs security and lint jobs only (`.github/workflows/ci.yml`).
- Coverage (line and branch) is collected on every Rails run into `coverage/`, without a failing threshold (`spec/rails_helper.rb`).
