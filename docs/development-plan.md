# Ravi development plan

Reviewed against the implementation and test suite on 2026-07-23. This plan
uses verified behavior as the definition of completion. Architecture documents
describe the intended destination, but do not by themselves establish feature
status.

## Current baseline

The initial audit findings above were converted into work items. The following
foundation improvements are now implemented and verified:

- The test runner reports the correct counts and exit status; all 27 executable
  examples pass with no expected-failure exclusions.
- The fast dispatcher is now selected by `Vm.runValue` for verified supported
  chunks and falls back to the reference execution loop for all other opcodes;
  differential arithmetic tests protect the optimization boundary.
- CI covers Windows/Linux and Debug, ReleaseSafe, and ReleaseFast builds, and
  all formerly dormant infrastructure modules have direct tests.
- Bytecode carries real source locations, diagnostics render codes/excerpts/
  carets, runtime failures retain Ravi frames, and `ravi bytecode` disassembles
  instructions with stack effects and source positions.
- Classes instantiate, constructors bind implicit `tanna`, properties persist,
  and methods dispatch through verified bytecode.
- The managed-object collector is non-moving mark/sweep with roots and traced
  child graphs. Migration of the reference VM's fixed object tables remains.
- The scheduler uses stable heap-owned state, synchronized bounded queues, and
  deterministic draining/shutdown. Futures now provide bounded timeout-aware
  waits with distinct cancellation/timeout outcomes. Work stealing remains a
  later milestone; channels now expose explicit close state for safe shutdown.
- Channel receive operations can now distinguish empty from closed, allowing
  structured consumers to terminate without sentinel values.
- Short-circuit boolean logic, unary lowering, chained comparisons, formatter,
  module graph/export resolution, HIR-to-MIR verification, LSP document state,
  and repeatable ReleaseFast benchmark tooling have direct tests.
- The production VM grows operand/call/trace stacks, managed strings,
  collection contents, and object tables through checked allocator-backed
  storage. Frames and closure environments also grow dynamically and pass
  exhaustive allocation-failure testing. The executable VM now uses the
  NaN-boxed `Value` ABI with typed handles; `runValue` exposes it directly and
  `run` remains an `i64` compatibility wrapper. Collector integration and
  removal/aliasing of the legacy tagged-union module remain.
- The VM now owns a collector and polls safepoints on every instruction; its
  object tables still need migration to collector-managed traced allocations
  and precise roots.
- VM strings, arrays, dictionaries, closures, capture cells, and instances are
  now collector-managed records with explicit payload destruction, rooted while
  handles are live and reclaimed between executions. Frames remain
  allocator-backed execution state. Safepoints rebuild roots from live
  stack/frame/capture/exception values, recursively trace object references,
  and mutable stores invoke write barriers; generational policies remain out of
  scope until measurements justify them.
- A provider-based module loader now parses imports, resolves relative source
  paths, detects cycles, preserves per-module profiles, and the CLI executes
  dependency initializers in topological order. Stable imported-symbol binding
  now covers imported function declarations in the executable combined chunk;
  visibility enforcement for declared function/class exports is now enforced;
  shared module globals, artifacts, and incremental invalidation remain the
  next module milestone.
- Module artifacts now expose deterministic interface fingerprints that include
  compiler key and language profile, enabling safe cache identity checks.
- A tested DAP adapter now maps lifecycle, pause/continue, step, breakpoint,
  and stack-trace requests onto the in-process debugger using the same framed
  transport as LSP. A long-running stdio/socket host and full scope/evaluate
  serialization remain.
- A tested JSON-RPC LSP adapter now handles initialization, versioned document
  overlays, completion requests, shutdown, and Content-Length framing. Lexer
  and parser diagnostics now publish through document overlays, with pull-
  diagnostics, document-symbol, identifier-reference, and rename requests; a
  generic incremental reader/writer host now supports long-running stdio or
  socket-style sessions.
- Runtime resumable-machine metadata now records suspension/resume source
  locations, completion/failure, and parent cancellation propagation. HIR/MIR
  and bytecode function metadata now preserve resumable identity; compiler
  lowering from async/generator syntax remains the next concurrency step.
