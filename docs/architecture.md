# Ravi Compiler Architecture

## 1. Architectural Style

Ravi is organized as a dependency-directed set of libraries. Each compilation
phase consumes an explicit immutable input and returns an owned result plus
structured diagnostics. Phases do not reach into CLI state, global allocators,
or one another's private representations.

The architecture favors replaceable boundaries:

- source management is independent of the filesystem;
- the parser depends on a token stream contract, not lexer internals;
- semantic analysis depends on syntax interfaces, not source text;
- optimization operates on IR, not AST nodes;
- backends consume verified IR through a stable lowering contract;
- runtime allocation is exposed through a collector-neutral API.

## 2. End-to-end Pipeline

```text
.rk source
    |
    v
Source Manager and Module Resolver
    |
    v
Lexer -- emits tokens, newline, indent, dedent, and source spans
    |
    v
Parser -- builds lossless syntax and reports recoverable errors
    |
    v
AST Lowering -- produces compact semantic nodes
    |
    v
Name Resolution and Control-flow Validation
    |
    v
Gradual Type Analysis -- inserts guards, boxing, and conversions
    |
    v
HIR -- typed, structured, backend-independent representation
    |
    v
MIR -- explicit control flow, exceptions, ownership, and safepoints
    |
    v
Optimization and Specialization
    |
    +--------------------------+
    |                          |
    v                          v
Bytecode Lowering          Native Lowering
    |                          |
    v                          v
Verifier and VM           Machine code and object emission
    |                          |
    +-------------+------------+
                  |
                  v
       Ravi Runtime, GC, and standard library
```

Bytecode provides fast development, portability, and a reference execution
engine. Native lowering provides ahead-of-time performance. A future tiered JIT
may collect profiles in the VM and compile hot, guarded specializations from
MIR without changing the language front end.

## 3. Configuration and Constants

`src/config/constants.zig` owns immutable language facts and safe defaults.
`src/config/config.zig` defines validated runtime configuration values. A
configuration loader may read CLI, project, or environment settings, but later
phases receive only a validated `CompilerConfig` value.

No compiler package may embed keyword text, file extensions, format versions,
resource limits, or tuning thresholds. Feature behavior is selected using
typed enums and capability records rather than string comparisons.

The configuration layer has no dependency on lexer, parser, semantic, backend,
or runtime packages.

## 4. Source and Module Layer

### Source manager

The source manager assigns a stable `SourceId`, owns immutable UTF-8 buffers,
normalizes line-ending interpretation, and maps byte offsets to line and column
locations lazily. Compiler structures store compact source spans consisting of
a source identity and byte range.

It accepts memory buffers through an interface, allowing CLI files, editor
overlays, generated sources, and tests to use the same front end.

### Module resolver

The resolver converts import declarations into canonical module identities. It
is responsible for search paths, package boundaries, dependency graphs, cycle
policy, and cache lookup. The parser never accesses the filesystem.

The parser accepts imports in Kannada order: `math inda add tago`. AST lowering
normalizes this into a module identity, selection list, and aliases before the
resolver runs. The rejected English-order spelling cannot become an accidental
second grammar.

### Source language profiles

Ravi source language is selected per file, not per project or library. Kannada
order/Kanglish (`kn`) is the default. A file may opt into English spellings
with a first-line header:

```ravi
# ravi: language=en
```

The CLI may explicitly override the header with `--lang kn` or `--lang en`.
Exactly one profile applies to a file; keywords from the other profile are
diagnosed as mixed-language input. Every profile maps into the same canonical
keyword/token IDs before parsing, so AST, semantic analysis, IR, bytecode, and
runtime interfaces are language-neutral.

Libraries may contain modules using different profiles. Their public interface
artifacts expose canonical names, types, visibility, ownership, calling
conventions, and language/compiler versions; consumers do not parse a
dependency's source spelling. Language profile and header are part of source
cache keys and diagnostics may be localized independently of source language.

## 5. Lexer Architecture

