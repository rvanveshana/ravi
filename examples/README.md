# Executable Ravi Kannada examples

Every `.rk` file in this directory is an executable check with a matching `.out`
file containing its exact expected output. Examples use assertions that raise on
incorrect results, output snapshots, or both. The source header selects the profile.

From the repository root, after building:

```powershell
./tools/test_examples.ps1
./tools/test_examples.ps1 -Path examples/regressions
```

The runner discovers files recursively, runs each with a ten-second timeout, and
requires both exit code zero and matching output. Missing snapshots, unexpected
output, runtime errors, and timeouts fail the run. Snapshots normalize line endings
and trailing newlines only. The CLI currently emits output on stderr; the runner
captures both streams. Cross-stream interleaving is not an output contract.

Use `./test.ps1 -ExamplesOnly` to build and run examples without unit tests. Use
`./test.ps1` for build, unit tests, and examples. CI runs examples against the binary
already built for each optimization mode without rebuilding it.

The `regressions` directory covers source-order execution, expression functions,
class construction, collection expression roots, built-in methods, and English
profile parity. Add a minimal failing example before fixing a language behavior.
Keep expected output independent of the implementation; never regenerate snapshots
from failing program output to make a check pass.

Library fixtures imported by examples live in `lib/ravi`. All `.rk` files placed
under `examples` must themselves be runnable; do not place passive helper modules
here. See the [handbook](../docs/user_docs/README.md) for language documentation.