- Bytecode now emits explicit suspension-point markers for `yield`/`taru` and
  records their count; the synchronous VM preserves behavior while resumable
  frame execution remains.
- Large coordinator files are protected by ratcheting CI budgets but still need
  extraction toward the 200-300 line target.

## Delivery rules

Every milestone must:

1. Add unit, integration, negative, and resource-limit tests for its behavior.
2. Pass Debug and ReleaseSafe builds, all examples, and relevant stress tests.
3. Use structured diagnostics rather than printing from library code.
4. Update `progress.md` only after the acceptance tests pass.
5. Record benchmark results before and after performance changes.
6. Keep language semantics identical across Kannada and English profiles.

## Milestone 0 - Make the baseline trustworthy (P0)

Goal: no false-green build and no uncompiled production claims.

- Fix `test.ps1` scope handling and make each executable example's expected
  outcome explicit. Move unsupported examples to check-only or expected-failure
  suites until implemented.
- Add build targets that compile and test every source module, including debug,
  GC, scheduler, optimizer, backend, dispatcher, and both value representations.
- Add CI for Debug, ReleaseSafe, and ReleaseFast on Windows and Linux.
- Add malformed-bytecode verifier tests, allocation-failure tests, and lexer /
  parser fuzz entry points.
- Replace the approximate percentage in `progress.md` with a generated feature
  matrix: `designed`, `parsed`, `analyzed`, `lowered`, `executed`, `tested`.
- Split compiler, VM, and parser coordinators along the boundaries already
  listed in `docs/source-layout.md`.

Acceptance gate: any failing example or uncompiled module fails CI; all claimed
features have a direct test.

## Milestone 1 - Diagnostics and debug foundation (P0)

Goal: errors identify the Ravi source location, cause, and useful next action.

- Introduce `SourceId`, immutable source buffers, line indexes, and byte spans.
- Replace the minimal diagnostic with stable codes, severity, primary and
  related spans, typed arguments, notes, and optional fix-it edits.
- Provide human, compact, and JSON renderers. Show source snippets, carets,
  import chains, and consistent non-zero CLI exit codes.
- Propagate real source locations into every emitted bytecode instruction;
  eliminate zero-filled source maps.
- Add a bytecode disassembler with offsets, operands, stack effect, function,
  and source location. Add `ravi debug-bytecode <file>` or equivalent.
- Track function names, call sites, locals, captures, and exception locations;
  render Ravi-level stack traces instead of bytecode-only offsets.
- Implement debugger pause state, source breakpoints, step-in/over/out, stack,
  scopes, variables, expression evaluation, and exception breakpoints.
- Expose the debugger through DAP only after the in-process debugger API is
  tested independently.

Acceptance gate: golden diagnostic tests cover lex, parse, semantic, compile,
verify, and runtime faults; a nested-call failure prints accurate file, line,
column, source excerpt, and Ravi frames.

## Milestone 2 - Runtime correctness and memory ownership (P0)

Goal: one safe, scalable value/object model replaces fixed tables and sentinel
integer handles.

- [x] Select one runtime `Value` ABI and integrate it into the real VM;
  document integer range, float/NaN behavior,
  pointer assumptions, equality, hashing, and FFI representation.
- [ ] Remove or alias the legacy `src/runtime/value.zig` compatibility module
  after all public users migrate.
- Replace fixed arrays for strings, collections, closures, cells, frames, and
  locals with checked, configurable storage.
- Define object headers and trace descriptors for strings, arrays, tuples,
  sets, dictionaries, closures, cells, instances, futures, and channels.
- Implement a non-moving mark-sweep collector first: allocation pages, precise
  roots, mark worklist, sweep/free lists, large objects, collection thresholds,
  and heap statistics.
- [x] Integrate VM stack/frame/global/handle roots and safepoint polling. Add
  write barriers now so a later generational collector does not change object
  APIs.
- Add GC stress mode, tiny-heap tests, cyclic-object tests, out-of-memory
  propagation, and leak checks. Add generations only after mark-sweep is stable
  and benchmarks show a benefit.
