# Epic 2: Resource-Constrained Booking

## Description

Allow a user to request a service appointment for a specific vehicle, service type, and dealership at a desired time (**Scenario A, Requirement 1**). This epic covers request intake, validation, and the business pre-conditions that must pass **before** resource availability is checked: ownership, opening hours, same-vehicle overlap, and safe retries.

The availability check is delivered in Epic 3 and the persistent record in Epic 4. This epic defines the `Appointments::Book` service object and the collaborators it depends on.

## Dependencies

- Epic 1 (Rails foundation, schema, seed data, error handling)

## Acceptance Criteria

- Dealerships and service types can be browsed through the API
- `POST /api/v1/appointments` accepts a booking request and returns `201` or a meaningful error
- Invalid input is rejected with field-level feedback
- Vehicle ownership, opening hours, holidays, and same-vehicle overlap are enforced
- Retrying a request with the same idempotency key never creates a duplicate

---

### User Story 1: Browse Dealerships and Service Types

#### Description

- As a customer, I want to browse dealerships and service types so I know what I can book.

#### Requirements

- `GET /api/v1/dealerships` returns id, name, time zone, and opening hours
- `GET /api/v1/service-types` returns id, name, description, and `duration_minutes`
- Optional filter: `GET /api/v1/service-types?dealership_id=`
- Paginate both list endpoints with Pagy
- Cache these near-static reads with `Rails.cache.fetch` (Solid Cache) and a short TTL
- Serialize with Alba (`DealershipSerializer`, `ServiceTypeSerializer`)

#### Notes

- Responses use the standard envelope from Epic 1
- Do not expose internal requirements (bay type, qualification) unless useful to the client
- Use `includes(:opening_hours)` to avoid N+1 queries (Bullet enforces this in test)

#### Acceptance Criteria

- Both endpoints return seeded data in the envelope format
- Pagination metadata is included
- Endpoints are documented through rswag specs with examples

---

### User Story 2: Submit a Booking Request

#### Description

- As a customer, I want to submit a booking request (customer, vehicle, service type, dealership, desired start time) so I can schedule a service.

#### Requirements

- `POST /api/v1/appointments` accepts `{ customer_id, vehicle_id, service_type_id, dealership_id, start_at }`, where `start_at` is ISO-8601 with offset or UTC
- Implement `Appointments::Book` in `app/services/`; `call` returns a `Dry::Monads::Result` (`Success(appointment)` or `Failure(code, details)`)
- Shape and validate input with a `BookingRequest` form object (`ActiveModel::Model`) and Strong Parameters
- The service orchestrates in order: validation, ownership, opening hours, vehicle overlap, availability and assignment (Epic 3), persist (Epic 4)
- Inject collaborators as keyword arguments with defaults (`clock: Clock`, `availability: Availability::Finder`, `strategy: Scheduling::AssignmentStrategies::LeastLoaded`) so specs can substitute fakes
- Return `201` with the appointment (full response shape defined in Epic 4)

#### Notes

- The controller contains no business logic: params in, service call, serializer out
- Inject a `Clock` so "past time" checks are testable (specs may also use `travel_to`)

#### Acceptance Criteria

- Endpoint accepts the payload and returns `201` or a mapped error
- The service is unit-tested with doubles for every failure branch
- Business failures are returned as `Failure` results, not raised exceptions

---

### User Story 3: Validate Booking Requests

#### Description

- As a customer, I want my request validated so I get immediate feedback on bad input.

#### Requirements

- Reject missing or malformed fields (non-UUID ids, invalid date format) with `400` and field-level errors from the form object
- Reject unknown customer, vehicle, service type, or dealership IDs with `404` and a clear message
- Reject start times in the past with `422` (`START_TIME_IN_PAST`)
- Reject start times not on the 15-minute grid with `422` (`START_TIME_NOT_ON_SLOT_GRID`)
- Implement `Scheduling::SlotTime` as an immutable value object that enforces the grid

#### Notes

- Structural validation in the form object; business rules in the domain and service layers
- Slot size defaults to 15 minutes (assumption A7) and is configurable via `SLOT_MINUTES`
- Parse timestamps with `Time.iso8601` (strict) rather than lenient `Time.zone.parse`

