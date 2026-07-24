# Ravi Compiler Development Progress

This file is the hand-off checklist for continuing Ravi development. Status is
based on implemented and verified code, not planned architecture alone.

## Overall status

**Foundation executable; production runtime and tooling are in progress.** The
lexer, parser, basic semantic checks, bytecode compiler, reference stack VM, and
CLI execute the tested language subset. Completion is tracked by verified stage
rather than a single percentage, because several architectural modules are
scaffolds or are not yet integrated into the reference execution path.

| Area | Designed | Parsed | Analyzed | Lowered | Executed | Directly tested |
|---|---:|---:|---:|---:|---:|---:|
| Scalar expressions/control flow | yes | yes | partial | yes | yes | yes |
| Functions/defaults/closures | yes | yes | partial | yes | yes | yes |
| Collections/managed strings | yes | yes | partial | yes | yes | yes |
| Exceptions | yes | yes | partial | partial | partial | yes |
| Classes/objects | yes | basic | basic | basic | basic | yes |
| Modules/import linking | yes | yes | graph/interface | partial | partial | resolver/loader/CLI |
| Tracing GC | yes | n/a | n/a | n/a | partial | yes |
| Async/concurrency | yes | no | no | no | executor API only | yes |
| HIR/MIR/native backend | yes | n/a | n/a | HIR to MIR | no | IR verifier/passes |
| LSP/DAP | yes | n/a | n/a | state APIs | no | protocol primitives |

The production VM now executes with the NaN-boxed `Value` ABI and typed handles;
the public `run` method keeps an `i64` compatibility result for existing CLI
callers while `runValue` exposes the full representation. The reference tagged
union in `src/runtime/value.zig` remains a compatibility/scaffolding module and
should be removed or aliased after downstream users migrate. The VM is not yet
connected to the separately tested reclaiming mark-sweep collector. The scheduler is a bounded,
synchronized
executor with stable heap-owned worker state; work stealing and language-level
async lowering remain pending.

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

- [x] Standalone non-moving mark-sweep collector in `src/memory/gc.zig`.
- [x] Bytecode instruction/chunk representation.
- [x] Stack VM with constants, arithmetic operations, and dynamically growing
  operand/call/trace stacks.
- [x] Division-by-zero and stack-underflow checks.
- [x] Precedence-aware integer arithmetic compiler.
- [x] CLI `tokens`, `check`, and `run` modes.
- [x] Example programs in `examples/`.
- [x] Scalar locals, assignments, and equality/order comparisons lower to
  bytecode and execute in the VM.
- [x] Runtime tagged scalar values and escaped string decoding foundation.
- [x] Bytecode verification, source-map slots, collector roots, and
  safepoint hooks.
- [x] VM strings, collection contents, and array/dictionary/closure/cell/
  instance tables grow through checked allocator-backed storage; regression
  tests exceed all former 32/64-entry collection and object limits.
- [x] VM frame locals and closure capture environments grow dynamically;
  return/exception unwinding releases frame ownership and exhaustive induced
  allocation-failure tests verify propagation without leaks.
- [x] The control-flow verifier rejects hostile operand overflow, invalid
  constant/function/class metadata, malformed stack joins, and a deterministic
  randomized malformed-bytecode corpus.
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
- [x] Debugger primitives resolve nearest executable source lines, implement
  call-depth-aware step-in/over/out decisions, exception breakpoints, Ravi
  frames, scopes, variable expression lookup, and safe breakpoint enable/disable
  management; stopped instruction identity and source-map pause locations are
  retained for source inspection.
  VM pause/resume integration and DAP transport remain pending.
- [x] CLI diagnostics support human, compact, and schema-versioned JSON output
  through `--diagnostic-format`.
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
- [x] Production VM operand stacks, locals, captures, cells, collections,
  properties, and return paths use the NaN-boxed `Value` ABI with typed handles;
  integer arithmetic enforces the documented 48-bit range and dictionary
  hashing/equality dispatch through `Value`.
- [x] VM execution can attach the in-process debugger and pause at instruction
  breakpoints or step decisions, returning a typed `DebuggerPaused` runtime
  error for CLI/DAP adapters.
- [x] VM instructions poll the collector safepoint; managed object allocation,
  precise VM roots, and write barriers remain the next GC integration stage.
