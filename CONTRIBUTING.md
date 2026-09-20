# Contributing to Ravi Kannada

Thank you for helping build Ravi Kannada. Contributions are welcome from learners,
language users, documentarians, designers, and compiler developers.

## Before you start

Search existing issues before opening a new one. For a bug, include a minimal `.rk`
program, source profile, actual and expected behavior, operating system, and Zig
version. Discuss new syntax, semantics, public APIs, and broad architectural changes
in an issue before investing in an implementation.

Small fixes can go directly to a pull request. Keep each pull request focused and
explain the observable behavior it changes.

## Develop and validate

Use Zig `0.17.0-dev.1415+64dfaa568`. From the repository root, run:

```powershell
zig build
zig build test --summary all -j2
./tools/test_examples.ps1
zig fmt --check build.zig build config src tests
./tools/check_src_sizes.ps1
git diff --check
```

Add a focused regression test for behavior changes. Executable examples require an
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

Participation must follow the [Code of Conduct](CODE_OF_CONDUCT.md). Contributions
are licensed under the repository's [MIT License](LICENSE).
