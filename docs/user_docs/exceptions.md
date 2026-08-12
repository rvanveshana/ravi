# Exception Handling

Ravi uses exceptions for abnormal control flow. The default-profile keywords are `nodu` (try), `tappu` (except), `kone` (finally), and `yese` (raise). English source uses `try`, `except`, `finally`, and `raise`.

## Basic structure

```ravi
nodu:
    yese "something went wrong"
tappu:
    mudrisu("recovered")
kone:
    mudrisu("cleanup")
```

The `nodu` suite runs first. If it raises, control transfers to the matching `tappu` suite. The `kone` suite runs after either normal completion or exception handling.

## Raising a value

```ravi
kriya require_positive(value: int):
    adre value <= 0:
        yese "value must be positive"
    kodu value
```

An exception value may be an integer, string, dictionary, instance, or another runtime value. Use structured values when a handler needs details:

```ravi
yese {"code": 400, "message": "invalid input"}
```

## Binding the exception

The handler may bind the active exception payload:

```ravi
nodu:
    yese "bad input"
tappu error:
    mudrisu(error)
```

## Nested handlers

Handlers may be nested. An inner handler can consume an exception; an unhandled exception continues outward:

```ravi
nodu:
    nodu:
        yese 42
    tappu inner_error:
        mudrisu(inner_error)
tappu outer_error:
    mudrisu(outer_error)
kone:
    mudrisu("outer cleanup")
```

## Finally and control transfer

`kone` is the cleanup suite. It is intended to run when execution leaves the protected suite normally, through `return`, through loop control, or because an exception is raised. Cleanup should be idempotent because it may run on more than one error path in complex code.

## Runtime failures

The VM reports faults such as division by zero, invalid indexes, missing keys, failed type guards, and invalid calls as structured Ravi runtime diagnostics. An active handler can recover from supported VM faults. Unhandled faults include a Ravi-level function trace.

## Current limitations

Literal exception matching and payload binding are implemented. Exception class/type matching, complete VM-wide cleanup guarantees, and a large standard exception hierarchy remain planned. Do not assume Python exception classes or `finally` behavior for every future VM fault until the corresponding feature is marked complete in `progress.md`.
