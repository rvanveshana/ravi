# `ravi` Package

The `ravi` package is the standard-library namespace. Import modules with:

```ravi
ravi.math inda add tago
```

The language profile changes keywords, not library contracts. Therefore every
module publishes English names and Kanglish/Kannada aliases for the same
operation.

| Module | Purpose | Status |
| --- | --- | --- |
| `ravi.core` | shared helpers and contracts | foundation |
| `ravi.math` | numeric helpers | source implementation |
| `ravi.exceptions` | complete public exception facade | ABI migration |
| `ravi.json` | JSON encode/decode contract | blueprint |
| `ravi.network` | sockets, HTTP, DNS contract | blueprint |
| `ravi.kirana` | UI/application contract | blueprint |

Do not import internal future paths directly. Facades preserve compatibility
when a module is split into submodules.
