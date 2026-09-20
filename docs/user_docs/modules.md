# Modules and imports

Modules are `.rk` source files. The current loader resolves dependencies and joins
source before compilation; independent module compilation and isolated namespaces
are not complete. Keep application modules in the same source profile for now.

## Import syntax

Imports are module-first in both profiles:

| Default | English |
| --- | --- |
| `helpers inda add tago` | `helpers from add import` |

The English form is not Python's `from helpers import add` syntax. The current
AST import parser accepts names separated by commas; it does not accept `aagi`/`as`
alias clauses. Namespace enforcement remains incomplete.

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

Import graph and interface support exist, but the CLI currently concatenates
sources and compiles them under the root profile. Imported headers do not establish
independent compilation units. Avoid mixed-profile dependency graphs and conflicting
global names. Export visibility, cyclic dependencies, module initialization order,
and import aliases still need integrated conformance coverage.

There is no stable package registry or lockfile workflow. The [standard library
catalog](standard-library.md) lists actual repository modules and their readiness.
