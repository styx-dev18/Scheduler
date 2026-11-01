# Unified Service Scheduler

Rails 8 API-only backend for Keyloop Scenario A: book a service appointment for a vehicle, service type and dealership at a desired time. An appointment is confirmed only when a service bay **and** a qualified technician are free for the entire duration, and the appointment links the customer, vehicle, technician and bay.

Jump to: [Quick start](#quick-start) | [cURL examples](#curl-examples) | [AI Collaboration Narrative](#ai-collaboration-narrative) | [System Design Document](#system-design-document) | [Submission checklist](docs/submission-checklist.md)

## Overview

- Books, reschedules, cancels and lists appointments, and reports real-time availability per dealership, service type and date.
- Double-booking is prevented by PostgreSQL exclusion constraints on bay, technician and vehicle, which are the source of truth. The services translate a violation into a `409` and retry on another bay or technician.
- `Idempotency-Key` makes booking retries safe.
- Times are UTC `timestamptz` and intervals are half-open `[start, end)`. Responses add the dealership's local time.
- Observability: JSON logs, Prometheus metrics, OpenTelemetry traces, liveness and readiness probes.

## Scenario and layer

Scenario A of the Keyloop brief: the scheduling core of a dealership service system. This repository is the backend layer only (no UI, no authentication; customers and vehicles are pre-seeded and referenced by ID). The backlog and stack overview (Epic 0) live in [`epics/`](epics/README.md).

## Prerequisites

- Ruby 3.4.10 via rbenv (see `.ruby-version`) and Bundler
- PostgreSQL 16 running locally, or Docker with Compose
- Optional: the [Postman CLI](https://learning.postman.com/docs/postman-cli/postman-cli-overview/) for `make api-check` (it is not on `PATH` on every machine; pass `POSTMAN=/path/to/postman`)

## Quick start

With Docker (API on `http://localhost:3000`):

```sh
cp .env.example .env
docker compose up --build
```

The default run auto-loads `docker-compose.override.yml`: the `web` container runs in development against `scheduler_api_development`, runs `db:prepare db:seed` on start and serves on host port 3000. `.env` is optional. For the production-like stack, see [Docker](#docker).

Check it is up:

```sh
curl -fsS localhost:3000/health/ready
```

## Local development

```sh
bundle install
cp .env.example .env
bin/setup --skip-server
bin/dev
```

`bin/setup` installs dependencies and prepares the database, then starts the server unless `--skip-server` is given; `bin/dev` starts the server on `http://localhost:3000`. To prepare and seed manually, run `bin/rails db:prepare db:seed`. To restore the seed data to a known state (the cURL examples below assume this), run `bin/rails db:seed:replant`.

To use another port, run `bin/rails server -p 3055` (add `-P <pidfile>` if another server already uses `tmp/pids/server.pid`).

Puma loads the Yabeda plugin and the Puma control app only when `METRICS_ENABLED=true`.

## Running tests

```sh
bundle exec rspec
bundle exec rspec spec/domain
RACE_ITERATIONS=50 COVERAGE=false bundle exec rspec spec/concurrency
COVERAGE=false bundle exec rake rswag:specs:swaggerize && git diff --exit-code swagger/
.claude/scripts/verify.sh
```

- `spec/domain` needs no database, whatever the path form (`spec/domain`, `spec/domain/x_spec.rb:12`, `./spec/domain/x_spec.rb`). `spec/domain/architecture_spec.rb` fails if any `app/domain` file mentions `ActiveRecord`, `ApplicationRecord` or `Rails.`.
- `RACE_ITERATIONS` (default `5`) sets how many rounds the race specs run. Each round releases 20 threads at once at one bay and one technician and expects exactly one success. `spec/concurrency/http_booking_race_spec.rb` does it over HTTP and expects one `201` and nineteen `409`.
- `COVERAGE` switches SimpleCov threshold enforcement: `COVERAGE=true` enforces, `COVERAGE=false` disables, and when unset it follows `CI`. The thresholds are 90% line and 85% branch for the "Domain" (`app/domain`) and "Services" (`app/services`) groups, enforced in `.simplecov`. A run that misses exits with status 2. Set `COVERAGE=false` for partial runs on CI.
- `.claude/scripts/verify.sh` is the full gate (zeitwerk, RuboCop, Brakeman, RSpec); add `--quick` for the Zeitwerk check only.
- CI (`.github/workflows/ci.yml`) runs the jobs `scan_ruby`, `lint`, `zeitwerk`, `test` (Postgres 16, full suite with thresholds, then a 50-iteration race), `openapi_drift` and `docker`.

## API overview

All routes are under `/api/v1` and return the envelope `{ success, data, error, message, meta }`.

| Method and path | Purpose | Success |
|---|---|---|
| `GET /dealerships` | List dealerships with time zone and opening hours | 200 |
| `GET /dealerships/{dealership_id}/appointments` | Dealership schedule (`date`, `technician_id`, `service_bay_id`, `status`, `page`, `per_page`) | 200 |
| `GET /service-types` | List service types | 200 |
| `GET /availability?dealership_id&service_type_id&date` | Free slots for a local date | 200 |
| `POST /appointments` | Book (header `Idempotency-Key`) | 201 |
| `GET /appointments` | List (`customer_id`, `status`, `from`, `to`, `sort`, `per_page`) | 200 |
| `GET /appointments/{id}` | Show | 200 |
| `POST /appointments/{id}/reschedule` | Move to `new_start_at` with `lock_version` | 200 |
| `POST /appointments/{id}/cancel` | Cancel with optional `reason` | 200 |
| `PATCH /appointments/{id}/status` | Change status (`status`) | 200 |

Outside `/api/v1`: `GET /health/live`, `GET /health/ready`, `GET /up`, and `GET /metrics` when `METRICS_ENABLED=true`.

Errors use `{ error: { code, status, title, detail, ... } }`. Codes are listed in [`docs/error-catalogue.md`](docs/error-catalogue.md). The catalogue is the source for status codes, with one nuance in the code: `VALIDATION_ERROR` is returned as `400` when the request is malformed or incomplete (a form or parameter check in the controller, with per-field messages under `error.errors`), while rule violations raised by the services, such as `START_TIME_NOT_ON_SLOT_GRID`, `START_TIME_IN_PAST` and `OUTSIDE_OPENING_HOURS`, are `422`. Booking conflicts are `409` (`NO_BAY`, `NO_TECHNICIAN`, `NO_CAPACITY`, `VEHICLE_ALREADY_BOOKED`, `IDEMPOTENCY_KEY_IN_PROGRESS`), unknown referenced resources are `404` `NOT_FOUND`.

## cURL examples

These run in order against a freshly seeded server (`bin/rails db:seed:replant`) at `http://localhost:3000`, using the seeded Manhattan Auto Care IDs and Monday `2030-01-07`. Output below is real and trimmed with `...`. The booking in step 4 takes the only lift bay (Bay L1) and the only Lift Certified technician (Dan Dalton), so the rival booking in step 5 conflicts.

```sh
export BASE=http://localhost:3000
export DEALERSHIP=00000020-0000-4000-8000-000000000002
export FULL_SERVICE=00000050-0000-4000-8000-000000000002
```

### 1. List dealerships and service types (200)

```sh
curl -s -w '\nHTTP %{http_code}\n' $BASE/api/v1/dealerships
curl -s -w '\nHTTP %{http_code}\n' $BASE/api/v1/service-types
```

```json
{"success":true,"data":[{"id":"00000020-0000-4000-8000-000000000001","name":"Londinium Motors","time_zone":"Europe/London","opening_hours":[...]},{"id":"00000020-0000-4000-8000-000000000002","name":"Manhattan Auto Care","time_zone":"America/New_York","opening_hours":[{"day_of_week":1,"opens_at":"08:00","closes_at":"17:00"},...]}],"error":null,"message":null,"meta":{"page":1,"per_page":25,"total_pages":1,"total_count":2}}
HTTP 200
{"success":true,"data":[{"id":"00000050-0000-4000-8000-000000000002","name":"Full Service","description":"Comprehensive inspection and maintenance on a lift","duration_minutes":120},{"id":"00000050-0000-4000-8000-000000000001","name":"Oil Change",...},{"id":"00000050-0000-4000-8000-000000000003","name":"Wheel Alignment",...}],"error":null,"message":null,"meta":{"page":1,"per_page":25,"total_pages":1,"total_count":3}}
HTTP 200
```

### 2. Check availability (200)

```sh
curl -s -w '\nHTTP %{http_code}\n' "$BASE/api/v1/availability?dealership_id=$DEALERSHIP&service_type_id=$FULL_SERVICE&date=2030-01-07"
```

```json
{"success":true,"data":{"dealership_id":"00000020-0000-4000-8000-000000000002","service_type_id":"00000050-0000-4000-8000-000000000002","date":"2030-01-07","time_zone":"America/New_York","slots":[{"start_at":"2030-01-07T14:00:00Z","local_start_at":"2030-01-07T09:00:00-05:00"},{"start_at":"2030-01-07T14:15:00Z","local_start_at":"2030-01-07T09:15:00-05:00"},...,{"start_at":"2030-01-07T20:00:00Z","local_start_at":"2030-01-07T15:00:00-05:00"}]},"error":null,"message":null}
HTTP 200
```

### 3. Book an appointment (201)

```sh
curl -s -w '\nHTTP %{http_code}\n' -X POST $BASE/api/v1/appointments \
  -H 'Content-Type: application/json' -H 'Idempotency-Key: readme-demo-1' \
  -d '{"customer_id":"00000070-0000-4000-8000-000000000003","vehicle_id":"00000071-0000-4000-8000-000000000003","service_type_id":"'$FULL_SERVICE'","dealership_id":"'$DEALERSHIP'","start_at":"2030-01-07T15:00:00Z"}'
```

```json
{"success":true,"data":{"id":"8e1ffd30-009b-4c68-8c09-310fc3d9447a","status":"confirmed","customer_id":"00000070-0000-4000-8000-000000000003","vehicle_id":"00000071-0000-4000-8000-000000000003","service_type_id":"00000050-0000-4000-8000-000000000002","dealership_id":"00000020-0000-4000-8000-000000000002","technician_id":"00000060-0000-4000-8000-000000000004","service_bay_id":"00000040-0000-4000-8000-000000000007","start_at":"2030-01-07T15:00:00Z","end_at":"2030-01-07T17:00:00Z","time_zone":"America/New_York","local_start_at":"2030-01-07T10:00:00-05:00","local_end_at":"2030-01-07T12:00:00-05:00","lock_version":0,...,"technician":{"id":"00000060-0000-4000-8000-000000000004","display_name":"Dan Dalton"},"service_bay":{"id":"00000040-0000-4000-8000-000000000007","label":"Bay L1"}},"error":null,"message":null}
HTTP 201
```

The `id` is generated per run. Save it for steps 6 to 8:

```sh
export APPOINTMENT_ID=<the id from the response>
```

### 4. Conflicting booking (409)

A different customer and vehicle ask for the same slot with a new key.

```sh
curl -s -w '\nHTTP %{http_code}\n' -X POST $BASE/api/v1/appointments \
  -H 'Content-Type: application/json' -H 'Idempotency-Key: readme-demo-2' \
  -d '{"customer_id":"00000070-0000-4000-8000-000000000001","vehicle_id":"00000071-0000-4000-8000-000000000001","service_type_id":"'$FULL_SERVICE'","dealership_id":"'$DEALERSHIP'","start_at":"2030-01-07T15:00:00Z"}'
```

```json
{"success":false,"data":null,"error":{"type":"https://httpstatuses.com/409","title":"No capacity available","status":409,"code":"NO_CAPACITY","detail":"No service bay or technician is available","starts_at":"2030-01-07T15:00:00Z","ends_at":"2030-01-07T17:00:00Z","alternatives":["2030-01-07T17:00:00Z","2030-01-07T17:15:00Z","2030-01-07T17:30:00Z"]},"message":"No service bay or technician is available"}
HTTP 409
```

The response suggests the next free start times in `alternatives` (`ALTERNATIVE_SLOTS_COUNT` of them). Depending on which resource is exhausted, the code is `NO_BAY`, `NO_TECHNICIAN` or `NO_CAPACITY`.

### 5. Idempotent retry (201, same appointment)

Repeat step 3 with the same `Idempotency-Key` and body. The stored response is replayed and no second appointment is created.

```sh
curl -s -w '\nHTTP %{http_code}\n' -X POST $BASE/api/v1/appointments \
  -H 'Content-Type: application/json' -H 'Idempotency-Key: readme-demo-1' \
  -d '{"customer_id":"00000070-0000-4000-8000-000000000003","vehicle_id":"00000071-0000-4000-8000-000000000003","service_type_id":"'$FULL_SERVICE'","dealership_id":"'$DEALERSHIP'","start_at":"2030-01-07T15:00:00Z"}'
```

```json
{"success":true,"data":{"id":"8e1ffd30-009b-4c68-8c09-310fc3d9447a","status":"confirmed",...},"error":null,"message":null}
HTTP 201
```

The same key with a different body returns `422` `IDEMPOTENCY_KEY_REUSED`.

### 6. Reschedule (200)

`lock_version` must match the appointment (optimistic locking); a stale value returns `409` `CONCURRENT_MODIFICATION`.

```sh
curl -s -w '\nHTTP %{http_code}\n' -X POST $BASE/api/v1/appointments/$APPOINTMENT_ID/reschedule \
  -H 'Content-Type: application/json' -d '{"new_start_at":"2030-01-07T18:00:00Z","lock_version":0}'
```

```json
{"success":true,"data":{"id":"8e1ffd30-009b-4c68-8c09-310fc3d9447a","status":"confirmed",...,"start_at":"2030-01-07T18:00:00Z","end_at":"2030-01-07T20:00:00Z",...},"error":null,"message":null}
HTTP 200
```

### 7. Cancel (200)

```sh
curl -s -w '\nHTTP %{http_code}\n' -X POST $BASE/api/v1/appointments/$APPOINTMENT_ID/cancel \
  -H 'Content-Type: application/json' -d '{"reason":"customer request"}'
```

```json
{"success":true,"data":{"id":"8e1ffd30-009b-4c68-8c09-310fc3d9447a","status":"cancelled",...},"error":null,"message":null}
HTTP 200
```

Cancelled appointments never block a slot, so the slot is bookable again. Re-run `bin/rails db:seed:replant` and use new idempotency keys to repeat the sequence.

### Validation errors

A missing or malformed field is a `400`:

```sh
curl -s -w '\nHTTP %{http_code}\n' -X POST $BASE/api/v1/appointments -H 'Content-Type: application/json' -d '{"vehicle_id":"x"}'
```

```json
{"success":false,"data":null,"error":{"type":"https://httpstatuses.com/400","title":"Validation failed","status":400,"code":"VALIDATION_ERROR","detail":"Invalid booking request","errors":{"customer_id":["can't be blank"],"service_type_id":["can't be blank"],"dealership_id":["can't be blank"],"vehicle_id":["is not a valid UUID"],"start_at":["can't be blank"]}},"message":"Invalid booking request"}
HTTP 400
```

A well-formed request that breaks a scheduling rule is a `422`, for example `"start_at":"2030-01-07T15:10:00Z"`:

```json
{"success":false,"data":null,"error":{"type":"https://httpstatuses.com/422","title":"Start time is not on the slot grid","status":422,"code":"START_TIME_NOT_ON_SLOT_GRID","detail":"Start time must be on a 15-minute boundary"},"message":"Start time must be on a 15-minute boundary"}
HTTP 422
```

## Client harness

`make api-check` runs the Postman v3 collection in `postman/` against a running, seeded API (default `http://localhost:3000`, see `postman/environments/local.environment.yaml`):

```sh
bin/rails db:seed:replant
make api-check POSTMAN=/path/to/postman
make api-check BASE_URL=http://localhost:3061
```

`BASE_URL` is optional and overrides the environment's `baseUrl`; without it the collection targets `http://localhost:3000`.

`POSTMAN` defaults to `postman` on `PATH`. The collection computes a free Monday at least 7 days ahead, then lists dealerships and service types, checks availability, books (201), books the same slot with the rival vehicle (409 with a `NO_*` code), retries with the same key (201, same id), reschedules (200) and cancels (200). It uses a new `Idempotency-Key` per run and cancels its own booking, so it passes when run repeatedly. It is a local and demo check, not a CI job.

## Demo

`bin/demo` runs the whole story from the repo, for recording or a walkthrough: it reseeds (`bin/rails db:seed:replant`, or `docker compose exec -T web bin/rails db:seed:replant` with `DEMO_TARGET=docker`), checks `$BASE_URL/health/ready` (default `http://localhost:3000`), runs `make api-check`, then runs the two race specs with `--format documentation`. Start the API first with `bin/dev` or `docker compose up`. The recording plan is in [`docs/video-script.md`](docs/video-script.md).

## Environment variables

Copy `.env.example` to `.env` and adjust. Every key in `.env.example` is listed here.

| Variable | Default | Purpose |
|---|---|---|
| `DATABASE_URL` | commented out | Full connection URL; alternative to the `DB_*` variables |
| `DB_HOST` | empty | Database host (empty uses the local socket) |
| `DB_PORT` | `5432` | Database port |
| `DB_USERNAME` | empty | Database user |
| `DB_PASSWORD` | empty | Database password |
| `DB_NAME` | `scheduler_api_development` | Development database name |
| `DB_NAME_TEST` | `scheduler_api_test` | Test database name |
| `RAILS_MAX_THREADS` | `5` | Puma threads and DB pool size |
| `WEB_CONCURRENCY` | `1` | Puma worker count |
| `LOG_LEVEL` | `info` | Log level |
| `CORS_ORIGINS` | `http://localhost:3000` | Allowed CORS origins (required in production) |
| `DOCS_ENABLED` | `false` | Mount Swagger UI at `/api-docs` when `true` |
| `SLOT_MINUTES` | `15` | Slot grid size in minutes |
| `ALTERNATIVE_SLOTS_COUNT` | `3` | Alternative start times returned with a booking conflict |
| `IDEMPOTENCY_TTL` | `86400` | Seconds an idempotency key is kept |
| `CANCELLATION_CUTOFF_HOURS` | `0` | Hours before the start within which cancellation is refused (`0` disables the cutoff) |
| `DB_STATEMENT_TIMEOUT_MS` | `5000` | PostgreSQL statement timeout (`bin/docker-entrypoint` sets `0` for `db:prepare` so migrations are exempt) |
| `RACK_TIMEOUT_SERVICE_TIMEOUT` | `15` | Request timeout in seconds |
| `RATE_LIMIT_ENABLED` | `true` | Toggle Rack::Attack throttling |
| `RATE_LIMIT_REQUESTS` | `300` | General per-IP request limit |
| `RATE_LIMIT_PERIOD` | `60` | General limit window in seconds |
| `RATE_LIMIT_BOOKING_REQUESTS` | `20` | Limit for `POST /api/v1/appointments` |
| `RATE_LIMIT_BOOKING_PERIOD` | `60` | Booking limit window in seconds |
| `METRICS_ENABLED` | `false` | Expose Prometheus metrics at `/metrics` and load the Yabeda Puma plugin |
| `METRICS_TOKEN` | empty | Bearer token required by `/metrics` when set |
| `OTEL_ENABLED` | `false` | Enable OpenTelemetry tracing export |
| `OTEL_SERVICE_NAME` | `scheduler-api` | Service name on exported traces |
| `OTEL_EXPORTER_OTLP_ENDPOINT` | `http://localhost:4318` | OTLP collector endpoint |

Not in `.env.example`: `WORKER_SHUTDOWN_TIMEOUT` (default `25`, Puma worker graceful shutdown in seconds). In production, `DATABASE_URL` (or `DB_HOST`) and `CORS_ORIGINS` are required.

## Seeded IDs

Seeds in `db/seeds/` are idempotent and use deterministic UUIDs from `SeedSupport.uuid(namespace, number)` (`db/seeds.rb`). Reset with `bin/rails db:seed:replant`.

| Entity | ID | Name |
|---|---|---|
| Dealership 1 | `00000020-0000-4000-8000-000000000001` | Londinium Motors (`Europe/London`) |
| Dealership 2 | `00000020-0000-4000-8000-000000000002` | Manhattan Auto Care (`America/New_York`) |
| Service type 1 | `00000050-0000-4000-8000-000000000001` | Oil Change (30 min, general bay) |
| Service type 2 | `00000050-0000-4000-8000-000000000002` | Full Service (120 min, lift bay) |
| Service type 3 | `00000050-0000-4000-8000-000000000003` | Wheel Alignment (60 min, alignment bay) |
| Customer 1 / vehicle 1 | `00000070-0000-4000-8000-000000000001` / `00000071-0000-4000-8000-000000000001` | Grace Hopper, Honda Accord |
| Customer 2 / vehicle 2 | `00000070-0000-4000-8000-000000000002` / `00000071-0000-4000-8000-000000000002` | Alan Turing, Volkswagen Golf |
| Customer 3 / vehicle 3 | `00000070-0000-4000-8000-000000000003` / `00000071-0000-4000-8000-000000000003` | Katherine Johnson, Ford F-150 |
| Bay 1 | `00000040-0000-4000-8000-000000000001` | Londinium Bay G1 (general) |
| Bay 2 | `00000040-0000-4000-8000-000000000002` | Londinium Bay L1 (lift) |
| Bay 3 | `00000040-0000-4000-8000-000000000003` | Londinium Bay L2 (lift) |
| Bay 4 | `00000040-0000-4000-8000-000000000004` | Londinium Bay A1 (alignment) |
| Bay 5 | `00000040-0000-4000-8000-000000000005` | Manhattan Bay G1 (general) |
| Bay 6 | `00000040-0000-4000-8000-000000000006` | Manhattan Bay G2 (general) |
| Bay 7 | `00000040-0000-4000-8000-000000000007` | Manhattan Bay L1 (lift) |
| Bay 8 | `00000040-0000-4000-8000-000000000008` | Manhattan Bay A1 (alignment) |
| Technician 1 | `00000060-0000-4000-8000-000000000001` | Alice Archer (Londinium; general, lift) |
| Technician 2 | `00000060-0000-4000-8000-000000000002` | Bob Brewer (Londinium; general, alignment) |
| Technician 3 | `00000060-0000-4000-8000-000000000003` | Carol Chandler (Londinium; general) |
| Technician 4 | `00000060-0000-4000-8000-000000000004` | Dan Dalton (Manhattan; general, lift, alignment) |
| Technician 5 | `00000060-0000-4000-8000-000000000005` | Erin Eastwood (Manhattan; general) |
| Technician 6 | `00000060-0000-4000-8000-000000000006` | Frank Fowler (Manhattan; general, alignment) |

Qualifications use namespace `0x10` (`00000010-0000-4000-8000-00000000000N`: 1 General Service, 2 Lift Certified, 3 Alignment Certified). Technicians work Monday to Friday, odd-numbered ones 08:00-16:00 and even-numbered ones 09:00-17:00, in the dealership's local time. Both dealerships open Monday to Friday 08:00-17:00.

Single-lift-bay scenario: Manhattan Auto Care has exactly one lift bay (Bay L1) and one Lift Certified technician (Dan Dalton), so two overlapping Full Service bookings there exercise the double-booking conflict. Londinium Motors offers all three service types; Manhattan Auto Care offers Oil Change and Full Service only (`db/seeds/08_dealership_service_types.rb`).

## Assumptions

The brief leaves some points open. Assumptions A1 to A11 (fixed duration per service type, qualification-based technicians, automatic assignment, bay types, one bay and one technician per appointment, UTC with dealership time zones, a 15-minute grid, no authentication, vehicle ownership, no same-vehicle overlap, no payments or notifications) are listed in [`docs/system-design.md`](docs/system-design.md#assumptions).

## Project structure

```
app/
  controllers/  HTTP layer (api/, health)
  domain/       pure Ruby scheduling logic, no Rails or ActiveRecord
  errors/       error catalogue
  forms/        form objects for input validation
  jobs/         Solid Queue jobs (expired idempotency key cleanup)
  models/       ActiveRecord models
  queries/      read-side queries (availability, listings)
  serializers/  JSON serializers
  services/     use cases returning dry-monads Success/Failure
bin/            setup, dev, demo
config/         routes, initializers (lograge, opentelemetry, yabeda, rack-attack)
db/             migrations, structure.sql, seeds/
docs/           system design, ERD, error catalogue, AI log, video script
epics/          backlog and stack overview
postman/        Postman v3 collection and environment
spec/           RSpec (domain, models, requests, integration, concurrency, services)
swagger/        generated OpenAPI spec
```

Conventions: times are UTC `timestamptz`, intervals are half-open `[start, end)`, and PostgreSQL exclusion constraints are the source of truth for double-booking.

Common commands:

| Task | Command |
|---|---|
| Install and set up | `bin/setup` (`make setup`) |
| Run the server | `bin/dev` (`make up`) |
| Tests | `bundle exec rspec` (`make test`) |
| Lint | `bundle exec rubocop` (`make lint`) |
| Security scan | `bin/brakeman` |
| Dependency audit | `bin/bundler-audit` |
| Migrate / roll back | `bin/rails db:migrate` / `bin/rails db:rollback` |
| Seed / reset and reseed | `bin/rails db:seed` / `bin/rails db:seed:replant` |
| Regenerate OpenAPI | `bundle exec rake rswag:specs:swaggerize` (`make docs`) |
| Client harness | `make api-check` |
| Demo | `bin/demo` |

## Observability

Metrics, logs and traces are configured by the environment variables above:

- Metrics (`METRICS_ENABLED=true`, `/metrics`, protected by `METRICS_TOKEN` when set): `booking_attempts_total`, `booking_success_total`, `booking_failure_total{reason}`, `booking_duration_seconds`, `availability_query_duration_seconds`, plus Puma metrics.
- Logs: in production one JSON line per request with `request_id`, `trace_id`, `appointment_id`, `method`, `path`, `status` and `duration`.
- Traces: `OTEL_ENABLED=true` exports OpenTelemetry spans to `OTEL_EXPORTER_OTLP_ENDPOINT`.

Run the local stack (Prometheus on 9090, Grafana on 3001, Jaeger UI on 16686, OTLP on 4317 and 4318):

```sh
METRICS_ENABLED=true METRICS_TOKEN=secret bin/rails server
docker compose -f docker-compose.observability.yml up
```

Put the same token in `config/observability/prometheus.yml`. Import `config/observability/grafana-dashboard.json` in Grafana (success rate, conflict rate, p95 booking duration). More detail: [Observability in the design document](docs/system-design.md#observability).

## Health endpoints

- `GET /health/live`: liveness, no dependency checks (`GET /health` is an alias)
- `GET /health/ready`: readiness, runs `SELECT 1` and checks for pending migrations; `503` otherwise
- `GET /up`: Rails built-in health check

## Docker

`Dockerfile`, `docker-compose.yml` and `docker-compose.override.yml` define a `web` service and a PostgreSQL 16 `db` service with a health check. The web container runs `db:prepare db:seed` on start. The CI `docker` job builds the image.

```sh
docker compose up --build
```

The default command auto-loads the override: development environment, `scheduler_api_development`, plain `rails server` on port 3000 with the repository bind-mounted.

```sh
docker compose -f docker-compose.yml up --build
```

This is the production-like stack: Thruster, host port 3000 to container port 80, seeded `scheduler_api_production`.

The compose stack was not verified on the authoring machine (Docker is not installed there). The local path (`bin/setup`, `bin/dev`, cURL examples, `make api-check`) was verified by a clean-clone run. The cURL outputs in this README were produced against a local `bin/rails server`.

## API documentation

Docs are disabled by default. Start the server with `DOCS_ENABLED=true` to expose them:

- Swagger UI: `/api-docs`
- Raw OpenAPI spec: `/api-docs/v1/openapi.yaml`

The spec is generated from the rswag request specs (`make docs`), and CI fails if the committed `swagger/v1/openapi.yaml` drifts from them.

## System Design Document

[`docs/system-design.md`](docs/system-design.md) covers the architecture diagram and component roles, the booking sequence, technology choices, data model ([`docs/erd.md`](docs/erd.md)), assumptions, the double-booking strategy and alternatives, the error catalogue, observability, scaling and reliability, how GenAI assisted the design, and limitations and future work. The deliverable-by-deliverable map is in [`docs/submission-checklist.md`](docs/submission-checklist.md).

## AI Collaboration Narrative

The full running log, with every case's detection, fix and evidence, is [`docs/ai-log.md`](docs/ai-log.md). This section summarises it. Every defect below can be checked in the repository by the commit, file or spec cited.

### Strategy

Claude Code works from a written plan per epic (`epics/`), one feature branch per epic, and a coordinator/implementer split: a coordinator plans and gates, implementer agents each own a disjoint set of files (workflow in [`docs/claude-coordinator-workflow.md`](docs/claude-coordinator-workflow.md)). Project rules are kept in `CLAUDE.md` and `.claude/docs/` (coding, testing and architecture rules), which every agent reads before changing code. Rules that matter most are enforced by tools, not by memory: the domain is pure Ruby (checked by `spec/domain/architecture_spec.rb`), services return `Success`/`Failure`, and the database exclusion constraints decide double-booking.

### Prompting approach

Tasks are given as small, bounded items with explicit contracts (class names, signatures, response shapes), the files each agent may touch, and acceptance criteria written as given/when/then checks. Review is a separate pass: findings are numbered (F1, F2, ...), tagged with the rule they break, and fixed by an agent that reads that rule first. The prompts forbid comments, debug output and unrequested changes, so diffs stay surgical.

### Verification process

Nothing is accepted on the AI's word. Each change has to pass `.claude/scripts/verify.sh` (Zeitwerk, RuboCop, Brakeman, RSpec), and the claims that matter get a negative probe that makes the check fail on purpose. Concurrency claims are tested with real threads released by a barrier, against PostgreSQL, over the service and over HTTP. Documentation claims are checked against `config/routes.rb`, `app/errors/error_catalogue.rb`, `.env.example` and the generated OpenAPI file, and the cURL examples above were run and pasted.

Reproduce the checks:

```sh
.claude/scripts/verify.sh
RACE_ITERATIONS=50 COVERAGE=false bundle exec rspec spec/concurrency
bin/brakeman
bin/bundler-audit
COVERAGE=false bundle exec rake rswag:specs:swaggerize && git diff --exit-code swagger/
```

### Defects found in AI output

Detail and evidence for these and six more are in [`docs/ai-log.md`](docs/ai-log.md).

1. **Missing exclusion constraints let parallel requests double-book.**
   - Detection: while hardening booking against concurrent requests, the schema had no PostgreSQL exclusion constraints on `appointments`, so only application checks stood between two parallel requests and a double booking.
   - Fix: done by hand. A migration adds three GiST constraints (bay, technician, vehicle) over active appointments, and `Appointments::Placement` rescues `ActiveRecord::ExclusionViolation` and retries on another resource.
   - Evidence: commit `414a468`, squash-merged as `0f0af0b` (#10); `db/migrate/20260301000001_add_appointment_exclusion_constraints.rb`; `spec/models/appointment_exclusion_spec.rb`; `spec/concurrency/book_overlap_spec.rb`.
2. **A non-string cancel reason returned 500.**
   - Detection: review found that `{"reason": 123}` passes the strong parameters, then `123.length` raises and the generic handler answers `500 INTERNAL_ERROR`.
   - Fix: `Appointments::Cancel` validates the type first and returns `VALIDATION_ERROR`, so the client gets `400`.
   - Evidence: commit `ad5fa39` (#13); `app/services/appointments/cancel.rb`; `spec/requests/api/v1/appointment_cancel_spec.rb`.
3. **Coverage thresholds were silently not enforced.**
   - Detection: the first implementation called `minimum_coverage_by_group` in `.simplecov`, which SimpleCov 0.22.0 does not have. The file failed to load, yet the gate summary still read green. It was caught by reading the full RSpec log instead of the summary.
   - Fix: `.simplecov` checks the "Domain" and "Services" groups in an at-exit hook and exits with status 2 on a miss, proven by forcing a miss.
   - Evidence: `.simplecov`; `spec/spec_helper.rb`. Lesson: a green summary is not proof a check ran.
4. **The atomicity spec stubbed Active Record.**
   - Detection: convention review found `allow_any_instance_of(Appointment).to receive(:save!)`, which stubs persistence instead of exercising it.
   - Fix: the failure is injected through a real collaborator, so the rollback runs against the real database.
   - Evidence: commit `bae32d9` (#12); `spec/services/appointments/book_atomicity_spec.rb`.
5. **`docker compose up` failed on a fresh clone.**
   - Detection: review of `docker-compose.yml` found `env_file: .env` fails when `.env` is absent, and a production boot needs `SECRET_KEY_BASE` and `CORS_ORIGINS`, which were not set.
   - Fix: the `env_file` became optional and the missing variables were set under `environment:`.
   - Evidence: `docker-compose.yml`; foundation squash commit `f6ba77a`.

Not every suggestion was right. A review proposed removing `Appointment.build_confirmed` as a one-line wrapper. It was declined because the method is part of the epic's contract and is covered by specs (`app/models/appointment.rb`, `spec/models/appointment_spec.rb`).

### Quality gates

- `.claude/scripts/verify.sh`: Zeitwerk, RuboCop (omakase), Brakeman, RSpec, as one exit code.
- SimpleCov thresholds of 90% line and 85% branch on `app/domain` and `app/services`, enforced when `CI=true`.
- `spec/domain/architecture_spec.rb`: the domain layer may not reference `ActiveRecord`, `ApplicationRecord` or `Rails.`.
- Race specs: 20 threads, one bay, one technician, exactly one winner, repeatable with `RACE_ITERATIONS=50`, over the service and over HTTP.
- OpenAPI drift check in CI, and `bin/bundler-audit` for dependencies.
- Request specs for each booking error code, including `NO_BAY`, `NO_TECHNICIAN`, `IDEMPOTENCY_KEY_IN_PROGRESS`, 404 and 400.
- The Postman harness (`make api-check`) as a client-side check against a running stack.

Pitfalls that the brief warns about, such as double-booking under concurrency, N+1 queries and callbacks hiding rules, are guarded against by the constraints and race specs above, Bullet in development and test, and services that own the booking rules. They are described as guarded, not as AI defects, because no defect was recorded for them.

### Ownership

The author decides scope, reads every diff, and merges. AI output was changed by hand where it was wrong (the exclusion constraints), declined where it was wrong for this codebase (`build_confirmed`), and re-checked with probes where a green result was not enough (coverage thresholds). The AI log records those decisions so the reasoning is visible, and the design document says where GenAI helped ([How GenAI assisted the design](docs/system-design.md#how-genai-assisted-the-design)).
