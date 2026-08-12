# Getting Started

Create `hello.rk`:

```ravi
mudrisu("Namaskara, Ravi!")
```

Run it:

```powershell
ravi run hello.rk
```

A small typed function:

```ravi
kriya square(value: int):
    return value * value

mudrisu(square(6))
```

Ravi uses four-space indentation. A colon introduces a suite, and the indented lines below it form the suite.

## English profile

The same program can use English keywords:

```ravi
function square(value: int):
    return value * value

print(square(6))
```

Use `.rk` for both application files and importable library files.
