# English Examples

Use the English profile for teams that prefer English source vocabulary.

```ravi
function greet(name: string):
    return "Hello, " + name

for item in ["Ravi", "Python", "Kannada"]:
    print(greet(item))
```

A typed and dynamic combination:

```ravi
function total(first: int, *values, **options):
    result = first
    for value in values:
        result = result + value
    if options["bonus"]:
        result = result + options["bonus"]
    return result

print(total(1, 2, 3, bonus = 4))
```

The source uses the same runtime and semantics as the Kannada/Kanglish profile.
