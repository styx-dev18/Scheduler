# Coding Rules

> **Seed version.** Every rule must be evidence-backed, unobvious, actionable and stable. `/dev-onboard` rewrites this file from the code once it exists; each rule then cites a file or config. The always-on rules (no comments, no debug code and so on) are in `CLAUDE.md` and are not repeated here.

## Architecture
- NEVER reference `ActiveRecord`, `ApplicationRecord`, any model class or `Rails.` inside `app/domain/`. Feed domain objects plain data. (Epic 0 › Adaptation note; enforced by an architecture spec, Epic 7 Story 1)
- Controllers contain no business logic: Strong Parameters or a form object in, one service call, a serializer out. (Epic 0 › Design Patterns)
- ALWAYS put business rules in services or `app/domain`, never in model callbacks. Callbacks are for simple data integrity only. (Epic 0 › Pitfalls)
- Query logic that is more than one scope goes in a query object under `app/queries/`, not in the controller or service. (Epic 4 Story 5)

## Naming
- File path must match the Zeitwerk constant: `app/services/appointments/book.rb` defines `Appointments::Book`. Run `bin/rails zeitwerk:check` after adding files. (Epic 1 Story 1)
- Services are verb-named inside a plural namespace (`Appointments::Book`, `Appointments::Cancel`); query objects are noun-named (`Availability::FreeBays`). (Epic 0 › Project Structure)
- Error codes are `UPPER_SNAKE_CASE` strings from the error catalogue; never invent a code inline. (Epic 6 Story 6)

## Validation and errors
- Services return `Dry::Monads::Result`. Return `Failure(code, details)` for expected business outcomes; never raise for them. (Epic 2 Story 2)
- Rescue `ActiveRecord::ExclusionViolation` for overlap conflicts, never a bare `ActiveRecord::StatementInvalid`. (activerecord 8.1 `errors.rb`)
- After a PostgreSQL error the transaction is aborted: retry only inside `transaction(requires_new: true)`. (Epic 3 Story 8)
- Parse timestamps with `Time.iso8601` (strict), never `Time.zone.parse`. Never do manual UTC-offset arithmetic; use `ActiveSupport::TimeZone`. (Epic 2 Stories 3, 5)

## Data
- Change the schema only through migrations; the schema format is `db/structure.sql` (`schema_format = :sql`). (Epic 1 Story 2)
- Intervals are half-open: SQL uses `tstzrange(start_at, end_at, '[)')` and `&&`; Ruby uses `Scheduling::TimeInterval#overlaps?`. Both must agree. (Epic 3 Story 1)
- `insert_all`, `update_all` and `upsert_all` are allowed only in seeds and load tasks; they skip validations and callbacks. (Epic 0 › Pitfalls)
- Treat `appointments.time_range` as read-only; it is a stored generated column. (Epic 4 Story 1)
