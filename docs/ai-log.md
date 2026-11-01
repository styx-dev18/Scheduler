# AI Usage Log

A running log of defects and judgement calls found while working with Claude Code on this repository. Every entry cites evidence that exists in the repository: commits, files and specs. Entries are chronological. Reviewer findings from the local plans (`.claude/plans/`, which is gitignored) are summarised inline so this log stands alone.

## 2026-10-30 Appointment exclusion constraints were missing from the schema

- **Detection**: Found while hardening booking against concurrent requests. Before commit `414a468` the schema had no PostgreSQL exclusion constraints on `appointments`, so double-booking was guarded only by application checks, and two parallel requests could both pass them.
- **Fix**: Fixed by hand on the branch. Migration `db/migrate/20260301000001_add_appointment_exclusion_constraints.rb` adds three GiST constraints (`appointments_no_bay_overlap`, `appointments_no_technician_overlap`, `appointments_no_vehicle_overlap`) over active appointments. `app/services/appointments/book.rb` was changed in the same commit, and `app/services/appointments/placement.rb:88` now rescues `ActiveRecord::ExclusionViolation`.
- **Evidence**: branch commit `414a468` and its squash-merge `0f0af0b` (#10); `db/migrate/20260301000001_add_appointment_exclusion_constraints.rb`; `db/structure.sql`; `spec/models/appointment_exclusion_spec.rb`; `spec/concurrency/book_overlap_spec.rb`.

## 2026-10-30 Epic 1 F1: time zone validation accepted too few IANA zones

- **Detection**: Review round on the foundation epic. The finding: any valid IANA zone (including `UTC` and `America/Detroit`) should be accepted, but `Dealership` validated against `ActiveSupport::TimeZone::MAPPING.values` (about 150 zones).
- **Fix**: `app/models/dealership.rb` defines `TIME_ZONES = TZInfo::Timezone.all_identifiers.freeze` and validates inclusion in it. The spec was updated alongside.
- **Evidence**: `app/models/dealership.rb:2,13`; `spec/models/dealership_spec.rb`; foundation squash commit `f6ba77a`.

## 2026-10-30 Epic 1 F2: OpenAPI `errors` shape contradicted the runtime body

- **Detection**: Review compared `swagger/v1/openapi.yaml` with `app/controllers/api/v1/base_controller.rb`. The schema declared `Error.errors` as an array of objects, while the controller emits a hash of field to messages.
- **Fix**: `spec/swagger_helper.rb` now declares `errors` as an object with `additionalProperties` that are arrays of strings, and the OpenAPI file was regenerated from it.
- **Evidence**: `spec/swagger_helper.rb`; `swagger/v1/openapi.yaml`; foundation squash commit `f6ba77a`.

## 2026-10-30 Epic 1 F3: `docker compose up` failed on a fresh clone

- **Detection**: Review of `docker-compose.yml`. `env_file: .env` fails when `.env` is absent, because a fresh clone has only `.env.example`. A production boot also needs `SECRET_KEY_BASE` and `CORS_ORIGINS`, and neither was set.
- **Fix**: The `env_file` was dropped and `CORS_ORIGINS`, `SECRET_KEY_BASE` (a development-only value) and `RAILS_LOG_TO_STDOUT` were set under `environment:`.
- **Evidence**: `docker-compose.yml`; foundation squash commit `f6ba77a`.

## 2026-10-30 Epic 2: domain specs raised NameError in a full run

- **Detection**: Recorded in the Epic 2 plan's current-state notes. `spec/spec_helper.rb` set up the `app/domain` loader only for domain-only runs, so a full run raised `NameError` on `Scheduling::*`.
- **Fix**: The loader was reworked in the Epic 2 work and is now in `spec/spec_helper.rb`: domain-only runs build a Zeitwerk loader for `app/domain` without Rails, and every other run loads `rails_helper`. In Epic 7 the detection was tightened so `./spec/domain/...` path forms are also treated as domain-only.
- **Evidence**: `spec/spec_helper.rb`; Epic 2 squash commit `0f0af0b` (#10) touches this file.

## 2026-10-30 Epic 4 F1: duplicated pagination rules in two form objects

- **Detection**: Convention review (DRY). `app/forms/dealership_schedule_request.rb` copied the `per_page` format validation, the positive check and the `limit` from `AppointmentListRequest`, and borrowed `MAX_PER_PAGE` across forms.
- **Fix**: The shared rules were extracted into a concern under `app/forms/concerns/` and included in both forms.
- **Evidence**: `app/forms/concerns/`; `app/forms/appointment_list_request.rb`; `app/forms/dealership_schedule_request.rb`; commit `bae32d9` (#12).

## 2026-10-30 Epic 4 F3: atomicity spec stubbed Active Record

- **Detection**: Convention review against the testing rules on mocking. `spec/services/appointments/book_atomicity_spec.rb` used `allow_any_instance_of(Appointment).to receive(:save!)` and the same on `IdempotencyKey#update!`, which stubs persistence instead of exercising it.
- **Fix**: The failure is injected through a real collaborator, so the rollback runs against the real database without stubbing Active Record.
- **Evidence**: `spec/services/appointments/book_atomicity_spec.rb`; commit `bae32d9` (#12).

## 2026-10-30 Epic 4 F2: removal of `build_confirmed` declined

- **Detection**: Convention review (YAGNI) flagged `Appointment.build_confirmed` as a one-line wrapper around `new(status: "confirmed")` and proposed removing it.
- **Fix**: Declined, not changed. The method is part of the epic's contract and is covered by specs, so the suggestion was rejected as incorrect for this codebase. This entry records that AI review output was weighed against the requirements and not applied blindly.
- **Evidence**: `app/models/appointment.rb:35`; `spec/models/appointment_spec.rb:42`; used at `app/services/appointments/book.rb:55`.

## 2026-10-30 Epic 5 F1: non-string cancel reason returned 500

- **Detection**: Missing-logic finding in review. A JSON body such as `{"reason": 123}` passes `params.permit(:reason)`, then `123.length` raises `NoMethodError` and the base controller's `StandardError` handler answers 500 `INTERNAL_ERROR`.
- **Fix**: `Appointments::Cancel#call` now returns a `VALIDATION_ERROR` on `reason` ("must be a string") before the length check, so the client gets 400 instead of 500.
- **Evidence**: `app/services/appointments/cancel.rb`; `spec/requests/api/v1/appointment_cancel_spec.rb`; commit `ad5fa39` (#13).

## 2026-10-30 Stale project knowledge doc

- **Detection**: `.claude/docs/knowledge.md` began as a seed written from the epics before any code existed, and described planned layers as fact.
- **Fix**: It was regenerated from the code at `f6ba77a`, with items not yet built marked as planned.
- **Evidence**: commit `c630f05` ("docs: refresh .claude/docs from foundation code"); `.claude/docs/knowledge.md`.

## 2026-11-01 Epic 7 W1: coverage thresholds silently unenforced

- **Detection**: The first W1 implementation put `minimum_coverage_by_group` in `.simplecov`. SimpleCov 0.22.0 does not provide that method, so `.simplecov` failed to load, and the quality gate still reported a pass with the thresholds not enforced. The coordinator caught it by reading the full RSpec log at `.claude/plans/.verify/test.log` instead of trusting the green summary.
- **Fix**: `.simplecov` now enforces the thresholds in a `SimpleCov.at_exit` hook. It checks the "Domain" and "Services" groups against 90% line and 85% branch, prints each miss to stderr and exits with `SimpleCov::ExitCodes::MINIMUM_COVERAGE` (2). Enforcement runs only when `COVERAGE=true`, or when `CI=true` and `COVERAGE` is unset. It was proven by forcing a miss and observing exit code 2.
- **Evidence**: `.simplecov`; `spec/spec_helper.rb:1`; local log `.claude/plans/.verify/test.log` (gitignored). Lesson: a green gate summary is not proof that a check ran, so a gate needs a negative probe that makes it fail.

## 2026-11-01 Epic 6: Puma metrics plugin broke server boot while the gate was green

- **Detection**: The Epic 6 commit `16eb96a` (#14) added `plugin :yabeda` to `config/puma.rb`. With yabeda-puma-plugin 0.9.0, Puma raises "Puma control app is not activated" at boot, so `bin/rails s` and `bin/dev` could not start. The full gate (zeitwerk, RuboCop, Brakeman, RSpec) passed because nothing in it boots Puma. The Postman-harness implementer found it in Epic 7 W2 when trying to start a server, and the coordinator reproduced it with `bin/rails s -p 3917`.
- **Fix**: In `config/puma.rb`, the Yabeda plugin and `activate_control_app` on a unix socket under `tmp/sockets` are now loaded only when `METRICS_ENABLED=true`. Fixed in the Epic 7 commit "Chore: CI pipeline and repository hygiene", which also adds the CI boot smoke step. It was verified by booting with metrics off and on, and seeing `puma_*` series on `/metrics`.
- **Evidence**: commit `16eb96a` (#14); `config/puma.rb`; the "Boot smoke" step in `.github/workflows/ci.yml`. Lesson: a gate that never starts the server cannot catch boot failures, so the CI `test` job now boots the server with metrics off and on.
