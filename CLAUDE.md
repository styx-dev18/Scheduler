# Unified Service Scheduler

Rails 8 API-only backend (Ruby 3.4 via rbenv, PostgreSQL 16) for Keyloop Scenario A: book a service appointment for a vehicle, service type and dealership at a desired time; confirm only when a ServiceBay **and** a qualified Technician are free for the entire duration; persist an Appointment linking customer, vehicle, technician and bay. The backlog lives in `epics/` (Epic 0, the stack overview, is at the top of `epics/epic-1-backend-project-foundation.md`). `backend-tech-stack-template.md` is superseded by Epic 0.

## Always-on rules
- No code comments, docstrings or TODO/FIXME markers. Exceptions: magic comments, and a one-line reason next to a `strong_migrations` `safety_assured` block.
- No debug output (`puts`, `p`, `pp`, `binding.irb`, `debugger`) in committed code.
- Validate every external input: Strong Parameters or a form object in controllers, value objects in the domain.
- `app/domain/` is pure Ruby: no `ActiveRecord`, `ApplicationRecord`, models or `Rails.`.
- Services return dry-monads `Success`/`Failure` for expected outcomes; never raise for business rules.
- Times are UTC `timestamptz`, intervals are half-open `[start, end)`, and the PostgreSQL exclusion constraints are the source of truth for double-booking.
- Make surgical changes that match the surrounding code. A change is done only when `.claude/scripts/verify.sh` exits 0.

## Which doc to read when
| You are | Read |
|---|---|
| Writing or changing production code | `.claude/docs/coding-rules.md`, then the relevant section of `.claude/docs/coding-convention.md` |
| Writing or changing specs | `.claude/docs/testing-rules.md`, then `.claude/docs/testing-convention.md` |
| Planning or needing architecture context | `.claude/docs/knowledge.md`, `epics/README.md` |
| Asking clarification questions | `.claude/docs/guides/planning.md` |
| Triaging PR review threads | `.claude/docs/guides/pr-triage.md` |

## Commands
- `bin/setup`, `bin/dev`: install and run
- `bundle exec rspec` (all), `bundle exec rspec spec/domain` (no database)
- `.claude/scripts/verify.sh [--quick]`: the gate (zeitwerk, RuboCop, Brakeman, RSpec)
