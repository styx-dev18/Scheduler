# Epic 7: Quality, Documentation and Delivery

## Description

Produce the three submission artifacts required by the Keyloop brief: the **System Design Document**, the **working code repository** (README, AI Collaboration Narrative, test suite), and the **5-10 minute video**. This epic also defines the quality gates that demonstrate ownership of AI-generated Rails code, which is a primary evaluation criterion.

## Dependencies

- Epics 1-4 (core implementation); Epics 5-6 as completed

## Evaluation Mapping

| Evaluation dimension | Where it is addressed |
|---|---|
| Problem Solving & System Design | User Story 5 (System Design Document), Epic 3 |
| Technical Execution | User Stories 1-3 (tests), Epics 1-4 |
| AI Engineering & Verification | User Story 4 (AI Collaboration Narrative), AI usage log |
| Communication & Presentation | User Stories 3, 5, 6 |

## Acceptance Criteria

- Unit, integration, and concurrency specs validate the core business logic
- A fresh clone can be built, run, and tested by following the README
- The README contains a dedicated AI Collaboration Narrative
- The System Design Document includes every item required by the brief
- A 5-10 minute video covers all required topics

---

### User Story 1: Unit Specs for Core Business Logic

#### Description

- As a reviewer, I want unit specs for the core business logic.

#### Requirements

- Cover pure domain and service logic with RSpec, using doubles or fakes for collaborators:
  - `Scheduling::TimeInterval` overlap and boundary behaviour
  - `Scheduling::SlotTime` grid enforcement
  - `Scheduling::OpeningHoursPolicy` (opening hours, holidays, DST)
  - Qualification matching and shift containment
  - Assignment strategy determinism and tie-breaking
  - `Scheduling::StatusMachine` (table-driven)
  - `Appointments::Book` for each success and failure branch
- Pure-domain specs (`spec/domain`) load only `spec_helper` and run without a database (`bundle exec rspec spec/domain`)
- Enforce SimpleCov thresholds (line and branch) on `app/domain` and `app/services` (e.g. 90% line, 85% branch)
- Architecture spec: asserts files under `app/domain` never reference `ActiveRecord`, `ApplicationRecord`, or `Rails.`

#### Notes

- Keep specs deterministic: inject the `Clock` or use `travel_to`; never depend on real time
- Name examples by behaviour, not implementation

#### Acceptance Criteria

- `bundle exec rspec spec/domain` passes with no database
- Coverage thresholds are enforced in CI and locally
- Every edge case listed in Epics 2 and 3 has a spec

---

### User Story 2: Integration and Concurrency Specs

#### Description

- As a reviewer, I want integration and concurrency specs against a real database.

#### Requirements

- All DB-backed specs run against real PostgreSQL (compose `db` locally, a service container in CI); schema loaded from `db/structure.sql`
- Query specs for free-bay, free-technician, and overlap queries
- Constraint specs proving direct overlapping inserts are rejected with `PG::ExclusionViolation`
- **Double-booking race spec** in `spec/concurrency`: N (e.g. 20) threads, each with its own connection and released together with a latch, all booking the last slot; assert exactly one success, the rest `409`, and exactly one row in the database
- Idempotency race spec (same key, parallel requests, one appointment)
- Atomicity spec (forced failure leaves no partial data)
- Request specs for the full HTTP flow (happy path and each error code)
- Concurrency specs disable transactional tests (`use_transactional_tests = false`) and clean up explicitly (or with `database_cleaner-active_record` scoped to this suite only)

#### Notes

- Run the race spec repeatedly (e.g. 50 iterations) at least once in CI to demonstrate stability
- Ensure the test database pool size is at least N

#### Acceptance Criteria

- `bundle exec rspec` passes on a clean machine with the database available
- The race spec is stable across repeated runs
- Test database setup needs no manual steps (`bin/rails db:test:prepare`)

---

### User Story 3: README with Build, Run and Test Instructions

#### Description

- As a reviewer, I want a README with clear build, run, and test instructions plus cURL examples.

#### Requirements

- Sections: overview, chosen scenario and layer, prerequisites (Ruby via rbenv, PostgreSQL 16 or Docker), quick start (`docker compose up`), local development (`bin/setup`, `bin/dev`), running tests, project structure, API overview, assumptions, links to the System Design Document and Swagger UI
- cURL examples for: list dealerships and service types, check availability, book successfully, book a conflicting slot (`409`), idempotent retry, cancel, reschedule
- Provide an optional `.http` / Bruno collection as the client-side test harness
- Document environment variables and the seeded IDs used in the examples

