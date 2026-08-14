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

The full scalable layout and namespace policy are maintained in
[Standard Library Structure](standard-library-structure.md). The planned
families are:

- `math`, `random`: numeric operations and random sources;
- `text`, `regex`: strings, Unicode, and pattern matching;
- `collections`: sequences, mappings, sets, queues, and iteration;
- `io`, `os`, `process`: resources, platform access, and subprocesses;
- `time`: clocks, durations, dates, and time zones;
- `json`, `encoding`: structured data and codecs;
- `network`, `crypto`: protocols and security primitives;
- `async`, `sync`: tasks, cancellation, locks, events, and channels;
- `logging`, `testing`: observability and verification;
- `kirana`: optional UI/application integration.

These planned modules do not imply that the APIs already exist. Each module
needs implementation, profile-aware names, resource limits, tests, and
documentation before it becomes part of the stable reference.

## Library design rules

A standard module should:

1. expose a small public interface;
2. use explicit annotations where useful;
3. document errors and resource ownership;
4. work from both Kannada/Kanglish and English callers;
5. avoid hidden global state;
6. have unit, integration, negative, and resource-limit tests.

## Naming standard

English names are the stable public references. Kannada/Kanglish names are
the canonical implementations, and English names delegate to them. Exception
and type names use PascalCase in both profiles: `BaseException` maps to
`MoolaDosha`, `ZeroDivisionError` maps to `ShunyaBhagaDosha`, and
`ValidationError` maps to `ParikshaneDosha`. The underscore form
`moola_dosha` is not part of the standard API.
