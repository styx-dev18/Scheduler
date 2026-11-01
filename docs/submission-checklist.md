# Submission Checklist

Status values: Done means the evidence exists in the repository and can be re-run with the command shown. Pending means a user action outside the repository.

## Deliverables

| Brief item | Status | Evidence (file / spec / command) |
|---|---|---|
| System Design Document | Done | `docs/system-design.md` (table of contents at the top); `docs/erd.md`; `docs/error-catalogue.md` |
| Working code repository | Done | `README.md` (build, run, test); `.claude/scripts/verify.sh`; `bundle exec rspec` |
| AI Collaboration Narrative | Done | README section "AI Collaboration Narrative"; `docs/ai-log.md` |
| Video, 5-10 minutes | Pending (user records it) | Script: `docs/video-script.md`; demo kit: `bin/demo` |

## Evaluation dimensions

| Brief item | Status | Evidence (file / spec / command) |
|---|---|---|
| Problem Solving and System Design | Done | `docs/system-design.md` sections "Architecture", "Booking data flow", "Double-booking strategy and alternatives", "Scaling & Reliability"; `db/structure.sql` exclusion constraints |
| Technical Execution | Done | `bundle exec rspec`; `spec/domain`, `spec/services`, `spec/requests`, `spec/concurrency`; `bundle exec rubocop`; `bin/brakeman` |
| AI Engineering and Verification | Done | README section "AI Collaboration Narrative"; `docs/ai-log.md`; `.claude/scripts/verify.sh` |
| Communication and Presentation | Partly pending (video) | `README.md`; `docs/system-design.md`; `docs/video-script.md`; recording is pending |

## Epic 7 acceptance criteria

| Brief item | Status | Evidence (file / spec / command) |
|---|---|---|
| Unit, integration and concurrency specs validate the core business logic | Done | `bundle exec rspec` |
| A fresh clone can be built, run and tested by following the README | Done (local path); Docker compose path pending (needs Docker) | `README.md` sections "Quick start" and "Running tests"; clean-clone steps below; Clean-clone run on the local path passed: `bin/setup --skip-server`, seeds, server boot, Postman 16/16, `CI=true bundle exec rspec` 572/0 with thresholds |
| README contains a dedicated AI Collaboration Narrative | Done | README section "AI Collaboration Narrative" |
| System Design Document includes every item required by the brief | Done | `docs/system-design.md` table of contents |
| 5-10 minute video covers all required topics | Pending (user records it) | `docs/video-script.md` (five segments, target about 8:30-9:00) |
| US1: `bundle exec rspec spec/domain` passes with no database | Done | `bundle exec rspec spec/domain` with PostgreSQL stopped; `spec/spec_helper.rb` |
| US1: Coverage thresholds enforced in CI and locally | Done | `.simplecov`; `CI=true bundle exec rspec`; `COVERAGE=true bundle exec rspec`; job `test` in `.github/workflows/ci.yml` |
| US1: Every edge case in Epics 2 and 3 has a spec | Done | `spec/domain/scheduling`, `spec/queries/availability`, `spec/services/appointments/placement_spec.rb`, `spec/requests/api/v1/availability_spec.rb` |
| US1: `app/domain` stays pure Ruby | Done | `bundle exec rspec spec/domain/architecture_spec.rb` |
| US2: `bundle exec rspec` passes on a clean machine with the database available | Done | `bin/rails db:test:prepare && bundle exec rspec` |
| US2: Race spec stable across repeated runs | Done | `RACE_ITERATIONS=50 COVERAGE=false bundle exec rspec spec/concurrency`; `spec/concurrency/book_overlap_spec.rb`; `spec/concurrency/http_booking_race_spec.rb` |
| US2: Test database setup needs no manual steps | Done | `bin/rails db:test:prepare`; job `test` in `.github/workflows/ci.yml` |
| US2: Booking error codes covered over HTTP | Done | `spec/requests/api/v1/appointments_spec.rb` |
| US3: Fresh clone reaches a working API using only the README | Done (local path); Docker pending | `README.md` sections "Quick start", "Local development"; `.env.example`; clean-clone run (local path) |
| US3: All cURL examples run against the seeded stack with the documented output | Done | README section "cURL examples"; `bin/rails db:seed:replant` |
| US3: Client-side harness passes | Done | `make api-check`; `postman/` |
| US4: At least three concrete examples of corrected AI output, with evidence | Done | README section "AI Collaboration Narrative"; `docs/ai-log.md` (ten cases with commits and paths) |
| US4: Verification steps reproducible | Done | `.claude/scripts/verify.sh`; `RACE_ITERATIONS=50 bundle exec rspec spec/concurrency`; `bin/brakeman`; `bin/bundler-audit` |
| US4: Section clearly labelled and easy to find | Done | README section "AI Collaboration Narrative", linked from the top of the README |
| US5: Every brief item present and findable via a table of contents | Done | `docs/system-design.md` table of contents |
| US5: Diagrams render on GitHub | Done | Mermaid blocks in `docs/system-design.md` sections "Architecture" and "Booking data flow" |
| US5: Consistent with the code and OpenAPI document | Done | `swagger/v1/openapi.yaml`; `config/routes.rb`; `app/errors/error_catalogue.rb`; `.env.example` |
| US6: Video length between 5 and 10 minutes | Pending (user records it) | `docs/video-script.md` timings |
| US6: All five required topics covered | Pending (user records it) | `docs/video-script.md` segments 1-5 |
| US6: Demo runs from the submitted repository | Done | `bin/demo` |
| US7: CI is green on the main branch | Pending (user action after merge) | `.github/workflows/ci.yml` (jobs `scan_ruby`, `lint`, `zeitwerk`, `test`, `openapi_drift`, `docker`); check the Actions tab on `main` |
| US7: OpenAPI documents every route and drift is caught | Done | `swagger/v1/openapi.yaml`; `spec/integration/dealership_appointments_spec.rb`; job `openapi_drift` |
| US7: `.env.example` tracked, secrets ignored | Done | `git check-ignore .env.example` (exit 1); `git check-ignore .env` and `git check-ignore config/master.key` (exit 0); `.gitignore` |
| US7: Checklist confirms all three deliverables | Done, except the video | This file |