#### Notes

- Verify every command by following the README on a clean clone

#### Acceptance Criteria

- A fresh clone reaches a working API using only the README
- All cURL examples run against the seeded stack and produce the documented output

---

### User Story 4: AI Collaboration Narrative

#### Description

- As a reviewer, I want an **AI Collaboration Narrative** in the README showing how AI was directed, verified, and owned.

#### Requirements

- A dedicated README section covering:
  - **Strategy:** tools used, how work was broken down (epics, stories, prompts), how Rails conventions, architecture rules, and assumptions were given to the AI up front (e.g. a project rules file)
  - **Prompting approach:** examples of effective prompts and context documents
  - **Verification process:** reviewing diffs, writing specs first for domain logic, running the race spec, checking `explain(:analyze)` output, running RuboCop, Brakeman, bundler-audit, and Bullet
  - **Defects found in AI output:** concrete examples (e.g. naive check-then-insert race, closed-interval overlap bug, retrying inside an aborted transaction without a savepoint, `update_all` bypassing validations, N+1 queries, timezone/DST errors) and how each was detected and fixed
  - **Quality gates:** coverage thresholds, architecture spec, CI checks
  - **Ownership:** decisions the human made against AI suggestions and why
- Keep a running log (`docs/ai-log.md`) while building so the narrative reflects real events

#### Notes

- Honesty matters more than polish: include what the AI got wrong
- This content is reused for the 1-2 minute AI segment of the video

#### Acceptance Criteria

- The narrative contains at least three concrete examples of corrected AI output, with evidence
- Verification steps are reproducible (commands or specs are referenced)
- The section is clearly labelled and easy to find in the README

---

### User Story 5: System Design Document

#### Description

- As a reviewer, I want a System Design Document that presents the architectural plan.

#### Requirements

- Format: Markdown (`docs/system-design.md`) with Mermaid diagrams (optionally exported to PNG/PDF)
- Must include:
  - Architecture diagram (Rails layers, components, PostgreSQL, Solid Queue/Cache, observability stack)
  - Role of each component
  - Data flow explanation, including a sequence diagram of the booking request
  - Technology choices with justifications (from the Epic 0 stack overview)
  - Observability strategy (logging, metrics, tracing; from Epic 6)
  - Dedicated section on **how GenAI assisted the design phase**
- Also include: assumptions table (A1-A11), ERD, double-booking strategy and alternatives considered, error catalogue summary, scaling and reliability strategy, limitations and future work

#### Notes

- Reuse the Key Design Decision table from Epic 3
- Keep diagrams readable; one diagram per concern

#### Acceptance Criteria

- Every item required by the brief is present and findable via a table of contents
- Diagrams render on GitHub
- The document is consistent with the implemented code and the OpenAPI document

---

### User Story 6: Video Submission

#### Description

- As a reviewer, I want a 5-10 minute video presentation.

#### Requirements

- Script and record a video covering, in order:
  1. Brief introduction and the chosen scenario (about 30 s)
  2. System design walkthrough and implementation highlights, including the exclusion-constraint strategy (about 3 min)
  3. AI collaboration story (1-2 min)
  4. Live demo: availability, successful booking, conflicting booking, cancel/reschedule (about 2 min)
  5. Learnings and challenges (about 1 min)
- Rehearse against the 10-minute limit

#### Notes

- Prepare demo data and a terminal/Swagger layout beforehand
- Have the concurrency spec output ready as a visual proof point

#### Acceptance Criteria

- Video length is between 5 and 10 minutes
- All five required topics are covered
- The demo runs from the submitted repository, not a different local state

---

### User Story 7: Repository Hygiene and Final Review

#### Description

- As a maintainer, I want the repository polished and verified before submission.

#### Requirements

- Extend the Rails-generated GitHub Actions CI: `bin/rails zeitwerk:check`, RuboCop, Brakeman, bundler-audit, full RSpec suite against a PostgreSQL service container, Docker image build
- CI step that regenerates the OpenAPI document (`rswag:specs:swaggerize`) and fails on `git diff` (drift check)
- Meaningful commit history
- `.env.example`, `.gitignore`, no secrets committed (`config/master.key` ignored)
- Final checklist walk-through against the brief's deliverables and evaluation framework

#### Notes

- Do a final clean-clone dry run in a fresh directory

#### Acceptance Criteria

- CI is green on the main branch
- A clean-clone run succeeds end to end
- The checklist confirms all three deliverables are complete

---
