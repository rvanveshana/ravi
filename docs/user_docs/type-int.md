# Integer (`int`)

An integer is a signed whole number.

```ravi
count = 42
negative = -7
sum = count + 8
```

## Operators

- `+`, `-`, `*`: addition, subtraction, multiplication.
- `/`: truncating integer division.
- `%`: remainder.
- `<`, `<=`, `>`, `>=`: ordering.
- `==`, `!=`: equality.
- `and`, `or`, `not` or `mattu`, `athva`, `alla`: logical operations using truthiness.

Division by zero and values outside the runtime integer range produce runtime errors.

## Index positions

Integers are commonly used as sequence indexes:

```ravi
values = [10, 20, 30]
first = values[0]
last = values[2]
```

`int` has no type-specific methods. Use `vidha(value)`/`type(value)` to inspect a value and annotations such as `value: int` to document expected inputs.
