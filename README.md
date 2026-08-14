# Ravi

Ravi is a Python-inspired programming language implemented in Zig. It uses indentation-based syntax, supports Kannada/Kanglish and English keyword profiles, and executes `.rk` source files on a verified bytecode virtual machine.

The project is under active development. The current implementation includes a working compiler, VM, diagnostics, formatter, module loader, managed runtime values, debugger foundations, and concurrency primitives. HIR/MIR lowering is being expanded incrementally; unsupported shapes still use a compatibility path during the migration.

## Quick Start

### Requirements

- Zig 0.17 or newer
- PowerShell on Windows for the repository test runner

Build the compiler:

```powershell
zig build
```

The executable is written to `zig-out/bin/ravi.exe` on Windows.

Create `hello.rk`:

```ravi
mudrisu("Namaskara, Ravi!")
```

Run it:

```powershell
.\zig-out\bin\ravi.exe run .\hello.rk
```

## Language Example

Ravi's default profile uses Kannada/Kanglish keywords:

```ravi
kriya square(value: int):
    return value * value

mudrisu(square(6))
```

The English profile is also available:

```ravi
function square(value: int):
    return value * value

print(square(6))
```

Run an English-profile file with:

```powershell
.\zig-out\bin\ravi.exe run --lang en .\program.rk
```

Source files use four-space indentation. A colon introduces a block, and the indented statements below it form the block body.

## CLI

```text
ravi <command> [options] <file.rk>
```

Available commands:

- `check` parse and analyze a module
- `run` compile and execute a module
- `trace` print instructions, then execute the module
- `bytecode` print verified bytecode with source locations
- `tokens` print lexer tokens
- `fmt` format a file in place
- `fmt-check` fail when a file is not formatted

Useful options:

```powershell
.\zig-out\bin\ravi.exe check .\program.rk
.\zig-out\bin\ravi.exe tokens .\program.rk
.\zig-out\bin\ravi.exe bytecode .\program.rk
.\zig-out\bin\ravi.exe trace .\program.rk
.\zig-out\bin\ravi.exe fmt .\program.rk
.\zig-out\bin\ravi.exe fmt-check .\program.rk
.\zig-out\bin\ravi.exe run --diagnostic-format json .\program.rk
```

Language profiles can be selected with `--lang kn` or `--lang en`. The default profile is Kannada/Kanglish. Diagnostics support `human`, `compact`, and `json` output formats.

## Current Language Surface

Verified examples cover:

- Integers, floats, strings, booleans, `none`, arithmetic, comparisons, and operators
- Lists, tuples, sets, dictionaries, indexing, slicing, and collection methods
- Functions, default arguments, recursion, lambdas, closures, nested functions, and variadic calls
- `if`/`else`, `while`, `for`, `range`/`shreni`, `break`, and `continue`
- Classes, constructors, properties, methods, and inheritance examples
- `try`/`except`/`finally` exception flow
- Modules and imports from `.rk` files
- Explicit concurrency operations such as `horabidu`/`spawn`, `kaayu`/`wait`, and `malagu`/`sleep`
- Optional type annotations and typed scalar lowering

Advanced work remains in progress, including complete general-purpose HIR/MIR statement lowering, generator state machines, full async scheduling and cancellation, context-manager protocols, decorators, complete type inference and generics, shared module globals, and executable native machine-code generation.

## Testing

Run the complete acceptance suite on Windows:

```powershell
.\test.ps1
```

This builds the compiler, runs the Zig test suite, and executes every `.rk` file under `examples/` as a self-verifying contract.

Run the Zig tests directly:

```powershell
zig build test --summary all
```

Check source-size budgets and patch whitespace:

```powershell
.\tools\check_src_sizes.ps1
git diff --check
```

The project treats passing unit tests, the executable example corpus, source-size checks, and whitespace checks as its standing validation gates.

## Repository Layout

```text
ravi/
|-- build.zig              Zig build graph
|-- config/                Language and feature configuration
|-- docs/                  Architecture, plans, and user documentation
|-- examples/              Executable Ravi programs and regression contracts
|-- lib/                   Ravi standard-library source files
|-- src/
|   |-- lexer/             Tokenization and language profiles
|   |-- parser/            Syntax and AST construction
|   |-- semantic/          Name, scope, and semantic analysis
|   |-- compiler/          AST and HIR/MIR lowering
|   |-- ir/                HIR, MIR, and bytecode emission
|   |-- bytecode/           Bytecode format and verification
|   |-- vm/                Virtual machine and runtime values
|   |-- concurrency/       Scheduler and task primitives
|   |-- memory/            Managed memory and garbage collection
|   |-- modules/            Module resolution and loading
|   |-- debug/              Debugger and DAP foundations
|   `-- lsp/                Language-server foundations
|-- tests/                 Zig unit and integration tests
`-- tools/                 Benchmarks, checks, and feature-matrix tools
```

## Documentation

- [Getting Started](docs/user_docs/getting-started.md)
- [Language Features](docs/user_docs/features.md)
- [Control Flow](docs/user_docs/control-flow.md)
- [Functions](docs/user_docs/functions.md)
- [Collections](docs/user_docs/collections.md)
- [Classes and Inheritance](docs/user_docs/classes-inheritance.md)
- [Exceptions](docs/user_docs/exceptions.md)
- [Async and Concurrency](docs/user_docs/async-concurrency.md)
- [Architecture](docs/architecture.md)
- [Development Plan](docs/development-plan.md)
- [Verified Progress](progress.md)

## Development Notes

Ravi aims to keep language semantics consistent across the Kannada/Kanglish and English profiles. New language behavior should include a focused Zig test and an executable example when appropriate. Update `progress.md` only after the relevant behavior has been built and validated.
