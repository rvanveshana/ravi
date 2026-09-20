# Control flow

Ravi Kannada uses indented suites for conditions and loops. This page uses the
`kn` profile; [Keywords](keywords.md) lists the English equivalents.

## Conditions

Use `adre`, optional `inadre` branches, and `illa`:

```ravi
score = 72
adre score >= 90:
    mudrisu("excellent")
inadre score >= 50:
    mudrisu("pass")
illa:
    mudrisu("retry")
```

Output: `pass`. Prefer explicit comparisons when the intended condition matters;
truth conversion for every future object type is not yet a stable protocol.

`mattu`/`and` and `athva`/`or` short-circuit: the right operand runs only
when needed. Comparisons such as `1 < value < 10` compare adjacent operands
and evaluate the middle operand once. Explicit parentheses preserve grouping.
See the [evaluation regression](../../examples/regressions/evaluation_semantics.rk).

## While loops

`vargu` repeats a suite while its condition holds:

```ravi
count = 3
vargu count > 0:
    mudrisu(count)
    count = count - 1
```

Output: `3`, `2`, and `1`, each on a separate line.

## Counted iteration

`prati` introduces a loop variable and `alli` introduces the iterable.
`shreni(start, stop, step)` excludes the stop value:

```ravi
total = 0
prati value alli shreni(1, 4, 1):
    total = total + value
mudrisu(total)
```

Output: `6`. The English equivalents are `for`, `in`, and `range`.
Use a nonzero step whose sign matches the intended direction.

## Transfers and empty suites

`nillu` exits the nearest loop. `munde` continues with its next iteration.
Both require an enclosing loop. `bidu` is an executable no-op for an otherwise
empty suite. `kodu` returns from a function; it is not a loop-control substitute.

Collection mutation during iteration has no complete, documented invalidation
contract yet. Prefer constructing a separate result collection.

See [Collections](collections.md) and [Exceptions](exceptions.md).
