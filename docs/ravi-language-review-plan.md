# Ravi Programming Language: Engineering Review and Remediation Plan

**Review scope:** repository state audited on 2026-08-13

**Important status:** this document is a technical plan only. No source code was changed for this review.

## 1. Executive Assessment

Ravi has a promising direction: a Kannada/English language profile system, a NaN-boxed runtime value, a bytecode VM, a collector abstraction, a scheduler, LSP/DAP foundations, HIR/MIR experiments, and a growing conformance corpus. The repository is further along than a prototype in breadth, but it is not yet a credible Python replacement, C++-speed static compiler, all-core runtime, or native compiler.

The central problem is not a missing optimization. The controlling architecture is incomplete:

1. Two compiler implementations exist, so the repository does not yet have one authoritative real compiler.
2. Semantic analysis is not yet the authoritative source of typing, names, captures, control flow, or lowering decisions.
3. HIR/MIR exists as a partial isolated subset and does not own compilation.
4. The bytecode verifier and runtime do not share one formally defined instruction-effect model.
5. The native backend is a placeholder and therefore there is currently no native near-C++ execution path.
6. The runtime still combines collector-managed objects with VM-owned tables and handle/index addressing.
7. Async/concurrency APIs exist, but language lowering, task ownership, blocking behavior, and scheduler correctness are not complete.
8. The static type system is currently a small name-to-kind mapper, not a sound gradual type system.
9. Performance claims are not yet supported by phase-level benchmarks, native comparisons, allocation data, or multi-core scaling measurements.

The right strategy is to remove the token/range compiler completely and make one verified, AST-driven, typed HIR/MIR pipeline the only compiler. Both bytecode and native execution must be built from verified MIR. Do not add more language features or micro-optimizations until the semantic and runtime contracts are frozen.

## 2. Evidence Baseline

The following repository claims are useful and should remain the current baseline, but they do not prove the final goals:

- `zig build test` and `test.ps1` pass the current 30-example corpus through the currently selected compiler paths, but this does not justify retaining two implementations.
- A fast dispatcher supports only a very small opcode subset: integer constants, addition, return, and halt.
- A non-moving mark/sweep collector, safepoints, roots, and write-barrier hooks exist.
- Module resolution, interface fingerprints, LSP framing, DAP adapters, packed bytecode, and benchmark reports exist in partial form.
- Classes, modules, async, native lowering, and complete gradual typing remain incomplete according to `progress.md` and `development-plan.md`.
- Existing bug history shows real defects in stack effects, capture detection, loop lowering, operator coverage, unary parsing, booleans, and expression-statement cleanup. This is evidence that invariant, conformance, and backend differential testing must remain mandatory after the compiler is unified.

The example corpus is an important smoke suite, not a language specification. It does not establish memory safety, type soundness, concurrency safety, native equivalence, ABI stability, package security, or performance superiority.

## 3. Priority Model

- **P0 correctness boundary:** a defect can silently produce wrong results, corrupt memory, violate ownership, accept invalid bytecode, or make the compiler non-deterministic.
- **P1 product completeness:** a public feature is parsed or advertised but not implemented as a complete semantic/runtime workflow.
- **P2 performance/scalability:** behavior works but cannot yet support the stated speed, memory, startup, or all-core claims.
- **P3 ecosystem and hardening:** packaging, compatibility, security, observability, fuzzing, and long-term maintenance.

Completion must be measured by acceptance tests and benchmark gates, not by the number of source files or documented intentions.

## 4. P0 Findings and Required Fixes

### 4.1 Remove the duplicate compiler and establish one real compiler

**Current issue:** `src/compiler/compiler.zig` contains a token/range compiler while `src/compiler/ast_compiler.zig` and `src/compiler/ast_statements.zig` provide a separate AST path selected by `--ast-compiler`. The same language behavior has already diverged between them. Keeping both makes a feature appear implemented when it works in only one path.

**Risk:** every new feature needs two implementations; fixes can pass one path and silently fail in the other; token shape can incorrectly control semantics; production behavior is ambiguous; maintenance cost and bug surface grow with every feature.

