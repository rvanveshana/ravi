# Ravi Kannada documentation

Ravi Kannada is an experimental, Python-inspired programming language implemented
in Zig. The public language name is **Ravi Kannada**; the command is `ravi` and
source files use `.rk`.

## For language users

Start with the [user handbook](user_docs/README.md). It covers installation,
source profiles, language fundamentals, runtime behavior, and available libraries.
Examples use the Kannada/Kanglish profile unless an English header is shown.

## For contributors

| Document | Purpose |
| --- | --- |
| [Implementation status](implementation-status.md) | Current capabilities, limitations, and dated validation evidence |
| [Architecture](architecture.md) | Actual compiler/runtime structure and its integration gaps |
| [Robustness review](robustness-review.md) | 2026-10-30 fixes and remaining async, threading, library, and performance gates |
| [Task/runtime contracts](task-runtime.md) | Implemented task ownership, copy transfer, channels, library limits, and profiling |
| [Language design](language-design.md) | Accepted direction and contracts still to implement |
| [Development plan](development-plan.md) | Ordered milestones and acceptance criteria |
| [Runtime ABI](runtime-abi.md) | Internal value representation and ownership constraints |
| [Contributing](contributing.md) | Repository layout, validation, and maintenance rules |
| [Feature matrix](feature-matrix.md) | Generated, maintainer-entered development-stage flags |

## Documentation conventions

**Implemented** means an implementation exists; it does not imply complete
conformance. **Experimental** means behavior or integration is incomplete.
**Planned** means the feature must not be relied on in application code.
The implementation status page owns test results; other pages link to it.

User documentation describes the current language. Proposed contracts belong in
the language design and development plan. Superseded reviews and duplicate guides
have been consolidated into these documents rather than retained as competing
references. Existing tracked versions remain available in Git history.
