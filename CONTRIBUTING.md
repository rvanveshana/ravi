# Contributing to Ravi Kannada

Thank you for helping build Ravi Kannada. Contributions are welcome from learners,
language users, documentarians, designers, and compiler developers.

Help us build a fast, flexible, robust language with dynamic values, useful type
checks, async execution, threading, and equivalent English/Kannada APIs.

## Find a contribution

Visit [Ravi on GitHub](https://github.com/rvanveshana/ravi) and choose an
[issue form](https://github.com/rvanveshana/ravi/issues/new/choose). Search
[good first issues](https://github.com/rvanveshana/ravi/labels/good%20first%20issue)
or [help wanted](https://github.com/rvanveshana/ravi/labels/help%20wanted), or
propose a small task from the [development plan](docs/development-plan.md).
Ask in the issue if you need help locating the relevant code.

Useful starting points include clearer diagnostics, English/Kannada examples,
library documentation, reduced bug reproductions, and focused regression fixes.
Compiler, GC, task ownership, cancellation, and performance work benefit from
an agreed scope and explicit acceptance criteria before implementation.

## Before you start

Search existing issues before opening a new one. For a bug, include a minimal `.rk`
program, source profile, actual and expected behavior, operating system, and Zig
version. Discuss new syntax, semantics, public APIs, and broad architectural changes
in an issue before investing in an implementation.

Small fixes can go directly to a pull request. Keep each pull request focused and
explain the observable behavior it changes.

## Develop and validate

1. Fork [rvanveshana/ravi](https://github.com/rvanveshana/ravi).
2. Clone your fork and create a branch:

```shell
git clone https://github.com/YOUR_USERNAME/ravi.git
cd ravi
git remote add upstream https://github.com/rvanveshana/ravi.git
git switch -c fix/short-description
```

3. Install Zig `0.17.0-dev.1415+64dfaa568` and run `zig build`.
4. Make one focused change and update the relevant documentation.
5. Validate the affected behavior, then commit and push your branch.
6. Open a PR against `rvanveshana/ravi` and complete its template. Respond to
   review comments; maintainers handle repository labels and merging.

From the repository root, use the checks appropriate to your change:

```powershell
zig build
zig build test-vm --summary all -j2
./tools/test_examples.ps1
./tools/test_cli.ps1
zig fmt --check build.zig build config src tests
./tools/check_src_sizes.ps1
git diff --check
```

Select `test-lexer`, `test-parser`, `test-scheduler`, `test-loader`, or another
target for its component. Use `zig build --help` to find targets. Changes to
shared compiler/runtime invariants warrant one complete ReleaseSafe run:
`zig build test -Doptimize=ReleaseSafe --summary all -j2`. Repeat only affected
checks after fixes. Documentation-only changes need link/example validation,
not an unrelated runtime suite. State skipped checks and the reason in your PR.

Add a focused regression test for behavior changes when it protects a meaningful
contract. Executable examples require an
exact `.out` snapshot. Do not disable checks or weaken correct expectations merely
to make a failure pass. Keep maintained source, test, build, and script files at or
below 300 physical lines; split files by responsibility when needed.

The detailed repository layout, focused targets, and documentation ownership are in
[docs/contributing.md](docs/contributing.md).

## Pull requests

State the problem, describe the resulting behavior, link related issues, and list
validation commands. Update user documentation when public behavior changes.
Maintainers may request changes to preserve semantic parity between the
Kannada/Kanglish and English profiles.

For library work, document arguments, results, mutation, limits, errors, and
resource closure. Keep Kannada names and English aliases tied to one semantic
implementation. For concurrency, describe ownership, cancellation, deadlines,
shutdown, and saturation behavior. For performance, include the workload,
hardware, pinned toolchain, optimization mode, correctness checks, and measured
results; a timing claim needs reproducible evidence.

Issue forms cover bugs, features, documentation, performance, concurrency,
libraries, questions, and scoped contributor tasks. Their category labels are
defined in [.github/labels.yml](.github/labels.yml). This file is configuration;
GitHub labels must be applied by a maintainer using a label-sync tool. It does
not change the live repository automatically.

The PR template uses Markdown because GitHub supports YAML forms for issues,
but does not support YAML pull-request forms.

Participation must follow the [Code of Conduct](CODE_OF_CONDUCT.md). Contributions
are licensed under the repository's [MIT License](LICENSE).
