# Float (`float`)

A float is a number with a fractional component.

```ravi
pi = 3.14159
radius = 2.0
area = pi * radius * radius
```

Floats support arithmetic, ordering, equality, and mixed operations with integers.

```ravi
whole = 4
fraction = whole / 2.0
mudrisu(fraction == 2.0)
```

Use a float annotation when a function expects fractional input:

```ravi
kriya circle_area(radius: float):
    kodu 3.14159 * radius * radius
```

`float` has no type-specific methods. Formatting supports width, alignment, and basic `f` formatting; precision and advanced conversion flags remain under development.
