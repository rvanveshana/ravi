# Tasks and concurrency

Ordinary function calls execute sequentially. Explicit `horabidu` (`spawn` in
English) starts a task, and `kaayu` (`wait`) waits for its result.

```ravi
kriya square(value: int):
    kodu value * value

task = horabidu square(6)
mudrisu(kaayu task)
```

The expected output is `36`. The current spawn form accepts a direct function call.
Pass scalar arguments and return scalar results: integers, floats, booleans, or
`none`. VM-local handles, including strings, collections, instances, and closures,
cannot be transferred between workers; unsupported transfers fail.

## Current execution model

Tasks use a bounded queue and OS worker threads. Waiting and
`malagu(milliseconds)` (`sleep` in English) block the current thread. Sleep does
not busy-wait, but it does not suspend a resumable language task either.
Task failures propagate runtime error identities. Accepted scheduler work is
drained during shutdown.

Channels, cancellation state, and future primitives exist internally. They are
not yet a complete public structured-concurrency API. Nested blocking waits can
exhaust available workers; avoid designs that require a blocked worker to execute
its own dependent task.

## Intended execution model

The target is synchronous-looking calls that can suspend in the backend during
I/O. Ordinary calls will still complete before the next statement; independent
work will require an explicit concurrency boundary. Structured task scopes,
cancellation cleanup, safe object transfer, and nonblocking waits remain planned.

See [language design](../language-design.md) for that contract. Parallel workers
alone do not establish that a program is faster than Python; no comparative
performance result is currently published.
