# Set (`set`)

A set stores unique values. Set literals use braces without key/value colons.

```ravi
numbers = {1, 2, 2, 3}
# numbers contains 1, 2, and 3
```

Sets support membership, iteration, indexing only through iteration views where applicable, and set algebra.

## Methods and operations

| Operation | Kanglish | Purpose |
|---|---|---|
| `contains(value)` | `olagide(value)` | membership test |
| `union(other)` | `koodu(other)` | values in either set |
| `intersection(other)` | `ondu(other)` | values in both sets |
| `difference(other)` | `bere(other)` | values in the left set only |
| `length()` | `gatra()` | number of unique values |

Examples:

```ravi
left = {1, 2, 3}
right = {3, 4, 5}
mudrisu(left.contains(2))
all_values = left.union(right)
common = left.intersection(right)
only_left = left.difference(right)
```

Set values are unique according to Ravi equality and hashing rules. Use a list when ordering or duplicate entries matter.
