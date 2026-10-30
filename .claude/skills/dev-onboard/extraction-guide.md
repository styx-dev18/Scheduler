# Extraction Guide (analyst: `onboard-coding` and `onboard-testing` modes)

## Method
- **Sample, don't read everything.** Read the manifests and configs (`Gemfile`, `Gemfile.lock`, `.ruby-version`, `.rubocop.yml`, `.rspec`, `config/application.rb`, `config/database.yml`, `config/initializers/*`, `docker-compose*`, `.env.example`). Then read 2–3 representative files per layer.
- **Anchor every observation** to at least one file path.
- **Scope split.**
  - `onboard-coding` covers production code only. It never documents test files, runners, mocks or coverage.
  - `onboard-testing` covers only those. If there's no test evidence (no `spec/**/*_spec.rb` and no `.rspec`), reply `blocked`.
- **Merge pass at the end.** Merge near-duplicates and tighten the wording. Keep version numbers, config values and paths exactly as they appear.

## Filters every rule must pass
1. **Evidence-backed.** Cites a manifest, config setting or sampled file. No invented rules.
2. **Unobvious.** It would surprise a competent engineer who is new to this project. Leave out generic best practice.
3. **Actionable.** One imperative an agent can check its own output against: `USE …`, `NEVER …`, `ALWAYS …`.
4. **Non-redundant.** Not already in `CLAUDE.md` or another `.claude/docs/*.md` file.
5. **Stable.** A settled decision, not a temporary state.
6. **Verbatim.** Exact versions, thresholds and paths.
7. **Omit empty.** Drop any section that has no rules. No empty headings.

## `coding-rules.md` sections
| Section | Look for | Exclude |
|---|---|---|
| Language | dry-monads `Result` usage, `Data.define` value objects, keyword-argument injection, frozen-string and `require` usage outside Zeitwerk | Things Ruby practitioners do anyway |
| Framework | Autoload roots and namespaces (`app/domain`, `app/services`, `app/queries`, `app/forms`), `BaseController` `rescue_from` and envelope helpers, Strong Parameters, Active Record scopes and constraints, migration and `structure.sql` setup, `strong_migrations`, config loading | Framework defaults |
| Code quality and style | Lint rules at non-default severity, naming exceptions, file size or complexity limits, formatter settings that change code | Anything the formatter fixes automatically |
| Security | `current_customer` seam, credentials and `ENV.fetch`, `filter_parameters`, `rack-cors` and `rack-attack` setup, Brakeman ignores | Generic OWASP advice |
| Critical don't-miss | What NOT to do and WHY, in 1–2 lines each: traps from configs, ADRs, CONTRIBUTING and lint rules, and **paths agents must not touch** (generated files, applied migrations) | – |

## `testing-rules.md` sections
| Section | Look for | Exclude |
|---|---|---|
| Framework and tooling | `.rspec`, `spec_helper` vs `rails_helper`, `spec/support` loading, rswag `swagger_helper`, SimpleCov setup, commands | – |
| Structure and style | File placement, `describe`/`it` naming, AAA layout, helpers | – |
| Mocking | Injected collaborators vs `instance_double`, `travel_to` vs injected `Clock`, what must never be mocked (exclusion constraints, PostgreSQL), forbidden patterns | – |
| Test data and fixtures | FactoryBot factories and traits, transactional tests vs `use_transactional_tests = false` for concurrency specs, isolation | – |
| Coverage and quality gates | Global and per-path thresholds, CI test commands | – |
| Critical don't-miss | Test traps: real time, database access from `spec/domain`, connection pool size for thread specs, Bullet raising in test | – |

## `knowledge.md` sections
Write these sections: architecture, design patterns (and **why** each was chosen), implementation patterns, data architecture, API design, and cross-cutting concerns (auth, validation, errors, logging, config).
- Describe the data architecture **without listing entities**, and the API design **without listing endpoints**. Reference the folders that own each concern.
- Never include business logic, feature lists, code snippets or diagrams.
- Put testing knowledge (test pyramid, isolation, test data, environments) under `## Testing`.

## Convention docs
Keep their existing structure. Replace every placeholder with values from the code. Update entries the code contradicts, and cite the evidence.

## Reply
```
status: done | blocked
docs: <files written to out>
sections: kept <list> · dropped <list>
rules: <count> (<count> per section)
notes: <gaps or contradictions with the existing docs>
```
