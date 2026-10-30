# Testing Rules

> Extracted from the RSpec config and the spec files on 2026-10-30. Each rule cites its evidence. `CLAUDE.md` covers the basic commands and the no-database rule for `spec/domain`, so they aren't repeated here.

## Framework and tooling
- `.rspec` contains only `--require spec_helper`. ALWAYS start Rails or database specs with `require "rails_helper"`, and rswag documentation specs with `require "swagger_helper"`. (`.rspec`, `spec/models/appointment_spec.rb`, `spec/integration/health_spec.rb`)
- USE `RSpec.describe` at the top level. A bare `describe` fails because `config.disable_monkey_patching!` is set. Examples run in random order (`config.order = :random`), so reproduce an order-dependent failure with `--seed <n>`. (`spec/spec_helper.rb`)
- Put shared helpers, matchers and shared contexts in `spec/support/**/*.rb`. `rails_helper` requires every file there in sorted order. Domain-only runs never load them. (`spec/rails_helper.rb`; `spec/support/` is empty today)
- The gate runs specs as `CI=true RAILS_ENV=test bundle exec rspec`. `CI=true` turns on `config.eager_load`, so an app file that fails to load breaks the gate even when a plain `bundle exec rspec` passes. ALWAYS confirm with `.claude/scripts/verify.sh`. (`.claude/scripts/verify.sh`, `config/environments/test.rb`)

## Structure and style
- Model specs `RSpec.describe <Model>`. Request specs in `spec/requests/` describe `"<VERB> <path>"` or the behaviour under test (`"CORS"`, `"BaseController error handling"`). rswag specs in `spec/integration/` use the `path`/`get`/`response` DSL with `run_test!`. (`spec/requests/health_spec.rb`, `spec/requests/cors_spec.rb`, `spec/integration/health_spec.rb`)
- Write the AC/EC id first in the example text, both in `it` strings and in rswag `response` descriptions (`response "200", "AC10 service is healthy"`). The rswag text ends up in `swagger/v1/openapi.yaml`. (`spec/models/bay_block_spec.rb`, `spec/integration/health_spec.rb`)
- In model specs, set `subject { build(:<factory>) }` and use shoulda one-liners (`it { is_expected.to belong_to(...) }`). Use `create` only when the example needs a saved row. (`spec/models/technician_spec.rb`, `spec/models/appointment_spec.rb`)
- Group database-level checks under `describe "database"`. Bypass model validations with `update_columns` and match the constraint by name: `raise_error(ActiveRecord::StatementInvalid, /<constraint_name>/)`. (`spec/models/appointment_spec.rb`)
- In request specs, assert on `response.parsed_body` against the whole envelope (`success`, `data`, `error`, `message`), and on `error.code` for failures. (`spec/requests/health_spec.rb`, `spec/requests/error_handling_spec.rb`)
- To test `Api::V1::BaseController` behaviour without a real endpoint, subclass it in a uniquely named `*ProbeController` in the spec file, redraw the routes in `before`, and ALWAYS call `Rails.application.reload_routes!` in `after`. (`spec/requests/error_handling_spec.rb`)

## Mocking
- Partial doubles are verified (`verify_partial_doubles = true`): stubbing a method the object doesn't define fails. USE `instance_double` for injected collaborators, never a plain `double`. (`spec/spec_helper.rb`)
- NEVER stub Active Record, SQL or PostgreSQL behaviour (check constraints, generated columns, range overlap, exclusion constraints, transactions). Constraint specs run against the real test database. (`spec/models/appointment_spec.rb` `describe "database"`, `db/structure.sql`)
- Control time with an injected clock or `travel_to`, never the real clock. `travel_to` is NOT available yet: `rails_helper` doesn't include `ActiveSupport::Testing::TimeHelpers` (calling it raised `NoMethodError` when tried). Add `config.include ActiveSupport::Testing::TimeHelpers` to `rails_helper` or `spec/support` before first use. (`spec/rails_helper.rb`)

