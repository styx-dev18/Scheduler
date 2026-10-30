# System Design

## Scope
Booking a service appointment needs a free service bay and a qualified, on-shift technician for the whole duration. This document records the assignment rule, the concurrency model, caching, performance targets and the measurements taken at 1,000,000 appointments.

## Assignment rule
- Candidate bays are active bays of the dealership with the service type's `required_bay_type` and no overlapping active appointment or bay block.
- Candidate technicians are active, qualified when the service type requires a qualification, on a shift that covers the whole local interval, and free of time off and overlapping active appointments.
- `Scheduling::AssignmentStrategies::LeastLoaded` picks the technician with the fewest active appointments on the dealership-local day, ties broken by the lowest id, and the bay with the lowest id.

## Concurrency
- Bookings run at the PostgreSQL default `READ COMMITTED` isolation level. Two requests can both see a resource as free, so the availability read is advisory.
- Three partial GiST exclusion constraints on `confirmed` and `in_progress` appointments are the source of truth: `appointments_no_bay_overlap`, `appointments_no_technician_overlap` and `appointments_no_vehicle_overlap`.
- `Appointments::Book` runs each attempt in `transaction(requires_new: true)`. A `StatementInvalid` whose cause is `PG::ExclusionViolation` removes the losing bay or technician from the candidates and retries; a vehicle violation returns `VEHICLE_ALREADY_BOOKED`.
- The retry bound is `MAX_ASSIGNMENT_ATTEMPTS = 3`. Each failed attempt removes one candidate, so when the candidates run out or the bound is reached the result is `NO_CAPACITY` (`409`).
- The 20-thread race spec books the last slot in parallel and expects exactly one success and 19 `409`s.

## Caching
`GET /api/v1/availability` caches the response body per dealership, service type and local date for 30 seconds. A booking does not invalidate it, so a listed slot may already be taken; `POST /api/v1/appointments` stays authoritative and returns alternatives on failure.

## Targets
| Operation | p95 target |
|---|---|
| Booking | under 100 ms at 1,000,000 appointments |
| Day availability | under 200 ms at 1,000,000 appointments |

## Measurements
Run on a scratch PostgreSQL 16 database on a developer laptop after `bin/rails "scheduler:load_data[1000000]"` (N = 1,000,000 appointments over 20 bays and 20 technicians, 180 appointments per day), then `ANALYZE`. Each figure is the p95 of 50 runs after 5 warm-up runs, in a single Rails process on a local database.

| Operation | p95 |
|---|---|
| `Availability::Finder#call` (one interval) | 1.08 ms |
| `Availability::DaySlots#call` (one fully booked day) | 7.08 ms |
| `Appointments::Book#call` (successful, rolled back) | 18.46 ms |

All three are inside their targets. These are in-process figures and exclude HTTP, serialization and network latency.

## EXPLAIN findings at 1,000,000 rows
- `FreeBays`: the `NOT IN` subquery on appointments uses an index scan on a GiST exclusion-constraint index (`appointments_no_vehicle_overlap`) with `time_range && tstzrange(...)`, about 0.11 ms. Bays are a 20-row sequential scan, which is cheaper than an index.
- `FreeTechnicians`: the same GiST index scan for the appointment subquery, about 0.22 ms; shifts, time off and technicians are tiny tables read sequentially.
- `DaySlots` appointment query: a bitmap scan on `index_appointments_on_technician_id_and_time_range` returns the 180 rows of the day in about 0.23 ms.
- No query reads `appointments` sequentially, so no index migration was added. `spec/queries/availability/query_plan_spec.rb` keeps this under test with `enable_seqscan = off` on the small test database.

## Persistence and backup
Appointments live in PostgreSQL on the named volume `pgdata`. `docker compose down` keeps the volume, so data survives; `docker compose down -v` deletes it. Restarting `web` or `db` never touches the volume.

Backup (custom-format dump of the compose database):
```
docker compose exec -T db pg_dump -U postgres -Fc scheduler_api_production > scheduler.dump
```

