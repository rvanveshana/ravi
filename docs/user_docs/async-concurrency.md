# Async and Concurrency

Ravi's runtime contains scheduler foundations, futures, channels, cancellation state, and resumable metadata. The intended language model is Go-like: functions remain ordinary synchronous functions, while a call can be launched as a schedulable task. Ravi does not need an `async` function modifier or mandatory `await` syntax.

## Language spellings

The language should distinguish sequential execution from concurrent execution at the call site. The exact keyword is still open, but the shape should be equivalent to:

```ravi
kriya fetch_value():
    kodu request()

task = horabidu fetch_value()
value = kaayu task
```

In the default Kannada profile, `horabidu` starts a task, `kaayu` waits for its result, and `malagu(milliseconds)` blocks the current thread without busy-waiting. In the English profile, the equivalent spellings are `spawn`, `wait`, and `sleep(milliseconds)`. These are language spellings for the same runtime operations.

`horabidu`/`spawn` is the concurrency boundary; the function itself is not a different kind of function. A normal call executes immediately. A spawned call returns a task or future, and `kaayu`/`wait` is the explicit synchronization point when the result is needed. Channel send/receive operations provide the preferred communication path between tasks.

The current syntax uses `spawn` and `wait` keywords. `spawn` currently accepts a direct function call and returns a future handle; `wait` joins that handle. Task results are currently restricted to scalar values because child VM objects are not yet transferred between heaps.

## Runtime concepts

- **Task:** a schedulable invocation of an ordinary function.
- **Future:** a handle for a spawned result that may complete later; waiting on it propagates its result or failure.
- **Channel:** a bounded communication queue with explicit closed state.
- **Cancellation:** a propagated request that lets tasks stop cooperatively.
- **Scheduler:** an executor that drains runnable work with bounded resources. It may use worker threads, but task scheduling must not change ordinary function semantics.

## Design requirements

The completed feature must specify spawn ownership, ordering, fairness, channel close behavior, timeout behavior, exception propagation, cancellation cleanup, interaction with generators, and whether shared mutable state requires synchronization. It must also define whether task creation is eager, how many workers are used by default, and what happens when a task is abandoned without being waited on.

## Current status

The scheduler and async-state modules are tested runtime foundations. The current `examples/async_concurrency.rk` demonstrates ordinary sequential calls, blocking synchronous sleep, and executable `spawn`/`wait` tasks. Structured cancellation, channel syntax, resumable waiting, and non-scalar result transfer remain follow-up work.
