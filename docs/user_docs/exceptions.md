# Exceptions

Use `nodu`/`try` for a protected suite, `tappu`/`except` for a handler, and
`kone`/`finally` for cleanup. These constructs are statements, not expressions.

```ravi
result = 0
nodu:
    result = 5 / 0
tappu:
    result = 7
mudrisu(result)
```

This prints `7`. Raise explicitly with `yese` (`raise` in English).

The implementation includes handler tables, runtime error identities, and cleanup
paths. It does not yet provide a complete, uniform public exception object model.
Typed catches, payloads, cause chains, traceback inspection, re-raising, and cleanup
across every control-flow exit still require conformance work. In particular,
worker tasks preserve runtime error identities but do not transfer rich exception
objects between VM heaps.

The `ravi.exceptions` module contains named exception facades. These are not a
complete Python-compatible class hierarchy and should not be treated as one.

Keep protected suites small and report the original diagnostic when filing a bug.
Do not rely on experimental cleanup behavior for essential external resource
management. Context managers and complete deterministic cleanup are tracked in
[planned features](planned-features.md).