Restore into a running stack:
```
docker compose exec -T db pg_restore -U postgres -d scheduler_api_production --clean --if-exists < scheduler.dump
```

In production, use the managed database's automated backups and point-in-time recovery instead of dumps from the container.

`scripts/persistence_check.sh` needs only `docker compose` and `curl`. It starts the stack, books an appointment through the API, then checks that `GET /api/v1/appointments/{id}` returns 200 after creation, a `web` restart, a `db` restart and `docker compose down` followed by `up`. It prints one line per step and exits 1 naming the failed step. Run it manually; it is not part of `verify.sh` or CI.

## Appointment lifecycle and domain events
Status transitions live in the pure-Ruby `Scheduling::StatusMachine`; `Appointment#start!`, `#complete!`, `#mark_no_show!` and `#cancel!` delegate to it and raise `InvalidTransition` for a move the table doesn't allow.

| From | Allowed to |
|---|---|
| `confirmed` | `in_progress`, `cancelled`, `no_show` |
| `in_progress` | `completed` |
| `completed`, `cancelled`, `no_show` | none |

- `no_show` is accepted only at or after `start_at`, using the injected `Clock`.
- Every transition writes an `appointment_status_histories` row with `from_status`, `to_status`, `changed_at` and `actor`.

### Locking
Cancel, reschedule and status change start with `appointment.lock!` (`SELECT ... FOR UPDATE`), so concurrent lifecycle calls on one appointment serialize on the row and the final state matches one of the two orders. `lock_version` stays as optimistic locking; a reschedule request that sends a stale `lock_version` gets `409 CONCURRENT_MODIFICATION`.

### Reschedule
- The pipeline (past and slot-grid checks, opening hours, vehicle conflict, availability, assignment, savepoint retry) is shared with booking through `Appointments::Placement`.
- The appointment row is updated in place, so its id is kept and the exclusion constraints compare the new interval only against other rows.
- The availability queries and the vehicle conflict check take `exclude_appointment_id`, so a 15-minute shift is not blocked by the appointment's own old interval.
- The current bay and technician are kept when both are free at the new time; otherwise the assignment strategy picks.
- The previous and new intervals, actor and request id go to `appointment_reschedules`. A failed reschedule writes nothing.

### Cancel
Cancel sets `cancelled`, `cancelled_at` and `cancellation_reason` and writes the history row in one transaction. Cancelled appointments leave the `confirmed`/`in_progress` exclusion constraints, so the bay, technician and vehicle are free at once. A repeat cancel returns the current state without a new history row or event. `CANCELLATION_CUTOFF_HOURS` (default `0`, off) blocks cancelling closer to the start than the cut-off with `422 CANCELLATION_WINDOW_CLOSED`.

### Domain events
`Appointments::Events.publish` publishes through `ActiveSupport::Notifications` after the outermost transaction commits (`ActiveRecord.after_all_transactions_commit`), so a rollback, a failure or an idempotent repeat publishes nothing.

| Event | Extra payload |
|---|---|
| `appointment.confirmed` | none |
| `appointment.rescheduled` | `previous_start_at`, `previous_end_at`, `technician_id`, `service_bay_id` |
| `appointment.cancelled` | `cancelled_at`, `reason` |
| `appointment.status_changed` | `from_status`, `to_status` |

Every payload carries `appointment_id`, `customer_id`, `dealership_id`, `status`, `start_at`, `end_at`, `occurred_at` (UTC, from the injected clock) and `request_id` (`Current.request_id`, set per request from `X-Request-Id`).

`config/initializers/event_subscribers.rb` subscribes to `/\Aappointment\./` and writes one JSON line per event to `Rails.logger`.

### Outbox (production path)
In-process notifications are lost if the process dies between commit and publish. For at-least-once delivery, write an `outbox_events` row (event name, JSON payload, `published_at`) in the same transaction as the appointment change, then relay unpublished rows with a Solid Queue job that marks them published after delivery. Consumers dedupe on the event id. This is documented only; it is not implemented.

