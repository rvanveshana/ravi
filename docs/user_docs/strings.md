# Strings

Strings hold UTF-8 text. Quote literals with single or double quotes. The current
API distinguishes Unicode scalar positions from byte offsets; these units are
not interchangeable.

```ravi
text = "AÀB"
mudrisu(text.gatra())
mudrisu(text[1])
mudrisu(text[1:2])
```

This prints `3`, `192`, and `À`. Indexing returns the integer Unicode scalar value,
not a one-character string. Slices return strings. A visible character can contain
multiple scalars, so length is not a count of grapheme clusters. Negative indexing
is not supported.

## Methods

| Default / English | Arguments | Result |
| --- | --- | --- |
| `gatra` / `length` | None | Unicode scalar count |
| `chikku` / `lower` | None | New string with ASCII letters lowercased |
| `doddu` / `upper` | None | New string with ASCII letters uppercased |
| `kadi` / `strip` | None | New string with surrounding ASCII whitespace removed |
| `huduk` / `find` | Substring | Byte offset of first match, or `-1` |
| `badla` / `replace` | Old substring, replacement | New string with replacements |
| `ode` / `split` | Separator | Sequence of parts |
| `jote` / `join` | Sequence of strings | New string separated by the receiver |

Method calls use parentheses, including methods without arguments.

```text
label = "  Ravi  "
mudrisu(label.kadi().chikku())
```

The intended result is `ravi`, but chained method calls in this example currently
fail during CLI compilation. Treat this as experimental syntax rather than a
runnable example. Full Unicode case conversion, normalization, locale-aware
comparison, and grapheme iteration are planned. Do not use the current ASCII
transformations as a Unicode normalization or security boundary.
