# File Handling

File handling is a planned standard-library layer. It is intentionally documented here so the API can be designed before filesystem behavior is made part of the language contract.

## Intended API

The planned API uses an ordinary library function that returns a file resource:

```ravi
file = open("notes.txt", "w")
file.write("Namaskara\n")
file.close()
```

A context-manager form is preferred for cleanup:

```ravi
jote open("notes.txt", "w") aagi file:
    file.write("Namaskara\n")
```

## Planned operations

| Operation | Purpose |
|---|---|
| `open(path, mode)` | open a path with an explicit mode |
| `read()` | read the remaining text |
| `read(size)` | read at most a requested amount |
| `readline()` | read one line |
| `readlines()` | return all remaining lines |
| `write(text)` | write text and return the written count |
| `writelines(lines)` | write a sequence of lines |
| `flush()` | push buffered data |
| `close()` | release the descriptor |
| `closed()` | report whether the resource is closed |
| `seek(position)` | move the cursor |
| `tell()` | return the cursor position |

## Planned modes

- `r`: read existing text;
- `w`: write, truncating an existing file;
- `a`: append;
- `r+`: read and write;
- `b`: reserved for a future byte-buffer API.

## Error behavior

The final API must define errors for missing paths, permission failures, invalid modes, closed handles, invalid encodings, and filesystem limits. File resources must close deterministically even when a body raises.

## Current status

No public file module or `open` runtime API is currently part of the verified standard library. Do not use this page as a promise that the sample code runs today; it is the planned reference contract.
