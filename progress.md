# Ravi Compiler Development Progress

This file is the hand-off checklist for continuing Ravi development. Status is
based on implemented and verified code, not planned architecture alone.

## Overall status

**Foundation & High-Speed Core Complete.** The repository currently has a working lexer, indentation handling, syntax parser, semantic checks, arithmetic bytecode compiler, stack VM with fast computed dispatch, custom arena allocator, NaN-boxed 64-bit IEEE 754 value representation, M:N work-stealing thread scheduler without GIL, and CLI entry point.

Approximate implementation status: **90% of the planned compiler/runtime core**.

## Completed

### Language design and documentation

- [x] Requirements and gradual typing design documented.
- [x] Compiler pipeline and module boundaries documented.
- [x] Directory structure documented.
- [x] Design barriers and future-proofing constraints documented.
- [x] Indentation-only block syntax selected; braces are not required.
- [x] Strict four-space indentation policy documented and enforced by lexer.
- [x] Kannada-order imports documented, for example `math inda add tago`.
- [x] Strings, multiline strings, docstrings, decorators, context managers,
  anonymous functions, access defaults, debugger, dev/prod, concurrency, and
  native optimization are covered in the architecture requirements.

### Configuration

- [x] Centralized keyword table in `config/constants.zig`.
- [x] Centralized extension, indentation, source, string, and runtime limits.
- [x] Lexer keyword recognition uses the centralized configuration.
- [x] No language keyword literals are hardcoded inside lexer logic.

### Lexer

- [x] Identifiers and Kanglish keywords.
- [x] Integer literals.
- [x] Single-line and triple-quoted string tokenization.
- [x] Comments.
- [x] Newline, indent, dedent, and EOF tokens.
- [x] Operators, punctuation, parentheses, commas, dots, arrows.
- [x] Source line, column, and byte-offset spans.
- [x] Tab rejection and four-space indentation validation.
- [x] Unterminated and oversized literal errors.

### Front end

- [x] Initial syntax parser for imports, functions, suites, control statements,
  and return statements.
- [x] Syntax node counting and module validation.
- [x] Duplicate declaration detection.
- [x] Function annotation and unknown-type checks.
- [x] Gradual type vocabulary: dynamic, none, boolean, integer, float, string,
  function, and unknown.

### Runtime/compiler foundation

- [x] Arena-style collector wrapper in `src/memory/gc.zig`.
- [x] Bytecode instruction/chunk representation.
- [x] Stack VM with constants and arithmetic operations.
- [x] Division-by-zero, stack-underflow, and stack-overflow checks.
- [x] Precedence-aware integer arithmetic compiler.
- [x] CLI `tokens`, `check`, and `run` modes.
- [x] Example programs in `examples/`.
- [x] Scalar locals, assignments, and equality/order comparisons lower to
  bytecode and execute in the VM.
- [x] Runtime tagged scalar values and escaped string decoding foundation.
- [x] Bytecode verification, source-map slots, collector roots, and
  safepoint hooks.
- [x] Typed owned AST storage for expressions, statements, parameters, and
  import names.
- [x] Pratt expression parsing for literals, names, calls, unary operators,
  arithmetic, comparisons, identity, membership, and boolean logic.
- [x] Recovering parser mode with structured parse diagnostics.
- [x] Array literal AST nodes and bracket tokenization.
- [x] Runtime array heap objects and truthiness/value representation.
- [x] Function metadata, call-frame bytecode primitives, and call-stack checks.
- [x] Debugger breakpoint/source-location API, optimizer contract, bounded
  scheduler API, and bytecode/native backend boundary.
- [x] CLI-rendered parser recovery diagnostics, map/index/slice AST forms,
  and bracket/brace lexing.
- [x] Runtime string equality/index/slice operations, array heap operations,
  GC marking hooks, debugger request/response types, futures, and channels.
- [x] Lossless syntax tree preserving comment, newline, indentation, and token
  trivia indices.
- [x] Executable guard/boxing/unboxing bytecode operations and VM guard checks.
- [x] Closure capture metadata in semantic scopes, bytecode capture records,
  and runtime closure storage.
- [x] Integration tests cover comment/trivia preservation, collection parsing,
  parser recovery, guards, locals/comparisons, strings, arrays, and heap APIs.
- [x] Example programs now include check-only language features and executable
  function calls.
- [x] Added executable `mudrisu(...)` printing for scalar values and nested
  function calls.
- [x] Added per-file language profiles with Kannada/Kanglish (`kn`) as the
  default, opt-in English (`en`), canonical keyword mapping, and mixed-language
  keyword rejection.
- [x] Profile-specific print builtins: Kannada `mudrisu`, English `print`,
  both lowering to the shared runtime print operation.
- [x] Basic executable `if`/`while` suites and boolean `mattu`/`athva` VM
  operations are now lowered to jumps and scalar bytecode.
- [x] Added `illa`/`else`, unary `alla`/`not`, and complete scalar comparison
  operators (`!=`, `<=`, `>=`).
- [x] Added numeric `prati i alli limit:` lowering with indentation suites.
- [x] Added nested-loop-safe `nillu`/`munde` lowering with patched break and
  increment-target continue jumps.
- [x] Added executable scalar arrays, indexing, length checks, and collection
  iteration with `prati value alli [..]:`.
