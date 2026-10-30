# <Feature title>

<!-- Meta: the coordinator reads only this block on triage. -->
- branch: <branch>
- base: main
- route: feature | fix | tests | refactor | pr-feedback
- size: S | M | L
- status: planned | approved | building | checking | committed
- source: <request text or path, e.g. epics/epic-5-appointment-lifecycle.md#user-story-1-cancel-an-appointment>

## Requirements
<!-- Functional and non-functional, each with a measurable success criterion. Short bullets. -->
- R1 <requirement> - success: <criterion>
- R2 <requirement> - success: <criterion> [NEEDS CLARIFICATION → Q1]

## Current state
<!-- At most 3 lines: what exists today and the files involved, so implementers and reviewers don't re-explore. -->

## Risks
<!-- At most 3 lines: risk → mitigation. N/A if none. -->

## Approach
<!-- The simplest approach that satisfies the requirements, and in one line why it beats the alternatives. -->

## Decisions
<!-- Answered questions move here: "- <question> → <answer>". Unasked low-impact assumptions: "- <topic> → <answer> (assumed)". -->

## Open questions
<!-- At most 4, ranked by impact × uncertainty (see .claude/docs/guides/planning.md). The recommended option comes first, and every option has a means: line. -->
- Q1 <question>?
  - recommended: <answer>
    means: <effect on the feature>
  - alternative: <answer>
    means: <effect on the feature>
  - why: <one line>

## Contracts
<!-- Authoritative for every implementer and tester: exact names, fields, types, validation and file paths. -->
### Models / domain
- `Appointment` (app/models/appointment.rb): `cancel!(reason:, at:)`; adds `cancelled_at: timestamptz`, `cancellation_reason: string (≤500)`
- `Scheduling::StatusMachine.allowed?(from:, to:) -> Boolean` (app/domain/scheduling/status_machine.rb)
### Services / queries
- `Appointments::Cancel.new(clock: Clock).call(appointment_id:, reason: nil) -> Success(Appointment) | Failure(:invalid_status_transition, allowed:)` (app/services/appointments/cancel.rb)
### Endpoints / params
- `POST /api/v1/appointments/:id/cancel` params `{ reason?: string }` → 200 envelope with `AppointmentSerializer` (app/controllers/api/v1/appointments_controller.rb)
### Reused
- `<existing util>`: <what it does> (<path>)

## Tasks
<!-- A task goes in a later wave only if it depends on an earlier one. Tasks in the same wave never share an owned file. Related tasks in the same wave share a bundle (Bn), which is one implementer run. -->
### Wave 0 (TDD tests, only with --tdd)
- [ ] T0 Specs for AC1-EC2 - bundle: B0 - owns: spec/services/appointments/cancel_spec.rb, spec/requests/api/v1/appointments_cancel_spec.rb
### Wave 1
- [ ] T1 Migration for `cancelled_at` and `cancellation_reason` - bundle: B1 - owns: db/migrate/<ts>_add_cancellation_to_appointments.rb, db/structure.sql
- [ ] T2 `Scheduling::StatusMachine` cancel transitions - bundle: B2 - owns: app/domain/scheduling/status_machine.rb
### Wave 2
- [ ] T3 `Appointment#cancel!` and `Appointments::Cancel` - bundle: B3 - owns: app/models/appointment.rb, app/services/appointments/cancel.rb
- [ ] T4 `POST /api/v1/appointments/:id/cancel` route and action - bundle: B3 - owns: config/routes.rb, app/controllers/api/v1/appointments_controller.rb

## Acceptance criteria
<!-- Given/When/Then with scenario-specific test data. Every R has at least one AC, and every AC/EC cites its R id.
     EC categories to check: boundaries · errors/failures · empty/null · concurrency · authorization/ownership · integration failures. -->
- [ ] AC1 (R1) Cancel a confirmed appointment frees the slot
  - Given confirmed appointment "appt-ac1" for vehicle "veh-ac1" in bay "bay-ac1"
  - When POST /api/v1/appointments/{appt-ac1}/cancel { reason: "ac1" }
  - Then 200, status = cancelled, and a new booking for the same bay and interval returns 201
- [ ] EC1 (R1) Unknown appointment
  - Given no appointment with id "00000000-0000-0000-0000-000000000000"
  - When POST /api/v1/appointments/{that id}/cancel
  - Then 404 with code APPOINTMENT_NOT_FOUND
- [ ] EC2 (R1) Completed appointment cannot be cancelled
  - Given completed appointment "appt-ec2"
  - When POST /api/v1/appointments/{appt-ec2}/cancel
  - Then 409 with code INVALID_STATUS_TRANSITION and the status is unchanged

## Test plan
<!-- Written by the tester in diff/tdd modes, one block per source file. -->
### app/services/appointments/cancel.rb
- [ ] [NEW] call - Given a confirmed appointment, When call, Then Success with status cancelled
- [ ] [DELETED] legacy_cancel - remove its examples and the unused double

## Findings
<!-- Written by the reviewer:
     "- [ ] F<n> [<AC or rule>] (<missing-logic|wrong-condition|data-flow|contract|authz|convention>) <file>:<line> - expected <…>, actual <…>. Fix: <change>. owns: <files>"
     An implementer that can't close a finding appends " ⚠️ <reason>". -->

## PR feedback
<!-- Written by the analyst in pr mode (see .claude/docs/guides/pr-triage.md):
     "- [ ] R<n> <path>:<line> [code|reply-only] (thread:<id>) - <summary of the whole thread>. Fix: <ordered steps>. owns: <files>" -->

## Log
<!-- Appended by the coordinator: "- <YYYY-MM-DD> <event>" -->
