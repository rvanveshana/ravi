# Tuple (`tuple`)

A tuple is an ordered grouped sequence created with comma-separated values in parentheses.

```ravi
point = (10, 20)
record = ("Ravi", 1, true)
```

Use zero-based indexing and slicing:

```ravi
x = point[0]
coordinates = point[0:2]
for value in record:
    mudrisu(value)
```

Tuples support the sequence operations `length()`/`gatra()`, `count()`/`enisu()`, `contains()`/`olagide()`, indexing, slicing, and iteration. They are intended for fixed grouped values; use a list when the sequence should be edited with `append`, `insert`, or `remove`.

Tuples are also used by variadic parameters:

```ravi
kriya first_extra(*values):
    kodu values[0]
```