The lexer is a stateful, single-pass scanner over a source buffer. Its output is
a contiguous token sequence. Tokens contain a kind, source span, and only the
small payload required by their kind. Identifiers and literal text remain
slices of the immutable source buffer until interning or literal decoding is
actually required.

### Indentation algorithm

The lexer maintains a stack of indentation columns whose first entry is the
root level. One indentation level is exactly four ASCII spaces, defined by the
language constants.

1. At the beginning of a logical line, count leading spaces.
2. Ignore indentation changes for blank and comment-only lines.
3. Emit `indent` only when the column is exactly four greater than the stack top
   and push it; reject every other increase.
4. Emit one or more `dedent` tokens when the column is smaller.
5. Require the final column to equal an existing stack entry.
6. At end of file, emit outstanding `dedent` tokens, then `eof`.

Open parentheses and brackets suppress logical newline and indentation tokens
until their nesting returns to zero. Colons are ordinary tokens; the parser
decides whether a colon introduces a suite. Tabs in leading whitespace and
continuation columns not aligned to a four-space boundary are lexical errors.

Keyword recognition uses the centralized profile tables. The lexer reports
invalid UTF-8, malformed literals, illegal characters, inconsistent indentation,
and configured nesting-limit violations through the diagnostics sink.

String tokens retain their source span, delimiter kind, prefix flags, and whether
escape or indentation processing is required. A separate literal decoder handles
UTF-8 validation, escapes, raw strings, multiline dedentation, and interpolation
segments. This keeps the hot scanner small and lets tests exercise decoding
without invoking the parser.

## 6. Syntax Architecture

### Lossless syntax tree

The parser first produces a lossless syntax representation that retains tokens,
comments, and malformed regions. This tree supports formatting, editor features,
and error recovery. Nodes refer to child ranges in contiguous storage rather
than owning many small allocations.

### Parser

Statements and indentation suites use recursive descent. Expressions use a
Pratt parser driven by a centralized precedence table. The parser receives a
token cursor and diagnostic sink and has no dependency on semantic types.

Every suite follows this shape:

```ravi
adre condition:
    statement
    statement
illa:
    statement
```

A suite requires `colon`, `newline`, `indent`, zero or more statements, and
`dedent`. Single-line suites are excluded initially to preserve one canonical
style and simplify tooling.

`kriya` is parsed as a declaration in statement position and as an anonymous
function in expression position. Anonymous functions accept either `=>` followed
by one expression or a colon followed by the standard newline, indent, and
dedent suite. The arrow has deliberately low binding power so the body consumes
one complete expression without ambiguous call-site punctuation.

### AST lowering

AST lowering removes punctuation and trivia, canonicalizes equivalent syntax,
and produces compact nodes suitable for semantics. Syntax and AST node IDs are
not pointers; they are typed indices scoped to their owning module. A mapping
back to syntax spans preserves diagnostics and tooling navigation.

Docstrings remain ordinary string syntax in the lossless tree. AST lowering
recognizes only the first statement of a module, class, or function as a
docstring and stores it as declaration metadata. Decorators are ordered child
nodes attached to their declaration. Context suites are explicit nodes rather
than generic calls, preserving cleanup semantics before type analysis.

## 7. Semantic Pipeline

Semantic work is split into passes with explicit databases:

1. Declaration collection assigns stable symbol IDs.
2. Import binding connects module interfaces.
3. Name resolution maps references to symbols and scopes.
4. Control-flow construction validates transfers and reachability.
5. Constraint generation describes type relationships.
6. Type solving determines concrete, union, generic, or dynamic types.
7. Boundary elaboration inserts guards, boxing, unboxing, and conversions.
8. Access validation enforces public, private, protected, and internal use.
9. Closure, generator, and async analysis identifies captured or resumable
   state, escape behavior, and cross-thread capabilities.
10. Decorator validation checks input/output signatures, effects, visibility,
    async behavior, and allowed execution capability.
