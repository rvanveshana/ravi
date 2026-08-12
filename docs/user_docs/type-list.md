# List (`list`)

A list is an ordered, mutable sequence. List literals use square brackets and may contain mixed values.

```ravi
items = [3, 1, 2]
items.append(4)
```

## Indexing and slicing

```ravi
items = [10, 20, 30]
first = items[0]
part = items[1:3]
items[1] = 25
```

Indexes start at zero. Out-of-range indexes are runtime errors.

## Methods

| Method | Kanglish | Purpose |
|---|---|---|
| `append(value)` | `serisu(value)` | add one value at the end |
| `insert(index, value)` | `haku(index, value)` | insert before an index |
| `remove(value)` | `tegi(value)` | remove the first matching value |
| `contains(value)` | `olagide(value)` | return whether a value exists |
| `clear()` | `khaali()` | remove all values |
| `pop()` | `kithu()` | remove and return the last value |
| `count()` | `enisu()` | return the number of values |
| `length()` | `gatra()` | return the number of values |
| `reverse()` | `ultha()` | reverse the list in place |
| `sort()` | `jodisu()` | sort integer values in ascending order |

Examples:

```ravi
values = [3, 1, 2]
values.append(4)
values.insert(0, 9)
mudrisu(values.contains(2))
mudrisu(values.count())
last = values.pop()
values.reverse()
values.sort()
values.remove(1)
```

Mutation methods that change the list return `none` in ordinary statement use. `remove` and `pop` produce runtime errors when no matching value or element exists.