**Solution:** permanently select one pipeline: `source -> tokens -> lossless syntax -> AST -> semantic model -> HIR -> MIR -> backend`. The AST-to-HIR-to-MIR compiler is the real compiler. Completely remove the token/range compiler, its dispatch flag, its helper paths, and any compatibility logic. Do not retain it as a fallback, oracle, test-only compiler, or emergency path.

**Owning files/components:**

- `src/main.zig`: one production compilation entry point.
- `src/compiler/ast_compiler.zig`, `src/compiler/ast_statements.zig`: become the only compiler lowering implementation, then move their stable responsibilities into explicit frontend/HIR/MIR components.
- `src/compiler/compiler.zig`: delete completely, including all token-range code and helpers used only by it.
- `src/compiler/helpers.zig`, `src/compiler/expressions.zig`, `src/compiler/statements.zig`, and `src/compiler/calls.zig`: audit each symbol; delete token-based logic rather than preserving wrappers around it.
- New `src/frontend/`: canonical source-to-AST and AST-to-semantic pipeline.
- `tests/compiler_vm_tests.zig`: test the one compiler against the reference VM and supported backends; it must not compile through a second compiler.

**Algorithm:** assign stable AST node IDs and semantic symbol IDs; resolve names and types once; lower each construct once into typed HIR; lower verified HIR into CFG/SSA MIR; lower verified MIR into bytecode or native artifacts. Compiler decisions must use AST and semantic records only. No compiler phase may rescan tokens to rediscover meaning.

**Acceptance:** `--ast-compiler` is removed; the CLI has one compilation path; `src/compiler/compiler.zig` and token-range-only helpers are deleted; all examples and negative tests pass through the same compiler; optimized bytecode, unoptimized bytecode, and native artifacts are checked against the reference VM; no fallback compiler or legacy compatibility path remains in the build graph.

**Feature rule:** a feature is not implemented when it merely parses, type-checks, or has a partial lowering. A feature is complete only when the single compiler performs semantic analysis, emits verified HIR/MIR, produces an executable backend artifact, runs correctly in the VM/native target, reports correct diagnostics, preserves GC/debug metadata, and has positive, negative, resource-limit, and bilingual tests. Incomplete features must fail explicitly and must not be silently routed through an older implementation.

**Removal sequence:**

1. Finish the AST parser and semantic records needed by the next real feature.
2. Implement that feature once in AST/HIR/MIR and add its complete acceptance tests.
3. Route the CLI and test runner through that path only.
4. Delete the corresponding token-range implementation immediately; do not copy it into a new adapter.
5. Remove `--ast-compiler`, legacy-only imports, dead helpers, and build registrations.
6. Run repository-wide symbol and import checks to prove no production target references deleted compiler logic.

There is no compatibility compiler, token-based emergency path, feature-by-feature fallback, or second implementation. When the real compiler does not support a feature yet, compilation must return a precise unsupported-feature diagnostic. This keeps the implementation honest and ensures every newly added feature is real code in the one production pipeline.

### 4.2 Bytecode verification is not yet a complete formal contract

**Current issue:** `src/bytecode/verifier.zig` has both linear and control-flow stack analysis, but opcode effects are manually duplicated and at least known cases have disagreed with VM behavior. Function entry, locals, captures, exception handlers, calls, returns, suspension, constants, and metadata need a single complete model.

**Risk:** malformed or compiler-generated bytecode can underflow, use invalid locals, join at incompatible stack states, or corrupt exception/frame state.

**Solution:** define one `OpcodeSpec` table containing operand validation, stack inputs/outputs, local/capture effects, control-flow successors, handler effects, safepoint status, and result type behavior. Generate or reuse it in the verifier, disassembler, debugger, compiler checks, and VM dispatch assertions.

**Owning files/components:**

- New `src/bytecode/spec.zig`.
- `src/bytecode/verifier.zig`.
- `src/debug/debug.zig`.
- `src/vm/` dispatch and opcode handlers.
- New `tests/verifier_tests.zig` and malformed-bytecode fuzz target.

