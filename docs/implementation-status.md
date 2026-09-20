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

## Runtime validation recorded before documentation cleanup

The first complete execution of the repaired suite reported **99/131 passing,
29 failing, and 3 crashing tests**; additional groups had compilation errors.
Introduced compilation errors were subsequently corrected.

Focused follow-up checks passed for scheduler (11), VM (12), lexer (9), bytecode
(5), backend contract (1), MIR fixtures (9), symbols (1), UTF-8 API (1), HIR (5),
compiler control flow (4), loader (7), and compiler runtime (17). Counts belong to
test targets and may include related coverage. They are not a fresh full-suite total.

The executable builds, and the arithmetic and English CLI examples passed.
The full suite has **not** subsequently been certified green. Parser, LSP,
JSON-RPC, and other integration failures still require follow-up. There is no
published Python comparison, cross-platform runtime certification, or passing
claim for the complete repository example corpus.

The generated [feature matrix](feature-matrix.md) contains maintainer-entered stage
flags; its `tested` column is not a live test result or release readiness verdict.

## Documentation validation

The documentation review executed 17 examples against the existing development
executable: 13 passed, and four exposed CLI integration failures. Class method
access and list mutation/indexing failed with `InvalidName`; an expression-function
call failed with `NoEntryBlock`; a chained string-method call failed compilation.
Those four examples are now explicitly labeled experimental and fenced as text.
The remaining runnable examples include both source profiles and a two-file import.
This check did not rerun the runtime suite or certify the broader API reference.

## Next gate

Resolve the baseline failures before declaring Stage 0 complete. Continue with the
single compiler pipeline, runtime contracts, libraries, concurrency, and performance
in the order defined by the [development plan](development-plan.md).
