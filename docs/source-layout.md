# Ravi source layout

Ravi implementation files are kept small and cohesive. The target for new
modules is 200–300 lines; a module that grows beyond that should be split by
responsibility before adding another feature.

Current boundaries include:

- `src/compiler/model.zig`: compiler declaration and loop data structures.
- `src/compiler/helpers.zig`: reusable token, name, range, and suite helpers.
- `src/compiler/expressions.zig`: operator mapping and precedence.
- `src/compiler/calls.zig`: positional, default, keyword, `*args`, and
  `**kwargs` call lowering.
- `src/compiler/builtins.zig`: bilingual builtin and method-name matching.
- `src/parser/precedence.zig`: Pratt operator binding and language canonicalization.
- `src/vm/frames.zig`: call-frame, closure, and captured-cell records.
- `src/vm/errors.zig`: runtime errors and stable runtime type identifiers.
- `src/vm/strings.zig`: UTF-8 string primitives.
- `src/vm/collections.zig`: reusable collection primitives.
- `src/vm/trace.zig`: trace-frame storage constants.
- `src/vm/type_helpers.zig`: allocation-free runtime type classification.
- `src/vm/state_helpers.zig`: allocation-free stack, fault, and string-table state helpers.
- `src/vm/call_runtime.zig`: direct function and closure frame setup.

Dead duplicate implementations are removed after each extracted module passes
the test suite; coordinator files must not retain rollback copies.

The remaining large orchestration files (`compiler.zig`, `vm.zig`, and
`parser.zig`) are compatibility-facing coordinators. Their next extractions
should be calls/functions/collections/control flow for the compiler and
calls/closures/collections/exceptions for the VM. `tools/check_src_sizes.ps1`
is the guard used while completing those extractions.