## Future steps
- Partition `appointments` by `start_at` (monthly range partitions) once history grows past what one table serves; exclusion constraints need the partition key in the constraint, so the constraints must be re-expressed per partition.
- Invalidate or shorten the availability cache per dealership on booking if staleness becomes a problem.

## Scaling & Reliability

### Topology
```mermaid
flowchart LR
  C[Clients] --> LB[Load balancer]
  LB --> W1[Rails + Puma]
  LB --> W2[Rails + Puma]
  W1 --> PB[PgBouncer]
  W2 --> PB
  PB --> P[(Primary)]
  P -. replication .-> R[(Read replica)]
  W1 -. availability reads .-> R
  W1 --> SC[(Solid Cache / Queue)]
  Q[Solid Queue workers] --> PB
  W1 --> OBS[Prometheus / Jaeger]
  P --> BK[(WAL archive + base backups)]
```

### Scaling
- Stateless instances: no session or local state, so any number of web instances sit behind the load balancer; readiness gates traffic.
- Puma and pool: `WEB_CONCURRENCY` processes times `RAILS_MAX_THREADS` threads, with pool size equal to threads per process. Total connections = instances x workers x threads and must stay under PostgreSQL `max_connections`.
- PgBouncer in transaction pooling mode multiplexes many app connections onto few server connections; prepared statements must be disabled or protocol-level pooling used.
- Read replicas: `connects_to` with a reading role serves availability queries. Replica lag means a slot may show free that was just taken. This is acceptable because the read is advisory; booking, rescheduling and cancellation always run on the primary, where the exclusion constraint decides.
- Partitioning: range partition `appointments` by `start_at` monthly once history is large; constraints must include the partition key.
- Solid Cache holds short-lived availability results in the database, so no extra infrastructure; stale entries only cause a failed booking, never a double booking.
- Rate limiting: Rack::Attack per-IP throttles (general and booking); the counter store must be shared (Solid Cache) across instances. Responses are 429 with `Retry-After`.
- Idempotency: `Idempotency-Key` with `IDEMPOTENCY_TTL` makes client retries after timeouts safe.
- Solid Queue scaling: add worker processes or threads per queue; jobs are database-backed, so workers scale independently of web.

### Why scale-out is safe
Double-booking is prevented by PostgreSQL exclusion constraints on bay and technician time ranges, not by application locks or in-process state. Any number of instances can race; the database rejects the loser and the service returns a `Failure`.

### Backup and recovery
Continuous WAL archiving plus daily base backups give point-in-time recovery. Targets: RPO of 5 minutes or less (WAL archive interval), RTO of 30 minutes (restore base backup, replay WAL, repoint `DATABASE_URL`). Restore is rehearsed quarterly.

### Future path
- Transactional outbox plus a message broker for domain events (see Outbox above).
- Read models for dashboards and reporting, fed from events.
- Kamal for multi-host deploys with rolling restarts and health-checked traffic switching.

### Limitations
- A single primary is the write ceiling; failover is manual or managed by the provider.
- Replica reads are eventually consistent.
- Rate limiting is per IP, so shared NATs are throttled together.
- Tracing via OpenTelemetry is optional and not enabled by default.

### Quality attributes pass
- Reliability: exclusion constraints, idempotency keys, statement and request timeouts, graceful worker shutdown, backups with stated RPO/RTO.
- Scalability: stateless web tier, pooled connections, replicas for reads, partitioning path, queue workers scaled separately.
- Observability: JSON request logs with request and trace ids, Prometheus booking metrics, optional OTLP traces to Jaeger, liveness and readiness probes.
- Availability: multiple instances behind readiness-gated load balancing, rate limiting to shed abuse, replica and backup recovery paths.
- Maintainability: pure-Ruby domain, service objects returning `Success`/`Failure`, a single error catalogue, and docs kept next to the code.
