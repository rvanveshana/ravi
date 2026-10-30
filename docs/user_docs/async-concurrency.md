# Tasks and concurrency

Ordinary function calls execute sequentially. Explicit `horabidu` (`spawn` in
English) starts a task, and `kaayu` (`wait`) waits for its result.

```ravi
kriya square(value: int):
    kodu value * value

task = horabidu square(6)
mudrisu(kaayu task)
```

The expected output is `36`. Spawn accepts a function or closure call. Supported
strings and object graphs cross task boundaries as isolated copies, preserving
aliases and cycles within each transfer. Future handles and raw pointers cannot
cross that boundary.

## Current execution model

Spawned tasks use a bounded shared worker pool and retain VM stacks/frames when
they suspend. Nested spawn/wait shares the same pool. Waiting and
`malagu(milliseconds)` (`sleep` in English) park spawned tasks and release their
workers. Synchronous root execution blocks on those operations. Event-driven
timers wake parked tasks without idle polling.

`ravi.tasks` exposes cancel, completion, timed waits, and release. Task scope
completion joins children; unobserved child failures propagate. Release completed
futures in long-running loops to reclaim their storage. Cancellation injects an
error cooperatively, allowing handlers and cleanup to execute.

`ravi.channels` exposes bounded send/receive, deadlines, and close/drain. Channel
identities may be shared between tasks; messages are copied. A closed empty
channel raises an error, distinct from a valid `none` message. Waiting task
senders and receivers park without occupying workers.

Spawned file/environment operations use a separate bounded blocking I/O pool.
OS calls may finish before cancellation cleanup completes. This is not yet an
asynchronous socket/network stack.

## Intended execution model

The target is synchronous-looking calls that can suspend in the backend during
I/O. Ordinary calls will still complete before the next statement; independent
work will require an explicit concurrency boundary. Structured task scopes,
cancellation cleanup across all exits, full transfer conformance, and network
readiness integration still need broader implementation and validation.

See [language design](../language-design.md) for that contract. Parallel workers
alone do not establish that a program is faster than Python; no comparative
performance result is currently published.

See [runtime contracts](../task-runtime.md) for resource limits, lifecycle,
copy rules, deadlines, and remaining release gates.
