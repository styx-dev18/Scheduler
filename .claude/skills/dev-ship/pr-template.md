# PR templates

Write "N/A" for sections that don't apply. Keep each bullet to one line.

## Create

Title: Conventional Commits, for example `feat(appointments): cancel a confirmed appointment`.

```markdown
## Summary
<!-- What problem this solves and why, in 2-3 sentences. -->

## Implementation Details
- `<Component/Module>`: <change>
- `<path/to/file.rb>`: <change>

## Acceptance Criteria
<!-- From plan.md: AC/EC ids with one-line descriptions, ticked when they were verified. -->

## Self-testing Checklist
- [ ] Self-code review
<!-- Checks the author runs by hand before requesting review, based on the areas changed. Leave unchecked. -->

## Additional Notes
<!-- New dependencies, env vars, migrations, risks. -->
```

## Update

```markdown
I addressed the following comments in this PR:
- <R-id / reviewer ask> → <what changed>

## Self-testing Checklist
- [ ] Self-code review
<!-- Leave unchecked. -->

## Additional Notes
```
