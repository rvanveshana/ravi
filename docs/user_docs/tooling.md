# Command-line tools

Use the built `ravi` executable, or its full path under `zig-out/bin`. Run
`ravi --help` for available options and `ravi --version` for the development version.

| Command | Purpose |
| --- | --- |
| `ravi run program.rk` | Compile and execute a program |
| `ravi program.rk` | Shorthand for `run` |
| `ravi check program.rk` | Parse and analyze without executing |
| `ravi tokens program.rk` | Inspect lexer tokens |
| `ravi bytecode program.rk` | Inspect emitted bytecode |
| `ravi trace program.rk` | Run with execution tracing |
| `ravi fmt program.rk` | Rewrite the file using the formatter |
| `ravi fmt-check program.rk` | Check formatting without rewriting |

`check` is a partial front-end check. It is not proof that the runtime supports
every construct in a file. Compiler selection is internal; `--ast-compiler` is not
a supported public option.

## Profiles and diagnostics

```powershell
ravi run --lang en program.rk
ravi check --diagnostic-format json program.rk
ravi check --diagnostic-format compact program.rk
```

`--lang kn` and `--lang en` override the source header. Diagnostic formats are
`human` (default), `compact`, and `json`. Structured compiler diagnostics do not
imply that all runtime failures and tool output use the same JSON envelope.

The current executable writes program/debug output through the runtime's diagnostic
stream. Do not assume a stable stdout-only interface for shell pipelines. A final
top-level expression can also be displayed by the CLI.

## Editor integration and bug reports

LSP, DAP, and debugger components exist in the repository. They are under development
and are not advertised as a production editor integration.

When reporting a problem, include a minimal `.rk` file, its profile, the complete
command and diagnostic, operating system, Zig version, and repository revision.
For build and test instructions, see [Contributing](../contributing.md).
