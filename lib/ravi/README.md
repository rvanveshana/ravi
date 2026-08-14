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
| `ravi.text` | text and Unicode | planned |
| `ravi.collections` | sequence and mapping helpers | planned |
| `ravi.io` | files, paths, streams, and resources | planned |
| `ravi.os` | environment and platform information | planned |
| `ravi.process` | subprocesses and exit status | planned |
| `ravi.time` | clocks, durations, and dates | planned |
| `ravi.random` | deterministic and secure random sources | planned |
| `ravi.json` | JSON encode/decode contract | blueprint |
| `ravi.encoding` | data formats and codecs | planned |
| `ravi.regex` | regular expressions | planned |
| `ravi.network` | sockets, HTTP, DNS contract | blueprint |
| `ravi.crypto` | hashes and cryptographic primitives | planned |
| `ravi.async` | tasks, futures, and cancellation | planned |
| `ravi.sync` | locks, events, and channels | planned |
| `ravi.logging` | structured logging | planned |
| `ravi.testing` | assertions and test utilities | planned |
| `ravi.kirana` | UI/application contract | blueprint |

Do not import internal future paths directly. A facade such as `ravi.json`
may be split into `lib/ravi/json/decoder.rk` and related modules while the
public import remains unchanged. See
[`standard-library-structure.md`](../../docs/user_docs/standard-library-structure.md)
for the ownership and contribution rules.