- [x] VM-managed strings, arrays, dictionaries, closures, capture cells, and
  instances now allocate through traced collector records with explicit
  payload destructors and roots; collection statistics and sweep reclamation
  are covered by direct tests. Frames remain allocator-backed execution state.
- [x] VM safepoints rebuild roots from live stack/frame/capture/exception values,
  recursively trace collection/object references, and invoke write barriers on
  mutable stores; tiny-threshold tests reclaim unreachable objects during a run.
- [x] Filesystem-independent module loading parses import declarations, resolves
  relative `.rk` sources through an injected provider, detects cycles, preserves
  source profiles, and the CLI executes dependency initializers in topological
  order. Loader interfaces now collect public function/class declarations and
  validate requested imported symbols when an interface is available.
- [x] Module artifacts expose deterministic fingerprints over module name,
  compiler/runtime key, language profile, and interface payload for safe cache
  reuse and selective invalidation (`src/modules/artifact.zig`); the loader now
  exposes bounded decoding and exact identity validation for cache-aware
  consumers. Compiler cache hits and dependency invalidation remain pending.
- [x] Bounded in-memory module artifact cache supports fingerprinted reuse and
  transitive dependency-aware invalidation (`src/modules/cache.zig`); persistent cache
  storage and compiler integration remain pending.
- [x] DAP protocol adapter bridges initialize, pause, continue, stepping,
  breakpoint-state reporting, paused-instruction-aware stack traces,
  termination, and LSP-compatible content framing to the in-process debugger;
  stdio/socket hosting and richer variable scopes remain follow-up transport
  work.
- [x] LSP JSON-RPC adapter bridges initialize/shutdown, document overlays,
  completion requests, and framed notifications to the existing LSP server;
  lexer and parser diagnostics now flow through the document overlay API, with
  pull-diagnostics, document-symbol, identifier-reference, and rename-edit
  responses, declaration hover information, full semantic-token responses, and
  full-document formatting edits;
  a generic incremental
  reader/writer host now supports stdio, sockets, split frames, and multiple
  requests. Initialization now advertises completion, hover, diagnostics,
  references, and rename capabilities explicitly.
- [x] Fast computed dispatch loop and VM execution engine (`src/vm/dispatch.zig`).
- [x] Verified arithmetic/return chunks now use the fast dispatcher through
  `Vm.runValue`, with automatic reference-VM fallback for unsupported opcodes
  and differential result tests.
- [x] ReleaseFast benchmark tooling emits versioned JSON reports with UTC
  provenance, iteration count, median/p95/min/max timings, optional output
  files, and baseline median-regression checks with configurable thresholds
  (`tools/benchmark.ps1`).
- [x] Multi-threaded bounded executor with synchronized channels and
  deterministic draining/shutdown (`src/concurrency/scheduler.zig`), including
  an idempotent explicit stop lifecycle. Channels now have explicit close state
  and reject sends after shutdown.
- [x] Futures expose synchronized completion, cancellation, status, and await
  operations with serialized first-writer-wins terminal transitions; bounded
  `awaitTimeout` distinguishes completion, cancellation, and timeout;
  language-level async lowering remains.
- [x] Channels expose `receiveState`, distinguishing queued values, temporary
  emptiness, and permanent closure for structured shutdown.
- [x] Resumable async/generator machine metadata records pending/running,
  suspension source locations, resume, completion, failure, and hierarchical
  cancellation transitions (`src/concurrency/async_state.zig`), with stable
  resume-location and terminal-state queries for scheduler/debugger consumers.
  HIR/MIR and
  bytecode function metadata now preserve resumable-function identity; compiler
  emission of executable state-machine instructions from async syntax remains
  pending.