**Algorithm:** decode instructions; build basic blocks; propagate abstract state `(stack height/types, locals initialized, captures initialized, handler depth, resumable state)` to a fixed point; reject inconsistent joins; validate every reachable and metadata-referenced instruction; reject unreachable metadata that can be entered through a bad target. Model exceptional edges explicitly.

**Acceptance:** every opcode has one spec row and a stack-effect test; generated random bytecode never crashes the VM; invalid bytecode always returns a structured error before execution.

### 4.3 Runtime ownership is split between GC objects and VM tables

**Current issue:** `src/vm/vm.zig`, `src/vm/heap.zig`, `src/vm/object_storage.zig`, and `src/memory/gc.zig` expose both collector-managed records and arrays/counts/typed handle indexes. The collector currently tracks allocations by linear object search, and the value ABI includes both raw pointers and handles.

**Risk:** stale handles, incorrect roots, write-barrier omissions, object-table lifetime bugs, pointer canonicality assumptions, and poor scaling. A moving or concurrent collector cannot be introduced safely while runtime references are split.

**Solution:** choose one object identity model. Recommended: stable managed object pointers behind an object header and tracing descriptor, with `Value` holding a validated pointer/tag representation. If handles are required for moving GC or FFI, use generation-checked handles in a dedicated handle table and prohibit raw object pointers in `Value`.

**Owning files/components:**

- `src/vm/value.zig` and `src/vm/value_runtime.zig`: final ABI.
- `src/memory/gc.zig`: heap, pages, mark queue, roots, barriers, statistics.
- `src/vm/heap.zig`: object headers, payload destruction, trace descriptors.
- New `src/memory/handles.zig` only if the handle model is selected.
- `src/vm/object_storage.zig`: remove table ownership or make it the single handle owner.

**Algorithm:** segregated size classes for small objects, direct large-object lists, intrusive object headers, typed trace functions, precise root maps, remembered set for old-to-young references, and generation/version checks for handles. Replace linear `managed` scans with page metadata or hash-indexed allocation records.

**Acceptance:** cyclic graphs are reclaimed; stress GC passes every runtime test; stale references are detected; allocation, collection, live bytes, pause time, and fragmentation are measured; no object is reachable only through an unregistered VM table.

### 4.4 NaN-boxing and numeric semantics are underspecified

**Current issue:** `src/vm/value.zig` assumes a 48-bit integer payload and pointer payload/canonical address behavior. Float equality, NaN behavior, integer conversion, hashing, overflow, and FFI representation are only partly specified.

**Risk:** platform-dependent behavior, incorrect equality/hash contracts, silent overflow, inability to support future targets, and native/VM mismatches.

**Solution:** publish a versioned value ABI. Define exact integer range, float NaN policy, signed zero, numeric promotion, overflow behavior, pointer requirements, endianness, alignment, FFI conversion, and serialization rules. Use explicit checked/wrapping operations in MIR rather than relying on Zig arithmetic defaults.

**Owning files:** `src/vm/value.zig`, `src/types/type.zig`, new `src/runtime/numeric.zig`, `docs/runtime-abi.md`, `tests/runtime_value_tests.zig`.

**Acceptance:** exhaustive boundary tests, cross-target ABI tests where supported, equality/hash property tests, and VM/native execution-equivalence tests.

### 4.5 Runtime stack and frame effects are still fragile

**Current issue:** the repository history records stack leaks and verifier/VM mismatches for bare expressions and collection mutation. Several VM paths directly adjust `stack_top`, while call/exception/suspension transitions are distributed across modules.

**Solution:** define an explicit stack-effect contract for every instruction and a structured `StackCursor`/frame API. Compile expression statements according to the expression result contract, not token presence. Calls must return a declared effect even for mutating methods.

**Owning files:** `src/vm/stack_operations.zig`, `src/vm/frame_access.zig`, `src/vm/call_runtime.zig`, `src/vm/collection_mutation.zig`, `src/bytecode/spec.zig`.

**Acceptance:** stack height is identical at all CFG joins; every instruction has a runtime debug assertion against its spec; exception, return, break, continue, and cancellation paths pass stack-balance tests.

