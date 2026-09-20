# Examples

Start with the complete examples in [Getting started](getting-started.md), then
use the relevant handbook page for the behavior you want to explore.

| Topic | Handbook example |
| --- | --- |
| Default and English profiles | [First program](getting-started.md) |
| Conditions, loops, and ranges | [Control flow](control-flow.md) |
| UTF-8 indexing and transformations | [Strings](strings.md) |
| List construction and mutation (experimental) | [Collections](collections.md) |
| Defaults and named arguments; experimental expression functions | [Functions](functions.md) |
| Annotated parameters | [Typing](typing.md) |
| Constructors and methods (experimental) | [Classes](classes.md) |
| Handling an arithmetic error | [Exceptions](exceptions.md) |
| Two local modules | [Modules](modules.md) |
| Scalar worker task | [Concurrency](async-concurrency.md) |

The repository's [examples directory](../../examples) also contains development
fixtures. They cover more syntax than the verified handbook and are not all known
to pass. Treat them as implementation exercises, not a stable API specification.

Run a file with `ravi run examples/arithmetic.rk` from the repository root. A source
header selects its profile; use `--lang` only when intentionally overriding it.
See [implementation status](../implementation-status.md) for validation evidence.
