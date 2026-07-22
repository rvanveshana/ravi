# Ravi Design Barrier Register

## Purpose

Ravi aims to remove accidental limits found in existing language ecosystems
without pretending that fundamental tradeoffs do not exist. No language can
eliminate hardware limits, network partitions, undecidability, unsafe foreign
code, or every latency-throughput tradeoff. A credible advanced language makes
those constraints explicit, supplies safe high-performance defaults, and lets
specialized applications choose a different policy deliberately.

This register is a living architectural requirement. Each major language or
runtime feature must state which barriers it addresses, what cost it introduces,
how it is measured, and which limitations remain.

## Language and Type-system Barriers

| Barrier in existing ecosystems | Ravi response | Remaining explicit tradeoff |
| --- | --- | --- |
| Dynamic code gives fast iteration but loses optimization and early errors. | Gradual typing, flow-sensitive inference, guarded specialization, and a generic fallback allow dynamic and unboxed static paths in one module. | Dynamic uncertainty still requires tags, guards, or dispatch until profiling or proof removes them. |
| Static languages often force large annotation and ownership burdens. | Local inference, safe ownership defaults, concise annotations, and diagnostics that explain only the missing proof. | Public contracts and ambiguous boundaries still require explicit types. |
| Null values create implicit failure paths. | `none` is a distinct value; static code requires an optional or union type before it can contain `none`. | Dynamic code needs a checked operation when absence cannot be proven away. |
| Exceptions hide control-flow and error cost. | Error and exception edges are explicit in HIR/MIR, declarations expose error behavior, and docstrings can validate documented errors. | The language specification must still define when recoverable values or exceptions are the appropriate API. |
| Access control is convention-based or too verbose. | Optional modifiers with private class and internal module defaults; compiler-enforced public, protected, private, and internal identities. | Reflection and FFI require explicit capabilities and cannot be made both unrestricted and encapsulation-safe. |
| Inheritance can produce fragile base classes. | Visibility-safe overrides, explicit contracts, composition-friendly protocols, and sealed/final evolution points planned as typed features. | Open inheritance remains coupled to base-class behavior and must be chosen deliberately. |
| Metaprogramming and decorators can hide arbitrary transformations. | Typed decorators preserve signatures by default, declare transformations and effects, and remain visible in syntax, docs, caches, and debug metadata. | Powerful build-time generation increases cache and security complexity and therefore needs a restricted capability model. |
| Expression-only lambdas are too weak, while closures can hide allocation and unsafe shared state. | `kriya` supports concise and indentation-based anonymous functions; capture, escape, allocation, send/share capability, and debug identity are explicit compiler analyses. | Escaping mutable captures still require managed storage and synchronization; diagnostics must expose that cost. |

## Text and Data Barriers

| Barrier | Ravi response | Remaining explicit tradeoff |
| --- | --- | --- |
| A character may mean byte, Unicode scalar, or user-visible grapheme. | Immutable UTF-8 strings expose byte length, scalar iteration, and grapheme iteration as different operations. Byte buffers are a separate type. | Grapheme processing costs more than byte processing and must be requested when needed. |
| Repeated immutable-string concatenation becomes quadratic. | Compile-time folding, builders, known-capacity interpolation, and rope-style strategies for repeated growth. | Flattening a rope still has a linear cost when a contiguous ABI buffer is required. |
| Serialization copies data and shared layouts become unsafe. | Typed serialization and explicit offset-based shared-memory regions with versioned layouts. | Cross-process mutation still requires synchronization and cannot safely share ordinary pointers. |
| Numeric convenience causes overflow or silent precision loss. | Explicit width and conversion rules, checked development operations, and policy-selected production behavior recorded in IR. | Exact arithmetic, saturation, wrapping, and maximum speed are distinct policies; no single default is optimal everywhere. |

## Parallelism and Async Barriers

