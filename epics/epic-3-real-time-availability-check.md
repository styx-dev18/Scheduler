# Epic 3: Real-Time Availability Check

## Description

Before confirming a booking, verify that **both** a ServiceBay and a qualified Technician are free for the **entire service duration** (**Scenario A, Requirement 2**). This is the core of the challenge: correct interval logic, deterministic assignment, helpful failure explanations, and a hard guarantee against double-booking under concurrent load.

## Dependencies

- Epic 1 (schema, seed data)
- Epic 2 (`Appointments::Book` service and collaborators)

## Key Design Decision: Preventing Double-Booking

| Option | Pros | Cons |
|---|---|---|
| **PostgreSQL exclusion constraint** (`add_exclusion_constraint` with GiST on resource + `tstzrange`) | Strongest guarantee, enforced by the database, native Rails migration support | Postgres-specific |
| Pessimistic locks (`lock` / `with_lock`) on resource rows | Simple to reason about | Lower throughput, deadlock care |
| Optimistic locking (`lock_version`) / unique slot rows | Portable | More bookkeeping, does not protect new inserts |
| Distributed lock (Redis) | Cross-service | Extra infra, weaker than a DB guarantee |

**Chosen approach:** exclusion constraints as the final safety net, with the availability check and insert inside one transaction. The application check gives friendly errors; the constraint guarantees correctness even when checks race. Rails 8 has no dedicated Active Record error class for exclusion violations, so the service rescues `ActiveRecord::StatementInvalid` and inspects `cause` for `PG::ExclusionViolation`.

## Acceptance Criteria

- The appointment interval is computed from the service type duration using half-open `[start, end)` semantics
- Only bays of the required type that are free (no appointments or maintenance blocks) for the full interval are candidates
- Only technicians with the required qualification, on shift, not on leave, and free for the full interval are candidates
- Assignment is deterministic and documented
- Failures explain *why* (`NO_BAY`, `NO_TECHNICIAN`, `NO_CAPACITY`)
- Alternative slots and a day-availability endpoint are available
- N parallel requests for the last slot result in exactly one success
- Availability queries stay fast as data grows

---

### User Story 1: Compute the Appointment Interval

#### Description

- As the system, I need to compute the appointment interval `[start, start + duration)` from the service type so availability covers the full duration.

#### Requirements

- Implement `Scheduling::TimeInterval` as an immutable value object (`Data.define(:starts_at, :ends_at)`) with `overlaps?(other)`, `cover?(other)`, and `duration`
- Half-open semantics: `[10:00, 11:00)` and `[11:00, 12:00)` do **not** overlap
- Build the interval from `SlotTime` plus `ServiceType#duration_minutes`
- Reject zero or negative durations at construction (raise `ArgumentError`)
- Add `Appointment.overlapping(interval)` scope using `time_range && tstzrange(?, ?, '[)')`

#### Notes

- Pure Ruby with no Active Record dependency; the most important unit-test target in the project
- The Ruby overlap predicate and the SQL `&&` operator must agree; a spec compares them on shared fixtures

#### Acceptance Criteria

- Specs cover: back-to-back (allowed), 1-minute overlap (rejected), full containment, identical intervals, adjacent at midnight, invalid construction
- Property-based specs (`prop_check`) confirm `overlaps?` is symmetric
- Ruby and SQL overlap logic agree on the shared fixtures

---

### User Story 2: Find Free Service Bays

#### Description

- As the system, I need to find bays of the required type that are free for the entire interval.

#### Requirements

- Implement `Availability::FreeBays` in `app/queries/`: bays at the dealership matching `ServiceType#bay_type`
- Exclude bays with any overlapping active appointment or `bay_blocks` row, using `where.not(id: Appointment.active.overlapping(interval).select(:service_bay_id))`
- Cancelled appointments must not block
- Return an ordered relation so the assignment strategy stays deterministic

#### Notes

- Overlap is computed in SQL; never load all appointments into memory

#### Acceptance Criteria

- Query specs (real PostgreSQL) cover: no bookings, partial overlap at start, partial overlap at end, fully contained booking, maintenance block, cancelled booking, wrong bay type
- `relation.explain(:analyze)` shows the GiST index is used

---

### User Story 3: Find Qualified, Available Technicians

#### Description

- As the system, I need to find technicians with the required qualification who are on shift and free for the entire interval.

#### Requirements

- Implement `Availability::FreeTechnicians`: technicians at the dealership holding the service type's required qualification
- The entire interval must fit within a single shift (weekly shift pattern evaluated in the dealership time zone)
- Exclude technicians with overlapping `technician_time_off` or active appointments

#### Notes

- Assumption A5: one technician per appointment for the full duration
- An interval spanning a break between two shifts is rejected

#### Acceptance Criteria

- Excludes: unqualified, off-shift, partially off-shift, on leave, already booked
- Each exclusion rule has a dedicated spec
- An interval spanning two separate shifts is rejected

---

### User Story 4: Deterministic Assignment Strategy

#### Description

- As the system, I need a deterministic rule for choosing among several free bays and technicians.

#### Requirements

- Define the strategy interface (`#choose(bays:, technicians:, interval:)`) and the default `Scheduling::AssignmentStrategies::LeastLoaded` in `app/domain/scheduling/`
- Default rule: choose the **least-loaded technician for that local day** (ties broken by lowest ID) and the **lowest-ID free bay**
- Same inputs and data always produce the same assignment
- Strategy is injected into `Appointments::Book` so alternatives (preferred technician, balanced utilisation) can be added without changing the service

