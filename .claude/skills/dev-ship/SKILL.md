---
name: dev-ship
description: Pull-request lifecycle for the current branch. create opens a PR, update pushes and posts a change summary, feedback turns review threads into triaged, planned, gated fixes. Always confirms before pushing or posting.
argument-hint: "create [target-branch] | update | feedback <pr-number-or-url> [--yolo]"
disable-model-invocation: true
---

# /dev-ship

You are the coordinator described in [../dev/SKILL.md](../dev/SKILL.md). Arguments: `$ARGUMENTS`

**Outward-facing actions** (`git push`, `gh pr create`, `gh pr comment`, replies on review threads) need one explicit user confirmation per run, even with `--yolo`. Show the title and body, or the comment, before sending.

## `create [target]` (no sub-agents)
1. The target is the argument or `main`. Stop if `git status --short` shows uncommitted changes; suggest committing through `/dev` first.
2. Run `.claude/scripts/verify.sh`. Stop on failure.
3. Use `git log --oneline <target>..HEAD` and `git diff --stat <target>...HEAD` as the input. If the branch plan exists, take the summary and ACs from it. If there's no plan, read the diffs of **logic-bearing** files only: services, use cases, domain and controllers.
4. Draft the title (matching `git log` style, otherwise Conventional Commits) and the body from [pr-template.md](pr-template.md) › Create.
   - Give logic changes their own bullets. Summarise tests in one line and DTO or contract changes in one line; reviewers care about contract changes.
   - Leave the self-testing checklist items unchecked, for the author.
5. Confirm with the user, then run `git push -u origin HEAD` and `gh pr create --base <target> --title ... --body-file <tmp>`. Report the PR URL.

## `update` (no sub-agents)
1. Find the PR with `gh pr view --json number,url,headRefName`. Stop if there isn't one, or if the current branch isn't its `headRefName`.
2. Stop if `git log --oneline @{u}..HEAD` is empty; there's nothing to push.
3. Draft the comment from [pr-template.md](pr-template.md) › Update, using the ticked `R<n>` items in `## PR feedback` and the implementers' `per_item` lines in `## Log`. Don't read diffs.
4. Confirm, then run `git push` and `gh pr comment <n> --body-file <tmp>`.
5. For `reply-only` R-items, offer to post their suggested replies on the threads by `thread:<id>`, using `gh api graphql` with `addPullRequestReviewThreadReply`. Each reply needs its own confirmation.

## `feedback <pr>`
1. Check that the current branch is the PR's `headRefName` (`gh pr view <n> --json headRefName`). Stop if it isn't.
2. Spawn `analyst` (mode `pr`, `pr: <n>`). It triages every thread per `.claude/docs/guides/pr-triage.md` and writes R-items with a proposed fix, `owns` and the thread id.
3. **Gate.** Unless `--yolo` is set, show the `code` R-items in one `AskUserQuestion`: apply all proposed fixes (Recommended), choose which to apply, or stop. Record any skips in `## Decisions`.
4. **Fix.** Group the chosen items by `owns` into at most `max_parallel` bundles. Send `implementer` for source files or `tester` for test files, in one message. Append each reply's `per_item` lines to `## Log`.
5. **Gate.** Run `.claude/scripts/verify.sh` with the fix loop from `/dev` Phase 3.
6. **Commit** using the Phase 5 rules, for example `fix(review): <summary>`.
7. **Report** the items addressed, and the `reply-only` items with their suggested replies. If any fix changed runtime behaviour, suggest `/dev-test` or a `reviewer` `ac` pass first. Then suggest `/dev-ship update`.
