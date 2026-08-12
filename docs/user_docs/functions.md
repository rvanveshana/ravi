# Functions

Declare functions with `kriya` in the default profile or `function` in English.

```ravi
kriya greet(name = "friend"):
    kodu "Hello " + name

mudrisu(greet())
mudrisu(greet("Asha"))
```

Functions support positional arguments, keyword arguments, defaults, recursion, lambdas, closures, nested declarations, and explicit `kodu`/`return`.

## Lambda

```ravi
square = function value => value * value
```

## Variadic calls

```ravi
kriya total(first, *values):
    sum = first
    prati value alli values:
        sum = sum + value
    kodu sum

mudrisu(total(1, 2, 3))
```

The current AST and legacy compiler paths support tuple packing for `*values` and dictionary packing for `**options`.
