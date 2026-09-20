# Architecture

This document describes the current Ravi Kannada implementation. The desired
end state is specified in [Language design](language-design.md); completion is
tracked in the [Development plan](development-plan.md).

## Current compilation paths

```text
.rk source -> lexer -> parser / AST -> semantic checks
                                  |
                                  +-> supported HIR subset -> MIR -> bytecode
                                  |
                                  +-> direct AST compiler -> bytecode
                                                               |
                                                      verifier -> VM
```

`src/main.zig` coordinates the CLI. `src/compiler/hir_pipeline.zig` selects its
supported subset and sends other shapes through `hir_compatibility.zig` to the
AST compiler. The adapter uses the AST's source profile; it no longer retries
compiler failures under another language profile. The direct AST path remains.

Imports have a separate integration path: the loader builds a dependency graph,
then the CLI concatenates source and compiles it through the AST adapter. This
is not independent module compilation. Namespaces, cross-profile imports, source
identity, and module initialization still need a unified implementation.

## Component boundaries

| Component | Responsibility | Current constraint |
| --- | --- | --- |
| `src/source`, `src/diagnostics` | Source buffers, locations, diagnostic formatting | Locations are not complete across every lowering path |
| `config/constants.zig`, `src/lexer` | Profile vocabulary, tokens, indentation | Executable keywords use Latin-script Kanglish or English |
| `src/parser`, `src/ast` | Expressions, suites, declarations, source-profile metadata | Some parsed features have no complete executable semantics |
| `src/semantic`, `src/types` | Symbols, visibility metadata, type checks | Not a complete type inference or access-control system |
| `src/compiler`, `src/ir` | AST/HIR/MIR lowering and bytecode emission | Two lowering paths remain |
| `src/bytecode` | Instruction encoding, metadata, verification | Verification is a correctness boundary still under development |
| `src/vm` | Execution, frames, values, objects, collections, faults | Handle ownership and language protocols need further work |
| `src/memory` | Managed allocation, roots, mark/sweep collection | Non-moving collector; marking uses allocation-list searches |
| `src/concurrency` | Bounded workers, completion events, channels, state metadata | OS-thread tasks, not transparent async I/O |
| `src/modules` | Resolution, dependency graph, interface/cache artifacts | CLI execution does not yet preserve separate modules |
| `src/backend` | Backend contracts and native experiment | Native emitter handles an x86-64 constant-return shape only |
| `src/lsp`, `src/debug` | Editor/debugger infrastructure | Not complete production integrations |

## Runtime and ownership

A VM owns its operand stack, call frames, handle tables, collector, and task
futures. [Runtime ABI](runtime-abi.md) defines the internal `Value` representation.
Objects include strings, sequences, dictionaries, closures, captured cells,
instances, and exceptions. Allocation rollback releases unpublished objects.

Compiler/session arenas and managed program objects have different lifetimes.
The VM reconstructs roots from active values; allocation may trigger collection.
Correctness depends on covering temporary values and every allocation/suspension
boundary, not merely on using Zig or a garbage collector.

## Worker execution

The scheduler uses a bounded ring queue and I/O-backed synchronization. Submission
and shutdown share a lock; accepted tasks drain before the pool is destroyed.
Initialization rollback wakes started workers before joining them.

A spawned function runs in a child VM using a thread-safe allocator. Arguments
and results currently support scalar values only. VM-local object handles are
rejected instead of being interpreted in another heap. Completion preserves the
runtime error identity; structured exception payload transfer remains unfinished.

Ordinary waits and sleep can block an OS thread. Futures with timeouts use a
monotonic deadline and recheck it after spurious wakeups. Cancellation metadata
and channels exist as runtime components, without a complete language-level
structured-concurrency API.

## Required consolidation

The next architecture must route all supported programs through resolved, typed
HIR and verified MIR. Semantic analysis must own symbol resolution, captures,
access checks, and dynamic boundary guards. Backends must share exception,
cleanup, suspension, and memory contracts.

Remove the alternate compiler after the supported subset is represented in the
single pipeline. Unsupported features must report explicit diagnostics. Native
and VM backends may coexist as consumers of the same MIR; error-driven fallback
must not define language semantics.
