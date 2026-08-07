# Ravi Language Requirements

## 1. Vision

Ravi is a high-performance, gradually typed programming language with the file
extension `.rk`. It combines a compact, Python-like surface syntax with short
Kanglish keywords. A program may start as dynamic code and acquire static type
annotations incrementally without being rewritten.

The implementation targets Zig 0.17 and is designed as a collection of small,
testable compiler and runtime libraries rather than a monolithic executable.

## 2. Design Goals

- Keep common syntax short, readable, and quick to type.
- Use indentation as the only block delimiter.
- Support dynamic, inferred, and explicitly typed values in the same module.
- Compile proven static paths to specialized code without dynamic dispatch.
- Preserve predictable behavior at static and dynamic boundaries.
- Keep the lexer, parser, syntax tree, semantic analysis, backends, runtime,
  and garbage collector independently testable.
- Centralize language spellings, limits, target defaults, and tuning values.
- Provide deterministic diagnostics with precise source spans.
- Make new backends, analysis passes, and runtime policies pluggable.

## 3. Non-goals for the First Milestone

- Self-hosting the compiler.
- A stable foreign-function ABI.
- Distributed compilation.
- A fully concurrent or compacting garbage collector.
- Macro systems or arbitrary compile-time code execution.

These features may be added later without changing the front-end contracts.

## 4. Source and Lexical Rules

### 4.1 Source format

- Source files use the `.rk` extension.
- Source text is UTF-8.
- Identifiers may initially use ASCII letters, digits, and underscore. Unicode
  identifier support is a versioned language feature.
- Physical line endings are normalized by the source manager.
- Every suite level is exactly four ASCII spaces deeper than its parent.
- Tabs in leading indentation are always rejected. The four-space rule is a
  language rule, not a formatter preference or configurable option.
- Comments begin with `#` and continue to the end of the physical line.

### 4.2 Indentation suites

Ravi does not use braces to delimit blocks. A colon introduces a suite, and a
greater indentation level begins it. Returning to a previous indentation level
ends it.

```ravi
math inda add tago

kriya calculate(a: int, b: int):
    nodu:
        adre a > 10:
            kodu add(a, b)
        illa:
            kodu a
    tappu:
        kodu none
```

The lexer emits logical `newline`, `indent`, and `dedent` tokens. Blank lines
and comment-only lines do not affect indentation. A dedent must match a prior
indentation level; otherwise the lexer reports an inconsistent-dedent error.
Every new suite must advance exactly four columns. Newlines inside parentheses
or brackets do not terminate a logical line, but continuation indentation must
also use spaces and align to a four-column boundary.

### 4.3 Kannada-order imports

Import clauses follow natural Kannada word order: the source module comes first,
followed by `inda`, the imported names, and finally the action `tago`.

```ravi
math inda add tago
math inda sin, cos tago
math inda add aagi plus tago
```

The English-order form `inda math tago add` is invalid. Import AST nodes store
the module, selected names, and aliases independently, so this surface order
does not leak into module resolution.

### 4.4 Strings and byte sequences

Ravi strings are immutable UTF-8 text. Byte buffers are a separate type so text
APIs never silently interpret arbitrary bytes.

```ravi
name = 'Ravi'
message = "Namaskara, Ravi"
path = r'C:\data\input.rk'
report = f"Result: {value}"

help_text = """
    First line.
    Second line.
    """
```

- Single and double quotes create single-line strings with identical semantics.
  A project formatter may choose one style without changing behavior.
- Triple single or triple double quotes create multiline strings.
- A multiline string removes the first blank line when present and removes the
  common indentation of subsequent nonblank lines. Its closing delimiter must
  align with the statement that opened it.
- Standard escapes are centrally specified. Unknown escapes are compile errors.
- The `r` prefix creates a raw string and the `f` prefix creates an interpolated
  string. Prefixes may be combined only in combinations defined by the language
  specification.
- Interpolation uses `{expression}`, contains a normal Ravi expression, and is
  lowered to a typed formatting operation rather than runtime source evaluation.
