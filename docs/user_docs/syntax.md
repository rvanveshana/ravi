# Syntax

## Comments and indentation

```ravi
# A comment occupies the rest of the line.
if score >= 50:
    mudrisu("pass")
```

Blocks use exactly four spaces per indentation level. Comments and blank lines do not create a block.

## Values

```ravi
count = 42
ratio = 3.14
name = "Ravi"
active = true
missing = none
numbers = [1, 2, 3]
point = (10, 20)
options = {"fast": true}
```

## Expressions

Arithmetic, comparisons, logical operations, calls, indexing, slicing, and member access are supported:

```ravi
result = values[0] + options["offset"]
visible = ready and not hidden
piece = name[0:3]
```

## Declarations

```ravi
kriya greet(name: string):
    mudrisu("Hello " + name)

class Counter:
    kriya init(start: int):
        self.value = start
```

See [Keywords](keywords.md) for the vocabulary in each profile.
