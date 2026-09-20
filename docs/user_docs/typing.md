# Type annotations

Ravi Kannada currently combines runtime values with partial static analysis. The
target design is inferred static typing with explicit dynamic boundaries, but
omitted annotations do not yet provide that complete static guarantee.

```ravi
count: int = 3
kriya square(value: int):
    kodu value * value

mudrisu(square(count))
```

This prints `9`. Common annotation spellings include `int`, `float`, `bool`, and
`str`. Typed arrays use `int[]`, for example `values: int[] = [1, 2]`. Explicit
dynamic annotations use `dinamika` in the default profile and `dynamic` in English.

Annotations participate in checking, but coverage differs between compiler paths.
A successful `ravi check` does not certify runtime behavior. Collection aliasing,
mutation checks, generic constraints, and complete return-type inference remain
unfinished. Do not assume Python type-hint syntax or its standard typing module.

The [data type reference](data-types.md) describes actual numeric representations.
An `int` annotation does not widen the runtime's signed 48-bit integer range.

See the [language design](../language-design.md) for the intended static/dynamic
boundary and the [implementation status](../implementation-status.md) for limits.
