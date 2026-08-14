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

The single public exception facade is available from the standard library:

```ravi
exceptions inda RuntimeError, IndexError, KeyError tago
```

The facade includes base names (`BaseException`, `Exception`), arithmetic,
lookup, type, name, collection, stack, memory, instruction, debugger, and
application errors. These names are the stable Ravi-facing API; Zig VM error
names are implementation details. The current constructors return stable
numeric identities internally for compatibility. Application code should keep
constructor references and raise their returned exception references, for example `yese exception_callback()`. A built-in reference is the canonical public exception name (such as `"ZeroDivisionError"`), and native VM faults produce that same reference, so `tappu exception` receives one consistent value regardless of where the fault originated. It must not depend on numeric identities. The
authoritative native code, public name, and default diagnostic message are
defined in `src/vm/exception_constants.zig`. Unhandled native faults are
reported as `Name (code): message`, for example
`ZeroDivisionError (511): division by zero`; the code is diagnostic metadata,
not the value application code should raise.

The VM reports these built-in runtime faults as structured Ravi diagnostics:

| Runtime fault | Meaning |
| --- | --- |
| `DivisionByZero` | An integer or floating-point division used zero as its divisor. |
| `InvalidIndex` | A collection index was outside the valid range. |
| `MissingKey` | A dictionary lookup requested a key that is not present. |
| `TypeGuardFailed` | An operation received a value of the wrong type. |
| `IntegerOutOfRange` | An integer exceeded Ravi's supported representation. |
| `InvalidFunction` | A call target was not callable or its call metadata was invalid. |
| `InvalidInstruction` | The VM rejected malformed or unsupported bytecode. |
| `RaisedException` | A raised value escaped without a matching handler. |

Unhandled faults include the source file, line, column, a highlighted source
line, an actionable message, and a Ravi-level function trace when available.
Use `--diagnostic-format json` when an editor or tool needs machine-readable
positions.

## Current limitations

Literal exception matching and payload binding are implemented. Python-style
named built-in exception classes, `except SomeError as value` syntax, and
user-defined exception classes are not implemented yet. At present, a
programmer can create distinct structured payloads such as
`{"name": "PaymentDeclined", "message": "card was declined"}`
and bind them in `tappu error`; class/type matching and inheritance for
custom exceptions remain planned. Complete VM-wide cleanup guarantees and a
large standard exception hierarchy also remain planned. Do not assume Python
exception classes or `finally` behavior for every future VM fault until the
corresponding feature is marked complete in `progress.md`.
