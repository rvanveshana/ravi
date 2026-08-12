# Language Status and Stability

This page explains how to read the reference while Ravi is under active development.

## Stable and verified today

The repository currently verifies:

- `.rk` source files and four-space indentation;
- Kannada/Kanglish default profile and English profile selection;
- integers, floats, booleans, `none`, strings, arrays/lists, tuples, sets, and dictionaries;
- arithmetic, comparisons, logical operations, indexing, slicing, and formatting;
- functions, defaults, recursion, closures, nested functions, lambdas, and variadic arguments;
- basic classes, constructors, fields, methods, and property access;
- `if`, `while`, `for`, ranges, `break`, and `continue`;
- `nodu`/`tappu`/`kone` exception flow and explicit raises;
- `.rk` imports, dependency ordering, cycle checks, and `lib/` search paths;
- verified bytecode, diagnostics, managed runtime objects, and debugger foundations.

## Partial or migration-only

- AST compiler authority and semantic/HIR/MIR integration;
- inheritance and complete visibility contracts;
- exception type matching and universal cleanup guarantees;
- `jote`/`with` runtime context protocol;
- `taru`/`yield` executable generator state machines;
- gradual typing beyond current annotations and guards;
- advanced formatting, decorators, shared module globals, and full LSP/DAP hosting.

## Planned

- file and stream handling;
- a larger standard library;
- general iterator protocol;
- async language syntax and complete task execution;
- native code generation and incremental project builds.

A page may contain both verified examples and specification examples. Every planned or partial chapter labels its examples explicitly so programmers can distinguish runnable behavior from the future language contract.
