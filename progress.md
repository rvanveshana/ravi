# Ravi Progress

Short handoff for verified implementation status. Nothing is listed as done
until it executes and is covered by a test or an example contract.

## Current Status

- Both compiler paths — the legacy token compiler (default) and the AST
  compiler (`--ast-compiler`) — compile and execute the full example corpus
  with identical, verified output.
- All 30 files under `examples/` are self-verifying contracts (they assert
  real results with `adre ... : yese "message"` and end with a `PASS`
  marker), not just printed values a human has to eyeball.
- `zig build test` and `.\test.ps1` both pass (30/30 examples, dual-compiler
  output comparison). This is the standing acceptance bar for any change.

## Recently Fixed

A batch of real, previously-hidden compiler/runtime defects was found and
fixed while hardening the examples into assertion contracts (root causes and
debugging notes are kept in `/memories/repo/ravi-compiler-bugs-fixed.md`):

- AST: top-level function declarations leaked a stack value on every call.
- AST/legacy: naive capture detection treated any fresh local variable as a
  required closure capture, breaking functions with their own new locals.
- AST: generic `for`/`prati x alli y` loops pushed the loop-condition operands
  in the wrong order, so they silently ran zero iterations.
- Legacy: `for x in <bare variable>` failed instead of iterating; `for`
  iterables are now resolved uniformly (list/set/dict/int) at runtime.
- AST parser: `%` (modulo) was not recognized at all.
- Legacy: leading unary minus (`-5 + 3`) miscomputed as `-(5 + 3)`.
- Legacy: `true`/`false` literals were stored as untagged integers and
  printed as `1`/`0` once round-tripped through a variable.
- Legacy: bare, call-free expression statements (e.g. a `try`-body expression
  with no assignment) never popped their result, corrupting later stack
  depth once anything followed the block.

## Known Gaps / Next Work

- **AST authority**: semantic/HIR/MIR integration and default CLI routing to
  the AST path are still pending; `--ast-compiler` remains opt-in.
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

