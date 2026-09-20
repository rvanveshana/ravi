# Language design

This is the accepted direction for the Ravi Kannada redesign, not a statement
that every feature below is implemented. See [Implementation status](implementation-status.md)
for the current language and [Development plan](development-plan.md) for delivery gates.

## Consistent source profiles

Kannada/Kanglish and English vocabulary must normalize into the same semantic
operations before execution. Language selection must not add branches to the VM
hot path. Profile parity includes results, errors, mutation, access control, and
resource behavior. Unicode Kannada keywords require a separately validated lexer
and vocabulary; displaying Kannada text in a string does not establish that support.

## Synchronous-looking calls, backend suspension

A normal call completes before the next statement executes. An I/O operation may
suspend its task internally, allowing other runnable tasks to proceed. It must
not silently spawn work or reorder side effects. Explicit structured task scopes
introduce concurrency; isolated workers provide CPU parallelism.

The compiler must propagate suspension through direct and dynamic calls and
preserve frames, roots, exceptions, and cleanup state. Foreign calls that block
require a bounded blocking adapter. Users should not need two versions of every
function merely to select sync or async execution.

Task scopes join their children, propagate cancellation, and report failures.
Queues and channels provide backpressure. A process runtime owns worker budgets,
timers, and I/O resources. Separate mutable heaps and checked transfer rules are
the initial parallelism boundary; arbitrary shared mutable objects are not promised.

## Typing and values

Infer static types where possible and allow explicit dynamic values. Typed public
interfaces need stable signatures. Dynamic-to-static boundaries must validate
values; mutable collection checks must also protect writes through aliases.

The completed type system needs callable types, generic collections, unions,
nullable flow narrowing, protocols, and compatible overrides. Define numeric
widths, overflow, conversions, equality, hashing, collection ordering, evaluation
order, and iterator invalidation before optimizing them. Current VM integers are
signed 48-bit values; future numeric types require an explicit language decision.

## Objects and privacy

Use one object model for typed and dynamic execution: class identity, field
initialization, methods, properties, bound methods, single inheritance, and
protocols. Prefer composition and declared fields before metaclasses or unrestricted
class mutation. Public, internal, protected, and private access must be checked
consistently by static analysis and dynamic lookup.

Encapsulation is not an untrusted-code sandbox. Reflection and serialization must
respect access rules; resource permissions require a separate capability design.

## Errors and deterministic cleanup

Exceptions must carry class, message, cause, traceback, and structured fields.
Preserve worker failures and asynchronous call context. Cancellation must remain
distinguishable from ordinary recoverable errors. OOM reporting needs a bounded
emergency path.

One MIR cleanup model must handle `finally`, context managers, return, break,
continue, exceptions, and cancellation. Enter managers in order and exit successfully
entered managers in reverse order, exactly once. Define failed enter/exit,
exception suppression, and cleanup-error chaining. GC finalization must not be
the primary mechanism for closing files or sockets.

Decorators evaluate expressions in declaration order and apply wrappers from the
innermost decorator outward. Bind the final value only after success. Validate
typed wrappers and preserve metadata through a standard helper.

## Memory and native boundaries

Start with precise, non-moving tracing GC and explicit scoped roots. Cover stacks,
frames, globals, closures, temporary native values, suspended tasks, exceptions,
and queued messages. Separate compiler arenas from runtime heaps. Add safe handle
reuse and payload accounting before collector optimization.

An FFI must specify checked values, ownership, suspension, error conversion, and
resource lifetime. No stable public FFI or native ABI is promised by the current
internal value representation.

## Performance and portability

Optimize against reproducible workloads, including numeric, object-heavy, Unicode,
JSON, file, network, and concurrent programs. Measure startup, compilation, execution,
RSS, allocations, GC pauses, latency, and multi-core scaling separately.

Compare pinned Python implementations and Zig with equivalent algorithms and build
settings. Faster-than-Python execution is a goal, not an established general result.
Safety checks required by the language must survive release optimization. Efficient
resource use includes sleeping when idle, not maximizing CPU utilization.
