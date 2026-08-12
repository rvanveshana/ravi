# Imports and Modules

Every `.rk` file can be a program or a library. A module is loaded, parsed, checked, and initialized once in dependency order.

## Import grammar

The default Kanglish profile uses Kannada word order:

```ravi
math inda add tago
math inda sin, cos tago
math inda add aagi plus tago
```

English profile:

```ravi
# ravi: language=en
from math import add
from math import add as plus
```

The source module comes first in Kanglish, followed by `inda`, imported names, optional aliases, and `tago`.

## What happens during import

1. Ravi identifies the importing file.
2. It searches the importing directory.
3. It searches configured package roots such as `lib/`.
4. It resolves the module name to another `.rk` file.
5. It reads the module and applies that file's language header.
6. It parses imports and top-level declarations.
7. It detects cycles before execution.
8. It initializes dependencies before the importing module.
9. It binds requested public functions/classes into the importing module.

A module may use a different profile from its importer. Profiles affect source spelling, not the language-neutral imported symbol interface.

## Public exports

Top-level functions and classes form the importable interface according to visibility. Requested names must exist and be public when the dependency has an explicit interface. Side-effect modules with no exports remain possible for compatibility.

## Local library example

`lib/greetings.rk`:

```ravi
saarva kriya hello(name):
    kodu "Namaskara " + name
```

`app.rk`:

```ravi
greetings inda hello tago
mudrisu(hello("Ravi"))
```

## Cycles and caching

Import cycles are diagnosed instead of recursively executing forever. Module artifacts include identity, compiler key, language profile, and interface fingerprint so incompatible cached artifacts are rejected. Shared module globals and full incremental invalidation remain under development.