### 4.6 Exceptions, `finally`, cancellation, and suspension are not unified

**Current issue:** try/except, runtime faults, resumable markers, and scheduler cancellation are separate partial systems. A correct language must run cleanup exactly once on every transfer path.

**Solution:** represent normal and exceptional control flow explicitly in HIR/MIR. Lower cleanup regions to a common unwind protocol with reason values: normal exit, return, exception, break, continue, cancellation, and timeout. Store resumable frame state and precise GC roots at suspension points.

**Owning files:** `src/ir/hir.zig`, `src/ir/mir.zig`, new `src/ir/unwind.zig`, `src/vm/exceptions.zig`, `src/vm/control_flow.zig`, `src/runtime/scheduler.zig`.

**Acceptance:** cleanup ordering tests cover nested contexts and every transfer reason; logical Ravi stack traces survive await/yield; cancellation cannot skip cleanup or resume a completed frame.

## 5. P1 Language-System Findings

### 5.1 Gradual typing is not yet a complete type system

**Current issue:** `src/types/type.zig` maps a few names to a small enum. `src/semantic/analyzer.zig` performs limited declaration and array checks. Union/nullable types, generic types, structural collection types, function signatures, inference, narrowing, overloads, effects, ownership, and runtime conversion boundaries are absent or incomplete.

**Solution:** define a type algebra: primitive, literal, optional, union, tuple, array, map, set, function, class/protocol, type variable, dynamic, never, and error. Add a constraint solver and flow environment. Insert explicit `Guard`, `Box`, `Unbox`, `Convert`, and `Assume` operations into HIR. Define whether dynamic-to-static failures are exceptions or result values.

**Owning files:** `src/types/type.zig`, new `src/types/constraints.zig`, `src/types/inference.zig`, `src/semantic/flow.zig`, `src/semantic/analyzer.zig`, `src/ir/hir.zig`.

**Acceptance:** typed AST/HIR goldens, negative diagnostics, branch narrowing tests, generic/function variance tests, and runtime guard tests. A static function must not silently execute a dynamic operation.

### 5.2 Name resolution and captures need a canonical symbol graph

**Current issue:** prior capture defects show that capture detection was duplicated and sensitive to flat statement ordering. Scope data currently stores names and basic types but not a complete symbol identity/import/export graph.

**Solution:** resolve declarations, references, captures, imports, classes, methods, and closure cells into immutable symbol IDs before lowering. Represent lexical scopes as a tree with explicit visibility and declaration phases. Do not infer parent scopes from array indexes.

**Files:** new `src/semantic/symbols.zig`, `src/semantic/scopes.zig`, `src/semantic/resolution.zig`, `src/modules/loader.zig`, compiler lowering modules.

**Acceptance:** nested closure, shadowing, forward declaration, recursion, import alias, private access, and mutation-of-capture tests.

### 5.3 Parser and syntax architecture need completion

**Current issue:** intended lossless syntax, recovery, canonical language profiles, indentation rules, and formatter behavior are documented, but feature coverage and malformed-input guarantees remain incomplete.

**Solution:** make lexer output immutable spans and profile-neutral token IDs; make parser recovery produce lossless nodes with explicit error nodes; lower only valid semantic constructs. Centralize precedence and grammar tables. Add parser fuzzing and round-trip formatter tests.

**Files:** `src/lexer/lexer.zig`, `src/parser/parser.zig`, `src/parser/precedence.zig`, `src/syntax/`, `src/formatter/`.

**Acceptance:** no parser panic on arbitrary bytes; deterministic diagnostics; format(parse(format(source))) is stable; Kannada and English profiles produce identical canonical ASTs.

### 5.4 Classes and object contracts are incomplete

**Current issue:** class construction and method dispatch have partial support, but inheritance, visibility, overrides, `super`, layout evolution, and GC tracing need a complete contract.

**Solution:** add semantic class declarations with base validation, method signatures, override checks, sealed/final policy, visibility lattice, stable shape IDs, and explicit property operations. Start with fixed layouts and dictionary fallback; add caches only after invalidation tests.

