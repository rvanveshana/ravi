# Proposed Directory Structure

This tree is the intended repository shape. The initial implementation now
contains `build.zig`, `config/constants.zig`, `src/main.zig`,
`src/lexer/lexer.zig`, `src/parser/parser.zig`, and `src/memory/gc.zig`.
Remaining directories are introduced phase by phase behind these contracts.

```text
ravi/
|-- build.zig
|-- build.zig.zon
|-- README.md
|-- LICENSE
|-- docs/
|   |-- requirements.md
|   |-- architecture.md
|   |-- directory-structure.md
|   |-- design-barriers.md
|   |-- language/
|   |   |-- lexical-grammar.md
|   |   |-- syntax-grammar.md
|   |   |-- strings.md
|   |   |-- docstrings.md
|   |   |-- decorators.md
|   |   |-- context-managers.md
|   |   |-- anonymous-functions.md
|   |   |-- type-system.md
|   |   |-- modules.md
|   |   |-- access-control.md
|   |   |-- concurrency.md
|   |   `-- errors.md
|   |-- internals/
|   |   |-- bytecode-format.md
|   |   |-- runtime-abi.md
|   |   |-- debug-format.md
|   |   `-- gc-contract.md
|   `-- decisions/
|       `-- README.md
|-- examples/
|   `-- calculate.rk
|-- src/
|   |-- main.zig
|   |-- lib.zig
|   |-- config/
|   |   |-- constants.zig
|   |   |-- config.zig
|   |   `-- validation.zig
|   |-- common/
|   |   |-- ids.zig
|   |   |-- span.zig
|   |   |-- interner.zig
|   |   `-- collections.zig
|   |-- diagnostics/
|   |   |-- diagnostic.zig
|   |   |-- sink.zig
|   |   `-- renderer.zig
|   |-- source/
|   |   |-- source.zig
|   |   |-- manager.zig
|   |   `-- line_index.zig
|   |-- modules/
|   |   |-- module.zig
|   |   |-- resolver.zig
|   |   `-- graph.zig
|   |-- lexer/
|   |   |-- token.zig
|   |   |-- lexer.zig
|   |   |-- string_decoder.zig
|   |   `-- indentation.zig
|   |-- syntax/
|   |   |-- kind.zig
|   |   |-- tree.zig
|   |   `-- builder.zig
|   |-- parser/
|   |   |-- parser.zig
|   |   |-- statements.zig
|   |   |-- expressions.zig
|   |   `-- recovery.zig
|   |-- ast/
|   |   |-- ast.zig
|   |   |-- nodes.zig
|   |   `-- lower.zig
|   |-- semantic/
|   |   |-- symbols.zig
|   |   |-- scopes.zig
|   |   |-- resolver.zig
|   |   |-- visibility.zig
|   |   |-- control_flow.zig
|   |   |-- closures.zig
|   |   |-- concurrency.zig
|   |   `-- analyzer.zig
|   |-- types/
|   |   |-- type.zig
|   |   |-- interner.zig
|   |   |-- constraints.zig
|   |   |-- solver.zig
|   |   `-- boundaries.zig
|   |-- ir/
|   |   |-- hir/
|   |   |   |-- hir.zig
|   |   |   |-- builder.zig
|   |   |   `-- verify.zig
|   |   `-- mir/
|   |       |-- mir.zig
|   |       |-- builder.zig
|   |       `-- verify.zig
|   |-- optimize/
|   |   |-- pass.zig
|   |   |-- manager.zig
|   |   |-- analyses/
|   |   `-- transforms/
|   |-- bytecode/
|   |   |-- opcode.zig
|   |   |-- format.zig
|   |   |-- emitter.zig
|   |   |-- reader.zig
|   |   `-- verifier.zig
|   |-- backend/
|   |   |-- backend.zig
|   |   |-- bytecode_backend.zig
|   |   `-- native/
|   |       |-- native.zig
|   |       |-- abi.zig
|   |       |-- debug_info.zig
|   |       |-- linker.zig
|   |       `-- object_writer.zig
|   |-- vm/
|   |   |-- vm.zig
|   |   |-- frame.zig
|   |   |-- dispatch.zig
|   |   |-- debug_adapter.zig
|   |   `-- inline_cache.zig
|   |-- concurrency/
|   |   |-- scheduler.zig
|   |   |-- task.zig
|   |   |-- task_group.zig
|   |   |-- channel.zig
|   |   |-- sync.zig
|   |   |-- shared_memory.zig
|   |   |-- process_executor.zig
|   |   `-- reactor/
|   |       |-- reactor.zig
|   |       |-- iocp.zig
|   |       |-- linux.zig
|   |       `-- kqueue.zig
|   |-- runtime/
|   |   |-- runtime.zig
|   |   |-- value.zig
|   |   |-- object.zig
|   |   |-- exceptions.zig
|   |   |-- handles.zig
|   |   |-- async_state.zig
|   |   |-- string.zig
|   |   |-- string_builder.zig
|   |   |-- context.zig
|   |   |-- closure.zig
|   |   `-- builtins/
|   |-- memory/
|   |   |-- gc.zig
|   |   |-- heap.zig
|   |   |-- page_allocator.zig
|   |   |-- roots.zig
|   |   |-- tracer.zig
|   |   |-- thread_cache.zig
|   |   `-- barriers.zig
|   |-- debug/
|   |   |-- model.zig
|   |   |-- service.zig
|   |   |-- dap.zig
|   |   `-- native_adapter.zig
|   |-- artifacts/
|   |   |-- artifact.zig
|   |   `-- cache.zig
|   |-- documentation/
|   |   |-- docstring.zig
|   |   |-- validator.zig
|   |   `-- emitter.zig
|   |-- driver/
|   |   |-- session.zig
|   |   |-- pipeline.zig
|   |   |-- profile.zig
|   |   |-- resource_budget.zig
|   |   `-- scheduler.zig
|   `-- cli/
|       |-- cli.zig
|       `-- options.zig
|-- stdlib/
|   |-- src/
|   `-- tests/
|-- tests/
|   |-- unit/
|   |-- golden/
|   |-- integration/
|   |-- differential/
|   |-- concurrency/
|   |-- debugger/
|   |-- binary_size/
|   |-- fuzz/
|   `-- benchmarks/
|-- tools/
|   |-- formatter/
|   |-- language_server/
|   |-- debugger/
|   |-- documentation/
|   |-- bytecode_dump/
|   `-- benchmark_runner/
`-- ci/
    |-- test.ps1
    `-- test.sh
```

## Dependency Boundaries

- `config`, `common`, and `diagnostics` are foundational and import no compiler
  phases.
- `lexer` depends on source, config, common, and diagnostics only.
- `parser` consumes tokens and builds syntax; it does not import semantic code.
- `ast` lowers syntax into semantic-friendly nodes.
- `semantic` and `types` cooperate through narrow public APIs and never import
  a backend.
- `ir` is the boundary between language analysis and execution strategies.
- `backend` implementations depend on verified IR contracts.
- `vm` consumes verified bytecode and runtime interfaces, not frontend modules.
- `concurrency` owns schedulers, synchronization, reactors, process execution,
  and explicit shared memory without depending on frontend packages.
- `memory` owns managed allocation mechanics and has no compiler dependency.
- `debug` consumes common IR debug records through adapters and does not own
  semantic analysis.
- `driver` composes the pipeline; individual phases do not compose themselves.
- `cli` is an adapter over the driver and owns presentation and process exit
  behavior.

## Test Placement

Small white-box tests live beside the module they exercise. The top-level test
directories contain cross-package fixtures, golden snapshots, fuzz targets,
differential execution cases, and performance baselines. This preserves fast
local feedback without coupling package internals through a shared test helper.
