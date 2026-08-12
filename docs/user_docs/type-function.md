# Function

Functions are first-class values. They can be assigned to variables, passed as arguments, returned from other functions, and captured by closures.

```ravi
kriya add(a, b):
    kodu a + b

operation = add
mudrisu(operation(2, 3))
```

## Parameters

```ravi
kriya configure(name = "default", *values, **options):
    kodu (name, values, options)
```

- Positional parameters receive arguments by order.
- Keyword arguments can use `name = value` at the call site.
- Defaults provide values for omitted parameters.
- `*values` receives extra positional arguments as a tuple.
- `**options` receives extra keyword arguments as a dictionary.

## Closures

```ravi
kriya make_counter(start):
    value = start
    kriya next_value():
        value = value + 1
        kodu value
    kodu next_value

counter = make_counter(0)
mudrisu(counter())
```

A function has no built-in methods beyond calling it with parentheses. Function annotations are described in [Typing](typing.md).