11. Documentation validation resolves docstring fields against symbols, types,
    return values, yields, and declared error behavior.

Queries are designed to be memoizable by module and node identity. This permits
incremental analysis later without embedding an incremental framework into the
language rules.

### Visibility representation

Every declaration carries an explicit resolved visibility, including declarations
whose private or internal visibility came from a default. Access checks operate
on stable symbol and package identities, never name prefixes. Public interface
artifacts contain only public symbols and the minimum layout or inheritance
metadata required to consume them. Override validation prevents a derived class
from violating the base member's visibility contract.

Modifiers are not syntactically mandatory. Semantic declaration collection
materializes `swanta` for unmodified class members and `olage` for unmodified
top-level declarations, so all later passes see one explicit representation.

### Gradual typing representation

The type interner stores canonical types under compact `TypeId` values. Dynamic
is a first-class type, not an error escape hatch. A typed expression records its
result type and any required boundary operation. Diagnostics are emitted for
provably inconsistent static code, while uncertain dynamic operations become
checked IR operations.

## 8. Intermediate Representations

### HIR

High-level IR is typed and structured. It retains functions, lexical scopes,
high-level calls, generators, exception regions, and explicit dynamic boundary
operations. HIR is convenient for language-specific analyses and diagnostics.

### MIR

Mid-level IR uses basic blocks and explicit control-flow edges. It makes normal
and exceptional successors, phi-like block parameters, calls, allocations,
safepoints, guards, and deoptimization metadata visible. MIR is the principal
optimization boundary and must pass a verifier after every transformation in
debug builds.

Generators and async functions lower to explicit state machines. Suspension,
resumption, cancellation, cleanup, task-local context, exception propagation,
source locations, and live GC roots remain visible in MIR. This makes async code
optimizable and debuggable instead of hiding it in runtime callbacks.

Context managers lower to protected cleanup regions with explicit normal,
exceptional, cancellation, return, and loop-transfer exits. Decorator application
is represented as typed declaration elaboration, keeping wrapper costs and
effects visible to optimization. Interpolated strings lower to builder operations
with precomputed capacity when component sizes are known.

Closure conversion gives every anonymous function an internal function identity
and a typed environment layout. Capture-free closures become direct function
references. Non-escaping environments remain in the caller frame when valid;
escaping environments become precisely traced runtime objects. Escape analysis,
inlining, devirtualization, and scalar replacement may remove both the closure
object and indirect call while retaining a generic callable representation when
static proof is unavailable.

HIR preserves lexical capture identities. MIR makes environment creation,
capture loads, mutable synchronization, indirect calls, and safepoints explicit.
The verifier ensures no stack environment escapes and no closure is marked safe
to send or share unless all captures satisfy the corresponding requirements.

### Optimization manager

Passes declare required and preserved analyses. A pass manager controls ordering
using the selected optimization profile. Initial passes include constant
folding, control-flow simplification, dead-code removal, escape analysis,
unboxing, redundant-guard elimination, and monomorphic call specialization.

Passes cannot modify global compiler state. Each returns a change summary so
analysis caches can be invalidated precisely.

## 9. Backend Strategy

### Bytecode backend

The bytecode backend lowers MIR to a compact, versioned instruction format. The
format includes a constant pool, function metadata, exception tables, source
maps, GC stack maps, and optional type feedback slots. A mandatory verifier
checks instruction bounds, control-flow targets, register or stack discipline,
constant references, exception regions, and root metadata before execution.

The VM is a separate library with no parser or AST dependency. Its dispatch
engine may evolve independently from the bytecode format.

### Native backend

The native backend lowers MIR through a backend-neutral interface to target
machine code and object files. The initial implementation can choose a direct
code generator or an external compiler framework without leaking that choice
into semantic analysis. Runtime calls use a documented internal ABI.

Static values use native representations and calling conventions where proven.
Dynamic values use a uniform tagged representation. Generated stack maps expose
managed roots at safepoints.

### Future tiered execution

