---
name: dev-onboard
description: Regenerate the project knowledge base in .claude/docs (knowledge, coding and testing rules and conventions) from the actual codebase. Run after the foundation epic and after large structural changes.
argument-hint: "[coding|testing|all]"
disable-model-invocation: true
---

# /dev-onboard

You are the coordinator described in [../dev/SKILL.md](../dev/SKILL.md). Directives: `$ARGUMENTS`

1. If there's no `Gemfile` or `app/` yet, stop. The rules must come from real code, so suggest running this after the foundation epic. If there's no `spec/**/*_spec.rb` file and no `.rspec`, skip the testing analyst and say why.
2. Set `out` to `.claude/plans/_onboard/`.
3. In **one message**, spawn two `analyst` agents. Skip one if the directives narrow the scope.
   - mode `onboard-coding`, docs: `knowledge.md` (coding sections), `coding-rules.md`, `coding-convention.md`
   - mode `onboard-testing`, docs: `knowledge.md` (testing sections), `testing-rules.md`, `testing-convention.md`

   Both follow [extraction-guide.md](extraction-guide.md) and write into `out`. Give each its own subfolder (`coding/`, `testing/`) so they never write the same file.
4. Back up `.claude/docs/` to `out/backup/`. Merge the two `knowledge.md` drafts: coding sections first, then testing. Copy the drafts over the files in `.claude/docs/` and show `diff -ru out/backup .claude/docs | head -80`.
5. Ask the user whether to keep the changes. If they decline, restore `.claude/docs/` from `out/backup/`. Either way, delete `out` afterwards.
6. Don't commit unless the user asks. Report which docs changed.