- Literal braces in formatted strings use doubled braces: `{{` and `}}`.
- Indexing, byte length, Unicode scalar iteration, and grapheme iteration are
  distinct APIs. Text cannot be accidentally sliced through a UTF-8 sequence.
- Compile-time concatenation and interning avoid duplicate immutable constants.
  Runtime concatenation uses a builder or rope strategy when repeated growth
  would otherwise become quadratic.

Literal size, decoded size, interpolation depth, escape forms, and compile-time
folding limits are centralized constants. The lexer records raw spans; decoding
and allocation occur only when required.

### 4.5 Centralized language definition

No subsystem owns private copies of language spellings or system limits. The
future `src/config/constants.zig` module is the source of truth for:

- keyword spellings and their token kinds;
- source extension and encoding policy;
- indentation and nesting limits;
- numeric and string literal limits;
- compiler and bytecode format versions;
- default optimization, diagnostics, GC, and target settings;
- resource limits and growth factors.

### 4.6 Source language selection and multilingual modules

Kannada/Kanglish (`kn`) is Ravi's default source profile. English (`en`) is an
opt-in profile selected by the first line of a file:

```ravi
# ravi: language=en
```

The command line may override a file header with `--lang kn` or `--lang en`.
If neither is present, `kn` is selected. A file cannot mix keyword profiles;
using a keyword from the inactive profile is a lexical error. Ordinary
identifiers, literals, punctuation, source spans, and comments are unchanged
by profile selection.

Each profile maps spellings to the same canonical token and semantic keyword.
Therefore a Kannada module and an English module can be compiled into the same
library or dependency graph. Public interfaces are language-neutral and carry
canonical symbols, types, visibility, ownership, calling conventions, and
language/compiler version metadata. The source profile is included in cache
keys, while diagnostic presentation language remains an independent setting.

Built-in spellings follow the active profile as well: Kannada uses `mudrisu`
for scalar output, while English uses `print`. Both lower to the same
language-neutral runtime print operation and cannot be mixed within one file.

Command-line and project configuration may override permitted defaults, but
must be validated into an immutable `CompilerConfig` before compilation.

## 5. Language Surface and Kanglish Keywords

| Category | Conventional meaning | Ravi spelling |
| --- | --- | --- |
| Control flow | `if` | `adre` |
| Control flow | `elif` | `inadre` |
| Control flow | `else` | `illa` |
| Control flow | `while` | `vargu` |
| Control flow | `for` | `prati` |
| Control flow | `break` | `nillu` |
| Control flow | `continue` | `munde` |
| Control flow | `pass` | `bidu` |
| Functions | `function` | `kriya` |
| Functions | `return` | `kodu` |
| Functions | `yield` | `taru` |
| Errors | `try` | `nodu` |
| Errors | `except` | `tappu` |
| Errors | `finally` | `kone` |
| Modules | `import` | `tago` |
| Modules | `from` | `inda` |
| Context | `with` | `jote` |
| Context | `as` | `aagi` |
| Values | true | `true` |
| Values | false | `false` |
| Values | no value | `none` |
| Logic | `and` | `mattu` |
| Logic | `or` | `athva` |
| Logic | `not` | `alla` |
| Membership | `in` | `alli` |
| Identity | `is` | `ide` |
| Objects | `class` | `roopa` |
| Scope | `global` | `ella` |
| Visibility | public | `saarva` |
| Visibility | private | `swanta` |
| Visibility | protected | `vansha` |
| Visibility | module-internal | `olage` |

Keywords are reserved and case-sensitive. Contextual keywords may be introduced
later only through a language-version change.

### 5.1 Access control

Ravi access control is explicit, statically enforced, and never implemented by
name mangling conventions. The initial visibility model is:

- `saarva`: accessible through the declaring module's public interface;
- `swanta`: accessible only inside the declaring class body;
- `vansha`: accessible inside the declaring class and its subclasses;
- `olage`: accessible only inside the declaring package or module boundary.

Visibility modifiers are optional. Class members default to `swanta`, while
top-level declarations default to `olage`. A developer writes a modifier only
when the declaration needs different visibility. Anything exported from a
package must be marked `saarva`; the compiler emits a versioned public interface
containing only exported declarations. A subclass cannot widen or narrow an
override incompatibly with its base contract.