**Files:** `src/semantic/classes.zig`, `src/runtime/object_model.zig`, `src/bytecode/spec.zig`, `src/vm/dispatch.zig`, `src/vm/object_storage.zig`.

**Acceptance:** inheritance, override mismatch, protected/private, constructor failure, property mutation, method cache invalidation, and GC cycle tests.

### 5.5 Core features are advertised before their full semantics exist

Known incomplete areas include iterator protocol, generators, decorators, context managers, rich formatting/interpolation, Unicode operations, module globals, persistent artifacts, and complete async lowering.

**Solution:** maintain a generated feature matrix with states `designed`, `parsed`, `analyzed`, `lowered`, `executed`, `tested`. A feature cannot be listed as supported or included in the default examples until every required state is complete.

**Owning files:** `docs/requirements.md`, `progress.md`, new `config/feature-matrix.json`, tests grouped by feature.

## 6. P1 Module, Tooling, and Compatibility Findings

### 6.1 Module loading is not yet a complete package system

**Current issue:** resolution and interface fingerprints exist, but shared globals, once-only initialization, artifact validation, invalidation, parallel compilation, and package boundaries remain incomplete.

**Solution:** define canonical module IDs, package roots, explicit exports, initialization SCC handling, versioned interface schemas, content-addressed artifacts, dependency fingerprints, and deterministic topological scheduling.

**Files:** `src/modules/resolver.zig`, `src/modules/loader.zig`, `src/modules/artifact.zig`, `src/modules/cache.zig`, new `src/modules/graph.zig`.

**Acceptance:** alias/private/missing import, cycles, profile mixing, cache hit/miss, selective invalidation, and parallel build tests.

### 6.2 LSP/DAP are transport foundations, not complete developer tooling

**Issue:** framing and several requests exist, but semantic features depend on the authoritative source manager, incremental syntax tree, symbol graph, and stable diagnostics.

**Solution:** complete compiler services over shared immutable snapshots. Add cancellation, stale-result rejection, workspace module graphs, hover types, definition, references, completion, semantic tokens, formatting, rename, and code actions.

**Files:** `src/lsp/`, `src/source/source.zig`, `src/diagnostics/`, semantic service layer.

### 6.3 Versioning, FFI, package security, and reproducibility need explicit contracts

Add source editions, compiler/version keys, bytecode and interface schemas, target/ABI IDs, generated typed FFI bindings, ownership rules at FFI boundaries, locked dependency hashes, capability-restricted build scripts, reproducible artifact metadata, and deterministic diagnostics.

**Files:** new `src/project/`, `src/ffi/`, `src/security/`, `docs/runtime-abi.md`, `docs/requirements.md`.

## 7. P1 Concurrency and Parallelism Findings

### 7.1 Scheduler behavior is not yet a complete all-core execution model

**Current issue:** `src/concurrency/scheduler.zig` contains bounded queues, futures, channels, and thread state, but timeout waiting uses repeated yielding, channel receive removes from the front of an array, and work stealing/language-level async lowering are incomplete.

**Solution:** define structured concurrency first. Use condition/event-based parking, cancellation trees, task ownership, bounded admission, timer wheel or deadline heap, and per-worker queues. Add work stealing only after race tests pass. Use a ring buffer for channels and explicit wait queues for full/empty states.

**Files:** `src/concurrency/scheduler.zig`, new `src/concurrency/task.zig`, `future.zig`, `channel.zig`, `executor.zig`, `timer.zig`, `src/runtime/scheduler.zig`.

**Acceptance:** repeated stress tests under ThreadSanitizer-equivalent tooling where available, deterministic executor tests, no lost tasks, no hangs, bounded shutdown, cancellation propagation, backpressure, and measured scaling across 1/2/4/8 workers.

### 7.2 Shared mutable values need ownership and send/share rules

No-GIL execution is not enough. Add immutable-share, move/send, synchronized-share, and unsafe-FFI capabilities to the type system. Dynamic crossings must perform runtime checks or reject the operation.

**Acceptance:** compile-time rejection of illegal sends, runtime checks for dynamic values, race-focused collection tests, and explicit lock-order diagnostics for low-level synchronization.