## Test data and fixtures
- USE FactoryBot only. `fixture_paths` points to `spec/fixtures`, which doesn't exist. NEVER add YAML fixtures. (`spec/rails_helper.rb`, `spec/factories/`)
- Factory times are fixed UTC literals on Monday 2030-01-07 (`Time.utc(2030, 1, 7, 9)`). That date matches `day_of_week { 1 }` and the default `08:00`–`17:00` window in the shift and opening-hour factories. ALWAYS build scenario times with `Time.utc(...)` on that date, never `Time.now` or relative times. (`spec/factories/appointments.rb`, `spec/factories/technician_shifts.rb`, `spec/factories/dealership_opening_hours.rb`)
- The `:appointment` factory takes the vehicle from `customer` and the technician and bay from `dealership`. Override them as a consistent set, because a technician or bay from another dealership makes the record invalid. (`spec/factories/appointments.rb`, `spec/models/appointment_spec.rb`)
- The only traits are `:appointment, :cancelled` and `:service_bay, :lift_bay`. A new appointment is `confirmed` because of the column default (`db/structure.sql`), so there is no `:confirmed` trait. Add new traits to the factory file rather than inline attribute hashes repeated across specs. (`spec/factories/appointments.rb`, `spec/factories/service_bays.rb`)
- Unique columns get their values from `sequence` (`name`, `email` as `customerN@example.test`, a 17-character `vin`, `QUAL_N` codes, `idem-key-N`). NEVER hard-code a unique value inside a factory. (`spec/factories/customers.rb`, `spec/factories/vehicles.rb`, `spec/factories/idempotency_keys.rb`)
- Every example runs in a transaction (`config.use_transactional_fixtures = true`). Concurrency specs opt out per group with `self.use_transactional_tests = false`, which rspec-rails honours, and must delete their own rows: `database_cleaner` is not in the `Gemfile`. (`spec/rails_helper.rb`, `Gemfile`)
- The test pool is `max_connections: [RAILS_MAX_THREADS || 5, 25].max` (Rails 8.1 key, not `pool`). Keep a race spec's thread count below 25, because the example's own thread also holds a connection. (`config/database.yml`)

## Coverage and quality gates
- SimpleCov starts at the top of `rails_helper` with the `"rails"` profile and `enable_coverage :branch`. No `minimum_coverage` is set, so coverage never fails a run. Report the numbers from `coverage/` (gitignored). Domain-only runs produce no coverage. (`spec/rails_helper.rb`, `.gitignore`)
- GitHub CI runs only Brakeman, bundler-audit and RuboCop. There is no RSpec job, so a failing spec is caught only by `.claude/scripts/verify.sh`. (`.github/workflows/ci.yml`)
- `swagger/v1/openapi.yaml` is generated from the rswag specs by `bundle exec rake rswag:specs:swaggerize` (`make docs`). Regenerate and commit it whenever an rswag spec or `spec/swagger_helper.rb` changes, and NEVER hand-edit it. No check detects drift. (`Makefile`, `spec/swagger_helper.rb`)

## Critical don't-miss
- `spec/spec_helper.rb` sets up the pure `app/domain` Zeitwerk loader only when every CLI argument starts with `spec/domain`. In a full or mixed run, `spec/domain` files load (alphabetically) before any `rails_helper`, so `RSpec.describe Scheduling::X` raises `NameError: uninitialized constant Scheduling` (seen with a probe spec). Fix the loader before adding the first domain spec. (`spec/spec_helper.rb`)
- Re-run domain specs as `spec/domain/...`, NEVER as `./spec/domain/...`. The rerun lines RSpec prints use `./`, which skips the domain loader and gives the same `NameError`. (`spec/spec_helper.rb`)
- Bullet raises (`Bullet.raise = true`) only inside requests that pass through the `Bullet::Rack` middleware. Model, service and query specs get no N+1 detection, so cover eager-loading with a request spec. (`config/environments/test.rb`, bullet 8.3.1)
