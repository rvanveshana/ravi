# Ravi Progress

Short handoff for verified implementation status. Planned behavior is not
listed as complete until it executes and has tests.

## Phase Status

- [x] **Phase 0: complete.** Baseline, benchmark contract, provenance, regression
  checks, and initial performance budgets are recorded.
- [ ] **Phase 1: active.** AST compiler migration is underway; the legacy token
  compiler remains the CLI production path and differential oracle.
- [ ] **Phases 2-8: pending.** Core language completion, runtime stability, async,
  modules/builds, tooling, measured optimization, and native backend work remain.

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

- [x] integers, strings, booleans, `none`
- [x] assignments, locals, names, unary operations
- [x] arithmetic, comparisons, eager logical operators
- [x] arrays, tuples, sets, maps
- [x] indexing and slicing
- [x] indirect call bytecode emission

Still needed before AST authority can replace the token compiler:

- [ ] function declarations and executable AST function bodies
- [ ] closures and complete semantic symbol binding
- [ ] statement/control-flow lowering
- [ ] exceptions and cleanup edges
- [ ] AST-to-token differential conformance tests
- [ ] parser/semantic/HIR/MIR integration and CLI routing

## Important Gaps

- [ ] Floats, interpolation/formatting, generators, context managers, decorators,
  and complete gradual typing remain incomplete or partial.
- [ ] Class inheritance/visibility contracts and shared module globals need further
  end-to-end integration.
- [ ] GC handle reuse/stale-handle rules, persistent mark worklists, stress/fuzz
  targets, and thread-ownership contracts remain stability work.
- [ ] Async/generator lowering, project builds, persistent artifact caching,
  complete LSP/DAP hosting, and native code generation remain pending.
- [ ] Benchmark phase timings and GC pause timings are intentionally unmeasured;
  only macro runtime distributions and binary size currently have budgets.

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

- [x] The last verified run passed all Zig tests and all 27 Ravi examples.

## Next Work

- [ ] Continue Phase 1 with executable AST function declarations and bodies, then
add differential tests before routing any CLI compilation through the AST path.