## 8. P2 Performance and Native Backend Findings

### 8.1 There is no native backend yet

`src/backend/backend.zig` supports bytecode and intentionally rejects native targets. `src/ir/mir_bytecode.zig` only lowers a straight-line integer subset. Therefore Ravi cannot currently claim near-C++ static performance.

**Required order:**

1. Finish typed HIR and CFG/SSA MIR.
2. Add MIR verifier, deoptimization metadata, safepoints, root maps, and exception edges.
3. Make bytecode lowering consume MIR.
4. Implement native x86_64 lowering through a proven object-emission path or a well-defined external backend interface.
5. Add ABI calls, stack maps, unwind data, debug info, linking, and runtime reachability stripping.
6. Add ARM64 only after x86_64 equivalence is stable.

**Files:** `src/ir/`, `src/backend/backend.zig`, new `src/backend/native/`, `src/backend/abi.zig`, `src/backend/object.zig`, `docs/runtime-abi.md`.

**Acceptance:** native output is behaviorally identical to reference VM across the conformance corpus, including GC, exceptions, classes, async, and FFI; unsupported targets fail clearly.

### 8.2 VM fast path is too narrow to establish performance claims

`src/vm/dispatch.zig` currently specializes only a tiny integer subset. It is a useful probe, not a production tier.

**Solution:** first improve the reference VM with table-driven or direct-threaded dispatch and specialized handlers generated from opcode specs. Then add profiling counters, hot-loop detection, inline caches, monomorphic/polymorphic call caches, unboxed locals, allocation fast paths, and guarded specialization only where benchmarks justify them.

**Rule:** no optimization may bypass verifier semantics, GC safepoints, debugger metadata, or exception behavior.

### 8.3 Optimizer is bytecode-local and currently fragile

`src/optimizer/optimizer.zig` rewrites instruction arrays and manually adjusts jump/function offsets. This does not scale to CFG optimization, source mapping, exception regions, or SSA reasoning.

**Solution:** move optimization to MIR: constant folding, CFG simplification, dead code elimination, dominator analysis, range/type propagation, guard elimination, escape analysis, scalar replacement, and specialization. Lower only after optimization. Preserve source identities and deoptimization maps.

**Acceptance:** optimized and unoptimized artifacts execute equivalently in the same compiler pipeline, property tests cover each pass, source mapping remains stable, and benchmark regressions are blocked in CI.

### 8.4 Benchmarking does not yet measure the stated goals

Add independent measurements for startup, frontend, type checking, compilation, calls, closures, collections, exceptions, allocation, GC pauses, peak memory, binary size, native runtime, VM runtime, and parallel scaling. Use distributions, pinned workloads, warmups, CPU/environment metadata, and noise thresholds.

**Files:** `tools/benchmark.ps1`, `tools/compare_benchmark.ps1`, `config/performance-budgets.json`, new `benchmarks/` corpus and report schema.

**Acceptance:** every performance claim has a reproducible baseline, confidence interval or stable percentile, and a comparison against Python and an appropriate native baseline. Claims must state workload and memory conditions.

## 9. Recommended Repository Structure

Use component boundaries with one direction of dependency:

```text
src/
  config/                 constants, validated compiler/runtime config
  source/                 immutable sources, spans, line indexes, snapshots
  lexer/                  profile-neutral tokens and scanning
  syntax/                 lossless tree and recovery
  parser/                 grammar and Pratt expression parser
  ast/                    compact semantic syntax nodes
  semantic/
    symbols.zig           declaration and symbol identity
    resolution.zig        names, imports, captures
    types.zig             type algebra and constraints
    flow.zig              narrowing and control-flow facts
    classes.zig           class contracts and layouts
  ir/
    hir.zig               typed structured IR
    mir.zig               CFG/SSA, effects, exceptions, safepoints
    verify.zig            IR invariants
    passes/                independently tested optimizations
  bytecode/               opcode spec, encoding, verifier, lowering
  backend/
    bytecode/             bytecode artifact emission
    native/               target lowering and object emission
    abi.zig               versioned runtime ABI
  runtime/
    value/                scalar ABI and numeric semantics
    objects/               headers, layouts, tracing
    gc/                    allocator, collector, barriers
    scheduler/             tasks, futures, channels, timers
    io/                    OS and async adapters
    ffi/                   explicit unsafe boundary
  vm/                     reference execution and generated handlers
  modules/                resolver, graph, interfaces, artifacts, cache
  tooling/                diagnostics, formatter, LSP, DAP, debugger
  cli/                    command parsing and process policy
```

