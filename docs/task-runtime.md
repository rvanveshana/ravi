# Task runtime and core-library contracts

Development revision, 2026-10-30. These contracts describe the implemented
runtime, including its limits; they do not certify production readiness.

## Execution and ownership

`spawn` / `horabidu` starts independent work. `wait` / `kaayu` returns its
result or propagates its failure. Spawned tasks use retained VM frames, a shared
CPU worker pool, and one event-driven timer thread. Nested task VMs borrow that
pool. Sleeping and waiting tasks park without holding a CPU worker. Ordinary
root execution remains synchronous.

Each task still owns a separate VM heap. The pool admits at most 4,096 live
tasks; each VM retains at most 4,096 future entries. Scope completion joins child
tasks and propagates unobserved failures. An escaping root error requests child
cancellation; VM destruction joins and frees the scope. A cancelled task gets
one injected `CancelledError`, allowing its handlers and cleanup code to run.
Cancellation is cooperative, so cleanup that blocks indefinitely can delay
shutdown. Running OS file calls finish before their contexts are destroyed.

`ravi.tasks.cancel(task)` requests cancellation. `is_done(task)` checks
completion. `wait_for(task, milliseconds)` adds a monotonic deadline; a timeout
does not cancel the task. `release(task)` reclaims a completed future and
invalidates its handle. Repeated waits work before release. Future slots carry
generation numbers so a released handle cannot refer to a later task.

Futures are not automatically reclaimed by GC. Applications that create tasks
in a long-running loop must release completed futures or end the owning scope.
No general nested block-scope syntax is introduced by this revision.

## Program and value transfer

The first spawn captures an immutable, independently allocated program snapshot
and verifies it once. Nested tasks execute that same snapshot without repeating
full verification at each resume. Mutable caller chunks are never treated as
permanently verified. Changes to source chunks after spawning do not change the
captured program.

Arguments, results, and raised payloads use immutable copy packets. Strings,
lists, tuples, sets, dictionaries, captured cells, closures, instances, and
exception objects can be reconstructed in the receiving VM. A packet preserves
aliases and cycles within its graph. Mutable copies belong to different heaps.
Functions refer to the captured program's function table. Raw pointers and
future handles cannot cross this boundary.

A packet is limited to 65,536 nodes, 256 graph levels, and 8 MiB of charged
payload storage. Limit failures raise `ResourceLimitError`. Allocation failure
rolls back newly published receiver objects and roots. Packet arena overhead is
additional to the charged payload size.

## Channels

`ravi.channels.channel(capacity)` creates a bounded channel with capacity
1–4,096. `send` and `receive` wait for room or a message. `send_for` and
`receive_for` accept millisecond deadlines. Spawned tasks park while waiting;
root callers use I/O-backed conditions. Storage is a FIFO ring and locks are
I/O-backed mutexes rather than yielding spin locks.

`close` prevents further sends and wakes waiters. Receivers drain existing
messages, then get `ChannelClosedError`. `none` is a valid message, distinct
from closure or timeout. A receive restores its copy before removing the queued
packet, preserving the message if restoration runs out of memory.

Channel identity can be shared as a task argument or result. Channel identities
inside messages are rejected, including identities nested in a collection, to
avoid reference cycles between channel queues. Messages otherwise use the same
copy-transfer contracts as tasks. Each VM retains at most 4,096 channel handles;
closed handles remain until VM destruction. FIFO message order does not promise
FIFO scheduling of competing waiters.

## Core libraries

The module interfaces are development version `0.1`; a package-version resolver
is not implemented. Existing Kannada/Kanglish aliases remain available.

| Module | Operations and limits |
| --- | --- |
| `ravi.files` | `read_text`, `write_text`; UTF-8 only, 8 MiB per operation, paths up to 32,768 bytes without NUL; write truncates the named file |
| `ravi.paths` | `join`, `basename`, `dirname`; lexical platform path operations, not filesystem resolution |
| `ravi.bytes` | `encode_utf8`, `decode_utf8`; integer-list buffers, byte values 0–255, 8 MiB limit; no arbitrary binary file API yet |
| `ravi.json` | `parse`, `encode`; 8 MiB text, depth 128, bounded nodes; rejects duplicate keys, invalid UTF-8, nonfinite floats, cyclic output, and integers outside Ravi's 48-bit range |
| `ravi.time` | monotonic and wall-clock milliseconds, elapsed time, sleep; use monotonic time for intervals |
| `ravi.environment` | `get`; missing variables return `none` |
| `ravi.logging` | informational/error text to stderr; no rotation or structured sink yet |
| `ravi.testing` | true/equality assertions; string equality compares text, other equality follows current VM value semantics |
| `ravi.tasks` | cancellation, completion, timed waiting, explicit future release |
| `ravi.channels` | bounded communication, deadlines, close/drain |

File helpers use standard library operations that close handles before returning.
Spawned file/environment calls run on a separate shared pool with two workers;
their CPU task frames suspend until completion. This is bounded blocking I/O
offload, not a completion-based asynchronous networking implementation.
Networking/TLS and Kirana UI remain unfinished.

## Measurements and release gates

`ravi run --profile file.rk` reports load, lex, parse, link, compile, and execution
wall-clock nanoseconds. Compiler timings separate analysis, lowering,
optimization, and verification. Root VM counters include executed instructions,
verification time, managed allocation counts, live managed bytes, collection
count, and GC time. Scheduler output is a snapshot after execution. Worker VM
allocation totals, allocator latency, and scheduler latency distributions are
not yet aggregated. Profiling itself adds instrumentation overhead.

`tools/fuzz_source.ps1` runs deterministic bounded source mutations through
`check`, with per-process deadlines and retained reproduction inputs. CI runs
these on Windows and Linux ReleaseSafe builds. Configuring a job does not show
that it has executed successfully. Sustained concurrency/CPU/memory measurements,
cross-platform results, full allocator sweeps, and VM/native conformance remain
release gates.
