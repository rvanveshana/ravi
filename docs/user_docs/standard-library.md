# Standard library

The current standard library is small and experimental. Built-in operations are
provided by the compiler/VM; source modules live under `lib/ravi`. A source file's
presence does not mean its advertised API works end to end.

## Built-in functions

| Default / English | Arguments | Behavior |
| --- | --- | --- |
| `mudrisu` / `print` | Value | Print a value; return `none` |
| `vidha` / `type` | Value | Return an internal numeric value-category identifier |
| `malagu` / `sleep` | Milliseconds | Block the current thread |
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
| `ravi.math` | `add`/`serisu`, `subtract`/`kadime`, `multiply`/`gunisu`, `divide`/`bhagisu` | Arithmetic wrappers, not a general mathematics library |
| `ravi.exceptions` | Named exception facades | Incomplete public exception hierarchy and catch protocol |
| `ravi.json` | API blueprint | JSON encoding/decoding is not delivered |
| `ravi.network` | API blueprint | Networking is not delivered |
| `ravi.kirana` | UI blueprint | UI runtime is not delivered |

The `answer()` helper in `ravi.math` is a fixture that returns `41`, not a standard
mathematical API. There is no separate `lib/math.rk` compatibility module.

The source modules use the default profile. Their English helper names are ordinary
identifiers; they do not make their source independently compilable in the English
profile. Read [module limitations](modules.md) before importing them.

## Planned library coverage

Files and streams, paths, bytes, complete Unicode operations, JSON, time, logging,
processes, networking, TLS, and testing APIs require implementation. The
[development plan](../development-plan.md) defines their delivery order and
acceptance criteria. No Python standard-library compatibility is promised.
