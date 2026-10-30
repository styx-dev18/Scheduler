# Epic 4: Confirmed Appointment Record

## Description

On a successful availability check, create a **persistent Appointment record** associating the customer, vehicle, technician, and service bay (**Scenario A, Requirement 3**). This epic also provides the read endpoints needed to retrieve and list appointments, and proves the data survives restarts.

## Dependencies

- Epic 1 (schema)
- Epic 2 (`Appointments::Book`)
- Epic 3 (availability, assignment, exclusion constraints)

## Acceptance Criteria

- An Appointment is persisted with all required associations and status `confirmed`
- Availability check and insert occur in one atomic transaction
- The booking response contains all details a customer needs
- Appointments can be retrieved by ID and listed with filters and pagination
- A dealership view supports daily workshop planning
- Data persists across application and database restarts

---

### User Story 1: Appointment Model and Persistence

#### Description

- As the system, I want to persist an Appointment linking customer, vehicle, technician, bay, service type, dealership, and time range.

#### Requirements

- `Appointment` (Active Record) with associations to `customer`, `vehicle`, `technician`, `service_bay`, `service_type`, `dealership`
- `enum :status, { confirmed:, in_progress:, completed:, cancelled:, no_show: }` and scopes `active` (`confirmed`, `in_progress`), `for_vehicle`, `for_technician`, `overlapping`
- Presence and consistency validations (end after start; resources belong to the same dealership)
- Factory method `Appointment.build_confirmed(...)` enforcing invariants and setting status `confirmed`
- Use Active Record's built-in **optimistic locking** (`lock_version`) to support safe concurrent updates in Epic 5
- Treat the virtual `time_range` column as read-only
- Store timestamps in UTC (`timestamptz`)

#### Notes

- Business rules stay in services and the domain layer; callbacks only for simple integrity
- Keep the model free of presentation logic (serializers handle formatting)

#### Acceptance Criteria

- All foreign keys are stored and enforced
- Status is `confirmed` on creation and timestamps are populated
- Model specs (shoulda-matchers plus custom examples) cover associations, validations, and scopes

---

### User Story 2: Atomic Booking Transaction

#### Description

- As the system, I want availability check and insert to happen in one atomic transaction.

#### Requirements

- `Appointments::Book` runs, inside `ApplicationRecord.transaction`: find candidates, assign, insert the appointment, store the idempotency record
- Any failure (including a constraint violation) rolls back everything, leaving no partial records
- On exclusion-constraint conflict, retry with the next candidate inside a savepoint (bounded), then return `409`
- Publish `appointment.confirmed` through `ActiveSupport::Notifications.instrument` only **after** the transaction commits

#### Notes

- Keep transactions short: perform validation and read-only lookups before opening the transaction where possible
- Never call external services inside the transaction
- Do not rely on model `after_commit` callbacks for events; the service owns when events fire

#### Acceptance Criteria

- Forced failure at each step (assignment, insert, idempotency write) leaves the database unchanged
- No event is published on rollback
- Integration specs against real PostgreSQL verify atomicity

---

### User Story 3: Booking Confirmation Response

#### Description

- As a customer, I want a confirmation response with all booking details.

#### Requirements

- `POST /api/v1/appointments` returns `201` with: appointment ID, status, customer, vehicle, service type (name and duration), dealership, assigned technician (id, display name), assigned service bay (id, label), and `start_at` / `end_at` in UTC **and** dealership local time with the time zone
- Add a `Location` header pointing to `GET /api/v1/appointments/{id}`
- Implement `AppointmentSerializer` with Alba; document the schema with a full example in the rswag spec

#### Notes

- Do not expose sensitive technician data (only id and display name)
- Use `includes` when loading associated records for the response

#### Acceptance Criteria

- Response contains every listed field
- Local and UTC times are consistent for dealerships in different time zones
- `Location` header resolves to the created appointment

---

### User Story 4: Retrieve an Appointment by ID

#### Description

- As a customer, I want to retrieve my appointment by ID.

#### Requirements

- `GET /api/v1/appointments/:id` returns the full record in the same shape as the confirmation response
- Return `404` with code `APPOINTMENT_NOT_FOUND` if unknown (`ActiveRecord::RecordNotFound` mapped in `BaseController`)
- Return `400` for a malformed UUID

#### Notes

- When authentication is added, scope the lookup to the current customer

#### Acceptance Criteria

- Existing appointment returns `200` with full details
- Unknown ID returns `404`; invalid ID format returns `400`

---

### User Story 5: List a Customer's Appointments

#### Description

- As a customer, I want to list my appointments (filter by status/date).

#### Requirements

- `GET /api/v1/appointments?customer_id=&status=&from=&to=&page=&per_page=`
- Default sort by `start_at` ascending; allow `sort=desc`
- Paginate with Pagy; return metadata and cap `per_page` (e.g. 100)
- `customer_id` is required for this query

#### Notes

- Uses the `(customer_id, start_at)` index from Epic 1
- Query logic lives in a query object (`Appointments::ListQuery`) rather than the controller

#### Acceptance Criteria

- Filters work individually and combined
- Pagination metadata is returned
- Results never include other customers' appointments

---

### User Story 6: Dealership Daily Schedule

#### Description

- As a service advisor, I want to list a dealership's appointments per day or per technician so I can run the workshop.

#### Requirements

- `GET /api/v1/dealerships/:id/appointments?date=&technician_id=&service_bay_id=&status=`
- Interpret `date` in the dealership time zone
- Return appointments sorted by start time with technician and bay details (`includes` to avoid N+1)
- Paginate with Pagy

#### Notes

- Consider a read-model if this query becomes hot (see scaling notes in Epic 6)

#### Acceptance Criteria

- Day, technician, and bay filters each return correct results
- An appointment near local midnight appears on the correct local day
- Query uses the `(dealership_id, start_at)` index

---

### User Story 7: Verify Persistence Across Restarts

#### Description

- As a data owner, I want the record to survive restarts.

#### Requirements

- Data stored in PostgreSQL on a named Docker volume (Docker Compose)
- Smoke test script (`scripts/persistence_check.sh`): create an appointment, restart the `web` container and, separately, the `db` container, then confirm the appointment is still retrievable
- Document the backup/restore approach (`pg_dump` / managed backups) in the System Design Document

#### Notes

- A scripted smoke test is enough if container restarts are impractical in CI

#### Acceptance Criteria

- Appointment is retrievable after an application restart and after a database container restart
- `docker compose down` (without `-v`) followed by `up` preserves data

---
