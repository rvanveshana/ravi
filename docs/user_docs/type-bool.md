# Boolean (`bool`)

A boolean is either `true` or `false`.

```ravi
is_ready = true
has_error = false
```

## Boolean operations

```ravi
if is_ready and not has_error:
    mudrisu("continue")

allowed = is_ready or has_error
```

The default-profile spellings are `mattu` for `and`, `athva` for `or`, and `alla` for `not`. English source uses `and`, `or`, and `not`.

Comparisons produce booleans. Booleans have no type-specific methods.
