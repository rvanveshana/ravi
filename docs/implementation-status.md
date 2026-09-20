# Implementation status

Updated 2026-09-20. Ravi Kannada is an experimental development language. This page
owns capability readiness and validation evidence; target behavior belongs in the
[language design](language-design.md).

## Capabilities

| Area | Current implementation | Main remaining gap |
| --- | --- | --- |
| Source profiles | Default Latin-script Kannada and English lexer/parser vocabulary | End-to-end parity; Kannada-script keywords |
| Compilation | Typed HIR/MIR subset plus direct AST compatibility path | One complete pipeline |
| Modules | Dependency graph and source concatenation in CLI | Independent compilation and namespaces |
| Values and memory | NaN-boxed values, signed 48-bit integers, nonmoving tracing GC | Complete ownership/rooting and failure coverage |
| Objects and typing | Classes, annotations, closures, visibility metadata | Consistent protocols and enforcement |
| Errors | Runtime identities and handler/cleanup machinery | Rich exception objects and all cleanup exits |
| Concurrency | Bounded worker queue, monotonic waits, scalar transfer | Resumable I/O, structured tasks and object transfer |
| Libraries | Primitive methods and small source helpers | Most application libraries; JSON/network/UI are blueprints |
| Native backend | Constant-return x86-64 prototype | General native compilation |
| Tools | CLI, formatter, diagnostics, editor/debugger foundations | Integration and conformance |

## Recent foundation work

The build now runs test executables instead of only compiling them. Scheduler work
replaced polling/shifting with a bounded ring queue and synchronization, introduced
monotonic deadlines, and improved shutdown and initialization rollback. Worker
heaps use a thread-safe allocator and reject unsupported VM-local handles.

Other changes preserve the source profile without an English retry, repair
construction rollback, use validated UTF-8 decoding, retain final expressions,
propagate source lines and verifier allocation failures, and correct loader cleanup.
Source, test, build, and maintenance files have a 300-line check without exemptions.

These changes are foundations, not evidence of complete language correctness.

## Validation on Windows

Validated on 2026-09-20 with Zig `0.17.0-dev.1415+64dfaa568`:

- `zig build test --summary all -j2`: **122/122 build steps succeeded**;
  **187/187 executed tests passed**, with other test runs satisfied by Zig's cache.
  The 187 count is this invocation's executed total, not the entire suite's inventory.
- `zig build`: Debug executable built successfully.
- `./tools/test_examples.ps1`: **42/42 executable examples passed** with exact
  output snapshots, exit-code checks, and per-process timeouts.
- `zig fmt --check src tests build config build.zig`, source-size checks, and
  `git diff --check`: passed.

This supersedes the earlier failing baselines. No tests were disabled or expected
results weakened to obtain this result. Invalid source-profile fixtures and fixture
allocation ownership were corrected while preserving their behavioral assertions.

Repairs cover JSON-RPC parsing and escaping, VM roots and collection safepoints,
bytecode string ownership, exception payloads and typed handlers, indexed assignment,
short-circuit evaluation, adjacent chained comparisons, and dictionary `pop(key)`.
Closures now share captured cells with outer locals and sibling closures. Additional
regressions verify cleanup preserves return values and captured assignments.
Nested generator suspension metadata is scoped to its own function; full generator
iteration and resumable I/O remain unfinished.

## Executable examples

The recursive example runner discovers programs and verifies their `.out` snapshots.
It fails on missing snapshots, incorrect output, nonzero exit codes, and timeouts.
CI reuses each optimization-mode binary instead of rebuilding Debug for examples.
The local results above apply to the Windows Debug executable; they do not certify
other platforms or optimization modes.

Compiler repairs preserve standalone side effects, local names in nested expressions,
lambda entry blocks, callable table lifetimes, and method receiver arity. Collections
store explicit element IDs, including nested expressions and dictionary pairs.
AST and HIR compilation share built-in method metadata. The evaluation regression
also exercises short-circuit expressions, comparison chains, dictionary pop, and
function return cleanup through the CLI.

The architecture retains HIR/MIR and direct AST compatibility paths. Most compiler/VM
unit tests exercise the AST path; green results do not establish complete pipeline
parity, complete libraries, native compilation, or roadmap completion. There is no
published Python performance comparison or cross-platform runtime certification.
The generated [feature matrix](feature-matrix.md) contains maintainer-entered stage
flags rather than live test results or release-readiness verdicts.

See [example conventions](../examples/README.md) for commands and output contracts.

## Next gate

Use the passing suite as the regression gate; Stage 0 and the broader roadmap still
require their remaining acceptance criteria. Continue with the
single compiler pipeline, runtime contracts, libraries, concurrency, and performance
in the order defined by the [development plan](development-plan.md).
