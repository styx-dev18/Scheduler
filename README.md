# Unified Service Scheduler

Rails 8 API-only backend for Keyloop Scenario A: book a service appointment for a vehicle, service type and dealership at a desired time. An appointment is confirmed only when a service bay **and** a qualified technician are free for the entire duration, and the appointment links the customer, vehicle, technician and bay.

This repository is the backend layer. The backlog and stack overview (Epic 0) live in [`epics/`](epics/README.md).

## Prerequisites

- Ruby 3.4.10 (via rbenv, see `.ruby-version`)
- PostgreSQL 16 running locally
- Bundler
- Docker is optional and not yet verified (see [Docker](#docker))

## Quick start

```sh
bundle install
cp .env.example .env
bin/setup
bin/dev
```

`bin/setup` installs dependencies and prepares the database. To prepare the database and load seeds manually, run `bin/rails db:prepare db:seed`.

The API is then available at `http://localhost:3000`.

## Running tests

```sh
bundle exec rspec
bundle exec rspec spec/domain
.claude/scripts/verify.sh
```

`spec/domain` needs no database. `.claude/scripts/verify.sh` is the full gate (zeitwerk, RuboCop, Brakeman, RSpec); add `--quick` for the Zeitwerk check only.

## Common commands

| Task | Command |
|---|---|
| Install and set up | `bin/setup` |
| Run the server | `bin/dev` |
| Lint | `bundle exec rubocop` |
| Security scan | `bin/brakeman` |
| Dependency audit | `bin/bundler-audit` |
| Migrate | `bin/rails db:migrate` |
| Roll back | `bin/rails db:rollback` |
| Seed | `bin/rails db:seed` |
| Reset and reseed | `bin/rails db:seed:replant` |
| Regenerate OpenAPI spec | `bundle exec rake rswag:specs:swaggerize` |

Make targets:

| Target | Runs |
|---|---|
| `make setup` | `bin/setup` |
| `make up` | `bin/dev` |
| `make test` | `bundle exec rspec` |
| `make lint` | `bundle exec rubocop` |
| `make reset-db` | `bin/rails db:drop db:create db:migrate` |
| `make docs` | `bundle exec rake rswag:specs:swaggerize` |

## API documentation

Docs are disabled by default. Start the server with `DOCS_ENABLED=true` to expose them:

- Swagger UI: `/api-docs`
- Raw OpenAPI spec: `/api-docs/v1/openapi.yaml`

Regenerate the spec with `make docs`.

## Health endpoints

- `GET /health/live`: liveness, no dependency checks (`GET /health` is an alias)
- `GET /health/ready`: readiness, runs `SELECT 1` and checks for pending migrations; `503` otherwise
- `GET /up`: Rails built-in health check

## Observability

Probes are described under Health endpoints. Metrics, logs and traces are configured by environment variables:

| Variable | Default | Purpose |
|---|---|---|
| `METRICS_ENABLED` | `false` | Expose Prometheus metrics at `/metrics` |
| `METRICS_TOKEN` | empty | Bearer token required by `/metrics` when set |
| `OTEL_ENABLED` | `false` | Enable OpenTelemetry tracing export (optional) |
| `OTEL_EXPORTER_OTLP_ENDPOINT` | `http://localhost:4318` | OTLP collector endpoint |
| `LOG_LEVEL` | `info` | Log level |
| `RATE_LIMIT_ENABLED` | `true` | Toggle Rack::Attack throttling |
| `RATE_LIMIT_REQUESTS` / `RATE_LIMIT_PERIOD` | `300` / `60` | General per-IP limit and window in seconds |
| `RATE_LIMIT_BOOKING_REQUESTS` / `RATE_LIMIT_BOOKING_PERIOD` | `20` / `60` | Limit for `POST /api/v1/appointments` |
| `DB_STATEMENT_TIMEOUT_MS` | `5000` | PostgreSQL statement timeout (`bin/docker-entrypoint` sets `0` for `db:prepare` so migrations are exempt) |
| `RACK_TIMEOUT_SERVICE_TIMEOUT` | `15` | Request timeout in seconds |
| `WORKER_SHUTDOWN_TIMEOUT` | `25` | Puma worker graceful shutdown in seconds |

Metrics: `booking_attempts_total`, `booking_success_total`, `booking_failure_total{reason}`, `booking_duration_seconds`, `availability_query_duration_seconds`.

Production logs are one JSON line per request with `request_id`, `trace_id`, `appointment_id`, `method`, `path`, `status` and `duration`.

Run the local stack (Prometheus on 9090, Grafana on 3001, Jaeger UI on 16686, OTLP on 4317 and 4318):

```sh
METRICS_ENABLED=true METRICS_TOKEN=secret bin/rails server
docker compose -f docker-compose.observability.yml up
```

Put the same token in `config/observability/prometheus.yml`. Import `config/observability/grafana-dashboard.json` in Grafana (success rate, conflict rate, p95 booking duration).

## Environment variables

Copy `.env.example` to `.env` and adjust.

| Variable | Default | Purpose |
|---|---|---|
| `DATABASE_URL` | commented out | Full connection URL; alternative to the `DB_*` variables |
| `DB_HOST` | empty | Database host |
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

In production, `DATABASE_URL` (or `DB_HOST`) and `CORS_ORIGINS` are required.

## Seeded data

Seeds in `db/seeds/` are idempotent and use stable, deterministic UUIDs generated by `SeedSupport.uuid(namespace, number)` in `db/seeds.rb`. Read the namespaces and numbers from the seed files:

| File | Contents |
|---|---|
| `01_qualifications.rb` | General Service, Lift Certified, Alignment Certified |
| `02_dealerships.rb` | Londinium Motors (`Europe/London`), Manhattan Auto Care (`America/New_York`) |
| `03_opening_hours_holidays.rb` | Mon-Fri 08:00-17:00; Christmas Day (London), Independence Day (Manhattan) |
| `04_service_bays.rb` | Londinium: G1, L1, L2, A1. Manhattan: G1, G2, L1, A1 |
| `05_service_types.rb` | Oil Change (30 min), Full Service (120 min, lift), Wheel Alignment (60 min, alignment) |
| `06_technicians.rb` | Three technicians at Londinium, three at Manhattan, with qualifications and shifts |
| `07_customers_vehicles.rb` | Three customers, each with one vehicle |

Single-lift-bay scenario: Manhattan Auto Care has exactly one lift bay (Bay L1) and one Lift Certified technician (Dan Dalton), so two overlapping Full Service bookings there exercise the double-booking conflict.

## Project structure

```
app/
  controllers/  HTTP layer (api/, health)
  domain/       pure Ruby scheduling logic, no Rails or ActiveRecord
  errors/       error catalogue
  forms/        form objects for input validation
  models/       ActiveRecord models
  queries/      read-side queries
  serializers/  JSON serializers
  services/     use cases returning dry-monads Success/Failure
config/         routes, initializers
db/             migrations, schema, seeds/
epics/          backlog and stack overview
spec/           RSpec (models, requests, integration, factories)
swagger/        generated OpenAPI specs
```

Conventions: times are UTC `timestamptz`, intervals are half-open `[start, end)`, and PostgreSQL exclusion constraints are the source of truth for double-booking.

## Docker

Written, not yet verified. `Dockerfile` and `docker-compose.yml` define a `web` service (host port 3000) and a PostgreSQL 16 `db` service. The web container runs `db:prepare db:seed` on start.

```sh
docker compose up --build
```

## AI Collaboration Narrative

To be added (Epic 7).

## System Design Document

To be added (Epic 7).