```ravi
saarva roopa Account:
    swanta balance: int

    saarva kriya deposit(amount: int):
        balance = balance + amount

    vansha kriya validate(amount: int) -> bool:
        kodu amount > 0
```

Ordinary reflection and dynamic member access must obey the same rules. Trusted
debugger inspection is a separate capability and does not make private members
accessible to Ravi program code.

### 5.2 Standard docstrings

A module, class, or function may place a string literal as its first statement.
The compiler recognizes it as documentation and does not execute or allocate it
as an ordinary runtime expression. Ravi uses a compact Sphinx-style field list:

```ravi
kriya divide(value: float, by: float) -> float:
    """Divide a value.

    :param value: Value to divide.
    :param by: Non-zero divisor.
    :return: Quotient of value and divisor.
    :raises ZeroDivisionError: When by is zero.
    """
    kodu value / by
```

The first line is a short summary. An optional blank line separates a longer
description. Supported standard fields include `param`, `type`, `return`,
`rtype`, `raises`, `yield`, `ytype`, `ivar`, `example`, `note`, and `warning`.
Types normally come from Ravi annotations, so repeating `type` or `rtype` is
optional and discouraged unless it adds information unavailable to the type
checker.

Docstrings are parsed into structured documentation during compilation. The
compiler validates parameter names and documented exceptions, and documentation
tools consume the structured form rather than reparsing source. Development
artifacts retain docstrings by default; production builds may strip them or emit
them into a separate documentation artifact.

### 5.3 Decorators

Decorators use a minimal `@name` or `@name(arguments)` form immediately above a
function, class, or supported declaration.

```ravi
@cache(size=256)
@trace
kriya calculate(value: int) -> int:
    kodu value * value
```

Decorator expressions are evaluated from top to bottom and applied from bottom
to top. Every decorator has a checked input and output declaration type. A
signature-changing decorator must declare that transformation explicitly;
otherwise it must preserve the wrapped signature, visibility, documentation,
effects, async behavior, and debugger identity.

Decorators cannot perform arbitrary hidden AST mutation. Compiler-recognized
attributes, runtime wrappers, and build-time code generation are separate typed
capabilities with separate security and caching rules. The syntax tree, semantic
model, generated documentation, and debugger all retain the decorator chain.

### 5.4 Context managers

`jote` provides deterministic acquisition and release using Kannada clause
order. `aagi` optionally binds the entered value.

```ravi
file_open('data.txt') jote file aagi:
    text = file.read()
```

Context values implement a typed context protocol with enter and exit operations.
Exit receives the completion reason and may explicitly suppress a matching
error. Cleanup runs for normal completion, `kodu`, `nillu`, `munde`, cancellation,
and exceptions. Multiple contexts enter left to right and exit right to left.

Synchronous and asynchronous contexts use distinct protocols so blocking cleanup
cannot accidentally run on an event-loop worker. HIR and MIR preserve context
regions and cleanup edges, allowing optimization without losing deterministic
release or debugger stepping.

### 5.5 Anonymous functions and closures

Anonymous functions use `kriya`, so Ravi does not need a second function keyword.
A concise expression body uses `=>`; a multiline body uses the normal colon and
strict four-space indentation rules.

```ravi
double = kriya(value: int) -> int => value * 2

validator = kriya(value: int) -> bool:
    adre value < 0:
        kodu false
    kodu true

numbers.map(kriya(value: int) => value * value)
```

The expression form returns its expression implicitly. The multiline form uses
normal `kodu` rules. Parameter annotations, defaults, variadic parameters,
return annotations, gradual types, generators, and future async modifiers follow
the same contracts as named functions.

Anonymous functions are lexical closures:

- referenced outer values are captured automatically for reading;
- mutable capture must be explicit and is rejected when safe lifetime or
  synchronization cannot be established;
- capture-free closures lower to ordinary function pointers when their calling
  convention permits it;
