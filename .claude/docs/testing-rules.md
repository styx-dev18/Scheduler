# Testing Rules

> **Seed version.** `/dev-onboard` rewrites this file from the real RSpec config and spec files. Each rule then cites its evidence.

## Framework
- Use RSpec. Specs mirror `app/` under `spec/` and end in `_spec.rb`. (Epic 0 › Testing)
- Specs in `spec/domain` require only `spec_helper`; every other spec requires `rails_helper`. (Epic 7 Story 1)
- Name the top-level `RSpec.describe` after the constant under test, for example `RSpec.describe Appointments::Book`. Request specs describe the route, for example `RSpec.describe "POST /api/v1/appointments"`.

## Isolation
- Domain specs are pure: no database, no Rails, no doubles of value objects.
- Service specs substitute injected collaborators (`clock:`, `availability:`, `strategy:`) with fakes or `instance_double`. Never stub Active Record internals.
- Never mock PostgreSQL behaviour: overlap, exclusion-constraint and atomicity specs run against the real database.
- Control time with an injected `Clock` or `travel_to`; never depend on the real clock.
- Concurrency specs set `self.use_transactional_tests = false`, clean up explicitly, and need a test pool size of at least the thread count.

## Behaviour over implementation
- Assert on returned `Result` values, HTTP status, envelope body and error `code`, persisted rows and published events. Don't assert on calls between collaborators unless the call is the behaviour, such as publishing a domain event.
- NEVER assert on instance variables, private methods, or internal data shapes. Specs must survive a refactor that keeps behaviour the same.
- Every AC/EC from `plan.md` that a spec covers is named in the example, for example `it "AC1 frees the slot after cancellation"`.
