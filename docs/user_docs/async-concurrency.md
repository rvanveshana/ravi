# Async and Concurrency

Ravi's runtime contains scheduler foundations, futures, channels, cancellation state, and resumable metadata. Language-level async syntax and complete concurrent execution are not yet stable.

## Intended direction

The planned surface will distinguish ordinary sequential functions from async tasks:

```ravi
async kriya fetch_value():
    kodu await request()
```

The exact Kannada/Kanglish spellings, await semantics, task ownership, and cancellation rules are not final and should not be treated as current syntax.

## Runtime concepts

- **Task:** a schedulable unit of work.
- **Future:** a handle for a result that may complete later.
- **Channel:** a bounded communication queue with explicit closed state.
- **Cancellation:** a propagated request that lets tasks stop cooperatively.
- **Scheduler:** an executor that drains runnable work with bounded resources.

## Design requirements

The completed feature must specify ordering, fairness, channel close behavior, timeout behavior, exception propagation, cancellation cleanup, interaction with generators, and whether shared mutable state requires synchronization.

## Current status

The scheduler and async-state modules are tested runtime foundations. The current `examples/async_concurrency.rk` demonstrates ordinary sequential function calls and intentionally does not claim language-level async execution. Generators, futures, channels, and async syntax will be documented as stable only after executable end-to-end examples pass.
