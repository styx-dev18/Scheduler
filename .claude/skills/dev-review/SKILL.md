---
name: dev-review
description: Convention review and refactor of the branch's changed code and/or tests against .claude/docs conventions, applied by implementers and gated before commit.
argument-hint: "[code|tests|all] [<commit>|<branch>] [extra directives]"
disable-model-invocation: true
---

# /dev-review

You are the coordinator described in [../dev/SKILL.md](../dev/SKILL.md). Follow its Settings, dispatch rules and commit rules. Directives: `$ARGUMENTS`

1. **Scope and range.** Use `code`, `tests` or `all` from the directives; the default is `all`. For the range, see `dispatch.md` › Ranges (default `main...HEAD`). If there's no plan for this branch, create a minimal one from the template with route `refactor`; it only holds Findings and Log.
2. **Globs** passed to the reviewer:
   - `code`: `'app/**/*.rb' 'lib/**/*.rb' 'config/routes.rb' 'config/initializers/**/*.rb' ':!db/**'`
   - `tests`: `'spec/**/*.rb'`
3. **Review.** Spawn `reviewer` with mode `convention`, `scope`, `globs` and `range`. The reviewer looks only at added lines. For `all`, send both reviewers in one message.
4. **Gate the user.** If there are more than 5 findings, ask once whether to apply all of them, only the high-impact ones, or to pick. Skip this question with `--yolo`.
5. **Fix code first, then tests.** Group the chosen code findings by `owns` into at most `max_parallel` implementer bundles, send them in one message, and run `.claude/scripts/verify.sh` with the Phase 3 fix loop. Only then send `tester` bundles for the test findings, so specs are edited against the refactored source. The exception: a spec bundled with its own source file can go in the same implementer run.
6. **Recheck.** Send the reviewer only the finding ids that were fixed, for at most `max_review_rounds` rounds.
7. **Commit** using the Phase 5 rules, for example `refactor(<scope>): <summary>`. Then report.
