# Planned and incomplete features

This page identifies features that are not ready as dependable application APIs.
Accepted syntax, compiler structures, and library blueprints do not establish
complete runtime behavior.

| Feature | Current boundary | Required work |
| --- | --- | --- |
| Generators | `taru`/`yield` syntax and internal state support | Resumable frames, iteration, close, exception propagation, cleanup |
| Decorators | Syntax and partial lowering | Definition-time evaluation, ordering, callable contracts, method interaction |
| Context managers | `jote`/`with` syntax and partial support | Entry/exit protocol, binding, suppression, deterministic cleanup on every exit |
| Files and streams | No complete public `open` API | Modes, encodings, bounded reads/writes, close, paths, platform errors |
| Transparent asynchronous I/O | Worker pool with blocking waits | Backend suspension, I/O reactor, cancellation, bounded blocking adapters |
| Structured concurrency | Internal task/future/channel foundations | Task scopes, public channel API, cancellation and safe value transfer |
| Complete static/dynamic typing | Partial checking and runtime values | Inference, generic constraints, mutation/alias checks, uniform dynamic boundaries |
| Complete object model | Classes and visibility metadata | Consistent dispatch, privacy, equality, hashing, reflection and protocols |
| Independent modules | Graph loading followed by source concatenation | Per-module profile resolution, namespaces, interfaces and initialization |
| Native compilation | Constant-return x86-64 backend prototype | General lowering, ABI, memory/exception support and cross-backend conformance |
| Kannada-script keywords | Latin-script Kannada and English profiles | Defined Unicode vocabulary, lexer/editor support and profile parity |

There are no runnable examples here because the missing contracts would make them
misleading. Use [current language references](README.md) for supported forms.

The [language design](../language-design.md) records intended semantics; the
[development plan](../development-plan.md) defines delivery gates. Higher performance
than Python is a measurable objective, not a current compatibility or speed guarantee.
