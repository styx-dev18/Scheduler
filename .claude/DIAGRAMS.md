# Workflow Diagrams

How each part of the `.claude/` workflow works. The diagrams are in Mermaid, which renders on GitHub, in VS Code (with a Mermaid extension) and in most Markdown viewers.

| # | Diagram | Shows |
|---|---|---|
| 1 | [Component map](#1-component-map) | Every file and how the pieces depend on each other |
| 2 | [Coordinator lifecycle](#2-coordinator-lifecycle-dev) | The phases of `/dev`, from triage to report |
| 3 | [A feature run, end to end](#3-a-feature-run-end-to-end) | Who talks to whom, in order |
| 4 | [Request routing](#4-request-routing) | How a prompt turns into a route and a size |
| 5 | [Context isolation](#5-context-isolation-and-token-flow) | Why the main thread stays small |
| 6 | [Agents](#6-agents) | What each worker reads, does, writes and returns |
| 7 | [Guard hooks](#7-guard-hooks) | How tool calls are allowed or denied |
| 8 | [Quality gate](#8-quality-gate-verifysh) | `verify.sh` step by step |
| 9 | [plan.md lifecycle](#9-planmd-lifecycle) | The single state file and its statuses |
| 10 | [Stage skills](#10-stage-skills) | `/dev-test`, `/dev-review`, `/dev-ship`, `/dev-onboard` |

---

## 1. Component map

```mermaid
flowchart LR
    subgraph ENTRY["Entry points: skills you type"]
        DEV["/dev<br/>coordinator"]
        STAGES["/dev-plan · /dev-build · /dev-test<br/>/dev-review · /dev-ship · /dev-onboard"]
    end

    subgraph REF["Coordinator references"]
        ROUTES["routes.md<br/>intent → pipeline"]
        TPL["plan-template.md<br/>plan.md schema"]
        DISP["dispatch.md<br/>brief and reply contract"]
    end

    subgraph AGENTS["Sub-agents: isolated context"]
        AN["analyst<br/>opus · read-only"]
        IM["implementer<br/>sonnet"]
        TE["tester<br/>sonnet"]
        RV["reviewer<br/>sonnet · read-only"]
    end

    subgraph GUARD["Enforcement"]
        H1["no-git-writes.sh"]
        H2["readonly-bash.sh"]
        H3["plan-only-writes.sh"]
        SET["settings.json<br/>allow · ask · deny"]
    end

    subgraph KNOW["Knowledge: read on demand"]
        DOCS["docs/<br/>knowledge · rules · conventions"]
        GUIDES["docs/guides/<br/>planning · pr-triage"]
        XG["dev-onboard/extraction-guide.md"]
    end

    GATE[["scripts/verify.sh<br/>deterministic gate"]]
    PLAN[("plans/&lt;branch&gt;/plan.md<br/>single state file")]
    ROOT["CLAUDE.md<br/>always-on rules"]

    STAGES -->|"reuse the rules of"| DEV
    DEV --> ROUTES & TPL & DISP
    DEV -->|"brief: paths + ids"| AN & IM & TE & RV
    DEV --> GATE
    AN & IM & TE & RV <-->|"read / tick / append"| PLAN
    AN -.-> GUIDES & XG & DOCS
    IM & TE & RV -.-> DOCS
    IM & TE -. guarded by .-> H1
    AN & RV -. guarded by .-> H2 & H3
    IM -->|"--quick"| GATE
    ROOT -. loaded every session .-> DEV
```

**Reading guide**

| Folder | Purpose | Loaded when |
|---|---|---|
| `skills/` | What runs when you type a command. `dev/` is the coordinator. The other skills each run one stage and follow the coordinator's rules. | When you invoke it (`disable-model-invocation: true`) |
| `agents/` | Workers, each with its own context window, tool list, model and hooks | When the coordinator dispatches it |
| `hooks/` | Bash + `jq` guards, wired into agent frontmatter | On every tool call that agent makes |
| `scripts/verify.sh` | The only definition of "done" | After every wave, and by implementers (`--quick`) |
| `docs/`, `docs/guides/` | Project knowledge and long checklists | Only by the agent and mode that needs them |
| `plans/` (gitignored) | One `plan.md` per branch | Throughout a run; this is how resume works |

---

## 2. Coordinator lifecycle (`/dev`)

```mermaid
flowchart TB
    START(["/dev &lt;request&gt; [flags]"]) --> T0

    subgraph P0["Phase 0 · Triage (inline, cheap)"]
        T0["branch · git status · plan exists?"] --> T1{"route?"}
        T1 -->|question| QA["answer inline<br/>or 1 Explore agent"]
        T1 -->|"resume (unchecked tasks)"| W1
        T1 -->|feature · fix · plan| SZ{"size?"}
        SZ -->|"S ≤2 files"| INLINE["coordinator edits itself<br/>→ gate → commit"]
    end

    SZ -->|"M · L"| A1

    subgraph P1["Phase 1 · Analyse"]
        A1["analyst (plan)<br/>writes plan.md"] --> A2["reply ≤15 lines<br/>waves · bundles · questions"]
    end

    A2 --> G1

    subgraph P2["Phase 2 · Gate (one round)"]
        G1{"--yolo?"} -->|no| G2["AskUserQuestion<br/>≤4 questions + approve<br/>(assumed decisions listed)"]
        G1 -->|yes| G3["accept the recommendations"]
        G2 --> G4["write answers into Decisions<br/>analyst amend only if scope changed"]
        G3 --> G4
        G4 --> G5{"approved?"}
    end

    G5 -->|no| STOP(["stop · resume later with /dev-build"])
    G5 -->|yes| W1

    subgraph P3["Phase 3 · Build in waves"]
        W1["next wave's bundles<br/>≤4 implementers, one message"] --> W2[["verify.sh"]]
        W2 -->|pass| W3{"more waves?"}
        W2 -->|"fail (≤3 attempts)"| W4["route errors to the owning agent<br/>(SendMessage continuation)"] --> W2
        W3 -->|yes| W1
    end

    W3 -->|no| R1

    subgraph P4["Phase 4 · Check"]
        R1["reviewer (ac)"] -->|findings| R2["implementers fix<br/>→ verify.sh"] --> R1
        R1 -->|"pass · ≤2 rounds"| R3["optional tester (api)<br/>--verify=api:url"]
    end

    R3 --> C1

    subgraph P5["Phase 5 · Commit (coordinator only)"]
        C1["match git log style"] --> C2["git add &lt;files&gt; && git commit"]
        C2 -->|"pre-commit fails (≤2)"| C3["fix · re-run the same command"] --> C2
    end

    C2 --> P6(["Phase 6 · Report ≤12 lines<br/>+ next-step suggestions"])
```

---

## 3. A feature run, end to end

```mermaid
sequenceDiagram
    autonumber
    actor You
    participant C as Coordinator (main thread)
    participant A as analyst
    participant I as implementer ×k
    participant G as verify.sh
    participant R as reviewer
    participant P as plan.md

    You->>C: /dev --tdd implement epics/epic-3 story 3.2
    C->>C: Triage → route feature, size L
    C->>A: brief(plan path, request)
    A->>P: Requirements, Current state, Contracts, Waves, ACs, Questions
    A-->>C: 3 waves · 4 bundles · 6 ACs · 2 questions
    C->>You: one AskUserQuestion (2 questions + approve)
    You-->>C: answers
    C->>P: Decisions
    loop each wave
        par bundles with disjoint owns
            C->>I: brief(items, owns)
            I->>I: implement → verify.sh --quick
            I->>P: tick own tasks
            I-->>C: done · changed_files
        end
        C->>G: full gate
        alt fail
            G-->>C: ≤40 lines + failing files
            C->>I: SendMessage(gate_errors) to the owner
        else pass
            C->>P: Log "W n gate pass"
        end
    end
    C->>R: brief(ac, range main...HEAD)
    R->>P: tick proven ACs, append F1
    R-->>C: findings F1
    C->>I: brief(items F1)
    C->>G: gate
    C->>R: recheck F1
    R-->>C: pass
    C->>C: git add files && git commit
    C-->>You: report: waves, runs, commit, notes, next steps
```

---

## 4. Request routing

```mermaid
flowchart LR
    REQ["your prompt"] --> K{"signals"}
    K -->|"how / why / explain"| Q["question<br/>0–1 runs"]
    K -->|"implement / add / epic path"| F["feature"]
    K -->|"bug / fails / stack trace"| X["fix<br/>(regression AC, --tdd advised)"]
    K -->|"plan / break down"| PL["plan → /dev-plan"]
    K -->|"plan has unchecked tasks"| RS["resume → /dev-build"]
    K -->|"unit test / coverage"| TS["tests → /dev-test"]
    K -->|"refactor / conventions"| RF["refactor → /dev-review"]
    K -->|"review comments"| PF["pr-feedback → /dev-ship feedback"]
    K -->|"open / update PR"| SH["ship → /dev-ship"]
    F & X --> S{"size"}
    S -->|S| S1["inline · 0 runs"]
    S -->|M| S2["analyst + implementer + reviewer · ≈3 runs"]
    S -->|L| S3["waves · ≈4–8 runs"]
```

---

## 5. Context isolation and token flow

Each sub-agent works in **its own context window**. Only small, structured replies come back into the long-lived main thread.

```mermaid
flowchart LR
    subgraph MAIN["Main thread context (kept small)"]
        C["Coordinator<br/>routes · plan headers · ≤15-line replies"]
    end
    subgraph ISO["Isolated sub-agent contexts (thrown away after use)"]
        A["analyst<br/>reads code, epics, docs"]
        I["implementer<br/>reads contracts and owned files"]
        R["reviewer<br/>reads the diff and traced files"]
    end
    C -- "brief: ~6 lines<br/>paths + ids only" --> A & I & R
    A & I & R -- "reply: ≤15 lines<br/>status · files · notes" --> C
    A & I & R -- "large outputs<br/>(plan, findings, R-items)" --> P[("plan.md")]
    G[["verify.sh"]] -- "≤40 lines + failing files<br/>full log stays on disk" --> C
```

| Mechanism | Effect |
|---|---|
| The coordinator never reads source | Exploration never fills the main thread |
| Briefs carry paths and ids, not content | Prompts stay tiny, and every agent reads the same `plan.md` |
| Replies of ≤15 lines; detail goes to `plan.md` | The main thread grows by a few lines per agent |
| Size S runs inline | No agent overhead for small edits |
| Bundles group related tasks | The number of runs scales with modules, not with task count |
| `SendMessage` continuation for fixes | The fixer already has its context loaded |
| Guides are read per mode | Each agent loads only the instructions it needs |

---

## 6. Agents

### 6.1 analyst (opus · read-only · writes only under `.claude/plans/`)

```mermaid
flowchart TB
    B["brief: mode · plan · request"] --> M{"mode"}
    M -->|plan| P1["read planning guide, knowledge, coding rules<br/>explore only the touched code"]
    P1 --> P2["gap scan over 9 categories"]
    P2 --> P3["write plan.md<br/>Current state · Risks · Contracts<br/>Waves/Bundles with owns · ACs/ECs traced to R ids"]
    P3 --> P4["≤4 questions ranked by impact × uncertainty<br/>everything else becomes an (assumed) Decision"]
    M -->|amend| AM["apply the answers<br/>no scope growth"]
    M -->|pr| PR["fetch threads, comments, review bodies<br/>read the current code at each line<br/>triage: skip · code · reply-only · already-fixed"]
    PR --> PR2["R-items grouped by file<br/>with thread ids"]
    M -->|"onboard-coding / onboard-testing"| ON["follow the extraction guide<br/>sample files · 7 filters · drafts to out/"]
    P4 & AM & PR2 & ON --> RE["reply ≤15 lines"]
```

### 6.2 implementer (sonnet · edits code · cannot commit)

```mermaid
flowchart TB
    B["brief: items · owns · gate_errors? · resume?"] --> R1["read Current state, Contracts, Decisions<br/>and the coding rules"]
    R1 --> R2{"resume?"}
    R2 -->|yes| D["git diff -- owns<br/>continue, don't redo"]
    R2 -->|no| IM
    D --> IM["implement the items<br/>contracts exact · surgical changes"]
    IM --> Q[["verify.sh --quick"]]
    Q -->|fail| FX["fix every error from that run, root cause first<br/>check imports, signatures, DI wiring<br/>read the full log if truncated"] --> Q
    Q -->|"pass, or 3 attempts used"| TK["tick items in plan.md<br/>or append a warning with the reason"]
    TK --> RE["reply: status · per_item · changed_files · notes"]
```

### 6.3 tester (sonnet · edits tests only · cannot commit)

```mermaid
flowchart TB
    B["brief: mode · items · owns · range? · url?"] --> M{"mode"}
    M -->|ac| AC["tests that prove the ACs/ECs<br/>against existing code"]
    M -->|diff| DF["classify functions: new · updated · deleted<br/>write the Test plan, then the tests"]
    M -->|tdd| TD["failing tests from Given/When/Then + Contracts<br/>written before the code exists"]
    M -->|api| AP{"url reachable?"}
    AP -->|no| BL["blocked<br/>never mark ❌"]
    AP -->|yes| CU["curl each scenario<br/>isolated data · cleanup<br/>❌ with the full curl and the response"]
    AC & DF & TD --> RUN["run own spec files<br/>fix tests ≤3 times"]
    RUN --> DEF{"code wrong?"}
    DEF -->|yes| CD["report code_defects<br/>never weaken the test"]
    DEF -->|no| AU["one audit pass against the testing rules"]
    CD & AU & CU & BL --> RE["reply: status · covered · tests · code_defects"]
```

### 6.4 reviewer (sonnet · read-only · writes only `plan.md`)

```mermaid
flowchart TB
    B["brief: mode · range · scope/globs · items?"] --> M{"mode"}
    M -->|ac| A1["map ACs to files through the tasks' owns"]
    A1 --> A2["trace route → validation → use case<br/>→ domain → repository → response"]
    A2 --> A3{"file:line produces Then?"}
    A3 -->|yes| TICK["tick the AC"]
    A3 -->|no| FND["finding F n"]
    A2 --> BUG["flag bugs: errors, status codes, validation,<br/>authz/ownership, null/empty, contracts"] --> FND
    M -->|convention| C1["git diff -U0: added lines only"]
    C1 --> C2["check against conventions and rules<br/>SRP · KISS · DRY · YAGNI · SOLID · layering"] --> FND
    FND --> FMT["F n · tag · file:line · expected vs actual · fix · owns"]
    TICK & FMT --> RE["reply: pass or findings + ids"]
```

---

## 7. Guard hooks

The hooks are wired through each agent's frontmatter, so they apply only to that agent. A denial comes back to the agent as a reason it can act on.

```mermaid
flowchart TB
    CALL["agent tool call"] --> WHO{"which agent?"}

    WHO -->|"implementer · tester"| NG["no-git-writes.sh<br/>(Bash)"]
    NG --> NG1{"commit · push · reset --hard · rebase · stash<br/>clean · restore · gh pr create/comment/merge?"}
    NG1 -->|yes| DENY1["deny: the coordinator commits"]
    NG1 -->|no| OK1["allow"]

    WHO -->|"analyst · reviewer"| RB["readonly-bash.sh<br/>(Bash)"]
    RB --> RB0{"redirect or command substitution?"}
    RB0 -->|yes| DENY2["deny"]
    RB0 -->|no| RB1{"each segment on the allowlist?<br/>git diff/log/show/status · gh pr view/diff<br/>gh api GET · graphql query · ls · rg · jq"}
    RB1 -->|no| DENY2
    RB1 -->|yes| RB2{"gh api write or graphql mutation?"}
    RB2 -->|yes| DENY2
    RB2 -->|no| OK2["allow"]

    WHO -->|"analyst · reviewer"| PW["plan-only-writes.sh<br/>(Write · Edit)"]
    PW --> PW1{"path under .claude/plans/<br/>and no '..'?"}
    PW1 -->|yes| OK3["allow"]
    PW1 -->|no| DENY3["deny: write findings into plan.md"]
```

**Project-wide permissions** (`settings.json`) cover everything else, including the coordinator:
- **allow:** the gate script, package scripts, read-only git and `gh` commands, `.claude/plans/**` edits
- **ask:** `git push`, `gh pr create`, `gh pr comment`, `gh pr merge`, writes through `gh api`
- **deny:** `--no-verify`, force-push

---

## 8. Quality gate (`verify.sh`)

```mermaid
flowchart TB
    S(["verify.sh [--quick] [--max-lines N]"]) --> PJ{"Gemfile?"}
    PJ -->|no| SKIP["SKIP · exit 0<br/>(pre-foundation)"]
    PJ -->|yes| ST["collect steps that exist:<br/>zeitwerk:check<br/>--quick: zeitwerk only<br/>full: + rubocop · brakeman · rspec"]
    ST --> NONE{"no steps?"}
    NONE -->|yes| SKIP
    NONE -->|no| RUN["run each step<br/>full log → .claude/plans/.verify/step.log"]
    RUN --> RES{"exit code"}
    RES -->|0| NEXT{"more steps?"}
    NEXT -->|yes| RUN
    NEXT -->|no| PASS(["ALL PASS · exit 0"])
    RES -->|"≠ 0"| FAIL(["FAIL · exit 1<br/>≤40 error lines + failing files list"])
```

The exit code is the single source of truth. No agent decides that a change is done.

---

## 9. plan.md lifecycle

```mermaid
stateDiagram-v2
    direction LR
    [*] --> planned: analyst (plan)
    planned --> planned: analyst (amend)
    planned --> approved: gate · Yes
    planned --> [*]: gate · No (resume later)
    approved --> building: wave 1 dispatched
    building --> building: wave n gate pass
    building --> checking: all tasks ticked
    checking --> building: findings → fixes
    checking --> committed: reviewer pass + gate pass + commit
    committed --> building: new findings or PR feedback
    committed --> [*]
```

| Section | Written by | Read by |
|---|---|---|
| Meta, Log | coordinator | coordinator (triage, resume) |
| Requirements, Current state, Risks, Approach, Contracts | analyst | implementer, tester, reviewer |
| Decisions, Open questions | analyst; coordinator writes the answers | everyone |
| Tasks (waves, bundles, owns) | analyst; implementers tick them | coordinator (dispatch) |
| Acceptance criteria | analyst; reviewer and tester tick them | tester, reviewer |
| Test plan | tester | tester (resume) |
| Findings | reviewer; implementers tick them | coordinator, implementer |
| PR feedback | analyst (pr) | coordinator, implementer, `/dev-ship update` |

---

## 10. Stage skills

### 10.1 `/dev-test` and `/dev-review`

```mermaid
flowchart LR
    subgraph T["/dev-test [ac|diff] [range]"]
        T1["work list:<br/>AC ids, or changed logic files<br/>(DTOs, interfaces, ports, modules excluded)"] --> T2["≤4 tester bundles"] --> T3[["verify.sh"]] --> T4["code_defects → findings<br/>covered gaps → re-dispatch once"] --> T5["commit test(...)"]
    end
    subgraph RV["/dev-review [code|tests|all] [range]"]
        R1["reviewer convention<br/>added lines only"] --> R2{"> 5 findings?"}
        R2 -->|yes| R3["ask: all · high-impact · pick"]
        R2 -->|no| R4
        R3 --> R4["code fixes → gate"] --> R5["then test fixes → gate"] --> R6["recheck ≤2 rounds"] --> R7["commit refactor(...)"]
    end
```

### 10.2 `/dev-ship`

```mermaid
flowchart TB
    S{"/dev-ship"} -->|create| C1["clean tree? → verify.sh"] --> C2["title + body from plan<br/>or from logic diffs"] --> C3{"confirm"} -->|yes| C4["git push -u · gh pr create"]
    S -->|update| U1["on the PR head branch?<br/>commits to push?"] --> U2["comment from ticked R-items<br/>and per_item lines"] --> U3{"confirm"} -->|yes| U4["git push · gh pr comment<br/>optional thread replies, each confirmed"]
    S -->|feedback| F1["on the PR head branch?"] --> F2["analyst (pr) → R-items"] --> F3{"apply which?"} --> F4["implementers by owns"] --> F5[["verify.sh"]] --> F6["commit fix(review)"] --> F7["suggest /dev-test, then /dev-ship update"]
```

### 10.3 `/dev-onboard`

```mermaid
flowchart LR
    O1{"Gemfile + app/?"} -->|no| O0(["stop: run after the foundation epic"])
    O1 -->|yes| O2["back up docs/ to out/backup"]
    O2 --> O3["analyst onboard-coding"] & O4["analyst onboard-testing<br/>(skipped if no tests)"]
    O3 & O4 --> O5["merge knowledge drafts<br/>copy into .claude/docs/"]
    O5 --> O6{"keep the changes?"}
    O6 -->|yes| O7(["report the changed docs"])
    O6 -->|no| O8(["restore from the backup"])
```
