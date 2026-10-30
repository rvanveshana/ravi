## Problem and resulting behavior

Describe the concrete problem and what changes for users or contributors.
Include a small before/after example when it helps review.

## Related issue

Closes #<!-- issue number, or explain why a small fix needs no issue -->

## Validation

List the commands you ran, their results, and any skipped checks with reasons.
Run focused checks for the affected component; one full ReleaseSafe run is
appropriate for shared compiler/runtime changes. Repeat tests only when needed.

| Check | Result |
| --- | --- |
| Build / affected tests | |
| Affected examples / CLI contracts | |
| Formatting / size budget / whitespace | |

## Documentation and compatibility

- [ ] Updated public documentation when behavior changed
- [ ] Preserved equivalent semantics across both source profiles
- [ ] Kept maintained files within the 300-line limit

## Runtime or API considerations

<!-- Delete if not applicable. Describe ownership, limits, cancellation/close
behavior, error compatibility, and OOM rollback. For performance changes include
reproducible measurements. Identify limitations reviewers should assess. -->
