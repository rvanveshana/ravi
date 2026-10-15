# Ravi Kannada

Ravi Kannada is an open-source, Python-inspired programming language built in Zig.
Its purpose is to make programming approachable through a Kannada/Kanglish source
profile while keeping an English profile with the same semantics. Programs use
indentation-based syntax and currently run on Ravi's bytecode virtual machine.

```ravi
kriya square(value: int):
    kodu value * value

mudrisu(square(6))
```

This prints `36`. The same program can be written with English keywords:

```ravi
# ravi: language=en
function square(value: int):
    return value * value

print(square(6))
```

## Why Ravi Kannada exists

Most mainstream programming languages require learners to begin with English
keywords. Ravi Kannada explores a language whose vocabulary can feel familiar to
Kannada speakers without creating a separate or less capable execution model. The
project aims to combine approachable syntax, gradual typing, useful diagnostics,
modern tooling, synchronous-looking asynchronous I/O, and explicit parallel work.

Ravi Kannada is experimental. The test suite and executable examples pass on the
pinned toolchain, but the broader language roadmap is unfinished. Complete static
typing, transparent asynchronous I/O, a production standard library, and general
native compilation remain under development. See the [implementation status](docs/implementation-status.md)
for verified capabilities and limitations.

## Build and run

Install Zig `0.17.0-dev.1415+64dfaa568`, then run from the repository root:

```powershell
zig build
./zig-out/bin/ravi.exe run examples/arithmetic.rk
```

On Linux, use `./zig-out/bin/ravi`. To validate the project:

```powershell
zig build test --summary all -j2
./tools/test_examples.ps1
./tools/test_cli.ps1
```

The [installation guide](docs/user_docs/installation.md) covers the supported setup,
and the [user handbook](docs/user_docs/README.md) introduces the language.

## Contribute

Contributions of code, tests, examples, documentation, design feedback, and bug
reports are welcome. Good first contributions include improving diagnostics,
adding focused regression tests, clarifying the handbook, and implementing scoped
items from the [development plan](docs/development-plan.md).

Before opening a pull request, read [CONTRIBUTING.md](CONTRIBUTING.md) and the
[Code of Conduct](CODE_OF_CONDUCT.md). Please discuss substantial language-design
changes in an issue before implementation so syntax and semantics remain coherent.
Security-sensitive reports should follow [SECURITY.md](SECURITY.md).

## Project documentation

- [User handbook](docs/user_docs/README.md)
- [Language design](docs/language-design.md)
- [Architecture](docs/architecture.md)
- [Implementation status](docs/implementation-status.md)
- [Development plan](docs/development-plan.md)
- [Example conventions](examples/README.md)

Ravi Kannada is licensed under the [MIT License](LICENSE). By contributing,
you agree that your contributions are provided under that license.
