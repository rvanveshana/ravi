## Problem and resulting behavior

Describe the concrete problem and what changes for users or contributors.

## Related issue

Closes #

## Validation

- [ ] Added or updated focused tests for behavior changes
- [ ] `zig build`
- [ ] `zig build test --summary all -j2`
- [ ] `./tools/test_examples.ps1`
- [ ] `zig fmt --check build.zig build config src tests`
- [ ] `./tools/check_src_sizes.ps1`
- [ ] `git diff --check`

List checks that do not apply and explain why.

## Documentation and compatibility

- [ ] Updated public documentation when behavior changed
- [ ] Preserved equivalent semantics across both source profiles
- [ ] Kept maintained files within the 300-line limit