- Make the bytecode verifier control-flow aware: validate stack state at basic
  block joins, call effects, handlers, locals, captures, constants, and source /
  root metadata.

Acceptance gate: programs can allocate beyond today's fixed capacities, cyclic
garbage is reclaimed, invalid bytecode cannot crash the VM, and GC stress passes
all runtime tests.

## Milestone 3 - Complete the existing language core (P1)

Goal: finish features already represented in the lexer/parser/compiler without
adding a new backend.

- Improve nested-suite parser recovery and preserve malformed regions/trivia;
  add round-trip syntax and formatter tests.
- Lower `and`/`or` with jumps for true short-circuit behavior. Implement chained
  comparisons with single evaluation of intermediate expressions.
- Drive code generation from AST/semantic results rather than rescanning token
  ranges in the compiler.
- Complete name resolution, control-flow validation, reachability, return-path
  checking, and loop/exception transfer validation.
- Implement annotation-driven type constraints and automatic guard, boxing,
  unboxing, and conversion insertion. Remove duplicated token-based semantic
  analysis once AST analysis covers it.
- Generalize exception unwinding across calls and implicit runtime faults;
  preserve `finally` behavior for return, break, continue, cancellation, and
  rethrow.
- Finish string formatting/interpolation, large managed strings, Unicode-safe
  operations, iterators/generators, decorators, context managers, and docstring
  metadata in dependency order.

Acceptance gate: semantic decisions have typed AST/HIR golden tests and every
core construct has bilingual end-to-end tests.

## Milestone 4 - Classes and object model (P1)

Goal: make the existing class syntax executable.

- Finalize grammar for fields, visibility, constructors (`huttu`), `tanna`,
  inheritance, `guru`, method calls, and class/member decorators.
- Add class, shape/layout, instance, bound-method, and method-table objects.
- Add verified property load/store, method call, instance creation, constructor,
  and super-call operations.
- Enforce visibility and override contracts in semantic analysis.
- Start with stable slot layouts and dictionary fallback; add inline property /
  method caches only after correctness and invalidation tests exist.

Acceptance gate: `examples/class_oop.rk` executes, visibility errors are source
diagnostics, inheritance/override tests pass, and GC traces object graphs.

## Milestone 5 - Modules, packages, and incremental compilation (P1)

Goal: imports resolve predictably and scale beyond one source file.

- Build a filesystem-independent source manager and module resolver with search
  paths, canonical module IDs, package roots, cycle diagnostics, and overlays.
- Collect explicit export/interface tables and bind imported symbols by stable
  IDs. Define initialization order and once-only module execution.
- Serialize versioned module interfaces and bytecode artifacts with checksums,
  target/profile/compiler keys, and safe deserialization limits.
- Add dependency graph invalidation and parallel compilation of independent
  modules with bounded memory use.

Acceptance gate: multi-package tests cover aliases, missing/private symbols,
cycles, mixed source-language profiles, cache hits, and selective invalidation.

## Milestone 6 - Async and concurrency (P1)

Goal: safe structured concurrency integrated with the VM and collector.

- Replace the current scheduler implementation before exposing it. Use stable
  heap-owned state, bounded queues, correct node ownership, condition-based
  parking, clean partial-init rollback, and deterministic shutdown.
- Implement tasks, futures, cancellation trees, channels, timers, and blocking
  work isolation first on a tested bounded executor.
- Add work stealing only after correctness tests; use per-worker deques and a
  global injection queue with race-tested ownership rules.
- Lower async functions and generators to explicit state machines with GC root,
  exception, cancellation, and debug metadata.
- Enforce send/share rules for mutable values and synchronize channel/future
  state. Add stress, shutdown, cancellation, and race tests.

Acceptance gate: scheduler stress tests run repeatedly without leaks, races,
lost tasks, hangs, or use-after-return; async stack traces retain logical Ravi
frames.

## Milestone 7 - Measured VM performance (P2)

Goal: improve speed using reproducible evidence, not isolated claims.

- Create versioned micro and macro benchmarks for startup, lex/parse/check,
  arithmetic, calls, closures, collections, exceptions, allocation/GC, modules,
  and concurrency. Record time, throughput, peak memory, allocations, GC pauses,
  and binary size.
