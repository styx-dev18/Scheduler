# Unified Service Scheduler: Epic Backlog (Ruby on Rails)

Backlog for **Scenario A: The Unified Service Scheduler** (Keyloop Technical Assessment). Chosen layer: **backend** (REST API + PostgreSQL), implemented with **Ruby on Rails 8 (API-only)** on Ruby 3.3+.

## Epics

| # | Epic | Maps to brief | Type | Stories |
|---|------|---------------|------|---------|
| 1 | [Backend Project Foundation](./epic-1-backend-project-foundation.md) (includes Epic 0 Rails stack overview) | Enabler | Foundation | 9 |
| 2 | [Resource-Constrained Booking](./epic-2-resource-constrained-booking.md) | Requirement 1 | Core | 7 |
| 3 | [Real-Time Availability Check](./epic-3-real-time-availability-check.md) | Requirement 2 | Core | 9 |
| 4 | [Confirmed Appointment Record](./epic-4-confirmed-appointment-record.md) | Requirement 3 | Core | 7 |
| 5 | [Appointment Lifecycle](./epic-5-appointment-lifecycle.md) | Should-have | Supporting | 4 |
| 6 | [Observability, Reliability and Scalability](./epic-6-observability-reliability-scalability.md) | "Build for the Future" | Supporting | 7 |
| 7 | [Quality, Documentation and Delivery](./epic-7-quality-documentation-delivery.md) | Deliverables | Supporting | 7 |

## Rails Stack Summary

| Concern | Choice |
|---|---|
| Language / framework | Ruby 3.3+ (YJIT), Rails 8 API-only |
| Database / ORM | PostgreSQL (`btree_gist`), Active Record, `db/structure.sql` |
| Architecture | Thin controllers, service objects, query objects, pure-Ruby `app/domain/scheduling` |
| Results | dry-monads |
| Serialization / pagination | Alba / Pagy |
| Validation | Active Record validations, Strong Parameters, form objects |
| Logging / metrics / tracing | Lograge / Yabeda + Prometheus / OpenTelemetry |
| Jobs / cache | Solid Queue / Solid Cache |
| Testing | RSpec, FactoryBot, Faker, shoulda-matchers, rswag, SimpleCov |
| Quality | RuboCop (omakase), Brakeman, bundler-audit, Bullet, Lefthook |
| Containers | Docker Compose, Rails 8 production Dockerfile |
| Auth | None for MVP (assumption A8) |

## Suggested Build Order

1. **Epic 1**: Rails app, schema, seed data
2. **Epic 3, Stories 1-4**: pure domain logic (interval, bays, technicians, assignment), specced in isolation
3. **Epic 2, Stories 2-3** and **Epic 4, Stories 1, 3**: end-to-end happy path
4. **Epic 3, Story 8** and **Epic 4, Story 2**: concurrency guarantee (the key differentiator)
5. **Epic 2, Stories 1, 4-7** and **Epic 3, Stories 5-7**: validation, ownership, hours, idempotency, alternatives, availability endpoint
6. **Epic 4, Stories 4-7**: read endpoints and persistence verification
7. **Epic 6**, then **Epic 5**: observability and reliability, then lifecycle
8. **Epic 3, Story 9** and **Epic 7**: performance review, docs, README, video

## Cross-Cutting Decisions

- **Response format:** envelope `{ success, data, error, message }`; the `error` object uses an RFC 7807-style shape with a stable `code`; JSON keys are snake_case
- **Double-booking:** PostgreSQL exclusion constraints (`add_exclusion_constraint`) on bay, technician, and vehicle, plus an atomic transaction; retries use savepoints
- **Time:** UTC storage, half-open intervals `[start, end)`, 15-minute grid, dealership-local opening hours via IANA time zones
- **Domain layering:** `app/domain` is pure Ruby and must not reference Active Record (enforced by an architecture spec)
- **Auth:** deferred (assumption A8); customer and vehicle referenced by ID
