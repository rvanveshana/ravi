# Examples

Start with the complete examples in [Getting started](getting-started.md), then
use the relevant handbook page for the behavior you want to explore.

| Topic | Handbook example |
| --- | --- |
| Default and English profiles | [First program](getting-started.md) |
| Conditions, loops, and ranges | [Control flow](control-flow.md) |
| UTF-8 indexing and transformations | [Strings](strings.md) |
| List construction and mutation | [Collections](collections.md) |
| Defaults, named arguments, and expression functions | [Functions](functions.md) |
| Annotated parameters | [Typing](typing.md) |
| Constructors and methods | [Classes](classes.md) |
| Handling an arithmetic error | [Exceptions](exceptions.md) |
| Two local modules | [Modules](modules.md) |
| Scalar worker task | [Concurrency](async-concurrency.md) |

The repository's [examples directory](../../examples/README.md) contains executable
checks with expected-output files. The recursive runner checks results and enforces
a timeout for each program. Regression fixtures cover the repaired handbook cases,
including collections, classes, lambdas, and chained string methods.

Run `./tools/test_examples.ps1` after building, or `./test.ps1 -ExamplesOnly` to
build and run examples without repeating unit tests. A successful example run does
not certify every combination of language features; see
[implementation status](../implementation-status.md) for remaining gaps.