## Clean-clone run steps

| Brief item | Status | Evidence (file / spec / command) |
|---|---|---|
| Clone and configure | Done (local path, verified) | `git clone <repo> && cd Scheduler && cp .env.example .env` |
| Build and start the stack | Done (local path: `bin/setup`, `bin/dev`); Docker compose Pending (needs Docker) | `docker compose up --build`; or `bin/setup` then `bin/dev` |
| Seed the database | Done (local path: seeds gave 2 dealerships, 3 service types) | `bin/rails db:seed:replant` (inside the web container with `docker compose exec web bin/rails db:seed:replant`) |
| Readiness check | Done (local path, verified) | `curl -fsS http://localhost:3000/health/ready` |
| Run the specs | Done (local path, verified) | `bin/rails db:test:prepare && bundle exec rspec` |
| Run the full gate | Done (local path, verified) | `.claude/scripts/verify.sh` |
| Run the client harness | Done (local path, verified) | `make api-check` (set `POSTMAN=/path/to/postman` if the CLI is not on PATH) |
| Run the demo | Done (local path, verified) | `bin/demo` |
| Open the API documentation | Done (local path, verified) | `DOCS_ENABLED=true bin/dev`, then `/api-docs`; README section "API documentation" |

Evidence: Clean-clone run on the local path passed: `bin/setup --skip-server`, seeds, server boot, Postman 16/16, `CI=true bundle exec rspec` 572/0 with thresholds. The `docker compose up --build` path was not run because Docker is not installed on the verifying machine.

## Pending user actions

| Brief item | Status | Evidence (file / spec / command) |
|---|---|---|
| Record and submit the 5-10 minute video | Pending | Follow `docs/video-script.md`; prepare with `bin/demo` |
| Confirm CI is green on `main` | Pending | GitHub Actions run for `main` after merge |
| Run the Docker compose path (`docker compose up --build`, seed, readiness check) | Pending (needs Docker) | Not run: Docker is not installed on the verifying machine |
