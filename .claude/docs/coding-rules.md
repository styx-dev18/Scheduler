# Coding Rules

> Every rule cites its evidence. The always-on rules (no comments, no debug output, pure `app/domain`, `Result` from services, UTC half-open intervals, `verify.sh`) are in `CLAUDE.md` and are not repeated here.

## Language
- NEVER add `# frozen_string_literal: true` or other magic comments to new files; no file in `app/`, `config/`, `db/` or `lib/` uses them, and `rubocop-rails-omakase` doesn't require them. (`.rubocop.yml`)
- ALWAYS use `Data.define` for value objects in `app/domain/`, not `Struct`. The `Struct` in `ErrorCatalogue::Entry` is a catalogue record, not a precedent. (Epic 0 › Design Patterns; `app/errors/error_catalogue.rb`)
- Services `include Dry::Monads[:result]` and return `Failure(code, details)` where `code` is an `ErrorCatalogue` key. (dry-monads 1.11.0, `Gemfile.lock`; Epic 0 › Result Handling)
- ALWAYS inject collaborators as keyword arguments with defaults (`clock: Clock`, `strategy: ...`). Never call `Time.current` directly inside services or `app/domain`. (Epic 2 › Notes)
- NEVER `require` application code. `require` appears only for gems outside Bundler's auto-require, as in `config/initializers/pagy.rb`. (`config/application.rb` `autoload_lib`)

## Framework
- Folders directly under `app/` are autoload roots, not namespaces: `app/errors/error_catalogue.rb` defines `ErrorCatalogue`, and `app/domain/scheduling/time_interval.rb` defines `Scheduling::TimeInterval`. (`app/errors/error_catalogue.rb`)
- API controllers live in `app/controllers/api/v1/` and inherit `Api::V1::BaseController`, never `ApplicationController`, so they get the `rescue_from` map, `Envelope` and `Pagy::Backend`. (`app/controllers/api/v1/base_controller.rb`)
- ALWAYS render through `render_success` / `render_failure`; never call `render json:` directly. (`app/controllers/concerns/envelope.rb`)
- ALWAYS add a new error code to `ErrorCatalogue::ENTRIES` with its `status` and `title` before you use it. Pass `status:` only when one code needs a second HTTP status, as `ParameterMissing` does with `400`. (`app/errors/error_catalogue.rb`, `app/controllers/api/v1/base_controller.rb`)
- Paginate with `pagy(scope)` and pass `pagination_meta(pagy)` as `meta:`. Pagy 9.4.0 calls the page size `limit`, not `items`. (`config/initializers/pagy.rb`, `app/controllers/api/v1/base_controller.rb`)
- In migrations: `create_table ..., id: :uuid`, `t.references ..., type: :uuid, null: false, foreign_key: true` (add `index: false` when a composite index starts with that column), and a `name:` on every check constraint in the form `<table>_<rule>_check`. (`db/migrate/20260101000002_create_dealership_tables.rb`, `db/migrate/20260101000005_create_appointments.rb`)
- ALWAYS use `t.timestamptz` for business instants. `t.datetime` and `t.timestamps` produce `timestamp without time zone` here. (`db/structure.sql`)
- Mirror every check constraint and unique index with a model validation, and keep allowed-value lists identical in the constraint and the model constant or enum (`ServiceBay::BAY_TYPES`, `Appointment` `status`). (`app/models/service_bay.rb`, `app/models/appointment.rb`)
- Enums are string-backed with `validate: true`: `enum :status, { confirmed: "confirmed", ... }, validate: true`. (`app/models/appointment.rb`)
- Use `dependent: :restrict_with_error` for associations to appointments, and `dependent: :destroy` only for configuration rows the parent owns. (`app/models/dealership.rb`, `app/models/technician.rb`)
- The range overlap predicate is `time_range && tstzrange(?, ?, '[)')`; reuse `Appointment.overlapping(interval)`, which expects an object that responds to `starts_at` and `ends_at`. (`app/models/appointment.rb`)
- Seeds go in a numbered `db/seeds/NN_name.rb` and use `SeedSupport.upsert!` with `SeedSupport.uuid(namespace, number)`. Pick an unused namespace byte so re-seeding stays idempotent. (`db/seeds.rb`)

