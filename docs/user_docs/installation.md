# Installation

Ravi Kannada currently builds from source. Use the repository's pinned Zig version;
compatibility with arbitrary newer development builds is not guaranteed.

## Requirements

| Requirement | Version or scope |
| --- | --- |
| Zig | `0.17.0-dev.1415+64dfaa568` |
| Source checkout | This repository, including `build/`, `config/`, `src/`, and `lib/` |
| Shell | PowerShell for repository `.ps1` maintenance scripts |
| CI targets | Windows and Linux; current local validation is recorded separately |

Install the required Zig toolchain and place its executable on `PATH`. Check it:

```powershell
zig version
```

Expected version: `0.17.0-dev.1415+64dfaa568`.

## Build

From the repository root:

```powershell
zig build
```

The Windows executable is `zig-out/bin/ravi.exe`. On Linux it is `zig-out/bin/ravi`.
Use the platform's executable path in commands throughout this handbook.

## Verify the installation

On Windows:

```powershell
./zig-out/bin/ravi.exe run examples/arithmetic.rk
```

Expected output: `arithmetic: PASS`. This is an installation smoke check, not a
complete language conformance test. Building the executable does not run the tests.

## Build modes

`zig build` uses the default debug mode. To build with release safety checks:

```powershell
zig build -Doptimize=ReleaseSafe
```

`ReleaseFast` is also available through Zig's build options. It does not establish
that all language safety guarantees have been verified in that configuration.
See [Contributing](../contributing.md) for component and milestone validation.

## Troubleshooting

If Zig is not found, correct `PATH` before building. If compilation fails after a
toolchain update, compare `zig version` with the pinned version above. Cache access
errors indicate a filesystem permission issue, not a Ravi Kannada syntax error.

Continue with [Getting started](getting-started.md).
