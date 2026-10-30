# Standard library

The current standard library is small and experimental. Built-in operations are
provided by the compiler/VM; source modules live under `lib/ravi`. A source file's
presence does not mean its advertised API works end to end.

## Built-in functions

| Default / English | Arguments | Behavior |
| --- | --- | --- |
| `mudrisu` / `print` | Value | Print a value; return `none` |
| `vidha` / `type` | Value | Return an internal numeric value-category identifier |
| `malagu` / `sleep` | Milliseconds | Park a spawned task; block synchronous root execution |
| `shreni` / `range` | Stop; start and stop; or start, stop, step | Integer range used by supported loops; stop is exclusive |

`type` does not return a Python-style public type object. Avoid depending on its
numeric identifiers. Range steps must be nonzero. General iterator protocols are
still incomplete.

For methods, use the [string reference](strings.md) and
[collection reference](collections.md). For task operations, see
[concurrency](async-concurrency.md).

## Source modules

| Module | Current contents | Readiness |
| --- | --- | --- |
| `ravi.core` | `identity`/`gurutisu`, `is_none`/`illa_moulya` | Small source helpers; module integration is experimental |
| `ravi.math` | Arithmetic wrappers, absolute value, minimum, maximum, clamp, GCD | Small source implementation; bounded VM arithmetic |
| `ravi.collections` | `sum`/`motta`, `all`/`ellavu`, `any`/`yavudadaru` | Eager supported collections; helpers create no explicit copies |
| `ravi.exceptions` | Named exception facades | Incomplete public exception hierarchy and catch protocol |
| `ravi.json` | Bounded JSON parsing/encoding | Development implementation; rejects cycles, duplicate keys, malformed UTF-8, nonfinite numbers |
| `ravi.files`, `ravi.paths` | UTF-8 text read/write and lexical paths | 8 MiB file-operation limit; deterministic closure |
| `ravi.bytes`, `ravi.time` | UTF-8 integer-list buffers, monotonic/wall time, sleep | No arbitrary binary file or stream API yet |
| `ravi.tasks`, `ravi.channels` | Cancel/release/deadlines, bounded send/receive/close | Shared bounded pools, copy transfer; explicit lifecycle limits |
| `ravi.logging`, `ravi.testing`, `ravi.environment` | Stderr logging, assertions, environment lookup | Small development interfaces |
| `ravi.network` | API blueprint | Networking is not delivered |
| `ravi.kirana` | UI blueprint | UI runtime is not delivered |

See [task and core-library contracts](../task-runtime.md) for exact limits,
copy semantics, deadlines, close behavior, and remaining validation gates.

The `answer()` helper in `ravi.math` is a fixture that returns `41`, not a standard
mathematical API. There is no separate `lib/math.rk` compatibility module.

### Minimal math and collection helpers

`abs`/`nirapeksha` returns the absolute value; `minimum`/`kanishta` and
`maximum`/`garishtha` compare two values. `clamp`/`miti(value, lower, upper)`
includes both bounds and raises an exception if `lower > upper`.
`gcd`/`samanya_bhajaka(left: int, right: int)` uses Euclid's algorithm and
returns a nonnegative integer, with `gcd(0, 0) == 0`. The absolute value of
the minimum signed 48-bit integer cannot be represented, so both `abs` and
`gcd` raise `OverflowError` for that input. Integer overflow is never wrapped.

`sum(values, start=0)` accumulates left to right, returning `start` for an
empty collection. `all(values)` and `any(values)` use Ravi's truth rules and
stop at the first decisive element. For empty collections, `all` is `true`
and `any` is `false`. These helpers use the existing collection iteration
protocol; they do not implement streaming generators. English helper names
and Kannada aliases are available through imports in either source profile.

```ravi
ravi.math inda gcd tago
ravi.collections inda motta tago
mudrisu(gcd(48, 18))
mudrisu(motta([1, 2, 3]))
```

Both lines print `6`. Executable examples and CLI regressions cover the helpers,
cross-profile imports, empty inputs, invalid arguments, and integer overflow.

The source modules use the default profile. Their English helper names are ordinary
identifiers; they do not make their source independently compilable in the English
profile. Read [module limitations](modules.md) before importing them.

## Planned library coverage

Files and streams, paths, bytes, complete Unicode operations, JSON, time, logging,
processes, networking, TLS, and testing APIs require implementation. The
[development plan](../development-plan.md) defines their delivery order and
acceptance criteria. No Python standard-library compatibility is promised.