VM feedback records value shapes and call targets. A future JIT may request a
specialized MIR clone guarded by observed assumptions. Guard failure transfers
to generic bytecode or less-specialized native code. Profiling is an optimization
input, never a semantic authority.

### Development and production profiles

The driver constructs both profiles from the same verified MIR and preserves
identical language semantics.

- Development favors cached frontend results, incremental function compilation,
  bytecode or quickly generated native code, complete safety checks, and rich
  debugger locations.
- Production uses ahead-of-time native lowering, cross-module reachability,
  specialization, inlining, section-level dead stripping, and optional link-time
  optimization.
- Size-oriented production removes unreachable runtime subsystems and optional
  metadata. Static-only applications do not link the VM or dynamic machinery.
- Debug metadata can be embedded, split into a companion artifact, or omitted.

The build interface stays simple: one command selects a typed profile. Detailed
tuning remains available in project configuration and is captured in cache keys.

## 10. Runtime and Garbage Collector

The runtime provides object models, dynamic operations, exceptions, module
initialization, VM services, and the collector-neutral allocation API.

The garbage collector is an independent package behind an interface containing:

- heap initialization and shutdown;
- managed allocation;
- root registration and scoped handles;
- collection requests and safepoints;
- object tracing through descriptors;
- write barriers;
- statistics and diagnostic hooks.

The initial collector is a custom non-moving mark-and-sweep design backed by
GC-owned pages or arenas. Marking starts from precise roots supplied by the VM,
native stack maps, globals, and host handles. Sweeping returns unreachable slots
to size-class free lists. Large objects are tracked separately.

The managed heap supports multiple mutator threads. Each worker uses a
thread-local allocation buffer or local size-class cache, while cross-thread
references live in the shared managed heap. Collection coordinates threads at
explicit safepoints; ordinary execution is not serialized. Root publication,
write barriers, and remembered metadata use atomics or narrow locks. The
collector contract permits later parallel marking and concurrent collection.

No frontend phase imports the GC. The compiler may use Zig allocators and its
own phase arenas; only executed Ravi programs use the managed heap.

## 11. Allocation and Ownership Rules

Each public API states who owns its result and which allocator controls it.

- Session arena: configuration and cross-module session data.
- Source arena: immutable source buffers and line indexes.
- Module arena: syntax, AST, symbols, and long-lived semantic results.
- Scratch arena: temporary pass state, reset after the pass.
- Artifact allocator: serialized bytecode, object data, and cache entries.
- Runtime managed heap: Ravi objects visible to garbage collection.
- Runtime native allocator: VM metadata and unmanaged runtime structures.

Typed IDs and slices must not outlive their owner. Debug builds validate arena
generation where practical. Deinitialization proceeds in reverse ownership
order and remains correct on partial failure.

## 12. Diagnostics

All packages emit structured `Diagnostic` values into an injected sink. A
diagnostic contains a stable identifier, severity, primary span, related spans,
arguments for a message template, and optional fix information. Only adapters
such as the CLI or language server render text.

This separation enables human output, JSON output, tests, localization, and IDE
protocols without compiler phases knowing their presentation environment.

## 13. Debug Architecture

HIR and MIR carry stable source scopes, inline chains, variable identities, and
async suspension locations. Backend-specific emitters translate that common
model into bytecode debug tables or native platform debug information. Optimizer
passes report value remapping and eliminated locations rather than silently
discarding debug state.

A debugger service exposes a Debug Adapter Protocol endpoint over a backend
adapter. Both VM and native adapters implement breakpoints, stepping, stack
unwinding, locals, exceptions, evaluation, and task enumeration. The service may
inspect private members through a capability unavailable to Ravi program code.
Debug builds retain assertions and verifier hooks; production builds compile
those facilities out unless explicitly requested.

Structured docstrings, decorator chains, context regions, and logical async
frames share the same source identity model. Hover help and debugger views can
therefore show the declaration users wrote rather than only generated wrappers
or state-machine functions.

