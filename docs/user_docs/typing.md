# Typing

Ravi supports both dynamic programming and optional annotations.

## Dynamic values

```ravi
value = 10
value = "ten"
```

## Annotations

```ravi
kriya add(left: int, right: int):
    return left + right

name: string = "Ravi"
```

Annotations document intent and allow compiler/runtime guards where supported. They do not require every program to be fully statically typed.

See [Data Types](data-types.md) for the complete built-in type catalog and the
individual type pages for literals, operators, methods, and examples.

## Variadic parameters

```ravi
kriya combine(first: int, *values, **options):
    return first + values[0] + options["bonus"]
```

`*values` receives extra positional arguments as a tuple. `**options` receives extra keyword arguments as a dictionary.

Unions, nullable flow narrowing, automatic conversions, and complete static semantic checking are active development areas.
