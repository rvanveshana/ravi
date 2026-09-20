# Contributing

Community expectations, issue guidance, and the pull-request process are summarized
in the repository-level [contribution guide](../CONTRIBUTING.md). All participation
must follow the [Code of Conduct](../CODE_OF_CONDUCT.md).

Read [Architecture](architecture.md) and [Implementation status](implementation-status.md)
before changing language behavior. Use the pinned toolchain in
[Installation](user_docs/installation.md).

## Repository layout

| Path | Contents |
| --- | --- |
| `build.zig`, `build/` | Executable, module graph, test artifacts and named targets |
| `config/` | Vocabulary/constants and development trackers |
| `src/lexer`, `src/parser`, `src/ast`, `src/semantic`, `src/types` | Frontend |
| `src/compiler`, `src/ir`, `src/optimizer`, `src/backend` | Lowering and backend work |
| `src/bytecode`, `src/vm`, `src/memory`, `src/concurrency` | Runtime |
| `src/modules`, `src/source`, `src/diagnostics` | Sources, modules, diagnostics |
| `src/lsp`, `src/debug`, `src/formatter` | Tooling infrastructure |
| `lib/ravi/` | Standard-library source and clearly identified blueprints |
| `tests/`, `examples/` | Test roots and executable programs |
| `docs/user_docs/` | Current user handbook |
| `tools/` | Size checks, feature-matrix generation, benchmarks |

## Maintenance rules

Keep maintained source, test, build, and script files at or below 300 physical
lines. Split by responsibility; do not compress code to bypass the limit. The
current checker has no exemptions. A future mandatory exception needs a documented
reason and a corresponding checker change.

Use one semantic implementation for both profiles. Resolve names and ownership at
explicit boundaries. Remove dead implementations rather than retaining rollback
copies. Never turn an OOM or unsupported feature into an unrelated success path.

## Validation

From the repository root:

```powershell
zig build
zig build test --summary all -j2
./tools/check_src_sizes.ps1
git diff --check
```

`zig build test` executes its test artifacts. For focused follow-up, select a
component instead of rerunning everything:

```powershell
zig build test-scheduler --summary all
zig build test-vm --summary all
zig build test-loader --summary all
zig build --help
```

The `test-compiler_vm-N` targets select individual compiler/VM groups; consult
`build/artifacts_tests.zig` for their ordering. Test names and counts can change.

`./test.ps1` builds, runs the full Zig suite, and recursively checks examples with
expected-output files and per-process timeouts. `./test.ps1 -ExamplesOnly` skips
unit tests; `./tools/test_examples.ps1` uses the existing binary without rebuilding.
See [example conventions](../examples/README.md). CI reuses each configured binary.
For documentation-only changes, validate links, source references, and selected
runnable examples; do not rerun runtime suites unnecessarily.

Run `zig fmt` on changed Zig files before final validation. Generate the feature
matrix with `./tools/generate_feature_matrix.ps1` if its tracker or generator changes.

## Documentation ownership

Current behavior belongs in the handbook. Test evidence and open defects belong in
implementation status. Future contracts belong in language design; delivery order
belongs in the development plan. Link to the owning document instead of copying
its status table into several pages.

Examples must identify their profile, use supported syntax, and show output where
useful. Unimplemented APIs belong in a planned-feature note, not a runnable block.
Use relative repository links and avoid local machine paths. API documentation
should state arguments, results, mutation, errors, and relevant resource limits.
