# Implementation status

Updated 2026-10-30. Ravi Kannada is an experimental development language. This page
owns capability readiness and validation evidence; target behavior belongs in the
[language design](language-design.md).

## Capabilities

| Area | Current implementation | Main remaining gap |
| --- | --- | --- |
| Source profiles | Default Latin-script Kannada and English lexer/parser vocabulary | End-to-end parity; Kannada-script keywords |
| Compilation | One resolved AST-to-bytecode executable pipeline | General source-to-MIR compilation |
| Modules | Dependency graph, qualified AST linking, per-module profiles and source IDs | Independent binary compilation |
| Values and memory | NaN-boxed values, signed 48-bit integers, nonmoving tracing GC | Complete ownership/rooting and failure coverage |
| Objects and typing | Classes, lexical scopes, scalar boundary guards, closures, import visibility | Complete object protocols and type inference |
| Errors | Runtime identities and handler/cleanup machinery | Rich exception objects and all cleanup exits |
| Concurrency | Resumable task VMs, shared bounded pool, event timers, copied graphs, channels and deadlines | Complete cancellation/soak/fairness coverage; interruptible OS I/O |
| Libraries | JSON, UTF-8 files/bytes, paths, time, task/channel lifecycle, logging/assertions/environment | Streams, networking/TLS, UI; broader platform/OOM coverage |
| Native backend | Constant-return x86-64 prototype | General native compilation |
| Tools | CLI, formatter, diagnostics, editor/debugger foundations | Integration and conformance |

## Recent foundation work

The [2026-10-30 robustness review](robustness-review.md) records the current
performance, async, threading, and library gaps with implementation gates.
VM bytecode verification now uses caller-owned scratch memory, preventing
workers from allocating through shared compiler arenas. Internal channels use
an O(1) FIFO ring, with wraparound, close/drain, null-payload, and allocation
failure regressions. The host Windows sleep API rejects signed tick overflow.
Small math and collection modules add absolute value, min/max, clamp, GCD,
sum, and all/any with aliases; both source profiles have executable examples.
Subsequent implementation adds resumable tasks, copy transfer, public channels,
and core application modules; see [runtime contracts](task-runtime.md).
General native compilation, networking/UI, and release certification remain open.

The build now runs test executables instead of only compiling them. Scheduler work
replaced polling/shifting with a bounded ring queue and synchronization, introduced
monotonic deadlines, and improved shutdown and initialization rollback. Worker
heaps use a thread-safe allocator; supported objects cross boundaries as copied
graphs rather than raw VM-local handles.

Other changes preserve the source profile without an English retry, repair
construction rollback, use validated UTF-8 decoding, retain final expressions,
propagate source lines and verifier allocation failures, and correct loader cleanup.
Source, test, build, and maintenance files have a 300-line check without exemptions.

These changes are foundations, not evidence of complete language correctness.

## Validation on Windows

### Subsequent task/core-library working revision

The broader implementation was checked with one full ReleaseSafe run. It
completed **122/125 build steps**, with **288/289 executed tests passing**;
the failing compiler/VM regression exposed closure initialization resetting
restored capture state. That bug and a nested function-reference bug were fixed.
Follow-up used affected targets rather than repeating the full suite:

- Compiler/VM runtime group: **21/21 passed**, including closure and raised
  payload transfer, cancellation cleanup, and failed-task descendant shutdown.
- VM: **25/25 passed**, including 2,000 parked timers on one worker, 5,000
  wait/release cycles, cyclic/aliased transfer and OOM rollback, JSON/UTF-8,
  and channel deadlines/close/drain. Scheduler **14/14** passed earlier in
  ReleaseSafe; the final targeted run reused that passing cache.
- Compiler pipeline **4/4** and module integration **7/7** passed.
- ReleaseSafe Windows executable: CLI **27/27**, examples **46/46** passed.
- Bounded malformed-source fuzz: **128 deterministic cases**, no crash or
  timeout; seed `20261030`. This is not sustained fuzzing.
- Contribution metadata: **8 issue forms**, **21 label definitions**, issue
  configuration, and workflow YAML parsed and checked for structure/references.
- Formatting, maintained-file size budget, and whitespace checks passed.

The full suite was not rerun after these corrections. The earlier full-suite
results below remain historical; they do not certify the newer working revision.

A Linux x86-64 ReleaseSafe executable was cross-built with the pinned toolchain
and executed under Ubuntu 24.04 WSL. Core-application, task-channel, and async
examples passed. This exposed and fixed a Linux sleep API incompatibility.
Linux unit/CLI matrices, extended concurrency soak/CPU measurements, general
native compilation, and networking/TLS remain acceptance gates.

### Earlier review validation

Validated the 2026-10-30 review changes on the same pinned toolchain:

- Full Debug and ReleaseSafe suites: **125/125 build steps succeeded** in both
  modes. The final runs executed 182 and 201 tests respectively; other tests
  used cached passing results, so these counts are not the suite inventory.
- Focused worker/bytecode checks: **19/19 tests passed** in Debug, including
  the parent-allocator isolation regression. Channel and compiler/VM checks
  passed in ReleaseSafe, including ring edge cases and host sleep overflow.
- ReleaseSafe executable built successfully; CLI regressions **27/27 passed**,
  executable examples **44/44 passed**, including both new library profiles.
- Formatting, maintained-file size budget, and whitespace checks passed.

No benchmark speedup or non-Windows runtime certification is claimed by this
review. The older evidence below remains historical validation context.

Validated on 2026-10-15 with Zig `0.17.0-dev.1415+64dfaa568`:

- `zig build test --summary all -j2` and the ReleaseSafe equivalent:
  **125/125 build steps succeeded in both modes**. Unchanged test runs were
  satisfied by Zig's cache; executed counts are not the suite's inventory.
- The seven module-pipeline tests pass in both modes, including deterministic
  allocation-failure sweeps with leak and error-propagation checks.
- `zig build -Doptimize=ReleaseSafe`: executable built successfully.
- `./tools/test_cli.ps1`: **21/21 regressions passed**, covering all source
  commands, module diagnostics, integer errors, and literal-preserving formatting.
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
The example and CLI results above apply to the Windows ReleaseSafe executable; they do not certify
other platforms or optimization modes.

Compiler repairs preserve standalone side effects, local names in nested expressions,
lambda entry blocks, callable table lifetimes, and method receiver arity. Collections
store explicit element IDs, including nested expressions and dictionary pairs.
Executable compilation uses shared built-in method metadata. The evaluation regression
also exercises short-circuit expressions, comparison chains, dictionary pop, and
function return cleanup through the CLI.

The executable compiler now has one AST lowering pipeline. The former HIR subset
selector and compatibility adapter were removed. Compiler/VM integration helpers
use the same semantic checks, optimizer, and verifier as the CLI. Module tests
cover profile overrides, cross-profile imports, helper-name isolation, local
shadowing, missing/private symbols, diamond dependencies, and source identities.
HIR/MIR and native emission remain explicit development components, not a
second source execution path. Complete inference, independent binary modules,
full libraries, native compilation, and roadmap completion remain unfinished.
There is no published Python performance comparison or cross-platform runtime
certification from this local development session.
The generated [feature matrix](feature-matrix.md) contains maintainer-entered stage
flags rather than live test results or release-readiness verdicts.

See [example conventions](../examples/README.md) for commands and output contracts.

## Next gate

Use the passing suite as the regression gate; Stage 0 and the broader roadmap still
require their remaining acceptance criteria. Continue with the
single compiler pipeline, runtime contracts, libraries, concurrency, and performance
in the order defined by the [development plan](development-plan.md).
