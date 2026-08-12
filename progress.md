# Ravi Progress

Short handoff for verified implementation status. Planned behavior is not
listed as complete until it executes and has tests.

## Phase Status

- [x] **Phase 0: complete.** Baseline, benchmark contract, provenance, regression
  checks, and initial performance budgets are recorded.
- [ ] **Phase 1: active.** AST compiler migration is underway; the legacy token
  compiler remains the CLI production path and differential oracle. The AST
  path now covers the verified example corpus, including variadic and keyword
  arguments.
- [ ] **Phase 2: active.** Float literals and basic numeric runtime semantics are
  implemented; the remaining core language surface is still pending.
- [ ] **Phases 3-8: pending.** Runtime stability, async, modules/builds, tooling,
  measured optimization, and native backend work remain.

## Verified Foundation

- [x] Lexer: Kannada/Kanglish default profile, optional English profile, strict
  four-space indentation, comments, strings, spans, recovery diagnostics.
- [x] Parser/semantic layer: lossless syntax storage, declarations, annotations,
  scopes, imports, classes, collections, calls, control flow, and diagnostics.
- [x] VM: NaN-boxed `Value` ABI, typed handles, growing stacks/frames, arithmetic,
  locals, closures, collections, strings, properties, methods, exceptions,
  debugger hooks, safepoints, write barriers, and managed-object tracing.
- [x] Bytecode: verification, source maps, packed encoding, control-flow checks,
  fast arithmetic dispatch, and reference-VM fallback.
- [x] Modules/tooling: provider-based loading, cycle checks, artifact fingerprints,
  bounded in-memory cache, LSP/DAP protocol adapters, formatter, and JSON
  diagnostics.
- [x] Scheduler: bounded executor, futures, channels, cancellation state, and
  resumable metadata. Language-level async execution is not complete.

## AST Migration

The token-independent `compileAstModule` boundary currently lowers and tests:

- [x] integers, strings, raw strings, booleans, `none`
- [x] brace formatted strings (`f"Result: {value}"`) parse normal expressions,
  lower through one VM formatting operation, and support escaped braces
- [x] float literals, mixed numeric arithmetic/comparisons, equality/hash rules,
  collection keys, malformed-literal diagnostics, and float-pool verifier checks
- [x] assignments, locals, names, unary operations
- [x] arithmetic, comparisons, eager logical operators
- [x] arrays, tuples, sets, maps
- [x] indexing and slicing
- [x] indirect call bytecode emission
- [x] AST `if` and `while` lowering with canonical profile keywords and patched
  VM jumps
- [x] AST `else`, `break`, and `continue` lowering with nested-loop patching
- [x] `pass`/`bidu` parses and lowers as an executable no-op in both compiler
  paths
- [x] AST call arguments use explicit expression IDs, preserving nested and
  multi-expression argument semantics
- [x] AST profile builtins lower `mudrisu`/`print` and `vidha`/`type`
- [x] AST direct calls resolve declared functions, including recursion
- [x] AST membership and identity comparisons lower through VM operations
- [x] parser normalizes `inadre`/`elif` into nested conditional branches;
  nested final-else parsing is covered; compound-statement range ownership
  still needs repair before AST conditional authority

Still needed before AST authority can replace the token compiler:

- [x] basic function declarations and executable AST function bodies with
  parameter locals, indirect calls, explicit returns, and capture-free lambdas
- [x] AST closure creation and read-only capture resolution for lambdas,
  including multiple capture slots
- [x] closure mutation propagation inside AST lambdas through shared capture
  cells
- [ ] mutation propagation across enclosing scopes and complete semantic
  symbol binding
- [x] AST member assignments preserve their object target and lower through
  instance property bytecode; full AST class declaration integration remains
  pending
- [x] capture-free nested AST function declarations with body-range skipping
- [x] numeric default parameters for AST and indirect function calls
- [x] basic AST `try`/`except`/`finally` range linking and VM fault recovery
- [x] nested AST closures forward enclosing capture cells
- [x] AST `except name` binds the active raised payload
- [x] literal exception value matching with unmatched-payload rethrow
- [ ] exception type matching and VM-wide exceptional cleanup guarantees;
  AST `finally` now runs before `return`, `break`, and `continue` transfers
- [x] AST `for` lowering iterates arrays and strings through indexed access
- [x] AST `for` lowering iterates dictionary keys through runtime normalization
- [x] AST dictionary view member calls expose keys, values, and items
- [x] AST dictionary `items` views yield indexable two-element key/value pairs
- [x] AST `for` lowering supports one-, two-, and three-argument `range`/`shreni`
- [x] initial AST-to-token differential conformance tests for arithmetic,
  iteration, and exception binding
- [ ] parser/semantic/HIR/MIR integration and full CLI authority
  - [x] CLI exposes `--ast-compiler` for controlled AST migration testing;
    legacy compilation remains the default until comments, profile keywords,
    imports, and remaining AST constructs are covered.
