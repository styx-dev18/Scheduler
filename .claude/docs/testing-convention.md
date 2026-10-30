# Testing Convention

## Purpose

Define the project's testing conventions including frameworks, file organization, naming patterns, and coverage expectations to enforce consistent testing practices across code reviews and unit test implementation. Seed version derived from Epics 0 and 7; `/dev-onboard` refreshes it from the code.

## Frameworks & Tooling

- Runner: RSpec (`rspec-rails`)
- HTTP and API docs: rswag request specs (`rswag-specs`), which also generate the OpenAPI document
- Assertions: RSpec expectations plus `shoulda-matchers` for associations and validations
- Supplementary tools: FactoryBot, Faker, SimpleCov (line and branch), Bullet (raises in test), optional `prop_check` for property-based interval specs
- Database: real PostgreSQL 16 (local Homebrew server now; compose `db` or a CI service container later), schema loaded from `db/structure.sql`

## File Organization & Naming

- File location: mirrored under `spec/` (`app/services/appointments/book.rb` → `spec/services/appointments/book_spec.rb`)
- Folders: `spec/domain`, `spec/models`, `spec/forms`, `spec/services`, `spec/queries`, `spec/requests`, `spec/concurrency`, `spec/support`, plus `spec/architecture` for the layering spec
- File naming: `*_spec.rb`
- Suite naming: `RSpec.describe <Constant>` for units; `RSpec.describe "<VERB> <path>"` or the rswag `path` DSL for requests

## Test Structure & Style

- Pattern: Arrange-Act-Assert, one behaviour per example
- Description style: behaviour in the present tense (`it "rejects a start time off the 15-minute grid"`); AC/EC ids prefixed when covered
- Nesting: `context "when ..."` blocks for scenarios
- Setup: `let` and `before` for per-example setup; `let!` only when the record must exist before the action; `before(:all)` is avoided because it leaks data between examples

## Mocking & Dependencies

- Domain specs: no doubles of value objects; pass plain data
- Service specs: substitute injected collaborators (`clock:`, `availability:`, `strategy:`) with fakes or `instance_double`
- Query, model, constraint and request specs: real database, no stubbing of Active Record or SQL
- Never mock exclusion constraints, range overlap, transactions or savepoints
- Time: inject a fake `Clock` or use `travel_to`; never depend on real time
- Environment: stub `ENV` with `stub_const` or `ClimateControl`-style helpers in `spec/support`, never by mutating `ENV` globally

## Test Data & Fixtures

- Data generation: FactoryBot factories with traits (`:confirmed`, `:cancelled`, `:lift_bay`); no YAML fixtures
- Scenario-specific identifiers (`appt-ac1`, `veh-ec3`) in names and labels
- Database handling:
  - Domain specs: no database
  - Most DB-backed specs: transactional tests (default)
  - Concurrency specs: `self.use_transactional_tests = false`, threads each checking out their own connection, explicit cleanup (or `database_cleaner-active_record` scoped to `spec/concurrency`)
- Test pool size is at least the concurrency spec's thread count

## Component / UI Specifics (If applicable)

Not applicable - this is a backend API project without UI components.

## Shared Test Utilities

- Location: `spec/support/` (loaded by `rails_helper`)
- Helpers: envelope and error-code matchers (for example `expect(response).to have_error_code("NO_CAPACITY")`), a thread latch for race specs, a fake `Clock`
- Domain loader: `spec/domain` loads `app/domain` without Rails through `spec_helper`

## Coverage & Quality Gates

- SimpleCov thresholds on `app/domain` and `app/services`: 90% line, 85% branch
- Architecture spec: no file under `app/domain` references `ActiveRecord`, `ApplicationRecord` or `Rails.`
- Race spec repeated (for example 50 iterations) at least once in CI
- Exclusions from coverage: `db/`, `config/`, `bin/`, `lib/tasks/`, serializers without logic

## Framework Best Practices

### RSpec
- Use `expect` syntax only; `config.disable_monkey_patching!`
- Prefer `aggregate_failures` for multi-field response assertions
- Use `instance_double` (verifying doubles), never plain `double`, for collaborators

### rswag
- Every endpoint and every error code it can return has an rswag example
- Reuse the envelope and error `components/schemas`
- Regenerate with `bin/rails rswag:specs:swaggerize`; CI fails on drift

### Concurrency specs
- Release all threads together with a latch (`Concurrent::CountDownLatch` or a `Queue`)
- Wrap each thread body in `ActiveRecord::Base.connection_pool.with_connection`
- Assert exactly one success, the rest `409`, and exactly one row

## Build Commands & Tooling

- `bundle exec rspec` - Full suite
- `bundle exec rspec spec/domain` - Pure domain specs, no database
- `bundle exec rspec <files>` - Selected specs
- `bin/rails db:test:prepare` - Prepare the test database
- `bin/rails rswag:specs:swaggerize` - Regenerate the OpenAPI document
- `COVERAGE=true bundle exec rspec` - Coverage report (if SimpleCov is gated by an env flag)
