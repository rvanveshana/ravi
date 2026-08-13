# Ravi Progress

Short handoff for verified implementation status. Nothing is listed as done
until it executes and is covered by a test or an example contract.

## Current Status

- The production entry point routes through the HIR/MIR pipeline for the
  currently supported subset. Unsupported AST shapes still use the isolated
  compatibility adapter in `src/compiler/hir_compatibility.zig`; removal of
  that adapter is a completion gate, not a completed task.
- All 30 files under `examples/` are self-verifying contracts (they assert
  real results with `adre ... : yese "message"` and end with a `PASS`
  marker), not just printed values a human has to eyeball.
- `zig build test --summary all` passes all 35 test targets, `zig build
  --summary all` passes, and `.\test.ps1` passes all 30 examples. These are
  the standing acceptance bars for any change. The examples passing does not
  prove that every example is currently lowered by HIR/MIR because the
  compatibility adapter remains active.

## Review Alignment

The engineering review plan is not complete. The repository has completed the
Phase 0/Phase 1 foundations and substantial runtime ownership work, but it is
not yet a complete single-authority HIR/MIR, native, or 1.0 implementation.
The compatibility adapter remains during migration. The review plan remains
the authoritative list of remaining acceptance work; passing the current
example corpus is necessary but does not prove type soundness, native
equivalence, concurrency safety, package reproducibility, or performance
superiority.

## Recently Fixed

A batch of real, previously-hidden compiler/runtime defects was found and
fixed while hardening the examples into assertion contracts (root causes and
debugging notes are kept in `/memories/repo/ravi-compiler-bugs-fixed.md`):

- AST: top-level function declarations leaked a stack value on every call.
- Compiler: naive capture detection treated any fresh local variable as a
  required closure capture, breaking functions with their own new locals.
- AST: generic `for`/`prati x alli y` loops pushed the loop-condition operands
  in the wrong order, so they silently ran zero iterations.
- Runtime: `for x in <bare variable>` failed instead of iterating; `for`
  iterables are now resolved uniformly (list/set/dict/int) at runtime.
- AST parser: `%` (modulo) was not recognized at all.
- Compiler: leading unary minus (`-5 + 3`) miscomputed as `-(5 + 3)`.
- Compiler: `true`/`false` literals were stored as untagged integers and
  printed as `1`/`0` once round-tripped through a variable.
- Compiler: bare, call-free expression statements (e.g. a `try`-body expression
  with no assignment) never popped their result, corrupting later stack
  depth once anything followed the block.

## Verified Current Gaps / Next Work

- **Semantic/HIR/MIR authority**: verified AST-to-HIR-to-MIR-to-bytecode
  lowering handles typed scalar constants, arithmetic/unary/comparison
  operations, print/raise effects, explicit blocks, jumps, conditional
  branches, basic locals, positional parameters, direct named calls, and
  simple while-loop CFGs through the production VM. The compatibility adapter
  remains the fallback for general statement lowering, defaults, variadics,
  recursion/function values, closures/capture cells, collections/indexing,
  classes/inheritance, exceptions/finally, modules/global state, and
  async/generator lowering. Stable symbol IDs, a complete type algebra, typed
  HIR, SSA construction, and full-language backend lowering are not complete.
- **Verifier contract**: bytecode verification has broad tests and validates
  stack/control-flow and metadata invariants. A shared opcode contract now
  defines exhaustive minimum-stack and termination effects and is consumed by
  the verifier; VM, debugger, disassembler, and compiler migration to that
  contract remains open.
- **Runtime ownership**: the non-moving collector, roots, barriers,
  destruction, stress options, and stale-handle checks are implemented. A
  single fully descriptor-driven object model, moving-collector readiness,
  fragmentation/pause measurement, and complete thread-ownership contract
  remain open.
- **Classes**: inheritance and visibility contracts are not implemented.
- **Iteration/generators**: no general iterator protocol or `yield`-backed
  generator state machines yet.
- **Context managers**: `jote`/`aagi` parse, but enter/exit protocol
  execution and guaranteed cleanup are not implemented.
- **Decorators**: not implemented.
- **Gradual typing**: annotations are accepted, but union/nullable types,
  generics, narrowing, inference, function signatures, ownership rules, and
  complete runtime conversion boundaries are not implemented.
- **Modules**: shared module globals and full profile-aware class behavior
  need further integration.
- **Exceptions/cleanup**: try/except and resumable metadata exist, but a
  unified unwind protocol for `finally`, return, break/continue, cancellation,
  timeout, and suspension is not complete.
- **Async/concurrency**: scheduler primitives exist, but language-level async
  lowering, structured cancellation, task ownership, send/share rules, race
  stress coverage, and measured 1/2/4/8-worker scaling are pending.
- **Native/backend**: `src/backend/native.zig` currently emits verified,
  deterministic textual `RAVI-NATIVE-MIR` records only. Executable machine
  code, target ABI calls, unwind/debug data, linking, and VM/native
  differential tests are pending.
- **Optimization/performance**: optimization remains bytecode-local, and
  benchmark phase timings, allocation data, GC pause timings, native
  comparisons, and multi-core scaling evidence remain incomplete.
