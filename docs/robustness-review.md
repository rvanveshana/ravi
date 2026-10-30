# Ravi performance and robustness review

Reviewed 2026-10-30 on Windows with Zig `0.17.0-dev.1415+64dfaa568`.
This is a compiler/runtime architecture review with targeted fixes and regression
validation. It is not an exhaustive security audit or a production certification.

## Assessment

Ravi has useful foundations: one executable AST compiler pipeline, checked
48-bit integer arithmetic shared with constant folding, NaN-boxed values,
bytecode verification, a nonmoving tracing collector, and a bounded worker pool.
These foundations do not yet deliver the complete fast, stable, asynchronous
language requested. Subsequent development adds resumable tasks, event timers,
copy transfer, public channels, and core libraries. General source-to-MIR/native
compilation and asynchronous networking remain unfinished. Passing tests
establish the covered behaviors only.

## Changes from this review

| Finding | Change | Regression coverage |
| --- | --- | --- |
| Worker verification allocated scratch through the shared chunk's compiler allocator, potentially a non-thread-safe arena | Verification accepts caller-owned scratch storage; VM paths use the VM allocator | Concurrent scalar tasks succeed with all further parent-chunk allocations forbidden |
| Channel receive shifted all queued elements while holding its lock | Bounded FIFO ring; O(1) send/receive after one lazy allocation | Wraparound, full/empty, close/drain, null payload, zero capacity, OOM recovery |
| Windows sleep converted unsigned ticks to a signed native interval without checking the signed bound | Reject unrepresentable intervals before conversion | Host-level signed and unsigned tick overflow; no real long waits |
| Math library contained only arithmetic wrappers | Added absolute value, two-argument min/max, clamp, and integer GCD | Both profiles, signs, zeros, clamp bounds, type checking, 48-bit overflow |
| No small collection reduction module | Added sum with optional start and short-circuit all/any | Empty inputs, aliases, truth rules, overflow and invalid element types |
| Module documentation described an obsolete source concatenation pipeline | Aligned handbook and architecture with AST linking and profile preservation | Existing module tests and new cross-profile library examples |

The Windows host sleep overflow lies beyond Ravi's current 48-bit millisecond
range; the check hardens the host API. No measured end-to-end speedup is claimed
for these changes. The channel complexity improvement follows from eliminating
the queue shift, and does not establish behavior under heavy contention.

## Original priorities and acceptance gates

The table records the initial findings that prompted this work. For current
implemented behavior and exact limits, see [runtime contracts](task-runtime.md).
Do not interpret the original findings below as a description of the new runtime.

| Priority | Evidence and impact | Required implementation and acceptance gate |
| --- | --- | --- |
| 1. Async execution | `src/vm/execution.zig` waits synchronously; sleep blocks OS threads. Suspension metadata alone does not provide async I/O | Scheduler-integrated continuation frames, event-driven timers/I/O, cancellation cleanup; thousands of idle tasks with bounded threads and CPU |
| 1. Task resource ownership | `src/vm/tasks.zig` creates a child VM per task; nested child VMs can create additional CPU-sized pools. Futures stay in the parent table until VM destruction | Structured scopes, explicit shared-pool ownership, completed-future reclamation, bounded total task resources; nested spawn, saturation, shutdown, and long-running soak tests |
| 1. Transfer semantics | Workers reject heap handles, so strings, collections, closures, and rich exception payloads cannot cross boundaries | Define immutable/copy transfer and rooting/ownership rules first; cycle, alias, OOM, cancellation, and exception transfer tests |
| 2. Channel contention | Internal channels still use a yielding spin mutex and nonblocking operations; not exposed as a complete public API | I/O-backed synchronization and bounded waiting with deadlines/cancellation; concurrent producer/consumer stress, fairness, close races, and CPU measurements |
| 2. Core application libraries | JSON, network, and UI files are blueprints; files, paths, bytes, time, logging, and a testing API are missing | Small versioned modules with explicit resource limits and close semantics; round trips, malformed inputs, UTF-8, cross-platform behavior, OOM rollback |
| 2. VM performance | Source execution remains generic bytecode; per-task VM construction and repeated full-chunk verification cost work | Instrument compiler/VM/allocation/GC/scheduler phases; immutable verified-program ownership before caching verification; typed specialization with differential tests |
| 3. Native code | `src/backend/native.zig` emits only an x86-64 constant-return shape | Complete supported source-to-MIR lowering and ABI-aware backend with VM/native conformance; never use a subset fallback to claim native support |
| 3. Release assurance | Local Windows validation does not certify Linux, long-running stability, or malformed-source resilience | Execute CI platform matrix, bounded fuzzing, allocator sweeps, GC stress, concurrency soak tests, reproducible release builds |

## Minimal library policy

Keep print, range, primitive value operations, and collection/string methods in
the VM. Put composable algorithms in small source modules, retaining shared
semantics and profile aliases. Introduce host primitives only for capabilities
the language cannot express efficiently: bounded streams, paths, monotonic time,
timers, bytes/encoding, and task synchronization. Keep networking/TLS and UI
separately scoped until resource ownership and cancellation are dependable.

The new reductions introduce no explicit copies. Existing iteration may itself
materialize a dictionary key view or an integer count; this is not a streaming
iterator implementation. Numeric helpers inherit Ravi arithmetic and comparison
rules, including truncating integer division and representability errors.

## Performance evidence needed

The existing `tools/benchmark.ps1` measures whole process latency, including
startup, loading, compilation, verification, execution, and output. `run --profile`
now separates compiler phases and root VM verification/GC metrics; peak process
memory and worker totals remain unmeasured. These tools cannot substantiate a
claim that Ravi is faster than Python or close to native speed.

Record median/p95, variation, hardware, toolchain, optimization mode, correctness
checks, and matched workloads. Measure steady-state execution separately from
startup and compilation. Include numeric loops, calls/closures, Unicode strings,
collections, allocation/GC, modules, and 1/2/4-worker CPU throughput. Async
benchmarks must include idle CPU, thread count, cancellation latency, and bounded
memory. Preserve overflow and error semantics while optimizing.