- non-escaping capture environments may live on the stack or be scalar-replaced;
- escaping environments use traced managed storage with precise field metadata;
- a closure's ability to move between threads or be shared concurrently is
  derived from every captured value;
- recursive use through an assigned binding follows definite-initialization
  rules and cannot observe a partially initialized closure.

Closure identity is reference identity; structural equality of captured state is
not implicit. Tooling assigns a stable display name from the enclosing symbol and
source location, exposes captured variables, and shows the written anonymous
function rather than compiler-generated environment machinery.

## 6. Gradual Type System

### 6.1 Type modes

Every expression is assigned a type during semantic analysis. That type may be
concrete, inferred, generic, a union, or `dynamic`.

- **Explicit static:** annotations such as `a: int` are checked at compile time.
- **Inferred static:** local values receive a concrete type when analysis can
  prove one without changing observable behavior.
- **Dynamic:** omitted annotations at unresolved boundaries use `dynamic` and
  carry runtime type information.

The absence of an annotation does not automatically force all downstream code
to remain dynamic. Flow-sensitive analysis may specialize stable paths while
retaining a guarded fallback.

### 6.2 Consistency and boundaries

Ravi uses type consistency, rather than unrestricted implicit conversion, at
static/dynamic boundaries:

- A static value may be boxed when passed into dynamic code.
- A dynamic value entering static code receives a runtime type guard.
- A failed guard raises a typed runtime error with the originating source span.
- Numeric widening rules are explicit and centrally defined.
- Narrowing conversions require an explicit conversion operation.

The compiler records inserted guards and boxing operations in typed IR so that
optimization passes may remove redundant checks safely.

### 6.3 Core types

The initial type universe includes:

- `none`, `bool`, fixed-width signed and unsigned integers, and floating point;
- UTF-8 strings and byte buffers;
- lists, maps, tuples, functions, generators, classes, and instances;
- unions and nullable types;
- `dynamic`, representing a runtime-tagged value;
- `never`, for paths that do not return.

Exact widths, aliases, ABI layouts, and permitted implicit promotions belong in
the language specification and centralized configuration.

### 6.4 Function contracts

Parameters and return values may be annotated independently. A function with a
fully concrete signature is eligible for an unboxed calling convention. A
partially dynamic signature uses the uniform runtime value representation at
the dynamic positions. Public module signatures are stored in interface
metadata so dependants need not parse implementation bodies.

### 6.5 Sound optimization

Optimization must never assume a concrete type merely because it was observed
during one execution. Specialization requires a proof from static analysis or a
runtime guard with a correct deoptimization or generic fallback path.

## 7. Error and Control-flow Semantics

- `nodu`, `tappu`, and `kone` define structured exception handling.
- `kone` executes on normal exit, return, loop transfer, and exceptional exit.
- `kodu` returns a value; a missing value produces `none`.
- `taru` transforms a function into a resumable generator.
- `nillu` and `munde` are legal only inside loops.
- Static analysis reports unreachable code and invalid control-flow placement.

The precise exception hierarchy and matching syntax are deferred to the core
language specification, but the IR must model exceptional edges explicitly.

The initial executable subset supports numeric and scalar-array iteration with
Kannada-order syntax such as `prati i alli 3:` and `prati item alli [1, 2, 3]:`.
Numeric iteration visits `0` through `limit - 1`; array iteration visits each
stored scalar. `nillu` and `munde` are valid inside these loops. Map iteration
and general iterator protocols remain part of the full control-flow contract.

`shreni(...)` is the Kannada numeric range constructor; `range(...)` is its
English-profile spelling. Both support `limit`, `start, stop`, and
`start, stop, step`, for example `prati i alli shreni(1, 5, 2):`. An
unannotated array such as `values = [1, 2]` is
dynamic. An annotated array such as `values: int[] = [1, 2]` is statically
checked for homogeneous element types; mixed elements are rejected before
execution.

## 8. Memory Model

### 8.1 Separate compiler and program memory

Compiler allocations and compiled-program allocations have different owners:

- The compiler uses phase or module arenas for source data, syntax nodes,
  symbols, types, and temporary pass data. Entire arenas are reset together.
