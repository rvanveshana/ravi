# Ravi source layout

Ravi implementation files are kept small and cohesive. The target for new
modules is 200–300 lines; a module that grows beyond that should be split by
responsibility before adding another feature.

Current boundaries include:

- `src/compiler/compiler.zig`: AST compiler coordinator and bytecode assembly.
- `src/compiler/ast_compiler.zig`: AST expression lowering.
- `src/compiler/ast_statements.zig`: AST statement lowering and control flow.
- `src/compiler/ast_helpers.zig`: AST function, capture, lambda, and loop
  discovery.
- `src/compiler/helpers.zig`: AST-safe name, capture, and opcode helpers.
- `src/compiler/builtins.zig`: bilingual builtin and method-name matching.
- `src/parser/parser.zig`: parser coordinator with stable public API (`init`, `initWithLanguage`, `parse`, `parseRecovering`).
- `src/parser/parser_statements.zig`: statement, suite, and control-flow parsing.
- `src/parser/parser_simple_statements.zig`: return/transfer/typed-assignment statement parsing.
- `src/parser/parser_expressions.zig`: Pratt expression parsing, lambdas, calls, indexing, and formatted strings.
- `src/parser/precedence.zig`: Pratt operator binding and language canonicalization.
- `src/vm/frames.zig`: call-frame, closure, and captured-cell records.
- `src/vm/errors.zig`: runtime errors and stable runtime type identifiers.
- `src/vm/strings.zig`: UTF-8 string primitives.
- `src/vm/collections.zig`: reusable collection primitives.
- `src/vm/trace.zig`: trace-frame storage constants.
- `src/vm/type_helpers.zig`: allocation-free runtime type classification.
- `src/vm/state_helpers.zig`: allocation-free stack, fault, and string-table state helpers.
- `src/vm/call_runtime.zig`: direct function and closure frame setup.
- `src/vm/execution.zig`: VM instruction dispatch/execute loop and opcode-level runtime coordination.

Dead duplicate implementations are removed after each extracted module passes
the test suite; coordinator files must not retain rollback copies. The former
token-range compiler modules have been deleted.

`vm.zig` now acts as the VM lifecycle/public API coordinator and delegates
the instruction loop to `execution.zig`, while other focused VM modules own
frames, calls, collections, strings, exceptions, construction, and value
operations. `compiler.zig` is now AST-only and below its protected
source-size budget. Parser coordinator extraction is complete: `parser.zig`
now delegates concrete statement and expression implementations to
`parser_statements.zig`, `parser_simple_statements.zig`, and
`parser_expressions.zig`; `tools/check_src_sizes.ps1` no longer needs a
temporary parser budget override.
