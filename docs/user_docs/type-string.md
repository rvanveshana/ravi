# String (`str` / `string`)

A string is an immutable sequence of text. Use single or double quotes according to the lexer rules, and use an `r` prefix for raw strings when backslashes should remain literal.

```ravi
name = "Ravi"
path = r"C:\\projects\\ravi"
```

## Indexing and slicing

Indexes are zero-based. String indexing returns a codepoint value; slicing returns a string.

```ravi
word = "Ravi"
mudrisu(word[0])
mudrisu(word[1:3])
```

## Methods

| English | Kanglish | Result |
|---|---|---|
| `length()` | `gatra()` | number of Unicode codepoints |
| `lower()` | `chikku()` | lowercase string |
| `upper()` | `doddu()` | uppercase string |
| `strip()` | `kadi()` | remove ASCII whitespace at both ends |
| `find(needle)` | `huduk(needle)` | byte position, or `-1` when absent |
| `replace(old, new)` | `badla(old, new)` | string with replacements |
| `split(delimiter)` | `ode(delimiter)` | list of substrings |
| `delimiter.join(values)` | `delimiter.jote(values)` | joined string |

Examples:

```ravi
text = "  Ravi Language  "
mudrisu(text.strip())
mudrisu(text.upper())
mudrisu("a,b,c".split(","))
mudrisu("-".join(["a", "b", "c"]))
mudrisu("banana".find("nan"))
mudrisu("ravi".replace("r", "R"))
```

String methods return new strings and do not modify the original value.
