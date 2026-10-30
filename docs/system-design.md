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


## Future steps
- Partition `appointments` by `start_at` (monthly range partitions) once history grows past what one table serves; exclusion constraints need the partition key in the constraint, so the constraints must be re-expressed per partition.
- Invalidate or shorten the availability cache per dealership on booking if staleness becomes a problem.
