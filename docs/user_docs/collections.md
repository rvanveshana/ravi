# Collections

Ravi provides ordered lists, tuples, unique sets, and dictionaries. This page
is an overview; use the individual type references for complete methods and
examples.

```ravi
numbers = [1, 2, 3]
coordinates = (10, 20)
unique = {1, 2, 3}
profile = {"name": "Ravi", "version": 1}
```

Access values with indexing:

```ravi
mudrisu(numbers[0])
mudrisu(profile["name"])
mudrisu(coordinates[0:1])
```

Collections can be iterated with `for`. Dictionary views expose keys, values, and items. An item view contains a two-element key/value pair.

Collections are managed runtime objects, so programs do not need to manage their memory manually.

## Detailed references

- [List](type-list.md)
- [Tuple](type-tuple.md)
- [Set](type-set.md)
- [Dictionary](type-dict.md)
- [Method Reference](method-reference.md)
