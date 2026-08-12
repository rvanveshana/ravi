# Modules

For the complete import grammar, resolution order, visibility rules, cycle
handling, and profile behavior, see [Imports and Modules](imports-and-modules.md).

Every `.rk` file can be used as a library. Keep reusable code in a module and import selected names from another Ravi file.

```ravi
# lib/math.rk
kriya add(left, right):
    return left + right
```

```ravi
# app.rk
math inda add tago
mudrisu(add(2, 3))
```

The repository automatically searches `lib/` for standard-library modules. Module loading resolves source paths, detects cycles, and initializes dependencies in order.

Use [Standard Library](standard-library.md) for the built-in module layout and [Installation](installation.md) for command examples.
