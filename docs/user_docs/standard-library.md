# Standard Library

See [Standard Library Reference](standard-library-reference.md) for the
current module API, planned library groups, and library design rules.

Ravi source modules live in `lib/` and are ordinary `.rk` files. This keeps the standard library readable and makes the same module mechanism available to application authors.

The canonical current module is:

- `lib/math.rk`: reusable arithmetic helpers and math-oriented functions.

Import a symbol with:

```ravi
math inda add tago
mudrisu(add(4, 5))
```

Library APIs should remain small, documented, and profile-compatible. A library module may itself import another `.rk` module.
