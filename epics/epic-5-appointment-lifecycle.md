# Epic 5: Appointment Lifecycle

## Description

Support the full life of an appointment after confirmation: cancellation, rescheduling, and workshop status progression. This epic is **supporting / should-have**. It is not required by the three core requirements but makes the scheduler realistic and demonstrates aggregate design and state-machine thinking.

## Dependencies

- Epic 3 (availability and constraints)
- Epic 4 (Appointment model and services)

## Status State Machine

```
confirmed ──► in_progress ──► completed
    │
    ├──► cancelled
    └──► no_show
```

Only `confirmed` and `in_progress` appointments hold resources. Terminal states: `completed`, `cancelled`, `no_show`. The transition table lives in `Scheduling::StatusMachine` (pure Ruby); the `Appointment` model delegates to it.

## Acceptance Criteria

- Customers can cancel, and the freed slot is immediately bookable
- Customers can reschedule atomically without ever losing the original slot on failure
- Staff can move appointments through valid statuses; invalid transitions are rejected
- Domain events are published for lifecycle changes

---

### User Story 1: Cancel an Appointment

#### Description

- As a customer, I want to cancel an appointment so the slot is freed.

#### Requirements

- `POST /api/v1/appointments/:id/cancel` with an optional `reason`, handled by `Appointments::Cancel`
- Only `confirmed` appointments can be cancelled by a customer; otherwise `409` `INVALID_STATUS_TRANSITION`
- Set status to `cancelled`, record `cancelled_at` and the reason
- Because the exclusion constraints are partial on active statuses, the bay, technician, and vehicle are immediately bookable again
- Idempotent: cancelling an already-cancelled appointment returns the current state with `200`

#### Notes

- Optional policy (configurable, default off): block customer cancellation within X hours of start
- Wrap the status change and history row in a transaction

#### Acceptance Criteria

- After cancellation a booking for the same slot succeeds
- Cancelling a completed appointment is rejected
- A repeat cancel call is safe

---

### User Story 2: Reschedule an Appointment

#### Description

- As a customer, I want to reschedule to a new time.

#### Requirements

- `POST /api/v1/appointments/:id/reschedule` with `{ new_start_at }`, handled by `Appointments::Reschedule`
- Re-run the full pipeline (grid, opening hours, availability, assignment) for the new interval
- **Atomic swap in one transaction:** the old slot is released only if the new slot is confirmed; on failure the original appointment is untouched
- The appointment may overlap its **own** old interval (e.g. shifting by 15 minutes) without conflicting with itself; update the row in place so the exclusion constraint compares the new range against other rows only
- Keep the same appointment ID; record the previous interval in the status history
- Only `confirmed` appointments can be rescheduled
- Rely on `lock_version`; map `ActiveRecord::StaleObjectError` to `409` `CONCURRENT_MODIFICATION`

#### Notes

- Technician or bay may change if the original resources are not free at the new time
- Use `with_lock` or the optimistic lock to serialize competing changes to the same appointment

#### Acceptance Criteria

- Successful reschedule updates interval and resources
- Failed reschedule (no availability) leaves the original appointment intact (tested)
- Shifting by 15 minutes works despite overlapping its own old interval
- Concurrent reschedule and cancel on the same appointment resolve safely

---

### User Story 3: Workshop Status Transitions

#### Description

- As a service advisor, I want to move appointments through `in_progress`, `completed`, and `no_show`.

#### Requirements

- `PATCH /api/v1/appointments/:id/status` with `{ status }`, handled by `Appointments::ChangeStatus`
- Implement the rules in `Scheduling::StatusMachine`; the model exposes `start!`, `complete!`, `mark_no_show!`, `cancel!`
- Invalid transitions return `409` with code `INVALID_STATUS_TRANSITION` and the list of allowed transitions
- Record each change in `appointment_status_histories` (from, to, at, actor)

#### Notes

- `no_show` is only allowed after the appointment start time (uses the injected `Clock`)
- Authorisation for staff-only operations is deferred (assumption A8)

#### Acceptance Criteria

- Table-driven specs cover every valid and invalid transition
- Status history rows are written for each change
- The API returns allowed transitions on rejection

---

### User Story 4: Publish Lifecycle Domain Events

#### Description

- As a developer, I want domain events for lifecycle changes so notifications and integrations can be added later without changing booking logic.

#### Requirements

- Define events: `appointment.confirmed`, `appointment.rescheduled`, `appointment.cancelled`, `appointment.status_changed`
- Publish through `ActiveSupport::Notifications.instrument` **after commit**, with a payload including appointment ID, timestamps, and request ID (`Current.request_id`)
- Register a logging subscriber in `config/initializers/event_subscribers.rb`
- Document the outbox-pattern extension (event rows written in the same transaction and relayed by a Solid Queue job) as the production path

#### Notes

- Notifications (email/SMS) remain out of scope (assumption A11)

#### Acceptance Criteria

- Events carry the appointment ID, timestamps, and correlation ID
- No event is published when the transaction rolls back (tested)
- The subscriber logs each event in structured form

---
