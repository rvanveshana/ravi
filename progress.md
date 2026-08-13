# Ravi Progress

Short handoff for verified implementation status. Nothing is listed as done
until it executes and is covered by a test or an example contract.

## Current Status

- The AST/semantic compiler is the only compiler. The legacy token compiler and
  `--ast-compiler` selection path have been removed.
- All 30 files under `examples/` are self-verifying contracts (they assert
  real results with `adre ... : yese "message"` and end with a `PASS`
  marker), not just printed values a human has to eyeball.
- `zig build test` and `.\test.ps1` both pass (30/30 examples through the sole
  compiler). This is the standing acceptance bar for any change.

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

## Known Gaps / Next Work

- **AST authority**: CLI, imports, tests, and examples now route through the
  AST compiler. Full semantic/HIR/MIR authority remains a later milestone.
- **Classes**: inheritance and visibility contracts are not implemented.
- **Iteration/generators**: no general iterator protocol or `yield`-backed
  generator state machines yet.
- **Context managers**: `jote`/`aagi` parse, but enter/exit protocol
  execution and guaranteed cleanup are not implemented.
- **Decorators**: not implemented.
- **Gradual typing**: annotations are accepted, but union/nullable types,
  narrowing, and runtime conversion guards are not implemented.
- **Modules**: shared module globals and full profile-aware class behavior
  need further integration.
- **Runtime stability**: GC handle reuse rules, stress/fuzz targets, and
  thread-ownership contracts are still open.
- **Async/native**: language-level async execution, project builds,
  persistent artifact caching, and native code generation are pending.
- Benchmark phase timings and GC pause timings remain unmeasured; only macro
  runtime distributions and binary size currently have budgets.

## Phase 0 Status

Completed validation work:

- CI checks formatting, source-size budgets, Debug/ReleaseSafe/ReleaseFast
  builds, unit tests, and the executable example corpus on Windows and Linux.
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

Remaining Phase 0 architecture work:

- Parser coordinator extraction is complete: `src/parser/parser.zig` now keeps
  the public parser API and delegates concrete implementations to
  `src/parser/parser_statements.zig`,
  `src/parser/parser_simple_statements.zig`, and
  `src/parser/parser_expressions.zig`.
- VM execute-loop coordinator extraction is complete: `src/vm/vm.zig` now keeps
  VM lifecycle/public API coordination while the instruction dispatch loop
  lives in `src/vm/execution.zig`.
- Remaining VM coordinator work is limited to any future splits identified by
  new feature growth; current source-size budgets are guardrails, not
  completion claims.

## Phase 1 Status

Diagnostics and debugger foundation work is implemented and covered by tests:

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