- The Ravi runtime uses a custom heap and garbage collector for managed program
  objects. It does not depend on compiler arenas.
- Native resources such as files and sockets are deterministic runtime handles;
  the GC is not the primary resource-management mechanism.

### 8.2 Managed heap

Heap objects contain a compact header describing object kind, tracing state,
size class, and runtime type metadata. References between managed objects are
visible to the collector through type-specific trace descriptors. Static scalar
values remain unboxed where possible and do not enter the managed heap.

The first implementation may use a non-moving, stop-the-world mark-and-sweep
collector backed by custom arena or page allocation. Its public interface must
already support later replacement by generational, incremental, or concurrent
collectors.

### 8.3 Roots and safety

Collector roots include VM stacks, native execution frames described by stack
maps, module globals, active handles, and explicitly registered host roots.
Compiler-generated safepoints occur at allocation sites and selected loop or
call boundaries. Precise roots are preferred; conservative scanning is not part
of the language contract.

Write barriers, even if initially inactive, are represented in the runtime API
so a generational collector can be introduced without redesigning every object
mutation operation.

### 8.4 Allocation policy

- Small objects use size-class allocation from GC-owned pages.
- Large objects use a separately tracked allocation path.
- Allocation counters trigger collection according to centralized policy.
- Out-of-memory behavior is explicit and propagated; it is never silently
  converted into a language-level value.
- Compiler and runtime tests may inject failing allocators.

## 9. Module, Build, and Deployment Model

- Each source file is a module with an explicit canonical identity.
- Imports resolve through a module resolver, not directly inside the parser.
- Import discovery and dependency analysis precede parallel module compilation.
- Cycles are diagnosed or supported according to a separately specified module
  initialization policy.
- Cache keys include source content, compiler version, language version, target,
  validated configuration, and dependency interfaces.
- Reproducible builds avoid timestamps and machine-specific paths in artifacts.
- `ravi run file.rk` runs a source file with the development profile.
- `ravi build` builds a project with an explicitly selected or documented
  default profile; `ravi build --prod` produces a production artifact.
- The development profile prioritizes incremental compilation, useful checks,
  full debugger metadata, and quick bytecode or low-optimization native output.
- The production profile uses ahead-of-time compilation, whole-program
  reachability, dead stripping, optional link-time optimization, compact
  metadata, and split or stripped debug information.
- Runtime features are linked by reachability. A static-only executable does not
  carry the VM, async reactor, reflection metadata, or unused standard modules.
- Speed, size, and balanced production policies are typed build options with
  centralized defaults; source semantics do not change between profiles.

## 10. Diagnostics and Tooling

All phases report structured diagnostics containing a stable code, severity,
primary source span, optional related spans, and remediation notes. Libraries do
not print directly. The CLI owns terminal rendering.

The parser should recover after common mistakes so editors receive multiple
useful diagnostics per pass. The architecture must support a formatter,
language server, documentation generator, debugger metadata, and incremental
analysis without duplicating front-end logic.

The debugger must support both bytecode and native programs through one debug
model: breakpoints, stepping, stack frames, locals, private-member inspection,
exception stops, async task views, and source-mapped optimized code. Ravi will
provide a Debug Adapter Protocol endpoint so editors need no compiler-specific
integration. Production debug information may be emitted as a separate file.

## 11. Parallelism, Concurrency, and Async I/O

### 11.1 No global interpreter lock

Ravi has no global interpreter lock. Independent Ravi threads may execute
language code simultaneously on different cores. Runtime bookkeeping uses
fine-grained synchronization, atomics, thread-local state, and safepoint
coordination; a garbage-collection pause is not a lock around normal execution.

### 11.2 Execution models

- Native threads provide true shared-memory parallelism for CPU work.
- Lightweight tasks use structured concurrency and an adaptive work-stealing
  scheduler across a bounded worker pool.
- Async functions suspend without blocking a worker and resume through an I/O
  reactor abstraction backed by the best supported operating-system facility.
- Processes provide failure isolation and independent heaps for workloads that
  benefit from multiprocess execution.
