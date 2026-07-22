# Ravi Compiler Development Progress

This file is the hand-off checklist for continuing Ravi development. Status is
based on implemented and verified code, not planned architecture alone.

## Overall status

**Foundation complete; executable language core in progress.** The repository
currently has a working lexer, indentation handling, syntax parser, semantic
checks, arithmetic bytecode compiler, stack VM, custom arena allocator, and CLI
entry point. The architecture documents describe a larger target than the
currently implemented subset.

Approximate implementation status: **45% of the planned compiler/runtime**.

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
.\zig-out\bin\ravi.exe run examples\english.rk
zig build test
zig build test
zig fmt --check src build.zig config
```

Language selection examples:

```powershell
.\zig-out\bin\ravi.exe run --lang en examples\english.rk
.\zig-out\bin\ravi.exe check examples\calculate.rk
```

Expected important results:

```text
valid Ravi module: 10 syntax nodes
7
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
- [ ] Bounded scheduler, futures, and channels exist; async event loops,
  work-stealing, and multicore execution remain pending.
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

- [ ] Add VM values, locals, globals, closures, and call frames.
- [ ] Lower `kriya`, `kodu`, `adre`, `illa`, loops, and exceptions.
- [ ] Implement string objects, formatting, and built-in calls.
- [ ] Add import/module resolution and standard-library boundaries.

### Phase 4: Memory and concurrency

- [ ] Replace arena-only lifetime management with tracing/generational GC.
- [ ] Add write barriers, safepoints, finalizers, and per-thread allocation
  regions.
- [ ] Add event-loop primitives, async functions, futures, channels, and a
  multicore scheduler without a global interpreter lock.
- [ ] Define safe shared-memory and message-passing APIs.

### Phase 5: Tooling and production backend

- [ ] Add structured diagnostics, source maps, stack traces, and debugger API.
- [ ] Add `dev`, `check`, `build`, `run`, `test`, and `debug` CLI workflows.
- [ ] Add bytecode verifier, profiling, caching, and deterministic builds.
- [ ] Add MIR/SSA optimizer and native lowering contract.
- [ ] Add release-size and startup-time benchmarks for optimized binaries.

## How to continue

Start with **Phase 1**, then update this file after each verified milestone.
Every completed item should include a test or command in the “Verified
commands” section. Keep architecture-only features in the pending lists until
they have executable code and tests.

- [x] Added executable tuple, set, and dictionary literals, collection handles, dictionary lookup, and a typed/dynamic collection example.

- [x] Parser now recognizes tuple and set literals in addition to existing maps.
- [x] Split VM collection storage and mutation primitives into reusable
  `src/vm/collections.zig`; runtime heap collections expose append, insert,
  pop, remove, clear, and contains operations.
- [x] Added bilingual source methods for collection append, contains, and clear:
  Kannada `serisu`, `olagide`, `khaali`; English `append`, `contains`, `clear`.
- [x] Added executable bilingual list insertion/removal: Kannada `haku`,
  `tegi`; English `insert`, `remove`.
- [x] Fixed comma-separated collection method arguments in the source compiler
  and aligned verifier stack effects with VM collection consumption.
- [x] Added regression coverage for ordered array mutation and dictionary
  update/remove primitives; verified Kannada and English collection examples.
- [x] Added executable list methods `kithu/pop`, `enisu/count`,
  `jodisu/sort`, and `ultha/reverse`, with VM opcodes, verifier effects,
  bilingual mappings, examples, and source-level tests.
- [x] Split collection tests into `tests/collection_tests.zig`; core tests
  remain focused on lexer, parser, semantic, compiler, and VM fundamentals.
- [x] Reworked runnable examples with explanatory comments and separate
  typed, dynamic, control-flow, function, language-profile, and collection
  demonstrations.
- [x] Replaced VM dictionary linear scans with reusable open-addressed hash
  storage, including collision-safe lookup and cluster repair after deletion.
  Existing dictionary literals and indexing remain compatible.
- [x] Added executable dictionary `tago/get`, `badala/update`, and
  `tegi/pop`/membership behavior through the shared hashed VM storage.
- [x] Added dictionary views `kili/keys`, `bele/values`, and `jodi/items`;
  `items()` is represented as a flat alternating key/value collection.