Rules:

- Frontend components never import VM or filesystem implementation details.
- Semantic analysis never rescans source tokens to rediscover meaning.
- Backends consume verified MIR only.
- Runtime objects are allocated through one memory interface.
- CLI code does not implement compiler semantics or runtime policy.
- Every public component has a narrow input/output contract and allocator ownership rules.

## 10. Delivery Plan

### Phase A: Trust boundary, 4-6 weeks

Freeze feature additions. Complete opcode specification, verifier, source spans, diagnostics, stack/frame contracts, malformed-input fuzzing, allocation-failure tests, and the generated feature matrix. Make all tests run in Debug, ReleaseSafe, and ReleaseFast.

### Phase B: One frontend, 4-8 weeks

Make the AST and semantic analysis pipeline authoritative immediately. Implement symbol IDs, full scope resolution, captures, control flow, and the first usable gradual type algebra. Route the CLI through this single path, delete the legacy compiler and `--ast-compiler` switch, and repair every feature directly in the real compiler.

### Phase C: Runtime ownership, 4-8 weeks

Select pointer or generation-checked handle identity, remove duplicate object tables, finish precise roots and object descriptors, harden barriers, replace linear collector metadata, and complete exception/suspension unwind semantics.

### Phase D: Complete core semantics, 6-10 weeks

Implement unions/optionals, iterator/generator state machines, context cleanup, decorators under a declared effect model, class contracts, module initialization/globals, and Unicode/string semantics. Each feature requires semantic, bytecode, VM, GC, diagnostics, and bilingual tests.

### Phase E: Concurrency, 6-10 weeks

Finish structured async lowering, cancellation, timers, channels, bounded executor behavior, ownership/send rules, deterministic scheduler tests, and measured multi-core scaling. Do not advertise all-core efficiency until this phase passes stress and scaling gates.

### Phase F: MIR optimization and native, 10-20 weeks

Finish CFG/SSA MIR, verified lowering, optimization passes, x86_64 native backend, runtime ABI, stack maps, exceptions, GC integration, debug info, and VM/native differential testing.

### Phase G: Ecosystem hardening, ongoing

Complete package manifests, lockfiles, artifact cache, FFI generator, security capabilities, LSP/DAP semantic services, compatibility editions, fuzzing, crash reporting, release engineering, and documentation generated from the feature matrix.

## 11. Definition of Done

Ravi is ready for a serious 1.0 performance claim only when all of these are true:

- One compiler pipeline is authoritative and all backends consume verified MIR.
- The type system has documented soundness boundaries for static, dynamic, and FFI code.
- The VM, verifier, debugger, disassembler, and compiler share one opcode contract.
- Managed objects have one ownership/identity model and complete precise tracing.
- Exceptions, `finally`, cancellation, generators, and async suspension share one unwind model.
- Classes, modules, imports, packages, and artifacts have versioned contracts.
- Native and VM executions pass execution-equivalence conformance tests from the same compiler and verified MIR.
- Multi-core benchmarks demonstrate scaling on specified workloads without data races.
- Python comparisons use equivalent workloads and include startup, memory, and throughput.
- Every documented feature is represented in the generated feature matrix and acceptance suite.
- Release builds are reproducible, dependency identities are locked, diagnostics are stable, and unsupported targets/features fail explicitly.

The goal should be stated precisely: Ravi can be faster than Python for workloads where specialization, lower runtime overhead, native compilation, or parallel execution applies. It cannot eliminate fundamental tradeoffs, and it should not claim to have done so. The engineering target is a language with explicit costs, verified semantics, predictable performance, and replaceable micro-components.