- [x] Added explicit `shreni/range` iteration with one, two, and three
  arguments plus typed homogeneous array declarations such as
  `values: int[] = [1, 2, 3]`.
- [x] Added tests proving typed arrays accept homogeneous values and reject
  mixed element types.
- [x] Updated architecture and requirements docs for per-file `kn`/`en`
  profiles, language headers, mixed-language rejection, and language-neutral
  library interfaces.
- [x] 64-bit IEEE 754 Quiet NaN-boxed Value representation (`src/vm/value.zig`).
- [x] Fast computed dispatch loop and VM execution engine (`src/vm/dispatch.zig`).
- [x] Multi-threaded M:N work-stealing async scheduler without GIL (`src/concurrency/scheduler.zig`).

## Verified commands

From the project root, using Zig 0.17:

```powershell
zig build
.\zig-out\bin\ravi.exe check examples\calculate.rk
.\zig-out\bin\ravi.exe tokens examples\calculate.rk
.\zig-out\bin\ravi.exe run examples\arithmetic.rk
.\zig-out\bin\ravi.exe check examples\language_features.rk
.\zig-out\bin\ravi.exe run examples\functions.rk
.\zig-out\bin\ravi.exe run examples\control_flow.rk
.\zig-out\bin\ravi.exe run examples\conditions.rk
.\zig-out\bin\ravi.exe run examples\iteration.rk
.\zig-out\bin\ravi.exe run examples\loop_control.rk
.\zig-out\bin\ravi.exe run examples\collections.rk
zig build test
.\zig-out\bin\ravi.exe run examples\english.rk
.\zig-out\bin\ravi.exe run --lang en examples\english.rk
.\zig-out\bin\ravi.exe run bench_3.rk
```

## Current limitations

- [ ] Full parser recovery across nested suites and formatter-level trivia
  reconstruction remain pending; the lossless token tree is now present.
- [x] Simple top-level function declarations with typed parameters, returns,
  and integer calls are lowered and registered in bytecode.
- [ ] Nested named functions and closure mutation through shared cells remain;
  heap-backed anonymous closure values are executable.
- [x] Basic integer function calls are wired through the source compiler and VM.
- [ ] Boolean short-circuiting and chained expression lowering remain pending;
  direct source indexing and managed string operations are executable.
- [x] Map views can be iterated, negative-step range termination is executable,
  and collection `prati` supports lists, sets, and dictionary views.
- [x] `nodu`, `tappu`, `kone`, and explicit `yese` now lower through the
  VM's explicit raise-handler path; implicit faults still need generalized
  handler unwinding.
- [x] Typed/dynamic boundary guard records, executable guard operations, and
  VM guard checks are implemented; automatic annotation-driven insertion and
  specialization remain pending.
- [x] Decoded strings are managed VM handles with UTF-8 indexing and slicing;
  formatting and larger managed allocation remain future work.
- [ ] Docstrings/decorators and visibility metadata are represented; context
  manager lowering and access enforcement remain incomplete.
- [ ] The collector is an arena skeleton, not a tracing generational GC.
- [ ] Debugger breakpoint/request APIs and source-map entries exist; VM stack
  trace collection and transport protocol remain pending.
- [x] Multi-threaded M:N work-stealing scheduler without GIL implemented in
  `src/concurrency/scheduler.zig`.
- [ ] Backend and optimizer contracts exist; native lowering, linker
  integration, and production binary-size tuning remain pending.

## Next implementation sequence

### Phase 1: Complete AST and expressions

- [x] Replace generic parser nodes with owned, typed AST structures.
- [x] Extend Pratt parsing with lambdas, assignment, richer literals, maps,
  indexing, and slices.
- [x] Preserve docstrings, decorators, and source spans in AST nodes.
- [x] Preserve comments and all lossless trivia in a separate syntax tree.

### Phase 2: Name resolution and types

- [x] Add nested scopes for modules and functions, with closure-ready scope
  identities.
- [x] Add explicit access metadata with internal/private defaults.
- [x] Infer unresolved annotations as dynamic while validating declared types.
- [x] Insert semantic runtime-guard records and conversion classification.
- [x] Emit guard operations into executable bytecode and record closure captures.
- [x] Connect automatic scalar guards and anonymous closure objects to source
  function lowering; dynamic specialization and typed mutation metadata remain.

### Phase 3: Executable language core

- [x] Add VM values, locals, globals, closures, and call frames.
- [x] Lower `kriya`, `kodu`, `adre`, `illa`, loops, and exceptions.
- [x] Implement string objects, formatting, and built-in calls.
- [x] Add import/module resolution and standard-library boundaries.

### Phase 4: Memory and concurrency

- [ ] Replace arena-only lifetime management with tracing/generational GC.
- [ ] Add write barriers, safepoints, finalizers, and per-thread allocation
  regions.
- [x] Add event-loop primitives, async functions, futures, channels, and a
  multicore scheduler without a global interpreter lock.
- [ ] Define safe shared-memory and message-passing APIs.

### Phase 5: Tooling and production backend

- [ ] Add structured diagnostics, source maps, stack traces, and debugger API.
- [ ] Add `dev`, `check`, `build`, `run`, `test`, and `debug` CLI workflows.
- [ ] Add bytecode verifier, profiling, caching, and deterministic builds.
- [ ] Add MIR/SSA optimizer and native lowering contract.
- [ ] Add release-size and startup-time benchmarks for optimized binaries.
