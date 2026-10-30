# Modules and imports

Modules are `.rk` source files. The current loader resolves dependencies and joins
parsed ASTs before compilation. Bindings are qualified by module, and each module
retains its source profile. Independent binary module compilation is unfinished.

## Import syntax

Imports are module-first in both profiles:

| Default | English |
| --- | --- |
| `helpers inda add tago` | `helpers from add import` |

The English form is not Python's `from helpers import add` syntax. The current
AST import parser accepts names separated by commas; it does not accept `aagi`/`as`
alias clauses. Imports are checked against public symbols; local bindings may
shadow imported names.

For a two-file default-profile example, place these files in one directory.

`helpers.rk`:

```ravi
saarva kriya add(left: int, right: int):
    kodu left + right
```

`main.rk`:

```ravi
helpers inda add tago
mudrisu(add(2, 3))
```

Run `ravi run path/to/main.rk`. The expected result is `5`. The loader searches
relative to the importing file and the repository library location. Run repository
examples from the repository root so the `lib` location can be found.

## Current limitations

The loader detects dependency cycles and initializes shared dependencies once.
The linker qualifies symbols and preserves dependency source locations. Kannada
and English modules may import one another, as exercised by the module tests and
standard-library examples. A CLI profile override applies to the root module.
These are whole-program source compilation units, without independent binary
artifacts. Import aliases and a stable packaging workflow remain unfinished.

There is no stable package registry or lockfile workflow. The [standard library
catalog](standard-library.md) lists actual repository modules and their readiness.
