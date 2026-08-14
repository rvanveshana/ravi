# Standard Library

See [Standard Library Reference](standard-library-reference.md) for the
current module API, planned library groups, and library design rules. See
[Standard Library Structure](standard-library-structure.md) for namespace
ownership, facade layout, and the growth plan for many libraries.

Ravi source modules live in `lib/ravi/` and are ordinary `.rk` files. This
keeps the standard library readable and makes the same module mechanism
available to application authors.

The canonical current module is:

- `lib/ravi/math.rk`: reusable arithmetic helpers and math-oriented functions.

Import a symbol with:

```ravi
ravi.math inda add tago
mudrisu(add(4, 5))
```

The legacy `lib/math.rk` path remains supported for compatibility. Library APIs
should remain small, documented, and profile-compatible. A facade may itself
import focused implementation modules from its domain directory.