| Barrier | Ravi response | Remaining explicit tradeoff |
| --- | --- | --- |
| A global interpreter lock prevents CPU parallelism. | There is no GIL. Native threads execute Ravi simultaneously; thread-local allocation and narrow runtime synchronization avoid a process-wide execution lock. | Stop-the-world collection may temporarily coordinate mutators until a concurrent collector is selected. |
| Thread APIs are powerful but data races and deadlocks are easy. | Send/share type checks, immutable sharing, ownership transfer, structured task groups, channels, atomics, and synchronized containers. Dynamic crossings are checked. | Explicit low-level locks can still deadlock; tooling, ordering annotations, and diagnostics reduce but cannot mathematically eliminate misuse of unrestricted locks. |
| Async creates a separate ecosystem and blocks accidentally. | Async functions lower to typed state machines; reactors, cancellation, deadlines, backpressure, and async context cleanup are runtime contracts from the start. | Suspension remains observable in scheduling and resource lifetime, so async behavior cannot be completely erased from API contracts. |
| One event loop or scheduler fits only one workload. | Pluggable executors and OS reactors, bounded work stealing, controlled blocking pools, and embedded single-thread executors. | Executor selection changes performance and fairness, though not source semantics. |
| Multiprocessing isolates failures but makes communication costly. | Process executors share task concepts and support typed messages, shared regions, cancellation, and explicit OS handles. | Isolation requires serialization or carefully synchronized shared memory. |
| Core count increases memory use and contention. | Resource-budgeted admission, worker-local scratch arenas, bounded queues, adaptive workers, and cache-conscious structures. | More parallel work is refused or delayed when the memory budget cannot support it. |

## Memory-management Barriers

| Barrier | Ravi response | Remaining explicit tradeoff |
| --- | --- | --- |
| Manual memory gives control but risks leaks and use-after-free. | Managed objects use precise tracing; deterministic context managers own external resources; static escape analysis removes unnecessary heap allocation. | FFI, raw memory, and custom allocators remain explicitly unsafe or capability-gated. |
| Garbage collection simplifies ownership but causes pauses and footprint. | Collector-neutral runtime API, precise roots, thread-local allocation, generational-ready barriers, explicit safepoints, and selectable GC policies. | Throughput, pause time, and memory overhead cannot all be minimized simultaneously; deployment profiles choose and measure a policy. |
| Reference counting adds atomic traffic and cannot naturally collect cycles. | Tracing is the default managed model; deterministic release is expressed by contexts rather than object destruction timing. | Applications requiring hard real-time destruction need restricted regions or a future real-time memory profile. |
| Shared heaps contend across cores. | Local allocation buffers, size-class caches, parallel-ready tracing, remembered metadata, and future NUMA placement behind stable interfaces. | Cross-node object graphs can still incur remote-memory cost. Metrics must make this visible. |
| Out-of-memory paths are rarely testable. | Allocation failures are explicit, allocator injection is supported, and compiler/runtime failure tests are quality gates. | The operating system may still terminate a process under overcommit policy; deployment guidance must account for it. |

## Compiler and Deployment Barriers

| Barrier | Ravi response | Remaining explicit tradeoff |
| --- | --- | --- |
| Fast compilers often produce slower code; optimizing compilers interrupt iteration. | One verified IR feeds fast incremental development and whole-program production pipelines. Persistent content-addressed caches reuse frontend and function work. | Maximum optimization takes more time and is reserved for production or explicit requests. |
| Rich runtimes create large executables. | Reachability-based runtime composition, dead stripping, compact metadata, split symbols, and no VM/async/reflection component unless required. | Highly dynamic reflection or runtime loading necessarily retains more metadata and generic machinery. |
| Build systems and package managers fragment the workflow. | One project model, resolver, lock data, compiler driver, cache key scheme, and simple `run`, `check`, `test`, and `build` commands. | External native dependencies still bring platform toolchain constraints. |
| Builds become non-reproducible and caches become unsound. | Content-based inputs, validated configuration, versioned interfaces, deterministic scheduling, stable diagnostic ordering, and no timestamps in artifacts. | Toolchains outside Ravi must expose reproducible modes or be recorded as non-reproducible inputs. |
| Cross compilation breaks on implicit host assumptions. | Target identity, ABI, runtime capabilities, and system interfaces are explicit driver inputs. Frontend and IR remain target-neutral until lowering. | OS services and native libraries are not universally portable and require target adapters. |
| Compiler parallelism consumes all workstation resources. | CPU, affinity, container, and RAM-aware bounded scheduling with user overrides and per-phase memory estimates. | A strict resource cap may reduce parallelism and extend build time. |

