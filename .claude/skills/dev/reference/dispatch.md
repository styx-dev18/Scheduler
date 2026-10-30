# Dispatch contract

## Brief format (coordinator → sub-agent)
A brief is a short key/value block. It carries **paths and ids only**. Never paste file contents, the plan or diffs into it, except the compact gate output in `gate_errors`.

```
plan: .claude/plans/<slug>/plan.md
mode: <mode>
items: T3, T4
owns: app/services/appointments/cancel.rb, app/controllers/api/v1/appointments_controller.rb
resume: false
directives: <only the user directives that concern this agent; omit if none>
```

Use the Agent tool with `subagent_type` set to the agent name and a 3–5 word `description`, for example "Build B3 wave 2".

| Agent | Modes | Extra keys |
|---|---|---|
| `analyst` | `plan`, `amend`, `pr`, `onboard-coding`, `onboard-testing` | `request` (plan), `answers` (amend), `pr` (pr), `out` (onboard) |
| `implementer` | – | `items`, `owns`, `gate_errors`, `resume` |
| `tester` | `ac`, `diff`, `tdd`, `api` | `items`, `owns`, `range` (diff), `url` (api) |
| `reviewer` | `ac`, `convention` | `range`, `scope` + `globs` (convention), `items` |

## Parallel dispatch
- Agents run in parallel only when their Agent calls are in **the same message**.
- Parallelise only within one wave, and only bundles whose `owns` sets don't overlap.
- Send at most `max_parallel` per message. If a wave has more bundles, send the next batch after the first one replies.
- Read-only agents (analyst, reviewer) can always run alongside each other. For example, `/dev-onboard` runs two analysts at once.

## Continuing an agent
When a gate failure or finding belongs to an agent you just ran, prefer `SendMessage` to that agent with only the new input: the gate errors or the finding ids. It still has the plan and the code loaded, which is cheaper than starting a new agent. Start a new agent with `resume: true` only if continuing isn't possible.

## Reply format (sub-agent → coordinator)
Each agent defines its own reply block, of at most 8–15 lines. Common keys:
- `status`: `done` | `partial` | `blocked` | `pass` | `findings`
- `changed_files`: what the coordinator stages at commit time
- `notes`: blockers, contract gaps, follow-ups, one line each. **Tell the user about every note in the final report.**
- `per_item` (implementer): one line per F/R id saying what changed. Keep these lines; `/dev-ship update` writes the PR comment from them.
- `covered` (tester): the AC/EC ids proven. Compare it against the plan to spot gaps without reading specs.

Anything longer, such as findings, PR-feedback items or plan sections, is written into `plan.md`, and the reply only names the ids.

## Ranges
`range` defaults to `main...HEAD`, and agents always add uncommitted work. A single commit becomes `<sha>^..<sha>`; a branch becomes `main...<branch>`.

## Handling replies
| Reply | Coordinator action |
|---|---|
| `done` / `pass` | continue |
| `partial` | re-dispatch the remaining items once with `resume: true`, then treat it as `blocked` |
| `blocked` | bring the notes to the user in one `AskUserQuestion`, record the decision in `## Decisions`, continue |
| `findings` | Phase 4 fix loop |
| `code_defects` (tester) | turn each one into an `F<n>` finding and run the fix loop |