Anonymous functions receive stable source-derived debug identities rather than
unstable compiler sequence numbers. Their frames show parameters and captures,
and optimized-away closure objects do not erase the logical callable frame.

## 14. Compilation Session and Concurrency

A `CompilationSession` owns validated configuration, sources, module graph,
interners, cache access, diagnostics, and cancellation state. It contains no
process-global mutable singleton.

After dependency discovery, independent modules may compile concurrently.
Shared interners and caches expose synchronization through narrow APIs. A
deterministic scheduler and stable diagnostic sort order ensure parallel builds
produce reproducible artifacts and messages.

The scheduler uses bounded work queues and derives its default worker count from
available processors, affinity, container quotas, and the configured memory
budget. Parallel module, function, optimization, and code-generation work is
admitted only when its memory estimate fits the session budget. Scratch arenas
are worker-local and reset promptly to avoid multiplying peak RAM by core count.

## 15. Runtime Concurrency and Eventing

Ravi's runtime has no global interpreter lock. Native threads may execute Ravi
code concurrently on separate cores. A work-stealing scheduler maps lightweight
tasks onto a bounded set of workers, supports structured task groups, and keeps
blocking foreign or filesystem work in a controlled blocking pool.

An event-reactor interface separates async semantics from operating-system I/O.
Backends may use IOCP, io_uring or epoll, and kqueue as appropriate. Completion
events schedule task continuations without blocking a worker. Timers,
cancellation, deadlines, and backpressure are common contracts across reactors.

The concurrency type checker determines whether a value can be moved between
workers and whether it may be referenced simultaneously. Immutable sharing,
ownership transfer, channels, atomics, and synchronized mutable containers have
explicit MIR operations. Unproven dynamic crossings use runtime checks.

Multiprocess execution uses the same task and cancellation concepts through a
process executor. Data crosses by serialization, explicit shared-memory regions,
or OS handles; it never relies on accidental pointer sharing. Shared regions use
typed layouts, explicit synchronization, and reference-independent offsets.

Scheduler, reactor, process executor, and shared-memory providers are interfaces,
allowing embedded, server, desktop, and high-throughput deployments to select
only the runtime components they use.

## 16. Public Package Contracts

Package dependencies flow downward:

```text
cli -> driver -> frontend -> semantic -> ir -> backend
                 |             |        |       |
                 v             v        v       v
              source       diagnostics types  artifacts

vm -> bytecode -> runtime -> concurrency -> memory
native runtime -----------> concurrency -> memory

all packages -------------> config and common utilities
```

Cycles between packages are forbidden. Shared abstractions move into a smaller
lower-level package; higher-level packages never solve cycles by importing each
other's internal files.

## 17. Verification and Testing

Each boundary has focused tests:

- lexer token streams and indentation edge cases;
- parser golden trees and malformed-input recovery;
- AST lowering invariants;
- name and type resolution tables;
- HIR and MIR verifier tests;
- optimization before-and-after snapshots;
- bytecode verifier rejection tests;
- VM/native differential execution;
- GC reachability, root, barrier, and allocation-failure tests;
- complete `.rk` programs with expected output and diagnostics;
- visibility and public-interface compatibility tests;
- deterministic scheduler, race, cancellation, and async-reactor tests;
- development/production parity and production binary-size tests;
- bytecode/native debugger conformance tests.

Fuzz targets consume bytes directly for the lexer, parser, bytecode verifier,
and artifact readers. Serialized data is treated as untrusted input.

## 18. Evolution Rules

- Source syntax changes require a language-version decision.
- Bytecode and cache formats carry explicit versions.
- Internal IR is not a persistence format.
- Public runtime ABI changes are versioned separately.
- Experimental features are capability-gated in validated configuration.
- New collector or backend implementations conform to existing interfaces
  before becoming selectable.
- The maintained barrier register in `docs/design-barriers.md` is reviewed for
  every major feature and release; unresolved tradeoffs remain explicit rather
  than being hidden behind syntax.