## Debugging and Operations Barriers

| Barrier | Ravi response | Remaining explicit tradeoff |
| --- | --- | --- |
| Optimized code is difficult to step and inspect. | Stable source identities, optimizer value remapping, inline chains, async logical frames, and common bytecode/native debug adapters. | Some optimized-away values cannot be reconstructed truthfully; the debugger reports this rather than inventing a value. |
| Generated wrappers and async machines hide user code. | Decorator chains, context regions, logical frames, and declaration metadata map generated operations back to written source. | Low-level debugging may intentionally expose generated frames in an advanced view. |
| Production observability increases binary size and runtime cost. | Metrics and tracing are capability-based, link-time selectable, sampled when appropriate, and may use separate metadata. | Observability that was stripped cannot be enabled retroactively without a compatible external probe mechanism. |
| Concurrency failures are nondeterministic. | Structured task IDs, scheduler tracing, deterministic test executors, race detection, and replay-compatible event hooks. | Full production replay can be expensive and is an opt-in diagnostic mode. |
| Crashes lose useful context or expose secrets. | Versioned crash records, symbol separation, redaction-aware structured diagnostics, and bounded emergency reporting. | Applications must classify sensitive values; the compiler cannot infer every secret reliably. |

## Ecosystem, Safety, and Evolution Barriers

| Barrier | Ravi response | Remaining explicit tradeoff |
| --- | --- | --- |
| Foreign interfaces bypass language safety. | Generated typed bindings, explicit ownership/calling conventions, pinned handles, and narrow unsafe boundaries. | Ravi cannot guarantee behavior inside foreign code. |
| Dependency scripts create supply-chain risk. | Locked dependency identities, hashes, capability-restricted build actions, auditable generated files, and offline/reproducible modes. | Trust in selected dependencies and compiler distribution remains a governance concern. |
| Language evolution breaks users or freezes design mistakes. | Versioned source editions, bytecode, cache formats, runtime ABI, deprecation diagnostics, and migration tooling. | Supporting old editions has maintenance cost and requires a documented support window. |
| Feature-rich languages become incoherent. | Small orthogonal core, typed capability interfaces, centralized constants, formal grammar, architecture decisions, and feature acceptance gates. | Saying no to overlapping features is an ongoing design responsibility. |
| Sandboxing is confused with memory safety. | Memory safety, capability security, process isolation, resource quotas, and package trust are modeled separately. | Strong adversarial sandboxing still depends on operating-system or virtual-machine enforcement. |

## Acceptance Gate for New Features

Before implementation, every significant feature must answer:

1. What user problem and existing barrier does it solve?
2. Can existing orthogonal features solve the same problem more simply?
3. What are its static, dynamic, memory, binary-size, and compile-time costs?
4. How does it interact with gradual typing, async, concurrency, GC, FFI,
   visibility, documentation, formatting, and debugging?
5. Can unused support be removed from a production binary?
6. Is behavior deterministic, cacheable, fuzzable, and versionable?
7. What remains impossible or deliberately unsupported?
8. Which benchmarks and failure tests prove the intended improvement?

The answer may be a rejection. A futuristic language stays strong by solving
real barriers coherently, not by accumulating every available feature.
