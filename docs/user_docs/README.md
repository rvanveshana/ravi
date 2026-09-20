# Ravi Kannada user handbook

Ravi Kannada is a Python-inspired language implemented in Zig. Programs use `.rk`
files and run with the `ravi` command. This handbook documents the current development
version, not a stable release or a Python compatibility layer.

## Start here

1. [Install and build](installation.md) the pinned toolchain and executable.
2. [Write your first program](getting-started.md).
3. Learn [source syntax and profiles](syntax.md) and [control flow](control-flow.md).
4. Use the [example catalog](examples.md) for larger programs.

## Language reference

| Topic | Reference |
| --- | --- |
| Kannada/Kanglish and English vocabulary | [Keywords](keywords.md) |
| Numbers, booleans, none, and value categories | [Data types](data-types.md) |
| Text, Unicode indexing, and string methods | [Strings](strings.md) |
| Lists, tuples, sets, dictionaries, and their methods | [Collections](collections.md) |
| Parameters, return values, lambdas, and closures | [Functions](functions.md) |
| Type annotations and dynamic values | [Typing](typing.md) |
| Instances, methods, inheritance, and visibility | [Classes](classes.md) |
| Raising, handling, and diagnosing errors | [Exceptions](exceptions.md) |
| Imports and module limitations | [Modules](modules.md) |
| Sequential calls, worker tasks, and waits | [Concurrency](async-concurrency.md) |
| Available library modules | [Standard library](standard-library.md) |
| Commands, diagnostics, formatting, and troubleshooting | [Tooling](tooling.md) |
| Features not ready for application use | [Planned features](planned-features.md) |

## Reading the examples

Unless a first-line `# ravi: language=en` header appears, executable examples use
the default `kn` profile: Kannada vocabulary written in Latin characters, also
called Kanglish. Kannada-script text is supported in strings; Kannada-script
keywords are not currently an executable profile.

Fenced `ravi` blocks show executable source. Regression examples under
`examples/regressions` check the repaired handbook cases against expected output.
Examples that print results show the expected output or describe the result.
Run commands from the repository root unless stated otherwise. Some advanced
features remain experimental even where syntax is accepted.

## Development status

The full suite is not yet green. Passing `check` does not prove that a program will
execute correctly, and an existing library file may only be a blueprint. Read the
limitations on each relevant page. Dated test evidence and open integration gaps
are maintained centrally in [Implementation status](../implementation-status.md).