- Channels, task groups, cancellation, deadlines, atomics, mutexes, reader-writer
  locks, semaphores, and condition variables are first-class runtime facilities.

Async is not syntax sugar over one hidden event loop. The compiler lowers async
functions to typed state machines in HIR/MIR, with suspension points, cancellation
cleanup, exception edges, debugger locations, and GC roots represented
explicitly. Event loops are runtime executors selected through a stable reactor
interface. Exact short Kanglish spellings for async operations require a
separate syntax decision before implementation.

### 11.3 Safe sharing

Immutable values are freely shareable. Mutable values cross task or thread
boundaries only when their type is proven safe to send and, for simultaneous
access, safe to share. Static code receives compile-time data-race diagnostics.
Dynamic code receives checked runtime barriers where proof is unavailable.

Explicit shared-memory regions support zero-copy exchange between threads and,
when requested, processes. Their lifetime, layout, synchronization, and element
types are explicit. Raw pointers never become process-portable references.
Message passing remains the preferred ownership-transfer mechanism.

### 11.4 Resource governance

Compiler and runtime schedulers derive initial parallelism from available CPUs,
process affinity, container quotas, and memory limits, then accept explicit
validated overrides. Queues are bounded, blocking operations use a controlled
blocking pool, and cancellation propagates through task trees.

Thread-local allocation buffers reduce allocator contention. Work placement,
allocation, object layout, and queue structures favor cache locality and avoid
false sharing. NUMA-aware placement is a future selectable policy behind the
same scheduler and heap contracts.

## 12. Performance and Footprint Requirements

- Token and syntax nodes refer to source spans instead of copying lexemes.
- The lexer performs a single forward scan and avoids allocation per token.
- Front-end data is cache-friendly and uses compact indices where practical.
- Static paths avoid boxing, tag checks, and GC allocation when proven safe.
- Dynamic call sites may use inline caches while preserving a generic fallback.
- Compilation phases expose timing and allocation metrics behind a diagnostics
  interface rather than writing telemetry directly.
- Front-end modules compile in parallel after dependency discovery; independent
  functions and backend units may also compile in parallel.
- Parallelism is adaptive and bounded so adding workers does not cause
  uncontrolled memory growth.
- Phase arenas, compact indices, string interning, incremental caches, and early
  release of scratch data bound compiler RAM use.
- Production binaries remove unreachable functions, types, runtime components,
  reflection data, bytecode, diagnostics text, and unwind data when the chosen
  deployment policy permits it.
- The runtime exposes CPU time, allocation, heap, pause, scheduler, and async I/O
  metrics without requiring them in stripped production builds.

Concrete budgets will be established by benchmark suites and then stored as
versioned configuration, not scattered literals.

## 13. Quality Gates

- Unit tests for every independent package.
- Golden tests for tokens, syntax trees, diagnostics, typed IR, and bytecode.
- Differential tests between interpreter and native execution.
- Fuzzing for lexer, parser, bytecode verifier, and deserializer inputs.
- Allocation-failure tests for recoverable compiler paths.
- End-to-end tests for mixed static and dynamic programs.
- Benchmark tracking for compilation latency, runtime, peak memory, and GC
  pauses.
- Race-detector and concurrency stress tests for shared-memory programs.
- Scheduler, cancellation, async I/O, and multiprocess integration tests.
- Binary-size budgets and stripped-artifact inspection for production profiles.

Tuple, set, and dictionary literals are executable collection values. Tuples use (a, b), sets use {a, b}, and dictionaries use {key: value}. Unannotated collections are dynamic; annotated homogeneous collections are checked by semantic analysis.

Collection APIs are type-specific: lists support append, extend, insert, pop,
remove, clear, contains, and indexed update; tuples are immutable and support
indexing and length; sets support add, remove, contains, union, intersection,
and difference; dictionaries support key lookup/update, remove, contains,
keys, values, items, and clear. VM collection storage is isolated in a
reusable module instead of the instruction dispatcher.

The first executable bilingual methods are `serisu`/`append`,
`olagide`/`contains`, and `khaali`/`clear` for Kannada/English respectively.
