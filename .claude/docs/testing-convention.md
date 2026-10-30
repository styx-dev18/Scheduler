# Testing Convention

## Purpose

Defines the project's testing conventions (frameworks, file organization, naming patterns and coverage expectations) so that code reviews and new specs follow the same practice. Taken from `spec/`, `.rspec`, `config/environments/test.rb`, `config/database.yml` and `.claude/scripts/verify.sh` as of 2026-10-30.

## Frameworks & Tooling

- Runner: RSpec, `rspec-rails` 8.0.4 (`Gemfile.lock`); `.rspec` = `--require spec_helper`
- HTTP and API docs: rswag request specs (`rswag-specs` 2.17.0) in `spec/integration/`, written to `swagger/v1/openapi.yaml` (`spec/swagger_helper.rb`: OpenAPI `3.0.3`, `openapi_format = :yaml`)
- Assertions: RSpec expectations, plus `shoulda-matchers` 6.5.0 (integrated in `spec/rails_helper.rb`) for associations, validations and enums
- Supplementary tools: FactoryBot (`factory_bot_rails`, `FactoryBot::Syntax::Methods` included), Faker 3.8.0 (in the `Gemfile`, not used by any factory yet), SimpleCov 0.22.0 (`"rails"` profile, branch coverage), Bullet 8.3.1 (`Bullet.raise = true` in test). There is no `prop_check`, `database_cleaner` or `climate_control`.
- Database: real PostgreSQL 16, `scheduler_api_test` (`DB_NAME_TEST`), schema kept current by `ActiveRecord::Migration.maintain_test_schema!` from `db/structure.sql`

## File Organization & Naming

- File location: mirrors `app/` (`app/models/appointment.rb` → `spec/models/appointment_spec.rb`)
- Folders that exist: `spec/models`, `spec/requests` (plain request specs), `spec/integration` (rswag), `spec/factories`, `spec/support` (empty, autoloaded). Planned with their first specs: `spec/domain`, `spec/forms`, `spec/services`, `spec/queries`, `spec/concurrency`, `spec/architecture`
- File naming: `*_spec.rb`; one factory file per model, named after the plural table (`spec/factories/service_bays.rb`)
- Suite naming: `RSpec.describe <Constant>` for units (`RSpec.describe Appointment`); `RSpec.describe "<VERB> <path>"` for endpoints (`"GET /health"`); a behaviour name for cross-cutting request specs (`"CORS"`, `"BaseController error handling"`)

## Test Structure & Style

- Pattern: Arrange-Act-Assert with a blank line between act and assert in request specs (`spec/requests/health_spec.rb`)
- Description style: present tense, with the AC/EC id first when one is covered (`it "AC5 rejects an empty interval"`, `response "200", "AC10 service is healthy"`)
- Model specs: `subject { build(:x) }` followed by shoulda one-liners (`it { is_expected.to validate_presence_of(:name) }`); a named `subject(:appointment) { create(:appointment) }` when the examples need a saved row
- Database-level checks: a `describe "database"` group that uses `update_columns` and `raise_error(ActiveRecord::StatementInvalid, /<constraint_name>/)` (`spec/models/appointment_spec.rb`)
- Nesting: `describe` for a sub-area (`"database"`), `context "when ..."` for scenarios
- Setup: `let`/`subject` for per-example data; `let!` only when the row must exist before the action; no `before(:all)`, which would leak rows outside the transaction

## Mocking & Dependencies