#### Acceptance Criteria

- Each rejection path has a request spec asserting status, error `code`, and message
- Field-level errors identify the offending parameter
- Valid, grid-aligned, future times pass validation

---

### User Story 4: Verify Vehicle Ownership

#### Description

- As a customer, I want the system to verify the vehicle belongs to me so no one books on my behalf by mistake.

#### Requirements

- Load the vehicle and compare its `customer_id` to the requested `customer_id`
- On mismatch return `422` with code `VEHICLE_OWNERSHIP_MISMATCH` (or `403` once authentication exists)
- Do not reveal who the real owner is

#### Notes

- Assumption A9: a vehicle has exactly one owner
- When authentication is added, `customer_id` should come from `current_customer`, not the request body

#### Acceptance Criteria

- Matching owner proceeds to the next check
- Mismatched owner is rejected with the documented code and no data leakage
- Service and request specs cover both outcomes

---

### User Story 5: Enforce Dealership Opening Hours and Holidays

#### Description

- As a customer, I want the system to reject requests outside dealership opening hours so I don't book impossible times.

#### Requirements

- Convert the requested interval `[start, start + duration)` to the dealership's IANA time zone with `ActiveSupport::TimeZone` / `Time.use_zone`
- The **entire** interval must fall within that day's opening hours (a service ending after closing is rejected)
- Reject dates in `dealership_holidays` and closed weekdays
- Return `422` with code `OUTSIDE_OPENING_HOURS` or `DEALERSHIP_CLOSED`
- Handle DST transitions correctly
- Implement the rules in `Scheduling::OpeningHoursPolicy` (pure Ruby, fed with plain data)

#### Notes

- Never do manual UTC-offset arithmetic; rely on TZInfo through ActiveSupport
- An interval ending exactly at closing time is allowed (half-open intervals)

#### Acceptance Criteria

- Specs cover: exactly at opening, ending exactly at closing, ending one minute after closing, holiday, closed weekday, and a DST-change day
- Two dealerships in different time zones behave correctly for the same UTC instant

---

### User Story 6: Prevent Overlapping Bookings for the Same Vehicle

#### Description

- As a customer, I want to be prevented from booking two overlapping services for the same vehicle.

#### Requirements

- Before assignment, check for any active (`confirmed` / `in_progress`) appointment on the vehicle that overlaps the interval (`Appointment.active.for_vehicle(id).overlapping(interval)`)
- Return `409` with code `VEHICLE_ALREADY_BOOKED` and the conflicting `appointment_id`
- Back this with a database exclusion constraint on `(vehicle_id, time_range)` (added in Epic 3, User Story 8)

#### Notes

- Back-to-back appointments for the same vehicle are allowed (half-open intervals)
- Cancelled appointments must not block

#### Acceptance Criteria

- Overlap returns `409` including the conflicting appointment ID
- Back-to-back and cancelled-appointment cases are allowed
- Covered by service specs and request specs against real PostgreSQL

---

### User Story 7: Idempotent Booking Requests

#### Description

- As a customer, I want to retry a booking safely after a network failure without creating a duplicate.

#### Requirements

- Accept an optional `Idempotency-Key` header on `POST /api/v1/appointments`
- Store the key, a SHA-256 hash of the request payload, and the response (status and body) in `idempotency_keys` with a unique index on the key
- Replay with the same key and payload returns the **original** response
- Same key with a different payload returns `422` with code `IDEMPOTENCY_KEY_REUSED`
- Concurrent requests with the same key: insert the key row first and rescue `ActiveRecord::RecordNotUnique`; the loser waits briefly or receives `409`, and never creates a second appointment
- Keys expire after a configurable TTL (e.g. 24 h), cleaned up by a recurring Solid Queue job

#### Notes

- Write the key row in the same transaction as the appointment so they commit or roll back together
- Failed business outcomes (e.g. `409`) may also be stored and replayed; document the chosen behaviour
- Schedule cleanup in `config/recurring.yml`

#### Acceptance Criteria

- Replay returns an identical response and creates exactly one appointment
- Payload mismatch is rejected
- Parallel duplicate requests result in exactly one appointment (tested with threads)
- Expired keys are removed by the recurring job

---
