# Examples

The repository examples are executable references, not syntax-only snippets.
Contract-style fixtures raise on incorrect results, so a zero exit code means
the demonstrated behavior was evaluated successfully.

Start with:

- `examples/arithmetic.rk`
- `examples/functions.rk`
- `examples/control_flow.rk`
- `examples/collections.rk`
- `examples/class_oop.rk`
- `examples/variadic_functions.rk`
- `examples/module_app.rk`

The two language-profile collections are documented separately:

- [English Examples](examples-english.md)
- [Kannada and Kanglish Examples](examples-kannada.md)

Run all production examples with `.\test.ps1` from PowerShell. Run an individual file with `ravi run path/to/file.rk`.

The broad data-type and method contract is in
`examples/data_types_and_methods.rk`. It checks literals, arithmetic,
strings, lists, tuples, sets, dictionaries, function values, defaults, and
variadic calls. Every production example is executed through both compiler
paths by the test runner. The runner fails when either path fails or when the
evaluated output differs, so examples cannot be marked successful by syntax
checking or by silently selecting only one compiler.
