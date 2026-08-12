# Standard Library Reference

Ravi's standard-library direction is deliberately source-based: a library module is a `.rk` file that uses the same parser, profile rules, visibility rules, and import system as application code.

## Current module

The repository currently provides:

### `lib/math.rk`

| Function | Parameters | Behavior |
|---|---|---|
| `add` | `a: int, b: int` | returns `a + b` |
| `answer` | none | returns `41` |

Usage:

```ravi
math inda add tago
mudrisu(add(2, 3))
```

## Planned library groups

The library is expected to grow into focused modules rather than one giant namespace:

- `math`: arithmetic, numeric helpers, constants;
- `strings`: text transformations, searching, Unicode helpers;
- `collections`: sequence and dictionary helpers;
- `io`: files, paths, streams, and resource handling;
- `os`: environment, process, and platform information;
- `json`: encoding and decoding structured data;
- `time`: clocks, durations, and date/time values;
- `async`: futures, channels, tasks, and cancellation;
- `testing`: assertions and test helpers.

These planned modules do not imply that the APIs already exist. Each module needs implementation, profile-aware names, resource limits, tests, and documentation before it becomes part of the stable reference.

## Library design rules

A standard module should:

1. expose a small public interface;
2. use explicit annotations where useful;
3. document errors and resource ownership;
4. work from both Kannada/Kanglish and English callers;
5. avoid hidden global state;
6. have unit, integration, negative, and resource-limit tests.
