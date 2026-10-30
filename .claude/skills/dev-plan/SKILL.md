---
name: dev-plan
description: Plan only. Runs the /dev coordinator through triage, analysis and the single question-and-approval gate, then stops. Re-run it to refine an existing plan.
argument-hint: "<request or epic/story path> [--yolo] [--fresh]"
disable-model-invocation: true
---

# /dev-plan

Read [../dev/SKILL.md](../dev/SKILL.md) and act as its coordinator with route `plan` for: `$ARGUMENTS`

- Run **Phases 0–2 only**. Never dispatch implementers or commit.
- If the branch already has a plan and `--fresh` isn't set, refine it: spawn `analyst` (mode `amend`) with the request as the change to make. Then run the gate again on any new open questions.
- End by telling the user how many waves, bundles and ACs the plan has, and that `/dev-build` starts the work.
