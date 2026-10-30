# Epic 6: Observability, Reliability and Scalability

## Description

Satisfy the brief's **"Build for the Future"** requirement: the service must consider scalability, performance, reliability, maintainability, and observability. This epic adds structured logging, metrics, tracing, health probes, a documented error catalogue, rate limiting, and a written scaling strategy for the Rails application. It is **supporting** work that feeds the System Design Document.

## Dependencies

- Epic 1 (foundation, logging setup, error envelope)
- Epics 2-4 (instrumented flows)

## Acceptance Criteria

- Every request produces structured JSON logs carrying a correlation ID
- Booking metrics (attempts, successes, conflicts, latency) are exposed for Prometheus
- Traces span request → service → database for the booking flow
- Liveness and readiness endpoints exist and reflect real dependency state
- Errors follow one documented catalogue
- A scaling and reliability strategy is documented

---

### User Story 1: Structured Logging with Correlation IDs

#### Description

- As an SRE, I want structured JSON logs with a correlation ID per request.

#### Requirements

- Configure **Lograge** with the JSON formatter and `config.log_tags = [:request_id]`; log to STDOUT in production
- Rails' `ActionDispatch::RequestId` honours an incoming `X-Request-Id` (or generates one) and returns it in the response header
- Add `custom_options` so each line includes `request_id`, `method`, `path`, `status`, `duration`, `appointment_id` (when relevant), and `trace_id`
- Store the request ID in `ActiveSupport::CurrentAttributes` (`Current.request_id`) and propagate it into Active Job payloads and domain events
- Redact sensitive fields with `config.filter_parameters`
- Log business outcomes at the right level (`info` for confirmed, `warn` for conflicts, `error` for unexpected failures)

#### Notes

- Never log full request bodies in production
- Pair with an error tracker (Sentry, Honeybadger, or Rollbar) later

#### Acceptance Criteria

- Any request can be traced end to end in the logs by its request ID
- Redaction is verified by a spec
- Log level is configurable via `LOG_LEVEL`

---

### User Story 2: Metrics for Booking Behaviour

#### Description

- As an SRE, I want metrics for booking attempts, successes, conflicts, and latency.

#### Requirements

- Expose `GET /metrics` in Prometheus format using **Yabeda** (`yabeda-rails`, `yabeda-puma-plugin`, `yabeda-prometheus`), mounted behind a configuration flag or network restriction
- Default runtime metrics (Puma, Active Record pool, request durations by controller/action/status)
- Business metrics defined in `config/initializers/yabeda.rb`:
  - `booking_attempts_total`
  - `booking_success_total`
  - `booking_failure_total{reason}` (`NO_BAY`, `NO_TECHNICIAN`, `NO_CAPACITY`, `VALIDATION`, `VEHICLE_OVERLAP`, `CONSTRAINT_CONFLICT`)
  - `booking_duration_seconds` histogram
  - `availability_query_duration_seconds` histogram
- Include an example Prometheus scrape config and a Grafana dashboard sketch in the design doc

#### Notes

- Keep label cardinality low (no IDs as labels)
- Optionally add Prometheus and Grafana in `docker-compose.observability.yml`
- Increment metrics in the service layer, not in controllers

#### Acceptance Criteria

- `/metrics` returns valid Prometheus output
- Counters increment correctly after success and conflict scenarios (specs)
- The dashboard sketch shows success rate, conflict rate, and p95 latency

---

### User Story 3: Distributed Tracing

#### Description

- As an SRE, I want distributed tracing across request → service → database.

#### Requirements

- Integrate the OpenTelemetry Ruby SDK with Rails, Rack, PG, and Active Record instrumentation
- Add manual spans (`tracer.in_span`) around `Availability::FreeBays`, `Availability::FreeTechnicians`, assignment, and the booking transaction
- Attach attributes (`dealership.id`, `service_type.id`, `outcome`) to spans
- Export via OTLP with a configurable endpoint; disabled by default via an environment flag
- Include `trace_id` / `span_id` in log lines

#### Notes

- Optionally add Jaeger to the observability compose file for demos

#### Acceptance Criteria

- A booking request shows a single trace with nested spans for each stage
- Logs and traces can be correlated by trace ID
- Tracing can be turned off without code changes

---

### User Story 4: Health and Readiness Endpoints

#### Description

