# Standard Library Structure

Ravi's standard library is a namespaced collection of `.rk` modules rooted at
`lib/ravi/`. The namespace is part of the public API and must not be inferred
from a filename chosen by an individual contributor.

## Canonical Layout

```text
lib/
|-- README.md
`-- ravi/
    |-- README.md
    |-- core.rk                 # small language/runtime-neutral helpers
    |-- exceptions.rk           # public exception references
    |-- math.rk                 # numeric facade
    |-- text.rk                 # text and Unicode facade
    |-- collections.rk          # sequence and mapping facade
    |-- io.rk                   # files, paths, streams, resources
    |-- os.rk                   # environment and platform information
    |-- process.rk              # subprocesses and exit status
    |-- time.rk                 # clocks, durations, dates
    |-- random.rk               # deterministic and secure random sources
    |-- json.rk                 # JSON facade
    |-- encoding.rk             # CSV, formats, and codecs
    |-- regex.rk                # regular-expression facade
    |-- network.rk              # DNS, sockets, HTTP, TLS
    |-- crypto.rk               # hashes, authentication, encryption
    |-- async.rk                # tasks, futures, cancellation
    |-- sync.rk                 # locks, events, channels
    |-- logging.rk              # structured logging
    |-- testing.rk              # assertions and test utilities
    |-- kirana.rk               # optional UI/application facade
    |-- math/                   # private implementation modules
    |-- text/
    |-- collections/
    |-- io/
    |-- os/
    |-- process/
    |-- time/
    |-- encoding/
    |-- network/
    |-- crypto/
    |-- async/
    |-- sync/
    |-- logging/
    |-- testing/
    `-- kirana/
```

A facade such as `lib/ravi/json.rk` is the stable public entry point for
`ravi.json`. When it becomes large, implementation files move into
`lib/ravi/json/`, for example:

```text
lib/ravi/json.rk
lib/ravi/json/decoder.rk
lib/ravi/json/encoder.rk
lib/ravi/json/errors.rk
```

The facade re-exports the supported public names. Callers continue to import
`ravi.json`; they do not depend on `ravi.json.decoder` unless that path is
explicitly promoted to the public API.

## Namespace Rules

- `ravi.<domain>` is the public standard-library namespace.
- `ravi.<domain>.<module>` is reserved for a documented public submodule or an
  implementation module owned by that domain.
- A domain owns one subject area. Do not place networking, file I/O, and process
  APIs in a generic `utils` or `helpers` module.
- `ravi.exceptions` is the single public exception reference catalog. Other
  libraries raise those references; they do not define competing exception
  names.
- `ravi.core` stays small and dependency-light. Domain libraries must not use
  it as a dumping ground for unrelated helpers.
- Native-backed features keep platform code in Zig runtime modules. The `.rk`
  facade owns the language-neutral API, aliases, errors, and resource rules.
- Application and third-party packages must use a package namespace other than
  `ravi`; they must never add files to the standard-library namespace.

The current resolver maps dots to directories and appends `.rk`. This means the
facade-plus-sibling-directory layout works today without introducing package
manifest semantics. A future manifest may add metadata and explicit exports,
but must preserve existing facade imports.

## Library Families

| Namespace | Responsibility | First stable milestone |
| --- | --- | --- |
| `ravi.core`, `ravi.exceptions` | language-neutral values and errors | shared contracts and diagnostics |
| `ravi.math`, `ravi.random` | numbers and reproducible randomness | integer/float helpers and seeded sources |
| `ravi.text`, `ravi.regex` | strings, Unicode, and pattern matching | Unicode-safe inspection and transforms |
| `ravi.collections` | lists, maps, sets, queues, and iteration helpers | allocation and mutation contracts |
| `ravi.io`, `ravi.os`, `ravi.process` | resources, paths, environment, subprocesses | ownership, cancellation, and platform errors |
| `ravi.time` | monotonic clocks, durations, dates, time zones | deterministic clock testing |
| `ravi.json`, `ravi.encoding` | data interchange and codecs | bounded parsing and clear format errors |
| `ravi.network`, `ravi.crypto` | network protocols and security primitives | native boundary and secret-handling review |
| `ravi.async`, `ravi.sync` | tasks, channels, locks, and cancellation | scheduler and shutdown semantics |
| `ravi.logging`, `ravi.testing` | observability and verification | stable output and test isolation |
| `ravi.kirana` | optional UI/application integration | separate platform capability set |

The table is a roadmap, not an API promise. A facade is stable only after its
implementation, bilingual names, focused tests, negative/resource tests,
documentation, and executable examples exist.

## Contribution Workflow

1. Choose the owning domain and reserve the `ravi.<domain>` name.
2. Add or update the domain facade; keep its public surface small.
3. Split internals by responsibility under the matching domain directory when
   the facade or implementation approaches the source-size budget.
4. Add English and Kanglish/Kannada aliases that share one implementation.
5. Define exception, ownership, cancellation, and resource-limit behavior.
6. Add focused unit tests, integration tests, negative tests, and an example.
7. Update the domain index and this roadmap before calling the API stable.

No library should be added as an unowned top-level `lib/*.rk` file. The legacy
`lib/math.rk` path remains a compatibility module; new code belongs under
`lib/ravi/`.
