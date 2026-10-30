---
name: dev-build
description: Build from the existing branch plan.md. Resumes from the first unchecked task, runs waves with the gate, reviews acceptance criteria and commits.
argument-hint: "[--tdd] [--verify=api:<url>] [extra directives]"
disable-model-invocation: true
---

# /dev-build

Read [../dev/SKILL.md](../dev/SKILL.md) and act as its coordinator with route `resume`. Directives: `$ARGUMENTS`

- If there is no plan for this branch, stop and suggest `/dev-plan <request>`.
- If `## Open questions` still has entries, run the Phase 2 gate first.
- Run **Phases 3–6**. Start from the first wave with unchecked tasks. Set `resume: true` for any bundle whose owned files already show up in `git status --short`.
- Don't re-plan. If the plan looks wrong while you build, stop and suggest `/dev-plan`.
