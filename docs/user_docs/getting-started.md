# Getting started

Build the executable as described in [Installation](installation.md). This tutorial
uses the default Kannada/Kanglish source profile.

## Create a program

Save the following as `hello.rk` in the repository root:

```ravi
kriya square(value: int):
    kodu value * value

result = square(6)
mudrisu(result)
```

`kriya` declares a function, `kodu` returns a value, and `mudrisu` prints a value.
The four spaces before `kodu` place it inside the function body. `: int` annotates
the parameter; [Typing](typing.md) explains the current limits of type checking.

Run it:

```powershell
./zig-out/bin/ravi.exe run hello.rk
```

Expected output:

```text
36
```

## Use English vocabulary

Save this complete program as `hello_en.rk`:

```ravi
# ravi: language=en
function square(value: int):
    return value * value

print(square(6))
```

Run it with the same command shape. The first-line header selects English for the
file. Alternatively, `--lang en` explicitly selects the profile for a CLI invocation.
Do not mix `function` with `kodu`, or `kriya` with `return`, in the same program.

## Check before running

```powershell
./zig-out/bin/ravi.exe check hello.rk
```

`check` performs the currently implemented syntax and semantic checks. It does not
execute the program and is not a complete static correctness guarantee.

Next: [Syntax](syntax.md), [Control flow](control-flow.md), and [Functions](functions.md).