- **Tooling/ecosystem**: semantic LSP services, versioned artifacts,
  persistent package caching, lockfiles, FFI generation, package security, and
  reproducible release metadata remain open.

## Phase 0 Status

Completed validation work:

- CI is intended to check formatting, source-size budgets,
  Debug/ReleaseSafe/ReleaseFast builds, unit tests, and the executable example
  corpus on Windows and Linux. The current local source-size check still
  reports three oversized modules, documented below.
- Dedicated verifier tests cover control-flow joins, stack effects, handlers,
  locals, captures, constants, jumps, source metadata, and malformed input.
- `std.testing.checkAllAllocationFailures` covers bytecode construction and
  lexer/parser cleanup paths.
- `tests/phase0_tests.zig` provides a deterministic lexer/parser fuzz entry
  point over arbitrary byte sequences.
- The generated feature matrix is maintained in
  [config/feature-matrix.json](config/feature-matrix.json) and rendered to
  [docs/feature-matrix.md](docs/feature-matrix.md) by
  `tools/generate_feature_matrix.ps1`.

Phase 0 architecture follow-up:

- Parser coordinator extraction is complete: `src/parser/parser.zig` now keeps
  the public parser API and delegates concrete implementations to
  `src/parser/parser_statements.zig`,
  `src/parser/parser_simple_statements.zig`, and
  `src/parser/parser_expressions.zig`.
- VM execute-loop coordinator extraction is complete: `src/vm/vm.zig` now keeps
  VM lifecycle/public API coordination while the instruction dispatch loop
  lives in `src/vm/execution.zig`.
- Current source-size budgets are guardrails, not completion claims; future
  coordinator splits should be driven by feature growth rather than file size
  alone.

Current size-check result:

- `tools/check_src_sizes.ps1` is compatible with the repository's Windows
  PowerShell runtime and now reports actual violations instead of failing on
  unavailable `Path.GetRelativePath`.
- The remaining oversized modules are `src/compiler/hir_pipeline.zig` (742
  lines), `src/ir/mir.zig` (435 lines), and `src/ir/mir_bytecode.zig` (431
  lines), against the default 300-line budget. These require focused
  extraction before broad HIR/MIR feature expansion is complete.

## Phase 1 Status

Diagnostics and debugger foundation work is implemented and covered by tests.
The full semantic tooling plan is still open:

- DAP now supports lifecycle, stepping, breakpoints, exception-breakpoint
  configuration, threads, stack traces, scopes, variables, and evaluation.
- The DAP adapter provides an incremental framed stream host reusable with
  stdio, sockets, and in-process test streams.
- Source-aware stack frames retain function names, source names, lines,
  columns, and instruction identities.
- Golden Phase 1 tests cover lexical, parse, semantic, compile, verifier, and
  runtime diagnostic contracts, including source excerpts and carets.
- Kannada/Kanglish and English profiles pass end-to-end lexer, parser,
  semantic, compiler, verifier, and VM execution tests.
- Resumable source identity and runtime failure source locations are covered
  by the Phase 1 test target.
- Shared immutable snapshots, cancellation/stale-result handling, workspace
  module graphs, hover types, references, completion, semantic tokens,
  rename, and code actions are not yet complete.

## Phase 2 Status

Runtime correctness foundations are implemented and covered by focused
acceptance tests. This does not close the broader runtime, async, or native
requirements in the review plan:

- `src/vm/value.zig` is the sole runtime value ABI; the legacy union-based
  runtime value module has been removed from the build and source tree.
- Runtime tables, collections, frames, locals, strings, closures, cells, and
  instances grow through checked allocator-backed storage.
- Managed object destruction releases owned payloads, and collector options
  expose tiny thresholds and stress mode for VM tests.
- Precise roots are rebuilt from live stack, frame, capture, and exception
  values; recursive object graphs are traced and mutable stores use barriers.
- Stale handles are rejected after collection, and repeated transient-object
  stress execution is covered by tests.
- Bytecode carries per-instruction source and root metadata. The verifier
  checks metadata alignment, operands, stack effects, handlers, calls, and
  reachable control-flow joins.
- VM initialization and runtime ownership paths have exhaustive allocation
  failure coverage.
- Thread ownership, a complete generic descriptor model, moving/generational
  collection, unified async cleanup, and native execution equivalence remain
  outside the completed Phase 2 scope.

Documentation for these contracts is maintained in
[docs/runtime-abi.md](docs/runtime-abi.md) and
[docs/architecture.md](docs/architecture.md).

## Phase 0 Baseline

ReleaseFast baseline on Windows x64 with Zig `0.17.0-dev.1415+64dfaa568`:

- 30 measured samples after 1 warmup; runtime median approximately
  `16.0-16.7 ms`; highest measured p95 `22.049 ms`; binary size
  `1,155,584` bytes.
- Budgets: [config/performance-budgets.json](config/performance-budgets.json)
- Benchmark runner: [tools/benchmark.ps1](tools/benchmark.ps1)

## Verification

Run from the repository root:

```powershell
zig build test
.\test.ps1
git diff --check
```

