# PR Triage Guide (analyst: `pr` mode)

## 1. Fetch everything reviewers said (GET only)
- Branch check: `gh pr view <n> --json number,url,headRefName,baseRefName`
- Review summaries: `gh pr view <n> --json reviews`. "Request changes" bodies often hold the main asks.
- General comments: `gh pr view <n> --json comments`
- Inline threads with their resolution state, using GraphQL:
  `gh api graphql -f query='query($o:String!,$r:String!,$n:Int!){repository(owner:$o,name:$r){pullRequest(number:$n){reviewThreads(first:100){nodes{id isResolved isOutdated path line comments(first:50){nodes{author{login} body createdAt}}}}}}}' -F o=<owner> -F r=<repo> -F n=<n>`

  The read-only hook allows `gh api graphql` queries.

## 2. Triage each thread
Read the **whole thread**, then read the **current code** at `path:line`. Comments may be outdated after later pushes, and the line may have moved.

| Triage | When |
|---|---|
| `skip` | Marked resolved, approved by the reviewer, confirmed fixed in the replies, or acknowledged as not applicable. Don't write an R-item. |
| `code` | A code change is still needed |
| `reply-only` | A question or discussion, or a request you recommend declining (give the reason) |
| `already-fixed` | The current code already does what was asked. Treat it as `reply-only` and cite the commit or the line. |

## 3. Write R-items
Write them under `## PR feedback` in `plan.md`, grouped by file and sorted by line number, so they bundle cleanly by `owns`.

```
- [ ] R<n> <path>:<line> [code|reply-only] (thread:<id>) - <summary of the whole thread, every point raised>. Fix: <ordered steps>. owns: <files>
```

- The **Fix** covers every point raised in the thread, not just the first comment.
- For `reply-only`, the Fix is the suggested reply text in one or two sentences.
- Keep `thread:<id>` (the GraphQL node id), so `/dev-ship update` can reply on the thread later.
- Write general comments and review-summary asks as R-items without `path:line`, with the location `(general)`.
- Don't copy comment bodies word for word. Summarise them.
