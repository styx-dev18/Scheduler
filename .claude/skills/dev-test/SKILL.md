---
name: dev-test
description: Write unit tests for the current branch, either from plan.md acceptance criteria (ac) or from the changed source files (diff), stabilise them and commit.
argument-hint: "[ac|diff] [<commit>|<branch>] [extra directives]"
disable-model-invocation: true
---

# /dev-test

You are the coordinator described in [../dev/SKILL.md](../dev/SKILL.md). Follow its Settings, dispatch rules and commit rules. Directives: `$ARGUMENTS`

1. **Mode and range.** Use the mode given in the directives. Otherwise use `ac` when the branch plan has ACs, and `diff` when it doesn't. For the range, see `dispatch.md` › Ranges (default `main...HEAD`; a commit becomes `<sha>^..<sha>`).
2. **Work list.**
   - `ac`: the AC/EC ids in the plan.
   - `diff`: logic-bearing **source** files changed in the range, plus uncommitted changes:
     ```
     git diff --name-only <range> -- 'app/domain/**/*.rb' 'app/services/**/*.rb' 'app/queries/**/*.rb' \
       'app/forms/**/*.rb' 'app/models/**/*.rb' 'app/controllers/**/*.rb' 'lib/**/*.rb' \
       ':!app/models/application_record.rb' ':!lib/tasks/**'
     ```
     Serializers, migrations (`db/**`) and `config/**` are left out: they are covered by request and migration specs, not unit specs.
3. **Bundle.** Group the items by module into at most `max_parallel` bundles. Each bundle owns its own spec files, mirrored under `spec/` per `.claude/docs/testing-convention.md`. Testers write `## Test plan` entries in `plan.md`; create a minimal plan from the template with route `tests` if there is none.
4. **Dispatch.** Send one `tester` per bundle in a single message, passing `mode`, `items`, `owns` and `range`.
5. **Gate.** Run `.claude/scripts/verify.sh`. Send failures in test files back to the tester that owns them, up to `max_fix_attempts`.
   - Compare each tester's `covered` against the requested items, and re-dispatch once for any gaps.
   - Turn any `code_defects` into `F<n>` findings and ask the user whether to fix them now through an implementer. Tests are never weakened to make them pass.
6. **Commit** the test files using the Phase 5 rules, for example `test(<scope>): <summary>`. Then report as in Phase 6.