- As an operator, I want health and readiness endpoints.

#### Requirements

- `GET /health/live`: process is up (no dependency checks); keep `GET /health` as an alias and Rails' `GET /up`
- `GET /health/ready`: executes `SELECT 1` and verifies no pending migrations (`needs_migration?`), returning `503` otherwise
- Graceful shutdown: Puma handles `SIGTERM` by draining in-flight requests; configure `worker_shutdown_timeout` and ensure Thruster forwards signals in the container
- Point the Docker `HEALTHCHECK` and orchestrator probes at the right endpoints

#### Notes

- Readiness should fail fast when the database is unreachable so traffic stops being routed to the instance

#### Acceptance Criteria

- Stopping the database makes `/health/ready` fail while `/health/live` still passes
- `SIGTERM` during an in-flight booking lets it complete
- Probes are documented in the README

---

### User Story 5: Rate Limiting and Resilience

#### Description

- As an operator, I want protection against abusive or runaway clients and slow dependencies.

#### Requirements

- Configure **rack-attack** with a general throttle and a stricter throttle on `POST /api/v1/appointments`
- Return `429` with `Retry-After` and error code `RATE_LIMITED`, using the standard envelope
- Set a PostgreSQL `statement_timeout` in `database.yml` and a request timeout with `rack-timeout`; map `ActiveRecord::QueryCanceled` and timeouts to `503`/`504` with a clear code
- Bounded retries (with jitter) only for exclusion/serialization conflicts, never for validation failures

#### Notes

- rack-attack uses `Rails.cache` (Solid Cache), which is shared across processes; move to Redis only if throughput demands it
- Safelist health and metrics endpoints

#### Acceptance Criteria

- Exceeding limits returns `429` with `Retry-After`
- Timeout paths are specced and leave no open transactions

---

### User Story 6: Error Catalogue

#### Description

- As a consumer, I want consistent, documented error responses.

#### Requirements

- Maintain one error catalogue as `docs/error-catalogue.md` and an `ErrorCatalogue` Ruby module mapping each code to HTTP status, title, and example
- Initial codes: `VALIDATION_ERROR`, `NOT_FOUND`, `APPOINTMENT_NOT_FOUND`, `START_TIME_IN_PAST`, `START_TIME_NOT_ON_SLOT_GRID`, `VEHICLE_OWNERSHIP_MISMATCH`, `OUTSIDE_OPENING_HOURS`, `DEALERSHIP_CLOSED`, `VEHICLE_ALREADY_BOOKED`, `NO_BAY`, `NO_TECHNICIAN`, `NO_CAPACITY`, `IDEMPOTENCY_KEY_REUSED`, `INVALID_STATUS_TRANSITION`, `CONCURRENT_MODIFICATION`, `RATE_LIMITED`, `INTERNAL_ERROR`
- Ensure every code appears in the OpenAPI error responses generated by rswag

#### Notes

- `Api::V1::BaseController#render_failure` raises in test if given a code missing from the catalogue

#### Acceptance Criteria

- All endpoints return only catalogued codes inside the standard envelope
- A spec verifies the catalogue, the Ruby module, and the OpenAPI document are consistent

---

### User Story 7: Document Scaling and Reliability Strategy

#### Description

- As an architect, I want a documented scaling strategy for the System Design Document.

#### Requirements

- Cover: stateless Rails instances behind a load balancer; Puma tuning (`WEB_CONCURRENCY`, `RAILS_MAX_THREADS`) with the Active Record pool sized to threads; PgBouncer for connection pooling; read replicas using Rails multiple databases (`connects_to` with reading/writing roles and automatic role switching) for availability and list queries, including the replica-lag trade-off; partitioning appointments by dealership or month; caching static data with Solid Cache; rate limiting; idempotency and retries; Solid Queue worker scaling; backup/restore and RPO/RTO targets
- Explain why correctness stays on the primary (the booking transaction) and why the exclusion constraint makes horizontal scaling of the Rails app safe
- Describe the future path: outbox pattern, message broker for notifications, read models for dashboards, Kamal for deployment
- List known limitations and trade-offs

#### Notes

- Include a Mermaid architecture diagram of the scale-out topology

#### Acceptance Criteria

- The strategy section is included in the System Design Document
- Each of scalability, performance, reliability, maintainability, and observability is addressed explicitly

---
