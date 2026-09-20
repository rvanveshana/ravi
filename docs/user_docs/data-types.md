# Data types

Values include scalar data, collections, functions, and instances. This page
covers scalars; specialized operations are documented in [Strings](strings.md),
[Collections](collections.md), [Functions](functions.md), and [Classes](classes.md).

| Category | Example | Main use |
| --- | --- | --- |
| Integer | `42`, `-7` | Whole-number arithmetic and indexes |
| Float | `3.5` | Fractional arithmetic |
| Boolean | `true`, `false` | Conditions and comparisons |
| None | `none` | Absence of a value |
| String | `"Namaskara"` | Text |
| List | `[1, 2, 3]` | Mutable ordered sequence |
| Tuple | `(10, 20)` | Grouped positional values |
| Set | `{1, 2, 3}` | Unique values |
| Dictionary | `{"score": 90}` | Key/value lookup |
| Function | A declared or anonymous function | Callable behavior |
| Instance | `Counter(0)` | Class-defined state and methods |

## Integers

The current runtime represents signed 48-bit integers, from `-140737488355328`
through `140737488355327`. It does not provide Python's arbitrary-precision integers.
Out-of-range arithmetic is intended to report overflow rather than wrap; complete
optimization-mode conformance remains under development.

`+`, `-`, `*`, `/`, and `%` perform arithmetic. Integer division truncates toward
zero: `7 / 2` is `3`. Division by zero raises a runtime error. Do not assume Python's
floor-division or negative-remainder rules. There is no documented `//` operator.

## Floating-point values

Floats use binary64 representation. Mixed integer/float arithmetic produces
floating-point results in supported operations: `7.0 / 2` is `3.5`.
Floating-point values approximate many decimal fractions; use tolerances where
appropriate. A decimal or arbitrary-precision numeric library is not available.

## Booleans and none

Both profiles spell the literals `true`, `false`, and `none` identically.
Comparisons produce boolean values. Use `mattu`, `athva`, `alla` in `kn`, or
`and`, `or`, `not` in English, for logical expressions.

`none` denotes absence and differs from an empty string or collection. `mudrisu`
and `print` are output operations, not numeric computations; their result is none.
Implicit return and advanced conversion behavior should not be assumed to match Python.

## Type queries

`vidha(value)` in `kn`, or `type(value)` in English, currently returns a runtime
category identifier. It is not Python's type-object API. Avoid persisting those
numeric identifiers or using them as a portable reflection interface.

Type names accepted as annotations are described in [Typing](typing.md). Runtime
value categories and supported annotation syntax are not the same feature set.