- [x] Added keyed English dictionary `pop(key)` and consistent missing-key
  behavior through the hashed storage primitive.
- [x] Set literals now remove duplicates and support `koodu/union`,
  `ondu/intersection`, and `bere/difference` with collection iteration.
- [x] Range loops now select ascending or descending termination from their
  step, including negative steps.
- [x] Added managed VM string handles for decoded literals, byte indexing,
  concatenation, equality, printing, and `gatra/length`.
- [x] Added managed string `chikku/lower`, `doddu/upper`, and `kadi/strip`
  operations with bilingual source mappings.
- [x] Added named function values and indirect calls with arity validation;
  `examples/function_values.rk` and a core regression test cover the path.
- [x] Added trailing positional numeric defaults for function calls, with
  validation that required parameters cannot be omitted.
- [x] Added keyword argument normalization by declared parameter name,
  including duplicate, unknown, ordering, and required-argument validation.
- [x] Added `*values` and `**options` function parameters; calls pack extra
  positional values into tuples and extra keywords into dictionaries.
- [x] Added bilingual runtime type queries and UTF-8 code-point indexing for
  managed source strings.
- [x] Added managed string split, join, replace, and find operations with
  bilingual source mappings.
- [x] Added source-level list and dictionary index assignment with shared VM
  `store_index` behavior.
- [x] Added capture-free anonymous `kriya(...) => expression` function values;
  captured closures remain in the next runtime environment batch.
- [x] Added heap-backed closure handles, captured lambda variables, and
  `load_capture` frame storage; closure values survive their creating scope.
- [x] Added executable `[start:end]` slices for arrays and UTF-8 strings.
- [x] Added automatic integer/boolean/string parameter guards at call sites.
- [x] Added explicit `yese` raise values, `nodu`/`tappu` handler bytecode,
  `kone` finally sequencing, and VM function trace frames.
- [x] Added closure and exception examples plus runtime feature documentation.
- [x] Added nested named-function lowering with captured enclosing parameters.
- [x] Extracted UTF-8 string primitives and VM trace frame contracts into
  independently testable `src/vm/strings.zig` and `src/vm/trace.zig` modules.
- [x] Added independent UTF-8 runtime tests to the build test graph.
- [x] Added shared closure cells, captured assignment, and nested closure
  mutation tests.
- [x] Routed division runtime faults through active `tappu` handlers.
- [x] Extracted compiler operator and precedence helpers into
  `src/compiler/expressions.zig` with independent tests.
- [x] Added runtime-fault and closure-cell examples.
- [x] Explicitly excluded method/function overloading from the Ravi design;
  protocols and distinct method names remain the preferred polymorphism model.
- [x] Added dedicated dictionary, set, string, and English-profile regression
  tests; `examples/strings.rk` demonstrates the managed string path.
- [x] CLI recovery diagnostics now render source line, column, and token span.
- [ ] Managed source strings, closure objects, anonymous-function execution,
  and exception handlers still require a value-stack/compiler redesign; the
  runtime `Value` and AST foundations remain in place.

## Source modularization

- Added shared compiler models and reusable token/name/suite helpers.
- Extracted compiler call lowering and bilingual builtin dispatch helpers;
  these are compile-time/static helpers and add no runtime dispatch overhead.
- Extracted parser precedence handling and VM runtime type classification;
  both remain allocation-free and statically dispatched.
- Extracted VM stack/fault/string-table state helpers with static generic
  calls; VM representation and hot opcode dispatch remain unchanged.
- Routed VM function and closure calls through `call_runtime.zig`; frame
  layout and call semantics remain unchanged.
- Removed the old duplicate compiler call/helper bodies and VM call-frame
  bodies after validation; compiler and VM coordinators are materially smaller.
- Fixed nested `prati ... shreni(...)` loops by giving each loop a private
  cursor/step slot; repeated user variables such as nested `i` now behave
  independently. Added a regression test.
- Added dedicated VM error/type and call-frame/closure record modules.
- Added `docs/source-layout.md` and `tools/check_src_sizes.ps1` for the
  200–300 line module target.
- Existing compiler, VM, and parser coordinators remain above the target and
  are scheduled for responsibility-based extraction; behavior is preserved
  while those boundaries are introduced.
