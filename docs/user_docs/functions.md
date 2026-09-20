# Functions

Define a function with `kriya` (`function` in English) and return with `kodu`
(`return`). Parameters use parentheses. Function bodies are indented.

```ravi
kriya multiply(value: int, factor: int = 2):
    kodu value * factor

mudrisu(multiply(3))
mudrisu(multiply(3, 4))
mudrisu(multiply(value = 3, factor = 5))
```

This prints `6`, `12`, and `15`. Trailing parameters may have defaults. Calls can
supply positional arguments or named arguments using `name = value`. Avoid
mixing advanced binding patterns until the argument-binding contract is complete.

## Function values

Functions can be assigned to variables and called through those variables.
Expression functions use `=>`:

```text
double = kriya(value: int) => value * 2
mudrisu(double(6))
```

The intended result is `12`, but this expression-function call currently fails in
the CLI with `NoEntryBlock`. Treat it as experimental syntax.
Nested functions and closures have implementation support;
closure lifetime and capture semantics remain part of the conformance work.

A function with no explicit returned value produces `none`. Built-in printing also
returns `none`; its result is not the value printed. See [typing](typing.md) for
annotations and [classes](classes.md) for implicit method receivers.

Variadic parameters and decorator syntax exist in the implementation but do not
yet form a complete public argument-binding or decoration protocol. Generators
are also incomplete. See [planned features](planned-features.md).
