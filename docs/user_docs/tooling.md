# Tooling

## Build and tests

```powershell
zig build
zig build test --summary all
.\test.ps1
```

## Compiler profiles

The normal CLI uses the stable legacy token compiler. The AST compiler is available for migration and conformance testing:

```powershell
ravi run --ast-compiler program.rk
```

## Source tools

The repository includes a formatter, structured diagnostics, bytecode verification, debugger hooks, LSP protocol support, DAP protocol support, and benchmark scripts. These components are actively developed and their implementation details are documented under `docs/`.

When reporting a problem, include the `.rk` file, selected profile, command, and complete diagnostic output.
