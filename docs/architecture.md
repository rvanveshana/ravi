# Architecture

This document describes the current Ravi Kannada implementation. The desired
end state is specified in [Language design](language-design.md); completion is
tracked in the [Development plan](development-plan.md).

## Executable compilation pipeline

```text
.rk files -> per-file lexer/parser -> module dependency graph
                                   -> qualified AST linking
                                   -> lexical resolution and type checks
                                   -> AST bytecode lowering
                                   -> verification -> optimization -> verification -> VM
```

`src/compiler/pipeline.zig` is the executable compilation service used by CLI
checking, running, tracing, disassembly, and compiler integration tests. The
former HIR subset selector, compatibility adapter, and unused AST-to-HIR lowering
implementation have been removed. Unsupported source constructs produce errors;
compiler failures never select a different compiler or source profile.

`src/modules/loader.zig` parses dependencies under their own profiles, checks
imports against public exports, detects cycles, and orders initialization.
`src/modules/linker.zig` relocates AST IDs and qualifies bindings by module ID.
It links parsed trees rather than concatenating source text. Dependencies are
initialized once, local bindings may shadow imports, and spans retain their
original source identity. CLI profile overrides apply to the root module.

This is whole-program AST linking, not independent binary module compilation.
HIR/MIR data structures and native backend experiments remain explicit research
components. A future source-to-MIR compiler must replace the executable lowering
as a complete implementation, rather than introducing another subset selector.

## Component boundaries

| Component | Responsibility | Current constraint |
| --- | --- | --- |
| `src/source`, `src/diagnostics` | Source buffers, locations, diagnostic formatting | Locations are not complete across every lowering path |
| `config/constants.zig`, `src/lexer` | Profile vocabulary, tokens, indentation | Executable keywords use Latin-script Kanglish or English |
| `src/parser`, `src/ast` | Expressions, suites, declarations, source-profile metadata | Some parsed features have no complete executable semantics |
| `src/semantic`, `src/types` | Symbols, visibility metadata, type checks | Not a complete type inference or access-control system |
| `src/compiler`, `src/ir` | AST/HIR/MIR lowering and bytecode emission | Executable lowering is AST-based; general source-to-MIR compilation is unfinished |
| `src/bytecode` | Instruction encoding, metadata, verification | Verification is a correctness boundary still under development |
| `src/vm` | Execution, frames, values, objects, collections, faults | Handle ownership and language protocols need further work |
| `src/memory` | Managed allocation, roots, mark/sweep collection | Non-moving collector with indexed allocation lookup and adaptive live-set thresholds |
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

## Shared contracts

Integer operands and results use one signed 48-bit arithmetic implementation.
Constant folding preserves operand-range errors, overflow, division by zero,
and truncating remainder semantics. The optimizer compacts instructions with a
relocation map and never folds across an incoming control-flow edge.

Semantic analysis builds lexical scopes and resolves references. Scalar
annotations are checked when argument types are known and enforced by bytecode
guards at function entry and explicit typed assignments. This remains gradual
analysis, not complete inference of object protocols and all dynamic behavior.

The VM verifies frame operands and metadata before execution. Packed bytecode
uses the same VM; it does not select a separate fast dispatcher. Compiler/session
arenas and reclaimable runtime allocations use separate backing allocators.
The collector indexes managed pointers and adjusts its collection threshold to
the live set. Literal-aware formatting preserves string bytes, including tabs,
trailing spaces, and embedded line endings.
