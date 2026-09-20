# Keywords and source profiles

Ravi Kannada provides two source profiles. The default profile uses Latin-script
Kannada spellings (Kanglish). Select English with `# ravi: language=en` on the first
line. Full Kannada-script keywords are planned; they are not an additional
executable profile today. Profile selection does not translate identifiers or strings.

| Default | English | Purpose |
| --- | --- | --- |
| `adre` | `if` | Conditional branch |
| `inadre` | `elif` | Additional condition |
| `illa` | `else` | Alternative branch |
| `vargu` | `while` | Conditional loop |
| `prati` | `for` | Iteration |
| `nillu` | `break` | Exit loop |
| `munde` | `continue` | Next iteration |
| `bidu` | `pass` | Empty statement |
| `kriya` | `function` | Function definition |
| `kodu` | `return` | Return a value |
| `horabidu` | `spawn` | Start a worker task |
| `kaayu` | `wait` | Wait for a task |
| `taru` | `yield` | Reserved generator syntax; incomplete execution |
| `nodu` | `try` | Protected suite |
| `tappu` | `except` | Exception handler |
| `kone` | `finally` | Cleanup suite |
| `yese` | `raise` | Raise an error |
| `tago` | `import` | Import declaration |
| `inda` | `from` | Import source |
| `jote` | `with` | Context syntax; incomplete protocol |
| `aagi` | `as` | Alias or binding |
| `mattu` | `and` | Logical conjunction |
| `athva` | `or` | Logical disjunction |
| `alla` | `not` | Logical negation |
| `alli` | `in` | Membership or iteration |
| `ide` | `is` | Identity syntax |
| `roopa` | `class` | Class definition |
| `ella` | `global` | Global declaration |
| `saarva` | `public` | Public visibility |
| `swanta` | `private` | Private visibility |
| `vansha` | `protected` | Protected visibility |
| `olage` | `internal` | Internal visibility |
| `true`, `false`, `none` | Same | Literal values |

Keyword recognition does not imply a complete runtime protocol. See
[implementation status](../implementation-status.md) for readiness and
[planned features](planned-features.md) for unfinished features.

Built-in functions and methods have their own mappings in the
[standard library](standard-library.md), [strings](strings.md), and
[collections](collections.md) references. `tanna`/`self`, `huttu`/`init`, and
`guru` are also used by the current [object model](classes.md).
