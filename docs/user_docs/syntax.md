# Syntax and source profiles

Source files use UTF-8 and the `.rk` extension. Identifiers and executable keywords
currently use the supported Latin-script vocabulary. Text literals may contain
Kannada and other Unicode text.

## Profile selection

The default profile is `kn` (Kannada/Kanglish). A first-line header selects English:

```text
# ravi: language=en
```

`# ravi: language=kn` explicitly selects the default vocabulary. A CLI `--lang kn`
or `--lang en` option overrides the header for that invocation. The language name
is Ravi Kannada; the `# ravi:` directive is the current source format.

The two profiles map to common operations. Use the [keyword table](keywords.md)
and the method tables on the string/collection pages. Cross-profile module
execution still has limitations; see [Modules](modules.md).

## Blocks and comments

A colon introduces an indented suite. Use four spaces for each indentation level;
tabs in indentation are rejected. `#` begins a comment extending to the line end.

```ravi
# Select a message using the Kannada/Kanglish profile.
score = 72
adre score >= 50:
    mudrisu("pass")
illa:
    mudrisu("retry")
```

Output: `pass`. Keep examples on ordinary physical lines; Python-style implicit
line continuation and every alternative quoting form are not guaranteed.

## Expressions

Parentheses group expressions. Multiplication, division, and remainder bind more
tightly than addition and subtraction. Comparison binds below arithmetic;
`mattu`/`and` binds more tightly than `athva`/`or`. Write parentheses whenever the
intended grouping is not obvious. Do not assume Python's chained-comparison or
short-circuit behavior for unverified combinations.

Calls use parentheses and comma-separated arguments: `square(6)`. Member access
uses a dot: `values.gatra()`. Indexing uses brackets: `values[0]`.

## Assignment and declarations

Assignment binds a name: `count = 3`. Functions and classes use declarations with
indented bodies. Type annotations are optional in supported positions. Keywords
are profile-specific; user-defined names do not need translation between profiles.

See [Data types](data-types.md), [Functions](functions.md), and [Typing](typing.md).
