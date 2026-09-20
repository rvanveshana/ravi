# Ravi Kannada feature matrix

Generated from `config/feature-matrix.json` by `tools/generate_feature_matrix.ps1`.

These maintainer-entered stage flags are historical tracking data, not automated test results or release readiness. See [Implementation status](implementation-status.md) for current evidence and limitations.

| Feature | designed | parsed | analyzed | lowered | executed | tested |
| --- | --- | --- | --- | --- | --- | --- |
| Lexer and parser | yes | yes | yes | yes | yes | yes |
| Single AST compiler | yes | yes | yes | yes | yes | yes |
| Bytecode verifier | yes | no | no | yes | yes | yes |
| Classes and inheritance | yes | yes | no | yes | no | no |
| Gradual typing | yes | yes | no | no | no | no |
| Modules and artifacts | yes | yes | yes | yes | yes | yes |
| Runtime Value ABI | yes | no | no | yes | yes | yes |
| Managed GC and ownership | yes | no | no | yes | yes | yes |
| Diagnostics and DAP | yes | yes | yes | yes | yes | yes |
| Async and generators | yes | yes | no | no | no | no |
| Native backend | yes | no | no | no | no | no |
