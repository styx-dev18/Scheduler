# Routes

The coordinator picks one route per request. Signal words are hints; when it's unclear, choose the narrower route.

| Route | Signals | Pipeline | Typical sub-agent runs |
|---|---|---|---|
| `question` | "how", "why", "where", "explain", no change asked | Answer inline. For a broad search, use one built-in `Explore` agent. No plan, no commit. | 0–1 |
| `feature` | "implement", "add", "build", epic or story path | Phase 1 → 2 → 3 → 4 → 5 | M: 3 · L: 4–7 |
| `fix` | "bug", "broken", "fails", error output | Same as `feature`. The analyst writes a regression AC; `--tdd` is recommended so a failing test exists first. | 3–5 |
| `plan` | "plan", "design", "break down", `/dev-plan` | Phases 0–2 only | 1–2 |
| `resume` | a plan with unchecked tasks exists, "continue", `/dev-build` | Phase 3 → 4 → 5 using the existing plan, with `resume: true` | 2–5 |
| `tests` | "unit test", "coverage", `/dev-test` | See `/dev-test` | 1–3 |
| `refactor` | "clean up", "refactor", "conventions", `/dev-review` | See `/dev-review` | 2–4 |
| `pr-feedback` | "review comments", "address PR", `/dev-ship feedback` | See `/dev-ship` | 2–4 |
| `ship` | "open PR", "push", "update PR", `/dev-ship` | See `/dev-ship` | 0 |

## Next-step suggestions (for the Phase 6 report)

| After | Suggest |
|---|---|
| `feature`, `fix`, `resume` | `/dev-test` (if no tests were written) · `/dev-review` · `/dev-ship create` |
| `tests` | `/dev-review tests` · `/dev-ship create` |
| `refactor` | `/dev-ship create` or `/dev-ship update` |
| `pr-feedback` | `/dev-ship update` |
| `ship create` | `/dev-ship feedback <pr>` once reviewers respond |
