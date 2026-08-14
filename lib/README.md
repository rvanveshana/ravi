# Ravi Standard Library

This directory contains Ravi's built-in library source and the contracts for
future native-backed libraries. The canonical package namespace is `ravi`.
The complete taxonomy, ownership rules, and growth plan are documented in
[`docs/user_docs/standard-library-structure.md`](../docs/user_docs/standard-library-structure.md).

## Import Rule

Use the package name, then select public names with `inda` and `tago`:

```ravi
ravi.math inda add, answer tago
value = add(2, 3)
```

English source uses the same import grammar:

```ravi
# ravi: language=en
ravi.math from add, answer import
```

A dotted module name maps to a path below this directory:

```text
ravi.math       -> lib/ravi/math.rk
ravi.exceptions -> lib/ravi/exceptions.rk
ravi.json       -> lib/ravi/json.rk
ravi.network    -> lib/ravi/network.rk
ravi.kirana     -> lib/ravi/kirana.rk
```

The older `lib/math.rk` module remains supported for compatibility. New
standard-library work belongs under `lib/ravi/`.

## Facades and Submodules

Each `lib/ravi/<domain>.rk` file is the public facade for one owned domain.
When an implementation grows, place focused modules in the sibling directory
`lib/ravi/<domain>/` and keep the facade import stable. For example:

```text
lib/ravi/json.rk
lib/ravi/json/decoder.rk
lib/ravi/json/encoder.rk
lib/ravi/json/errors.rk
```

Do not add unrelated files directly to `lib/`, and do not create a second
exception or utility namespace. New standard modules use `ravi.<domain>`;
application packages must use a namespace other than `ravi`.

## Bilingual API Rule

Every public built-in API must expose one canonical English name and one
stable Kanglish/Kannada alias. Both names must call the same implementation;
they must not become separate behavior paths.

Example:

```ravi
ravi.math inda add, serisu tago
value_a = add(2, 3)
value_b = serisu(2, 3)
```

Rules:

- English names are stable interoperability names for documentation and
  external packages.
- Function-based APIs use lowercase `snake_case`; future class-based
  exception types may use `PascalCase` after the runtime ABI supports them.
- Kanglish aliases are first-class public names, not translations added by
  the formatter.
- An alias must have identical arguments, return value, errors, and side
  effects.
- New APIs require both names, tests for both names, and a user-doc entry.
- Library modules must not depend on the selected language profile; imports
  work from both `kn` and `en` source.
- Do not expose Zig error names, pointers, handles, or ABI details in `.rk`
  APIs.
- Library code may delegate to a future native implementation, but the public
  contract must remain the same.

## Package Layout

```text
lib/
|-- README.md
|-- math.rk                 # legacy compatibility facade
`-- ravi/
    |-- README.md            # package index and status
    |-- core.rk              # core helpers and shared contracts
    |-- math.rk              # arithmetic and numeric helpers
    |-- exceptions.rk        # complete public exception facade
    |-- text.rk              # text and Unicode facade
    |-- collections.rk       # sequence and mapping facade
    |-- io.rk                # files, paths, and streams facade
    |-- os.rk                # environment and platform facade
    |-- process.rk           # subprocess facade
    |-- time.rk              # clocks and date/time facade
    |-- random.rk            # random-source facade
    |-- json.rk              # JSON blueprint
    |-- encoding.rk          # data-format facade
    |-- regex.rk             # pattern-matching facade
    |-- network.rk           # networking blueprint
    |-- crypto.rk            # cryptography facade
    |-- async.rk             # asynchronous task facade
    |-- sync.rk              # synchronization facade
    |-- logging.rk           # structured logging facade
    |-- testing.rk           # testing facade
    `-- kirana.rk            # UI blueprint: Kirana
```

When a module grows, split it without changing its public facade:

```text
lib/ravi/json/
|-- decoder.rk
|-- encoder.rk
`-- errors.rk
```

The facade remains `ravi.json`; it re-exports only the supported public names.
Internal helper modules are not public imports.

## Status

- `ravi.math`: source implementation, expanding incrementally.
- `ravi.exceptions`: the single public exception facade with English/Kanglish
  aliases; native exception objects and inheritance are runtime work in
  progress.
- `ravi.json`: blueprint only; no parser is claimed yet.
- `ravi.network`: blueprint only; no sockets or HTTP implementation is claimed.
- `ravi.kirana`: blueprint only; Kirana is the planned UI library.
- `ravi.core`: reserved for small cross-platform helpers and contracts.

## Native Boundary

Native libraries should be implemented behind a Zig runtime module, not by
embedding platform-specific Zig calls in every `.rk` file. The boundary should
provide:

1. validated Ravi values in;
2. owned Ravi values out;
3. Ravi exceptions on failure;
4. cancellation and resource cleanup where applicable; and
5. identical behavior for the English and Kanglish aliases.

A library is considered delivered only when its facade, aliases, docs, focused
Zig tests, and executable `.rk` examples are present.
