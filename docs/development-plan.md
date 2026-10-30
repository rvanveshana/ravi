# Development plan

The redesign is delivered in dependency order. No backward-compatibility compiler
or fallback behavior is required. The [implementation status](implementation-status.md)
records completed work; [language design](language-design.md) owns the target contracts.

## Milestones

| Stage | Deliverable | Acceptance gate |
| --- | --- | --- |
| 0. Trustworthy baseline | Real test execution, accurate status, coherent documentation, source-size enforcement | Remaining baseline failures resolved; clean build and reported test results |
| 1. One compiler | Resolved symbols/types, complete supported HIR/MIR, independent modules | Every supported CLI path uses one pipeline; direct AST adapter removed; unsupported features diagnosed |
| 2. Runtime correctness | Object ownership, precise roots, OOM rollback, structured exceptions and cleanup | Allocation-failure, cycle, temporary-root, nested-cleanup, and module-lifetime checks pass |
| 3. Usable core | Complete functions/classes/protocols, decorators, context managers, core and file/data libraries | A documented CLI application reads data, transforms it, handles errors, and closes resources |
| 4. Concurrency | Backend suspension, task scopes, bounded channels, cancellation, safe worker transfers | No busy idle loops; shutdown and cancellation are deterministic; CPU scaling and I/O bounds measured |
| 5. Performance | Typed specialization, reduced allocation, general native backend | VM/native conformance, target ABI checks, and reproducible performance results |
| 6. Release quality | Packages/lockfiles, editor/debugger integrations, extended libraries, versioned handbook | Clean installation, platform matrix, fuzzing, soak tests, and documentation examples pass |

The recorded baseline suite passes; Stage 0 remains open until its remaining
acceptance criteria have evidence. Stage 1 must preserve the single executable
compiler pipeline. See the implementation status for current validation results.

## Standard-library delivery

| Wave | Modules | Required coverage |
| --- | --- | --- |
| A | Collections, iterators, Unicode text, bytes, math, errors, testing | Boundary values, equality/hash rules, mutation, encoding errors |
| B | Paths, files/streams, environment, arguments, time, JSON, logging | Cross-platform behavior, bounded streaming, round trips, deterministic close |
| C | Tasks, channels, synchronization, cancellation, processes | Admission/shutdown races, timeouts, child failures, saturation, process reaping |
| D | DNS, TCP/UDP, TLS, HTTP, URL handling | Partial I/O, certificate validation, bounded bodies/headers, cancellation and backpressure |
| E | Regex, CSV, compression/archive, random, hashes, time zones, SQLite integration | Conformance corpora, limits, dependency policy, resource behavior |

Use maintained TLS/cryptography implementations. Distinguish secure random sources
from deterministic pseudorandom generators. Keep Kirana UI and large integrations
separately scoped until the runtime is dependable. A placeholder module is not a
delivered library.

## Completion criteria

A feature needs defined semantics, consistent profiles, integrated lowering and
execution, meaningful positive/negative tests, errors and resource handling, and
current user documentation. Record platform and performance limitations explicitly.

For compiler/runtime changes, include malformed input, allocation failure, and
cross-feature interactions where relevant. Shared contracts must be exercised
across backends when native execution becomes available. Do not equate parser
acceptance, compilation, or a `tested` tracker flag with release readiness.

Run the full suite at a milestone validation boundary. After a failure, use named
test targets to validate the correction. Repeat the full suite when integration
changes justify it, rather than after every edit. See [Contributing](contributing.md).