- Domain specs: no doubles of value objects; pass plain data
- Service specs: replace injected collaborators (`clock:`, `availability:`, `strategy:`) with fakes or `instance_double`. `verify_partial_doubles = true` (`spec/spec_helper.rb`)
- Model, query, constraint and request specs: real database, no stubbing of Active Record or SQL
- Never mock check or exclusion constraints, generated columns (`appointments.time_range`), range overlap, transactions or savepoints
- Time: an injected fake clock, or `travel_to` once `ActiveSupport::Testing::TimeHelpers` is included (it isn't yet; `spec/rails_helper.rb`). Never the real clock
- Environment: no ENV helper gem is installed; the production-only checks in `config/initializers/required_env.rb` don't run in test

## Test Data & Fixtures

- Data generation: FactoryBot factories (`spec/factories/*.rb`) with `sequence` for unique columns. No YAML fixtures (`spec/fixtures` doesn't exist)
- Traits that exist: `:appointment, :cancelled`; `:service_bay, :lift_bay`. Appointment status defaults to `confirmed` in the database
- Fixed times: factories use `Time.utc(2030, 1, 7, h)` (a Monday) and `day_of_week { 1 }`, `08:00`–`17:00`
- Consistent graphs: the `:appointment` factory builds the vehicle for its `customer`, and the technician and bay for its `dealership`
- Scenario identifiers: put the AC/EC id in the example description; factories generate their own unique names
- Database handling:
  - Domain specs: no database
  - DB-backed specs: transactional (`config.use_transactional_fixtures = true`)
  - Concurrency specs: `self.use_transactional_tests = false` per group, threads each checking out their own connection, explicit cleanup in `after` (no `database_cleaner`)
- Test pool: `max_connections` = max(`RAILS_MAX_THREADS` or 5, 25) (`config/database.yml`)

## Component / UI Specifics (If applicable)

Not applicable: this is a backend API project with no UI components.

## Shared Test Utilities

- Location: `spec/support/**/*.rb`, required by `spec/rails_helper.rb` (empty today)
- Envelope assertions are currently local to a spec (`def expect_envelope(status:, code:)` in `spec/requests/error_handling_spec.rb`). Move this into `spec/support` when a second spec needs it
- BaseController probes: a `*ProbeController < Api::V1::BaseController` defined in the spec, `Rails.application.routes.draw` in `before`, `Rails.application.reload_routes!` in `after` (`spec/requests/error_handling_spec.rb`)
- Domain loader: `spec/spec_helper.rb` creates a separate Zeitwerk loader for `app/domain`, only when every CLI argument starts with `spec/domain`
- OpenAPI schemas: `Envelope` and `Error` in `components/schemas` (`spec/swagger_helper.rb`), referenced as `schema "$ref" => "#/components/schemas/Envelope"`

## Coverage & Quality Gates

- SimpleCov: line and branch coverage, report in `coverage/` (gitignored). No `minimum_coverage` threshold is configured; the last gate run measured line 96.95%, branch 80.0%
- Exclusions: whatever the SimpleCov `"rails"` profile filters (`spec/`, `config/`, `db/`, `vendor/bundle/`); nothing custom
- Gate: `.claude/scripts/verify.sh` runs `CI=true RAILS_ENV=test bundle exec rspec --format progress` after zeitwerk, RuboCop and Brakeman. GitHub CI (`.github/workflows/ci.yml`) has no test job
- Architecture spec (no `ActiveRecord`, `ApplicationRecord` or `Rails.` under `app/domain`): planned, not yet present

## Framework Best Practices

### RSpec
- `expect` syntax only; `config.disable_monkey_patching!`
- Prefer `aggregate_failures` or a single array comparison for assertions on several fields (`spec/models/appointment_spec.rb` compares `[begin, end, exclude_end?]`)
- Use `instance_double` (verifying doubles), never a plain `double`, for collaborators

### rswag
- rswag specs live in `spec/integration/`, `require "swagger_helper"` and use `run_test!` with a `schema` `$ref`
- Every endpoint and every error code it can return gets an rswag `response` example
- Reuse the `Envelope` and `Error` `components/schemas`
- Regenerate with `bundle exec rake rswag:specs:swaggerize` (`make docs`) and commit `swagger/v1/openapi.yaml`; nothing checks for drift

### Bullet
- Raises only for code run inside a request (`Bullet::Rack`), so cover N+1 risks with a request spec

### Concurrency specs
- Release all threads together with a latch (`Concurrent::CountDownLatch`, from concurrent-ruby 1.3.8 which Rails already loads, or a `Queue`)
- Wrap each thread body in `ActiveRecord::Base.connection_pool.with_connection`
- Assert exactly one success, the rest `409`, and exactly one row

## Build Commands & Tooling

- `bundle exec rspec` (also `make test`): full suite
- `bundle exec rspec spec/domain[/<file>]`: pure domain specs without Rails (never prefix the path with `./`)
- `bundle exec rspec <files>` / `<file>:<line>`: selected specs
- `bundle exec rspec --seed <n>`: replay a random order
- `bin/rails db:test:prepare`: prepare the test database
- `bundle exec rake rswag:specs:swaggerize` (also `make docs`): regenerate the OpenAPI document
- `.claude/scripts/verify.sh`: the full gate (eager-loads because `CI=true`); coverage is always on through `rails_helper`
