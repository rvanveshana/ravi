# Collections

Lists, tuples, sets, and dictionaries are available, but their protocols are still
being made consistent. Prefer explicit operations and avoid relying on Python's
collection behavior where it is not documented here.

```ravi
values = [3, 1, 2]
values.serisu(4)
mudrisu(values.gatra())
mudrisu(values[0])
```

This prints `4` and `3`. See the [executable regression](../../examples/regressions/list_methods.rk).
Indices start at zero. Negative indices are not supported.
List assignment such as `values[0] = 9` updates an element.

## Lists

| Default / English | Arguments | Behavior |
| --- | --- | --- |
| `gatra` / `length` | None | Number of elements |
| `enisu` / `count` | None | Number of elements; not an occurrence count |
| `serisu` / `append` | Value | Append one element |
| `haku` / `insert` | Index, value | Insert one element |
| `tegi` / `remove` | Value | Remove the first matching element; missing values fail |
| `olagide` / `contains` | Value | Test membership |
| `khaali` / `clear` | None | Remove all elements |
| `kithu` / `pop` | None | Remove and return the last element |
| `ultha` / `reverse` | None | Reverse in place |
| `jodisu` / `sort` | None | Sort in place |

Use mutating operations as statements. Their return convention is not yet a stable
API; do not chain them. Sorting mixed types and custom ordering are not supported
as a general protocol.

## Tuples and sets

Tuples use `(1, 2)` and sets use `{1, 2}`. Set literals remove duplicates. Both
currently share array storage with lists. Tuple immutability and restrictions on
set mutation are incomplete; callers must not rely on enforced immutability.

Set methods `koodu`/`union`, `ondu`/`intersection`, and `bere`/`difference`
take another set and produce a new set. General user-defined equality and hashing
are not complete.

## Dictionaries

Dictionaries use key-value literals such as `{"answer": 42}`. Read with
`mapping[key]`; a missing key raises a runtime error. String-key lookup compares
text content.

| Default / English | Arguments | Behavior |
| --- | --- | --- |
| `tago` / `get` | Key | Look up a key; do not assume Python's optional default argument |
| `badala` / `update` | Key, value | Set one entry; does not accept a mapping |
| `tegi` / `remove` | Key | Remove an entry |
| `kithu` / `pop` | Key | Remove and return the value; missing keys fail |
| `olagide` / `contains` | Key | Test key membership |
| `kili` / `keys` | None | Materialize keys |
| `bele` / `values` | None | Materialize values |
| `jodi` / `items` | None | Materialize key-value pairs |

Iteration order and mutation during iteration are not stable contracts. Use
primitive keys until object equality and hashing are fully specified. For storage
and numeric limits, see [data types](data-types.md).