#### Notes

- Keep it a pure function of its inputs (load counts are passed in, not queried inside)
- Document the rule in the System Design Document

#### Acceptance Criteria

- Specs prove determinism and the tie-breaking rule
- Swapping the strategy requires no change to `Appointments::Book`

---

### User Story 5: Explain Why No Slot Is Available

#### Description

- As a customer, if no bay and technician pair is available, I want a clear explanation.

#### Requirements

- Return `409` with a reason code:
  - `NO_BAY`: qualified technicians exist but no bay is free
  - `NO_TECHNICIAN`: bays exist but no qualified technician is free
  - `NO_CAPACITY`: neither is available
- Include a human-readable `detail` and the requested interval in the error

#### Notes

- Do not expose other customers' appointment IDs or details

#### Acceptance Criteria

- Each reason code is produced by a dedicated spec scenario
- Codes are listed in the error catalogue (Epic 6)

---

### User Story 6: Suggest Alternative Slots

#### Description

- As a customer, I want suggested alternative slots when my choice is unavailable.

#### Requirements

- On a `NO_*` failure, include up to N (default 3) nearest available start times on the same local day, ordered by proximity to the requested time
- Suggestions respect opening hours, grid alignment, and full-duration availability
- N is configurable (`ALTERNATIVE_SLOTS_COUNT`)

#### Notes

- Suggestions are informational; booking re-validates at request time
- Reuse `Availability::DaySlots` from User Story 7

#### Acceptance Criteria

- Response contains `alternatives: [ISO timestamps]` when any exist, and an empty array otherwise
- Suggested slots are verified bookable in specs

---

### User Story 7: View Available Slots for a Day

#### Description

- As a customer, I want to view all available slots for a dealership, service type, and date before booking.

#### Requirements

- `GET /api/v1/availability?dealership_id=&service_type_id=&date=YYYY-MM-DD`
- Return all grid-aligned start times (dealership-local and UTC) where a bay **and** a qualified technician are free for the full duration
- Interpret `date` in the dealership time zone
- Avoid N+1 queries: load the day's appointments, blocks, shifts, and time off in bulk and compute slots in memory in `Availability::DaySlots`
- Optionally cache with `Rails.cache.fetch` using a short TTL keyed by `(dealership, service_type, date)`

#### Notes

- Results are advisory; a slot may disappear before booking
- Do not invalidate by touching the dealership row on every booking: that creates a hot-row lock that serializes bookings. Use a short TTL instead.

#### Acceptance Criteria

- Returns correct slots for seeded data, including after a booking is made
- Closed days and holidays return an empty list
- Endpoint is documented through rswag

---

### User Story 8: Guarantee No Double-Booking Under Concurrency

#### Description

- As the system, I must never double-book under concurrent requests.

#### Requirements

- Add a migration (with `strong_migrations` `safety_assured` where required) using `add_exclusion_constraint` for active appointments:
  - `service_bay_id WITH =, time_range WITH &&` where `status IN ('confirmed','in_progress')`
  - `technician_id WITH =, time_range WITH &&` with the same predicate
  - `vehicle_id WITH =, time_range WITH &&` with the same predicate
  - all `using: :gist`, with explicit constraint names
- Map `PG::ExclusionViolation` (SQLSTATE `23P01`) to a domain conflict failure; never let it surface as a `500`
- On conflict, **retry assignment** with the next candidate (bounded retries) before returning `409`
- Because a PostgreSQL error aborts the surrounding transaction, wrap each attempt in `transaction(requires_new: true)` (savepoint)
- Run availability check and insert in one transaction (Epic 4, User Story 2)

#### Notes

- The constraint is the source of truth; the application-level check is an optimisation that produces better errors
- READ COMMITTED plus the constraint is sufficient; document the reasoning
- Optional refinement: select candidates with `FOR UPDATE SKIP LOCKED` to reduce contention (documented, not required)

#### Acceptance Criteria

- Concurrency spec starts N (e.g. 20) threads, each with its own connection and released together by a latch, all booking the last slot: **exactly one succeeds, the rest receive `409`**, and exactly one row exists
- The spec is repeated many times without flakiness
- Direct SQL inserts that overlap are rejected by the database (constraint spec)
- The connection pool size in the test environment is at least N

---

### User Story 9: Keep Availability Fast as Data Grows

#### Description

- As an operator, I want the availability check to stay fast as data grows.

#### Requirements

- Review query plans (`relation.explain(:analyze)`) for free-bay, free-technician, and day-slot queries
- Confirm GiST and B-tree indexes from Epic 1 are used; add partial indexes on active statuses if beneficial
- Define a p95 latency target (e.g. under 100 ms for booking, under 200 ms for day availability at 1M appointments)
- Provide a `bin/rails scheduler:load_data[N]` rake task that generates a large dataset with `insert_all`
- Run Bullet in test to catch N+1 queries in the endpoints

#### Notes

- Partitioning appointments by dealership or month is a documented future step
- Record findings and benchmarks in the System Design Document

#### Acceptance Criteria

- Query plans show index usage (no sequential scans on `appointments` for hot paths)
- Benchmark results and the p95 target are documented
- The load task is committed and repeatable

---