- [x] AST variadic and keyword arguments pack `*values` into tuples and
  `**options` into dictionaries, with runtime binding and keyword lookup.

## Important Gaps

- [x] Float literals, NaN-boxed storage, mixed numeric arithmetic/comparisons,
  equality/hash rules, collection keys, malformed-literal diagnostics, and
  unary negation now execute through the AST path with verifier coverage.
- [x] Raw string prefixes preserve backslashes through lexing, AST lowering,
  and VM execution.
- [x] Formatted-string bytecode now rejects overflowing argument counts and
  reserves estimated output capacity before one-pass rendering.
- [x] Formatted placeholders track nested delimiters and quoted strings, so
  expressions such as `{items[index]}` do not stop at an inner delimiter.
- [x] Resumable metadata isolates nested `taru`/`yield` suspension points from
  their enclosing function.
- [x] Nested-function suspension scanning preserves generator metadata at the
  correct declaration boundary.
- [x] Bytecode verification rejects negative suspension locations and
  inconsistent resumable function metadata before VM execution.
- [x] Resumable machines expose yielded values exactly once, and HIR/MIR
  preserve suspension counts for future state-machine lowering.
- [x] Resumable machines expose side-effect-free suspension snapshots with
  resume location and yielded payload for scheduler/debugger consumers.
- [x] MIR verification counts actual suspension instructions and rejects
  mismatched resumable metadata before MIR-to-bytecode lowering.
- [x] Context-manager syntax parses `jote` suites and optional `aagi` bindings;
  malformed bindings produce parser diagnostics.
- [x] Formatted strings support minimum width, left/right/center alignment, and
  basic `s`/`d`/`f` type validation through the AST compiler and VM.
- [ ] Advanced format specifications, generators,
  context managers, decorators, and gradual typing remain incomplete or partial.
- [ ] Class inheritance/visibility contracts and shared module globals need further
  end-to-end integration.
- [ ] GC handle reuse/stale-handle rules, persistent mark worklists, stress/fuzz
  targets, and thread-ownership contracts remain stability work.
- [ ] Async/generator lowering, project builds, persistent artifact caching,
  complete LSP/DAP hosting, and native code generation remain pending.
- [ ] Benchmark phase timings and GC pause timings are intentionally unmeasured;
  only macro runtime distributions and binary size currently have budgets.

## Phase 2 Pending Work

- [ ] **AST authority:** semantic/HIR/MIR integration and default CLI routing
  remain; `--ast-compiler` provides a controlled route. Closure-cell mutation
  and nested named-function capture now execute.
- [ ] **Formatting:** precision, numeric formatting, conversion flags, and
  malformed-spec diagnostics remain pending; width/alignment/type validation
  are implemented and tested.
- [ ] **Iteration:** general iterator protocol and generator-backed iteration
  remain pending; arrays/strings, ranges, dictionary key/value/item views, and
  AST `continue` increment-target patching are implemented.
- [ ] **Generators:** lower `yield` into executable resumable state machines,
  preserve locals across suspension, implement resume/close behavior, and test
  nested generators and generator iteration.
- [ ] **Context managers:** define enter/exit protocols, bind the entered value,
  run exit on normal and exceptional paths, and guarantee deterministic cleanup.
- [ ] **Decorators:** parse arguments, preserve declaration order, apply wrappers
  at the correct phase, and validate decorated signatures.
- [ ] **Gradual typing:** unions and nullable types, flow narrowing, runtime
  conversions, boxing/unboxing contracts, and diagnostics for failed guards.
- [x] **AST variadics:** `*values` and `**options` parse, lower, bind, and
  execute through the AST call ABI; the variadic example passes in both
  compiler paths.
- [ ] **Classes/modules:** inheritance and visibility contracts, override checks,
  shared module globals, and end-to-end profile-aware class behavior.
- [ ] **Profiles/tooling:** route every frontend and LSP operation through the
  selected language profile; add bilingual negative and member-name tests.

## Phase 0 Baseline

ReleaseFast baseline on Windows X64 with Zig `0.17.0-dev.1415+64dfaa568`:

- [x] 30 measured samples after 1 warmup
- [x] runtime median: approximately `16.0-16.7 ms`
- [x] highest measured p95: `22.049 ms`
- [x] binary size: `1,155,584` bytes
- [x] budgets: [config/performance-budgets.json](config/performance-budgets.json)

- [x] Benchmark runner: [tools/benchmark.ps1](tools/benchmark.ps1)

## Verification

- [x] Verified from the repository root:

```powershell
zig build test
.\test.ps1
git diff --check
```

- [x] The latest verified run passes all Zig tests and all 25 production Ravi
  examples.

## Next Work

- [ ] Complete AST authority by integrating semantic analysis, HIR, and MIR,
  then make AST compilation the default CLI route after differential coverage.
- [ ] Add the general iterator protocol and iterator objects for user-defined
  iterables, including semantic and HIR/MIR validation.
