# Dictionary (`dict`)

A dictionary maps keys to values. Dictionary literals use braces with `key: value` pairs.

```ravi
user = {"name": "Ravi", "age": 1}
```

Keys can be indexed and assigned:

```ravi
mudrisu(user["name"])
user["age"] = 2
```

## Methods

| Method | Kanglish | Purpose |
|---|---|---|
| `get(key)` | `tago(key)` | read a value by key |
| `update(key, value)` | `badala(key, value)` | insert or replace a key |
| `remove(key)` | `tegi(key)` | delete a key |
| `contains(key)` | `olagide(key)` | test whether a key exists |
| `keys()` | `kili()` | list-like view of keys |
| `values()` | `bele()` | list-like view of values |
| `items()` | `jodi()` | list of two-value key/value pairs |
| `length()` | `gatra()` | number of entries |

Examples:

```ravi
scores = {"asha": 8, "ravi": 9}
scores.update("meera", 10)
mudrisu(scores.get("ravi"))
mudrisu(scores.contains("asha"))
for name in scores.keys():
    mudrisu(name)
for pair in scores.items():
    mudrisu(pair[0])
    mudrisu(pair[1])
scores.remove("asha")
```

Dictionary iteration directly visits keys. `keys`, `values`, and `items` create iterable views. Missing-key access, `get`, or `remove` behavior should be tested against the current runtime when designing error-sensitive code.
