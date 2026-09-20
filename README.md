# Ravi Kannada

Ravi Kannada is an experimental, Python-inspired programming language implemented
in Zig. It uses indentation-based syntax, supports Kannada/Kanglish and English
source profiles, and runs `.rk` files on a bytecode virtual machine.

The language is in early development. Core execution and runtime foundations exist,
but the full test suite has unresolved failures. Complete static typing, transparent
async I/O, a production standard library, and general native compilation remain
under development. No general performance advantage over Python has been established.

## Get started

Use Zig `0.17.0-dev.1415+64dfaa568`, the version pinned in CI. From this repository:

```powershell
zig build
./zig-out/bin/ravi.exe run examples/arithmetic.rk
```

On Linux, the executable is `./zig-out/bin/ravi`. The language name is Ravi Kannada;
the executable name remains `ravi`.

A program in the default Kannada/Kanglish profile:

```ravi
kriya square(value: int):
    kodu value * value

mudrisu(square(6))
```

Output: `36`.

## Documentation

- [User handbook](docs/user_docs/README.md): installation, tutorials, and reference.
- [Documentation index](docs/README.md): contributor and design documentation.
- [Implementation status](docs/implementation-status.md): capabilities and validation evidence.
- [Development plan](docs/development-plan.md): next stages and acceptance criteria.
- [Contributing](docs/contributing.md): layout, focused validation, and the 300-line rule.

## Development direction

The target combines approachable syntax, static inference with explicit dynamic
values, synchronous-looking I/O with backend suspension, and explicit CPU parallelism.
Both source profiles must share semantics and runtime operations. The current
implementation does not yet satisfy the complete target; see [Language design](docs/language-design.md).
