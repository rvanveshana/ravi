# Context Managers

Context managers provide deterministic setup and cleanup around a suite. The default-profile keywords are `jote` (with) and `aagi` (as). English source uses `with` and `as`.

## Intended syntax

```ravi
jote open_resource("data.txt") aagi resource:
    resource.write("hello")
```

The intended lifecycle is:

1. Evaluate the context expression.
2. Call its enter operation.
3. Bind the entered value when `aagi` is present.
4. Run the indented suite.
5. Call the exit operation on normal completion.
6. Call the exit operation during exception unwinding.
7. Preserve or suppress the exception according to the exit result.

## Multiple managers

The final syntax may support nesting or comma-separated managers. Nested spelling is unambiguous and should be used in design examples:

```ravi
jote open_resource("input.txt") aagi source:
    jote open_resource("output.txt") aagi target:
        target.write(source.read())
```

## Implementer contract

A context manager must define a stable enter/exit protocol. The protocol must specify the receiver, entered value, exception payload, suppression result, and behavior when enter itself fails.

## Current status

`jote` suites and optional `aagi` bindings are parsed, and malformed bindings produce diagnostics. Runtime enter/exit protocol execution and guaranteed cleanup on every normal and exceptional path remain incomplete. The examples above are reference syntax, not claims that file/resource objects currently exist.
