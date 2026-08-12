# Installation

## Requirements

- Windows, Linux, or another platform supported by Zig.
- Zig `0.17.0-dev.1415+64dfaa568` for building the current repository state.
- PowerShell on Windows for the repository helper scripts.

## Build Ravi from source

From the repository root:

```powershell
zig build
```

The executable is written to `zig-out/bin/ravi.exe` on Windows.

## Run a program

```powershell
.\zig-out\bin\ravi.exe run .\examples\arithmetic.rk
```

To test the AST compiler explicitly:

```powershell
.\zig-out\bin\ravi.exe run --ast-compiler .\examples\arithmetic.rk
```

## Verify the build

```powershell
zig build test --summary all
.\test.ps1
```

The repository test suite also exercises the retained examples and runtime components.
