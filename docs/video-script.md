# Video Script

Target length: about 8:30 to 9:00 (limit 10:00). The five segments follow the brief order.

| # | Segment | Target | Running total |
|---|---|---|---|
| 1 | Introduction and scenario | 0:30 | 0:30 |
| 2 | System design walkthrough and implementation highlights | 3:00 | 3:30 |
| 3 | AI collaboration story | 1:45 | 5:15 |
| 4 | Live demo | 2:15 | 7:30 |
| 5 | Learnings and challenges | 1:00 | 8:30 |

## 1. Introduction and scenario (0:30)

On screen: the README top section.

- Keyloop Scenario A: book a service appointment for a vehicle, service type and dealership at a desired time.
- A booking is confirmed only when a service bay and a qualified technician are both free for the whole duration.
- An Appointment links customer, vehicle, technician and bay.
- Stack: Rails 8 API-only, Ruby 3.4, PostgreSQL 16.

## 2. System design walkthrough and implementation highlights (3:00)

On screen: `docs/system-design.md` (architecture diagram, then the booking sequence diagram), then the code.

- Layers: controllers, forms, services, queries, pure-Ruby `app/domain`, models (0:45). Show `spec/domain/architecture_spec.rb`, which fails if the domain references ActiveRecord or `Rails.`.
- Booking flow (0:45): idempotency claim, form validation, lookups, `Appointments::Placement`, free bay and technician finders, assignment strategy, insert inside a savepoint.
- Exclusion-constraint strategy (1:00): open `db/migrate/20260301000001_add_appointment_exclusion_constraints.rb`. Half-open `[start, end)` ranges in UTC, with GiST exclusion constraints on bay, technician and vehicle as the source of truth. The application catches `ActiveRecord::ExclusionViolation` (`app/services/appointments/placement.rb:88`) and answers 409 with alternative slots.
- Reliability and observability (0:30): idempotency keys, rack-attack and rack-timeout, lograge, Yabeda metrics, OpenTelemetry.

## 3. AI collaboration story (1:45)

On screen: the README "AI Collaboration Narrative", then `docs/ai-log.md`.

- Strategy and prompting approach (0:30): plan first, work split into waves with owned files, review findings tracked as items.
- Verification (0:30): the gate `.claude/scripts/verify.sh` (zeitwerk, RuboCop, Brakeman, RSpec with coverage thresholds).
- Defects found in AI output (0:45), picked from `docs/ai-log.md`:
  - Missing exclusion constraints (`414a468`).
  - Non-string cancel reason returning 500 (`app/services/appointments/cancel.rb`).
  - Atomicity spec stubbing Active Record (`spec/services/appointments/book_atomicity_spec.rb`).
  - Coverage thresholds silently unenforced: the gate was green, and only the full log showed `.simplecov` had failed to load.

## 4. Live demo (2:15)

On screen: split terminal and Swagger UI at `/api-docs`. Everything runs from the repository with `bin/demo`; talk over its output.

- Availability (0:30): the `GET /api/v1/availability` request for the seeded Manhattan dealership and Full Service.
- Successful booking (0:40): `POST /api/v1/appointments` returns 201 `confirmed`, with the Idempotency-Key retry returning the same appointment.
- Conflicting booking (0:35): the rival vehicle for the same slot returns 409 with a `NO_*` code and alternative slots. Then show the race spec output (1 created, 19 conflicts) in documentation format.
- Cancel and reschedule (0:30): reschedule with `lock_version` returns 200, then cancel returns 200 `cancelled`.

## 5. Learnings and challenges (1:00)

- The database is the final authority on double-booking; the application checks only improve the error messages.
- A green gate is not proof a check ran: add a negative probe (the coverage case).
- Review findings on AI output were mostly about edge cases outside the happy path: input types, fresh-clone setup, test seams.
- Next steps: see "Limitations and future work" in `docs/system-design.md`.

## Pre-recording checklist

- [ ] PostgreSQL 16 is running and `bin/setup` has completed.
- [ ] `bin/dev` is running (or `docker compose up --build` with `DEMO_TARGET=docker`).
- [ ] Swagger is available: start the server with `DOCS_ENABLED=true` and open `/api-docs`.
- [ ] Postman CLI is installed; if it is not on PATH, run `make api-check POSTMAN=/path/to/postman` once to confirm.
- [ ] Run `bin/demo` once end to end before recording; it resets and seeds, so run it again immediately before recording.
- [ ] Terminal layout: server logs on the left, `bin/demo` on the right, browser with Swagger UI and `docs/system-design.md` on a second desktop.
- [ ] Large terminal font, notifications off, `.env` secrets not visible.
- [ ] Rehearse against the 10-minute limit with a timer.