## Code quality and style
- Style is `rubocop-rails-omakase` 1.1.0 with no overrides: double quotes and spaces inside array brackets (`[ :a, :b ]`). Run `bin/rubocop -a` rather than hand-formatting. (`.rubocop.yml`; Lefthook runs RuboCop on staged `*.rb`, `lefthook.yml`)
- CI also runs `bin/brakeman --no-pager` and `bin/bundler-audit`. The project has no `config/brakeman.ignore`, so fix every warning instead of ignoring it. (`.github/workflows/ci.yml`)

## Security
- Read required production settings with `ENV.fetch` and register them in `config/initializers/required_env.rb`, which aborts boot when they are missing. Add every new variable to `.env.example`. (`config/initializers/required_env.rb`)
- Any future authentication goes through `current_customer` in `Api::V1::BaseController`; never read customer identity from params in more than one place. (`app/controllers/api/v1/base_controller.rb`; Epic 0 assumption A8)
- CORS origins come only from `CORS_ORIGINS`, comma-separated. A response header that clients must read, such as `Location`, needs adding to `expose:`. (`config/initializers/cors.rb`)
- Keep rswag mounts behind `ENV["DOCS_ENABLED"] == "true"`. (`config/routes.rb`)
- Add new sensitive param names to `config.filter_parameters` and never log request bodies or params directly. (`config/initializers/filter_parameter_logging.rb`)

## Critical don't-miss
- Declare new `rescue_from` handlers **below** `rescue_from StandardError`. Rails checks handlers bottom-up, so a handler above it is never reached. (`app/controllers/api/v1/base_controller.rb`)
- `render_failure` with an unknown code raises `ArgumentError` in test but silently returns `500 INTERNAL_ERROR` in production. (`app/controllers/concerns/envelope.rb`)
- NEVER edit applied migrations `db/migrate/20260101000001` to `20260101000005`; add a new migration. (`db/structure.sql` `schema_migrations`)
- NEVER hand-edit generated files: `db/structure.sql` (from `db:migrate`), `db/cable_schema.rb`, `db/cache_schema.rb`, `db/queue_schema.rb`, `swagger/v1/openapi.yaml` (from `make docs`) or `config/credentials.yml.enc`.
- NEVER write `appointments.time_range`. It is a stored generated column and `attr_readonly`; set `start_at` and `end_at` instead. (`app/models/appointment.rb`)
- `strong_migrations` checks every migration after `20260101000000`. On existing tables, add check constraints with `validate: false` and then `validate_check_constraint`. `add_exclusion_constraint` has no safe form, so wrap it in `safety_assured` with a one-line reason. (`config/initializers/strong_migrations.rb`; strong_migrations 2.8.0 `checks.rb`)
- Rescue `ActiveRecord::ExclusionViolation` (SQLSTATE `23P01`, a subclass of `StatementInvalid` in Rails 8.1.4), not bare `StatementInvalid`. Epic 3 says the reverse, but it predates the Rails 8.1 class. (activerecord 8.1.4 `errors.rb`)
- After any PostgreSQL error the surrounding transaction is aborted. Only retry inside `transaction(requires_new: true)`. (Epic 0 › Pitfalls)
- Column names differ by type: instants are `start_at`/`end_at` (`timestamptz`), shift wall-clock times are `starts_at`/`ends_at` (`time`), and opening hours are `opens_at`/`closes_at` (`time`). Don't mix them up. (`db/structure.sql`)
- The `technician_time_off` table name is singular; `TechnicianTimeOff` sets `self.table_name`. Don't rename it or add another inflection. (`app/models/technician_time_off.rb`)
- `insert_all`, `update_all` and `upsert_all` skip validations and callbacks. Never use them in `app/`. (Epic 0 › Pitfalls)
