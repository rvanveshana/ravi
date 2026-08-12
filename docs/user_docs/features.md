# Features

## Core language

- Indentation-based blocks with comments and source diagnostics.
- Integers, floats, strings, raw strings, booleans, and `none`.
- Arithmetic, comparisons, eager logical operations, identity, and membership.
- Arrays, tuples, sets, dictionaries, indexing, and slicing.
- Functions, defaults, recursion, lambdas, closures, nested functions, and variadic parameters.
- Keyword arguments with `**options` dictionaries.
- Classes, properties, methods, constructors, and object state.
- Exceptions with `try`, `except`, and `finally`.
- `for`, `while`, `range`/`shreni`, `break`, and `continue`.

Detailed chapters are available for [exceptions](exceptions.md), [classes and
inheritance](classes-inheritance.md), [generators](generators.md), [context
managers](context-managers.md), [file handling](file-handling.md), and [async
concurrency](async-concurrency.md).

## Runtime and tooling

- Verified bytecode and a NaN-boxed runtime value representation.
- Managed strings and collections with tracing and write barriers.
- Module loading from `.rk` source files, including `lib/` standard-library modules.
- Formatter, diagnostics, LSP/DAP adapters, debugger hooks, and benchmark tools.

Some advanced features, including general generators, decorators, complete context managers, and native code generation, remain under development. See [Tooling](tooling.md) and the repository progress notes for current status.
