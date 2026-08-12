# Data Types

Ravi values are runtime values. A variable does not need a declaration before assignment, and a later assignment may use another compatible or dynamic value.

## Built-in types

| Type | Literal examples | Main operations |
|---|---|---|
| `int` | `0`, `42`, `-7` | arithmetic, comparison, indexing positions |
| `float` | `3.14`, `-0.5` | arithmetic, comparison, formatting |
| `bool` | `true`, `false` | conditions, logical operations |
| `none` | `none` | absence of a value |
| `str` | `"Ravi"` | text methods, indexing, slicing |
| `list` | `[1, 2, 3]` | ordered mutable sequence methods |
| `tuple` | `(1, 2, 3)` | ordered grouped sequence |
| `set` | `{1, 2, 3}` | uniqueness and set operations |
| `dict` | `{"name": "Ravi"}` | key/value lookup and views |
| `function` | `kriya f(): ...` | calls, defaults, closures |
| `instance` | `Counter(0)` | fields and methods |

Detailed reference: [Integer](type-int.md), [Float](type-float.md), [Boolean](type-bool.md), [None](type-none.md), [String](type-string.md), [List](type-list.md), [Tuple](type-tuple.md), [Set](type-set.md), [Dictionary](type-dict.md), [Function](type-function.md), and [Classes and Instances](classes.md).

## Discovering a value type

Use `vidha` in the default profile or `type` in English:

```ravi
value = [1, 2, 3]
mudrisu(vidha(value))
```

The exact numeric result of the VM type query is intended for runtime internals; application code should usually use operations appropriate to the known value type.