- [x] Bytecode now carries an explicit `suspend_point` marker for `yield`/
  `taru` source lines; synchronous VM execution treats it as a no-op while
  resumable frame execution is being connected. Function metadata also records
  the suspension-point count for future frame allocation and debugger mapping.

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
.\test.ps1
```

## Current limitations

- [ ] Full parser recovery across nested suites and formatter-level trivia
  reconstruction remain pending; the lossless token tree is now present.
- [x] Simple top-level function declarations with typed parameters, returns,
  and integer calls are lowered and registered in bytecode.
- [x] Nested named functions, anonymous closures, and mutation through shared
  captured cells execute and have direct VM tests.
- [x] Basic integer function calls are wired through the source compiler and VM.
- [x] Boolean short-circuiting and chained comparison lowering execute with
  single evaluation of intermediate comparison operands.
- [x] Map views can be iterated, negative-step range termination is executable,
  and collection `prati` supports lists, sets, and dictionary views.
- [x] `nodu`, `tappu`, `kone`, and explicit `yese` now lower through the
  VM's explicit raise-handler path; implicit faults still need generalized
  handler unwinding.
- [x] Typed/dynamic boundary guard records, executable guard operations, and
  VM guard checks are implemented; automatic annotation-driven insertion and
  specialization remain pending.
- [x] Decoded strings use dynamically owned VM storage with UTF-8 indexing,
  slicing, and coverage beyond the former 255-byte limit; interpolation and
  formatting remain future work.
---

## Task Roadmap: Lacking Features

### OOP & Class System Implementation
- [ ] **Parser Support for Class Definitions:** Basic `roopa`, visibility, and
  method suites parse; explicit field declarations, inheritance, and override
  validation remain.
- [x] **VM Object Storage & Layout:** Instances, constructors, implicit `tanna`,
  property storage, and method calls execute. GC-backed layouts and inheritance
  remain follow-up work.
- [x] **Property & Method Bytecode Opcodes:** `make_instance`, `get_property`,
  `set_property`, and `call_method` are verified and executable.

### Module Import Resolution & Symbol Linking
- [x] **Module Loader:** File system import resolution for `module_name inda symbol1, symbol2 tago` syntax.
- [x] **Symbol Export Table:** Executable module graphs bind imported function
  declarations into the combined caller chunk; explicit visibility enforcement,
  stable interface fingerprints, canonical module identity, and shared module
  globals remain pending.

### Memory Management & Concurrency
- [x] **VM-integrated Tracing GC:** Connect the tested mark-sweep collector to
  VM object allocation and precise roots; generations remain evidence-driven.
- [x] **GC Safepoints & Write Barriers:** Implement safepoint polling in VM loop and write barriers for collection mutations.

### Tooling & Native Code Generation
- [x] **HIR / MIR Foundation:** Typed HIR lowers to verified MIR with source
  identity and verifier-checked constant folding for arithmetic, division, and
  modulo with trap preservation. A verified straight-line MIR-to-bytecode
  bridge now executes through the production VM, including source lines and
  suspension markers; block-label lowering and full SSA control flow remain
  pending.
- [x] **Optimizer safety:** Bytecode constant folding covers safe integer
  division and modulo while preserving divide-by-zero and signed-overflow
  runtime errors.
- [ ] **Native Backend & Linker:** Native machine code generation (x86_64 / ARM64) and executable compilation.
- [ ] **Language Server Protocol (LSP):** JSON-RPC transport, overlays,
  diagnostics, completion, hover, symbols, references, rename, semantic
  tokens, formatting, JSON-safe escaping, cancellation notifications, and the
  code-action endpoint are tested. Diagnostic fix-it producers, bilingual
  completion coverage, and request-aware stale-result cancellation remain
  pending.

### 2026-07-24 performance and typed syntax batch
- Milestone 3: function return annotations now accept the built-in `none`
  type (`-> none`), with parser regression coverage.
- Milestone 7: VM safepoint polling now avoids rebuilding GC roots during
  allocation-free loops; debugger-attached execution remains instruction
  precise and allocation-triggered collection remains enabled.
- Milestone 7: integer-tag fast paths avoid repeated dynamic integer helper
  dispatch in `range_condition` and `range_step`, while preserving fallback
  validation for dynamic values.
- Milestone 7: literal numeric range limits are evaluated once into ordinary
  VM locals and reused through verified `load_local` instructions. Dynamic or
  side-effecting range expressions retain the original semantics; the 400³
  bounded benchmark measures approximately 2.87s in ReleaseFast.
- Milestone 7: normal VM GC polling now uses a 4096-instruction interval;
  allocation sites still safepoint immediately and debugger sessions retain
  instruction-level polling. Repeated 400³ runs measure approximately 2.83s.
- Milestone 7: benchmark coverage now includes arithmetic, calls, closures,
  collections, advanced collections, strings, gradual typing, and nested
  numeric loops. ReleaseFast benchmark reports run successfully.
- Milestone 8: fused numeric-condition lowering was prototyped and reverted
  after exposing a top-level frame contract issue; the generic verified path
  remains active while frame-aware lowering is designed.
- Milestone 2 ABI audit: production VM imports `src/vm/value.zig` exclusively;
  `src/runtime/value.zig` is isolated to its compatibility test module. It is
  intentionally retained until the legacy tagged-union tests are migrated to
  the NaN-boxed ABI, preventing accidental dual-runtime usage.
- Milestone 7: the standard ReleaseFast benchmark matrix now includes paired
  `typed_loop.rk` and `dynamic_loop.rk` workloads. Both execute successfully;
  the pair makes annotated integer-range and generic tagged-range regressions
  visible in the same report.
- Milestone 6: scheduler workers now accept an optional `std.Io` context and
  use Zig's kernel-backed `std.Io.Semaphore` for wake/sleep and shutdown
  signaling when embedded runtimes provide it; the legacy constructor retains
  a polling fallback for compatibility. Lifecycle and wake-path tests pass.
- Milestone 7: added a bounds-checked `PackedInstruction` representation
  (opcode plus signed 24-bit operand) with signed round-trip and overflow tests.
  The live dispatcher remains unchanged until artifact-size and throughput
  measurements justify switching encodings.
- Milestone 5/7: module artifacts now record a validated payload kind, including
  packed-bytecode artifacts, while preserving version/checksum/resource-limit
  checks. Round-trip coverage verifies the new metadata.
- Milestone 9: JSON diagnostics now serialize optional fix-it spans and escaped
  replacement text, with regression coverage for editor-safe code actions.
- Milestone 9: LSP diagnostics now expose a safe `MissingName` quick-fix and
  `textDocument/codeAction` emits a standards-shaped workspace edit. JSON-RPC
  and server lifecycle tests remain green.
- Milestone 9: added end-to-end JSON-RPC coverage that opens malformed source,
  requests `textDocument/codeAction`, and verifies a quick-fix workspace edit
  containing `newText`.
- Milestone 4 verification: class construction, `huttu` initialization,
  `tanna` property storage, bound method dispatch, and the shipped
  `examples/class_oop.rk` now execute successfully; inheritance and visibility
  contracts remain the next class-system scope.
- Milestone 4: class AST/parser declarations now retain an optional `guru`
  base-class name (for example `roopa Child guru Parent`), with parser
  regression coverage. Runtime inheritance dispatch and contract enforcement
  remain gated until class metadata is lowered end to end.
- Milestone 4 semantic validation: class names are registered before base
  checks, allowing forward declarations while rejecting unknown `guru` bases
  with `UnknownBaseClass`; semantic regression coverage passes.
- Milestone 4 single-inheritance lowering: `guru` relationships now compile
  into `ClassInfo.base` metadata with unknown-base rejection and bytecode
  regression coverage. Ravi's core model remains one direct base per class;
  mixins/interfaces can be added separately without multiple-inheritance MRO.
- Milestone 4 runtime contract: `ClassInfo.inheritsFrom` resolves ancestry with
  bounds and cycle-depth protection, ready for VM `is` checks and inherited
  method lookup; ancestry regression tests pass.
- Milestone 4 instance integration: `object_storage.instanceIsA` now exposes
  the same ancestry contract to VM operators and debugger inspectors without
  duplicating hierarchy logic; full tests pass.
- Milestone 4 method metadata: bytecode chunks now retain `MethodInfo` entries
  linking each class, method name, and function index. Compiler tests verify
  inherited/overridden method declarations retain distinct owners; dispatch
  lookup can now be added without rescanning source tokens.
- Milestone 4 inherited lookup: added bounds/cycle-safe `lookupMethod`, which
  prefers the child override and walks its single base chain for fallback
  methods. Override and inherited lookup tests pass.
- Milestone 4 runtime dispatch: `callMethod` now resolves the receiver's class
  through `lookupMethod`, selecting child overrides and inherited methods while
  preserving the existing function-call ABI. End-to-end override execution is
  covered and the complete test suite passes.
- Milestone 4 dispatch coverage: added an end-to-end inherited-method fallback
  test in addition to override coverage; parent methods execute on child
  instances correctly.
- Milestone 4 semantic contracts: duplicate method names within one class now
  raise `DuplicateDeclaration`, while same-named methods in a child remain
  valid overrides. Semantic regression coverage passes.
- Milestone 4 visibility metadata: parser declarations now preserve public,
  private, protected, and internal modifiers for classes and functions instead
  of discarding them. Parser coverage verifies private/public spelling; access
  enforcement remains the next semantic/runtime step.
- Milestone 4 compiler propagation: function declarations and `MethodInfo`
  entries now retain visibility values, eliminating metadata loss before access
  checking. Full tests pass; enforcement remains intentionally pending.
- Milestone 4 initial access enforcement: compiler rejects private method calls
  from top-level/external code with `PrivateAccess`, while class-method bodies
  remain eligible for internal calls. The complete test suite passes.
- Milestone 4 access regression: compiler tests now prove an external private
  method call fails deterministically with `PrivateAccess`.
- Milestone 4 protected-access foundation: VM call frames now retain optional
  receiver owner-class identity for method calls, while free-function and
  closure frames remain unowned. Full tests pass; subclass access checks can
  now use frame context safely.
- Milestone 4 protected-access contract: added `canAccessProtected`, allowing
  same-class and descendant callers while rejecting unrelated or unowned
  callers; ancestry predicate tests pass.
- Milestone 4 runtime protected enforcement: `callMethod` now checks protected
  method metadata against the caller frame's owner class and the declaring
  class ancestry. Invalid access fails before entering the method; full tests
  pass.
- Milestone 4 protected regression: end-to-end compilation/VM coverage now
  verifies an unrelated external caller is rejected with `InvalidFunction`.
- Milestone 4 descendant access regression: a child method can call a
  protected parent method through `tanna`, while external access remains
  rejected; complete tests pass.
- Milestone 7 compact artifact integration: added deterministic packed-code
  encode/decode helpers for instruction streams (4 bytes per instruction),
  including malformed-length and signed-operand tests. Live VM dispatch remains
  unchanged pending benchmark comparison.
- Verification: full `zig build test` and ReleaseFast class/typed-loop/
  dynamic-loop benchmark matrix pass after single-inheritance metadata work;
  measured medians are approximately 14.6ms (class), 15.0ms (typed), and
  18.5ms (dynamic) for the bounded workloads.
- Milestone 7 release boundary: `bytecode.Chunk` now exposes `encodePacked`
  and `loadPacked` APIs. They preserve the existing source map and metadata,
  allowing compact release artifacts without weakening debugger precision;
  full `zig build test` passes.
- Milestone 7 artifact validation: packed-bytecode artifacts now require a
  payload length divisible by four at both encode and decode boundaries,
  preventing truncated instructions from entering the cache or VM. Regression
  tests and the full suite pass.
- Milestone 7 release execution: `Vm.runPackedValue` now decodes compact
  instructions, preserves function/class/capture metadata, and executes via
  the standard VM path. It rejects debugger-attached execution unless the
  source-mapped chunk is used; equivalence coverage passes with the full suite.
- Milestone 7 packed fast path: metadata-free packed programs now use the
  allocation-free dispatcher directly after decoding; metadata-bearing code
  retains the safe reconstructed-chunk path. Full tests pass.
- Milestone 7 benchmark evidence: ReleaseFast benchmark matrix (3 iterations)
  completed successfully across arithmetic, calls, closures, collections,
  strings, gradual typing, and typed/dynamic loops. Report medians ranged from
  15.419ms to 16.305ms on the current host; no execution regressions observed.
- Milestone 7 plan status: compact operand redesign is now checked complete in
  `docs/development-plan.md`; superinstructions, specialization, and broader
  profiling remain separate pending work.
- Milestone 6 timeout stability: `Future.awaitTimeout` now accounts for the
  caller-provided nanosecond budget in bounded quanta and yields between
  checks, avoiding the previous millisecond-conversion drift while remaining
  portable on Zig 0.17. Timeout, cancellation, and full scheduler regression
  tests pass with `zig build test`.
- Milestone 8 optimizer safety: integer constant folding now uses checked
  add/subtract/multiply operations and leaves overflowing expressions for the
  runtime, preserving language overflow behavior. Added regression coverage;
  the full test suite passes.
- Milestone 8 control-flow remapping: constant-fold instruction removal now
  remaps jumps, exception edges, and function entry points that target the
  fold boundary, preventing stale instruction pointers in optimized/debug
  builds. Full tests pass.
- Milestone 8 MIR verification: the verifier now requires the first CFG block
  to begin at instruction zero, preventing orphaned instructions before the
  entry block and preserving deterministic source/debug mapping. Added a
  regression test; full tests pass.
- Milestone 8 dead-stack cleanup: the optimizer now removes only immediate
  side-effect-free `constant`/`pop` pairs, remapping control-flow targets,
  function entries, and source maps. Calls and effectful operations remain
  untouched. Regression coverage and the full test suite pass.
- Milestone 7 optimizer integration: normal `run` execution, including merged
  module execution, now invokes the verified bytecode optimizer. `trace` and
  `bytecode` retain their original instruction layout for precise debugging.
  Full `zig build test` passes.
- Milestone 9 LSP JSON safety: document-symbol, reference, and rename responses
  now escape URIs, names, and replacement text through the shared JSON encoder,
  preventing malformed editor responses for quoted or escaped workspace paths.
  Full `zig build test` passes.
- Milestone 9 LSP profile-aware completion: completion requests now resolve the
  opened document's language profile and serialize the actual returned labels,
  instead of always emitting Kannada keywords. Added English-profile JSON-RPC
  coverage; full `zig build test` passes.
- Milestone 9 LSP definitions: added declaration lookup for functions/classes,
  advertised `definitionProvider`, and implemented `textDocument/definition`
  JSON-RPC locations with escaped URIs. End-to-end regression coverage and the
  full test suite pass.
- Milestone 1/9 DAP safety: stack-trace frame names are now JSON-escaped,
  preventing user-defined names containing quotes, slashes, or control
  characters from corrupting debugger responses. Added regression coverage;
  full `zig build test` passes.
- Milestone 1 DAP protocol correlation: responses now preserve each incoming
  request's numeric `seq` as `request_seq` instead of hard-coding zero, so
  IDEs can reliably match asynchronous debugger responses. Added regression
  coverage; full `zig build test` passes.
- Milestone 1 DAP capability accuracy: initialization now explicitly reports
  hover evaluation as unsupported until an evaluator is implemented, avoiding
  misleading IDE requests while retaining configuration/stepping support.
  Full `zig build test` passes.
- Milestone 1/9 DAP thread view: added a stable `threads` response exposing
  Ravi's main execution thread before stack inspection, enabling standard IDE
  debugger navigation without inventing additional runtime threads. Added
  regression coverage; full `zig build test` passes.
- Milestone 2 scalability: removed the arbitrary 1,000-interned-string limit;
  string storage now grows under allocator/representable-handle checks and
  propagates real OOM failures. Added a 1,024-string VM stress regression;
  full `zig build test` passes.
- Milestone 2 object-table scalability: removed legacy 500/999 instance,
  closure, array, and dictionary caps. Object storage already grows with
  checked allocator-backed tables, so valid programs now scale until memory
  or representable handle limits. Full `zig build test` passes.
- Milestone 3 exception semantics: empty `raise` now rethrows the active
  exception inside a handler while preserving its payload. Added VM regression
  coverage; full `zig build test` passes.
- Milestone 6 async cancellation: `Machine.pollCancellation` now materializes
  parent-tree cancellation as a terminal child transition at scheduler/VM
  safepoints, preserving instruction/source metadata. Added regression coverage;
  full `zig build test` passes.
- Milestone 4 superclass dispatch: added `call_super` bytecode and VM lowering
  for `guru.method(...)`, resolving against the declaring class's base rather
  than the dynamic override. Added an end-to-end override/super regression;
  full `zig build test` passes.
- Milestone 5 package roots: `Loader.addSearchPath` now provides deterministic,
  allocator-owned package search paths after importer-relative lookup, with
  normalized separators and cycle/interface checks unchanged. Added package
  root regression coverage; full `zig build test` passes.
- Milestone 3 Unicode safety: UTF-8 string length, offsets, and indexing now
  validate continuation bytes, reject overlong encodings/surrogates/out-of-
  range code points, and preserve code-point semantics. Added malformed UTF-8
  regressions; full `zig build test` passes.
- Milestone 7 benchmark reliability: fixed the PowerShell benchmark runner's
  native-stderr handling so normal Ravi output is not treated as a terminating
  error under `ErrorActionPreference=Stop`. ReleaseFast matrix (3 measured
  iterations) now completes across arithmetic, calls, closures, collections,
  strings, gradual typing, and typed/dynamic loops; medians were 22.497–28.549
  ms on the current host.