- Establish performance budgets and a regression dashboard. Replace unrealistic
  examples such as the six-deep 400-iteration loop with bounded benchmarks.
- [x] Integrate the allocation-free dispatcher into `Vm.runValue` for its
  verified opcode subset with reference fallback and differential tests.
- ReleaseFast benchmark tooling now emits versioned JSON reports with timing
  distributions and reproducibility metadata, and can compare a run against a
  baseline with a configurable median-regression threshold. The standalone
  comparison report (`tools/compare_benchmark.ps1`) provides machine-readable
  historical comparisons; a hosted dashboard UI remains optional follow-up.
- [x] Redesign bytecode operands and instruction layout for compact decoding;
  retain the dispatcher contract while measuring this change.
- Profile before applying superinstructions, constant specialization, unboxed
  locals, string interning, faster hashing, inline call/property caches, or
  allocation fast paths.
- Preserve a simple reference execution mode for differential testing.

Acceptance gate: every optimization has correctness/differential tests and a
recorded improvement without unacceptable memory, startup, or debug regressions.

## Milestone 8 - HIR, MIR/SSA, and optimization (P2)

Goal: create the stable optimization and multi-backend boundary described by
the architecture.

- Define typed HIR from semantic AST with explicit guards, calls, closures,
  exception regions, and source/debug identities.
- Lower HIR into basic-block MIR with block parameters/SSA values, normal and
  exceptional edges, allocations, safepoints, root maps, and deoptimization
  metadata. Implement a verifier and textual golden format first.
- Make bytecode lowering consume verified MIR; retain AST-to-bytecode only as a
  temporary differential oracle, then remove it.
- Add constant folding, CFG simplification, dead-code elimination, guard
  elimination, escape analysis, unboxing, and monomorphic specialization one at
  a time with verifier checks after each pass.

Acceptance gate: optimized and unoptimized MIR are differentially equivalent,
and debug/source identities survive all enabled passes.

## Milestone 9 - Modern tooling (P2)

Goal: a productive editor and command-line experience.

- Add `ravi fmt`, canonical formatting, `ravi check --watch`, project manifests,
  deterministic configuration, and clear `--help`/version output.
- Build an incremental LSP over the source manager and lossless syntax tree:
  diagnostics, document symbols, hover, definition, references, completion,
  rename, semantic tokens, formatting, and code actions.
- Add DAP integration from Milestone 1, test it with LSP source overlays, and
  support task/thread views once async is implemented.
- Publish a stable machine-readable diagnostic/schema version for editors and
  build systems.

Acceptance gate: protocol tests cover incremental edits, cancellation, stale
results, malformed files, multi-module navigation, and both language profiles.

## Milestone 10 - Native backend (P3)

Goal: AOT compilation after MIR, runtime ABI, GC, and debug metadata are stable.

- Freeze a versioned internal ABI and target capability model.
- Implement x86_64 first through a proven object-emission path; add ARM64 after
  the backend contract is validated.
- Emit calls, control flow, stack maps, unwind/exception data, and platform debug
  information; link only required runtime components.
- Differentially test native output against the reference VM across the full
  conformance corpus. Track compile time, runtime, size, and memory.

Acceptance gate: native and VM behavior match, GC roots and exceptions survive
optimized code, source debugging works, and unsupported targets fail with a
structured diagnostic.

## Recommended immediate work order

1. Fix the false-green test runner and class example classification.
2. Compile/test every module and remove or relabel non-functional claims.
3. Implement source spans, structured diagnostics, real bytecode maps, and Ravi
   stack traces.
4. Unify runtime values and make the verifier control-flow aware.
5. Implement tracing GC and remove fixed-capacity object tables.
6. Complete AST-driven semantics, short-circuiting, chained comparisons, and
   exception unwinding.
7. Deliver classes, then modules, then safe async/concurrency.
8. Establish benchmarks before dispatcher/VM tuning.
9. Introduce HIR/MIR before native code generation.
10. Build LSP/DAP on the stable source, diagnostic, semantic, and debug models.
