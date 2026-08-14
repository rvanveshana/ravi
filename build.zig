const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const config_module = b.createModule(.{
        .root_source_file = b.path("config/constants.zig"),
        .target = target,
        .optimize = optimize,
    });

    const bytecode_module = b.createModule(.{
        .root_source_file = b.path("src/bytecode/bytecode.zig"),
        .target = target,
        .optimize = optimize,
    });
    const packed_bytecode_module = b.createModule(.{ .root_source_file = b.path("src/bytecode/packed.zig"), .target = target, .optimize = optimize });
    const opcode_spec_module = b.createModule(.{ .root_source_file = b.path("src/bytecode/spec.zig"), .target = target, .optimize = optimize });
    opcode_spec_module.addImport("ravi_packed_bytecode", packed_bytecode_module);
    bytecode_module.addImport("ravi_packed_bytecode", packed_bytecode_module);
    bytecode_module.addImport("ravi_opcode_spec", opcode_spec_module);
    const verifier_module = b.createModule(.{ .root_source_file = b.path("src/bytecode/verifier.zig"), .target = target, .optimize = optimize });
    verifier_module.addImport("ravi_opcode_spec", opcode_spec_module);
    bytecode_module.addImport("ravi_bytecode_verifier", verifier_module);
    const nan_value_module = b.createModule(.{ .root_source_file = b.path("src/vm/value.zig"), .target = target, .optimize = optimize });
    const vm_collections_module = b.createModule(.{ .root_source_file = b.path("src/vm/collections.zig"), .target = target, .optimize = optimize });
    vm_collections_module.addImport("ravi_vm_value", nan_value_module);
    const async_state_module = b.createModule(.{ .root_source_file = b.path("src/concurrency/async_state.zig"), .target = target, .optimize = optimize });
    async_state_module.addImport("ravi_vm_value", nan_value_module);
    const debug_module = b.createModule(.{ .root_source_file = b.path("src/debug/debug.zig"), .target = target, .optimize = optimize });
    debug_module.addImport("ravi_bytecode", bytecode_module);

    const scheduler_module = b.createModule(.{ .root_source_file = b.path("src/concurrency/scheduler.zig"), .target = target, .optimize = optimize });
    const vm_module = b.createModule(.{
        .root_source_file = b.path("src/vm/vm.zig"),
        .target = target,
        .optimize = optimize,
    });
    vm_module.addImport("ravi_scheduler", scheduler_module);
    vm_module.addImport("ravi_async_state", async_state_module);
    vm_module.addImport("ravi_vm_collections", vm_collections_module);
    vm_module.addImport("ravi_vm_value", nan_value_module);
    vm_module.addImport("ravi_bytecode", bytecode_module);
    vm_module.addImport("ravi_debug", debug_module);
    const gc_module = b.createModule(.{ .root_source_file = b.path("src/memory/gc.zig"), .target = target, .optimize = optimize });
    const dispatch_module = b.createModule(.{ .root_source_file = b.path("src/vm/dispatch.zig"), .target = target, .optimize = optimize });
    dispatch_module.addImport("ravi_bytecode", bytecode_module);
    dispatch_module.addImport("ravi_vm_value", nan_value_module);
    vm_module.addImport("ravi_gc", gc_module);
    vm_module.addImport("ravi_dispatch", dispatch_module);

    const lexer_module = b.createModule(.{
        .root_source_file = b.path("src/lexer/lexer.zig"),
        .target = target,
        .optimize = optimize,
    });
    lexer_module.addImport("ravi_config", config_module);

    const ast_module = b.createModule(.{ .root_source_file = b.path("src/ast/ast.zig"), .target = target, .optimize = optimize });
    const ast_helpers_module = b.createModule(.{ .root_source_file = b.path("src/compiler/ast_helpers.zig"), .target = target, .optimize = optimize });
    ast_helpers_module.addImport("ravi_ast", ast_module);
    const types_module = b.createModule(.{ .root_source_file = b.path("src/types/type.zig"), .target = target, .optimize = optimize });

    const compiler_module = b.createModule(.{
        .root_source_file = b.path("src/compiler/compiler.zig"),
        .target = target,
        .optimize = optimize,
    });
    compiler_module.addImport("ravi_ast", ast_module);
    compiler_module.addImport("ravi_bytecode", bytecode_module);
    compiler_module.addImport("ravi_config", config_module);
    compiler_module.addImport("ravi_ast_helpers", ast_helpers_module);

    const backend_module = b.createModule(.{ .root_source_file = b.path("src/backend/backend.zig"), .target = target, .optimize = optimize });
    const optimizer_module = b.createModule(.{ .root_source_file = b.path("src/optimizer/optimizer.zig"), .target = target, .optimize = optimize });
    optimizer_module.addImport("ravi_bytecode", bytecode_module);

    const syntax_module = b.createModule(.{ .root_source_file = b.path("src/syntax/syntax.zig"), .target = target, .optimize = optimize });
    syntax_module.addImport("ravi_lexer", lexer_module);
    const source_module = b.createModule(.{ .root_source_file = b.path("src/source/source.zig"), .target = target, .optimize = optimize });
    const diagnostics_module = b.createModule(.{ .root_source_file = b.path("src/diagnostics/diagnostic.zig"), .target = target, .optimize = optimize });
    diagnostics_module.addImport("ravi_source", source_module);
    const formatter_module = b.createModule(.{ .root_source_file = b.path("src/formatter/formatter.zig"), .target = target, .optimize = optimize });
    const resolver_module = b.createModule(.{ .root_source_file = b.path("src/modules/resolver.zig"), .target = target, .optimize = optimize });
    const module_artifact_module = b.createModule(.{ .root_source_file = b.path("src/modules/artifact.zig"), .target = target, .optimize = optimize });
    const hir_module = b.createModule(.{ .root_source_file = b.path("src/ir/hir.zig"), .target = target, .optimize = optimize });
    const mir_module = b.createModule(.{ .root_source_file = b.path("src/ir/mir.zig"), .target = target, .optimize = optimize });
    mir_module.addImport("ravi_hir", hir_module);
    const mir_verify_module = b.createModule(.{ .root_source_file = b.path("src/ir/mir_verify.zig"), .target = target, .optimize = optimize });
    mir_verify_module.addImport("ravi_mir", mir_module);
    mir_module.addImport("ravi_mir_verify", mir_verify_module);
    const mir_contract_module = b.createModule(.{ .root_source_file = b.path("src/backend/mir_contract.zig"), .target = target, .optimize = optimize });
    mir_contract_module.addImport("ravi_mir", mir_module);
    const native_backend_module = b.createModule(.{ .root_source_file = b.path("src/backend/native.zig"), .target = target, .optimize = optimize });
    native_backend_module.addImport("ravi_mir", mir_module);
    native_backend_module.addImport("ravi_mir_contract", mir_contract_module);
    backend_module.addImport("ravi_mir", mir_module);
    backend_module.addImport("ravi_native_backend", native_backend_module);
    const hir_compatibility_module = b.createModule(.{ .root_source_file = b.path("src/compiler/hir_compatibility.zig"), .target = target, .optimize = optimize });
    hir_compatibility_module.addImport("ravi_ast", ast_module);
    hir_compatibility_module.addImport("ravi_bytecode", bytecode_module);
    hir_compatibility_module.addImport("ravi_compiler", compiler_module);
    const mir_bytecode_module = b.createModule(.{ .root_source_file = b.path("src/ir/mir_bytecode.zig"), .target = target, .optimize = optimize });
    mir_bytecode_module.addImport("ravi_mir", mir_module);
    mir_bytecode_module.addImport("ravi_bytecode", bytecode_module);
    mir_bytecode_module.addImport("ravi_hir", hir_module);
    mir_bytecode_module.addImport("ravi_vm", vm_module);
    const mir_bytecode_emit_module = b.createModule(.{ .root_source_file = b.path("src/ir/mir_bytecode_emit.zig"), .target = target, .optimize = optimize });
    mir_bytecode_emit_module.addImport("ravi_mir", mir_module);
    mir_bytecode_emit_module.addImport("ravi_bytecode", bytecode_module);
    mir_bytecode_module.addImport("ravi_mir_bytecode_emit", mir_bytecode_emit_module);
    const hir_pipeline_module = b.createModule(.{ .root_source_file = b.path("src/compiler/hir_pipeline.zig"), .target = target, .optimize = optimize });
    const hir_pipeline_helpers_module = b.createModule(.{ .root_source_file = b.path("src/compiler/hir_pipeline_helpers.zig"), .target = target, .optimize = optimize });
    hir_pipeline_helpers_module.addImport("ravi_ast", ast_module);
    const hir_pipeline_support_module = b.createModule(.{ .root_source_file = b.path("src/compiler/hir_pipeline_support.zig"), .target = target, .optimize = optimize });
    hir_pipeline_support_module.addImport("ravi_ast", ast_module);
    hir_pipeline_support_module.addImport("ravi_hir_pipeline_helpers", hir_pipeline_helpers_module);
    const hir_lowering_module = b.createModule(.{ .root_source_file = b.path("src/compiler/hir_lowering.zig"), .target = target, .optimize = optimize });
    const hir_exception_lowering_module = b.createModule(.{ .root_source_file = b.path("src/compiler/hir_exception_lowering.zig"), .target = target, .optimize = optimize });
    const hir_local_discovery_module = b.createModule(.{ .root_source_file = b.path("src/compiler/hir_local_discovery.zig"), .target = target, .optimize = optimize });
    const hir_expr_lowering_module = b.createModule(.{ .root_source_file = b.path("src/compiler/hir_expr_lowering.zig"), .target = target, .optimize = optimize });
    const hir_call_lowering_module = b.createModule(.{ .root_source_file = b.path("src/compiler/hir_call_lowering.zig"), .target = target, .optimize = optimize });
    hir_expr_lowering_module.addImport("ravi_ast", ast_module);
    hir_expr_lowering_module.addImport("ravi_hir", hir_module);
    hir_expr_lowering_module.addImport("ravi_hir_call_lowering", hir_call_lowering_module);
    hir_call_lowering_module.addImport("ravi_ast", ast_module);
    hir_call_lowering_module.addImport("ravi_hir", hir_module);
    hir_lowering_module.addImport("ravi_ast", ast_module);
    hir_lowering_module.addImport("ravi_hir", hir_module);
    hir_lowering_module.addImport("ravi_mir", mir_module);
    hir_lowering_module.addImport("ravi_hir_expr_lowering", hir_expr_lowering_module);
    hir_lowering_module.addImport("ravi_hir_exception_lowering", hir_exception_lowering_module);
    hir_lowering_module.addImport("ravi_hir_local_discovery", hir_local_discovery_module);
    hir_exception_lowering_module.addImport("ravi_ast", ast_module);
    hir_exception_lowering_module.addImport("ravi_hir", hir_module);
    hir_exception_lowering_module.addImport("ravi_hir_expr_lowering", hir_expr_lowering_module);
    hir_local_discovery_module.addImport("ravi_ast", ast_module);
    hir_pipeline_support_module.addImport("ravi_hir_lowering", hir_lowering_module);
    hir_pipeline_module.addImport("ravi_compiler", compiler_module);
    hir_pipeline_module.addImport("ravi_ast", ast_module);
    hir_pipeline_module.addImport("ravi_hir", hir_module);
    hir_pipeline_module.addImport("ravi_mir", mir_module);
    hir_pipeline_module.addImport("ravi_mir_bytecode", mir_bytecode_module);
    hir_pipeline_module.addImport("ravi_bytecode", bytecode_module);
    hir_pipeline_module.addImport("ravi_hir_compatibility", hir_compatibility_module);
    hir_pipeline_module.addImport("ravi_vm", vm_module);
    hir_pipeline_module.addImport("ravi_hir_lowering", hir_lowering_module);
    hir_pipeline_module.addImport("ravi_ast_helpers", ast_helpers_module);
    hir_pipeline_module.addImport("ravi_hir_pipeline_helpers", hir_pipeline_helpers_module);
    hir_pipeline_module.addImport("ravi_hir_pipeline_support", hir_pipeline_support_module);
    const parser_module = b.createModule(.{ .root_source_file = b.path("src/parser/parser.zig"), .target = target, .optimize = optimize });
    parser_module.addImport("ravi_lexer", lexer_module);
    parser_module.addImport("ravi_ast", ast_module);
    parser_module.addImport("ravi_config", config_module);
    const lsp_module = b.createModule(.{ .root_source_file = b.path("src/lsp/server.zig"), .target = target, .optimize = optimize });
    lsp_module.addImport("ravi_lexer", lexer_module);
    lsp_module.addImport("ravi_parser", parser_module);
    lsp_module.addImport("ravi_config", config_module);
    lsp_module.addImport("ravi_formatter", formatter_module);
    const lsp_protocol_module = b.createModule(.{ .root_source_file = b.path("src/lsp/protocol.zig"), .target = target, .optimize = optimize });
    const jsonrpc_module = b.createModule(.{ .root_source_file = b.path("src/lsp/jsonrpc.zig"), .target = target, .optimize = optimize });
    jsonrpc_module.addImport("ravi_lsp_protocol", lsp_protocol_module);
    jsonrpc_module.addImport("ravi_lsp_server", lsp_module);
    jsonrpc_module.addImport("ravi_config", config_module);
    const dap_module = b.createModule(.{ .root_source_file = b.path("src/debug/dap.zig"), .target = target, .optimize = optimize });
    dap_module.addImport("ravi_lsp_protocol", lsp_protocol_module);
    dap_module.addImport("ravi_debug", debug_module);
    const loader_module = b.createModule(.{ .root_source_file = b.path("src/modules/loader.zig"), .target = target, .optimize = optimize });
    loader_module.addImport("ravi_lexer", lexer_module);
    loader_module.addImport("ravi_parser", parser_module);
    loader_module.addImport("ravi_ast", ast_module);
    loader_module.addImport("ravi_config", config_module);
    loader_module.addImport("ravi_artifact", module_artifact_module);

    const root_module = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });
    root_module.addImport("ravi_config", config_module);
    root_module.addImport("ravi_ast", ast_module);
    root_module.addImport("ravi_types", types_module);
    root_module.addImport("ravi_bytecode", bytecode_module);
    root_module.addImport("ravi_vm", vm_module);
    root_module.addImport("ravi_gc", gc_module);
    root_module.addImport("ravi_lexer", lexer_module);
    root_module.addImport("ravi_hir_pipeline", hir_pipeline_module);
    root_module.addImport("ravi_backend", backend_module);
    root_module.addImport("ravi_optimizer", optimizer_module);
    root_module.addImport("ravi_debug", debug_module);
    root_module.addImport("ravi_scheduler", scheduler_module);
    root_module.addImport("ravi_async_state", async_state_module);
    root_module.addImport("ravi_syntax", syntax_module);
    root_module.addImport("ravi_source", source_module);
    root_module.addImport("ravi_diagnostics", diagnostics_module);
    root_module.addImport("ravi_formatter", formatter_module);
    root_module.addImport("ravi_loader", loader_module);
    root_module.addImport("ravi_parser", parser_module);
    root_module.addImport("ravi_dap", dap_module);
    root_module.addImport("ravi_lsp_jsonrpc", jsonrpc_module);

    const exe = b.addExecutable(.{
        .name = "ravi",
        .root_module = root_module,
    });
    b.installArtifact(exe);

    const run = b.addRunArtifact(exe);
    const run_step = b.step("run", "Tokenize the sample Ravi program");
    run_step.dependOn(&run.step);

    const semantic_module = b.createModule(.{ .root_source_file = b.path("src/semantic/analyzer.zig"), .target = target, .optimize = optimize });
    semantic_module.addImport("ravi_lexer", lexer_module);
    semantic_module.addImport("ravi_ast", ast_module);
    semantic_module.addImport("ravi_config", config_module);
    semantic_module.addImport("ravi_types", types_module);
    const semantic_symbols_module = b.createModule(.{ .root_source_file = b.path("src/semantic/symbols.zig"), .target = target, .optimize = optimize });
    semantic_symbols_module.addImport("ravi_types", types_module);
    semantic_module.addImport("ravi_semantic_symbols", semantic_symbols_module);
    root_module.addImport("ravi_semantic_symbols", semantic_symbols_module);
    const lexer_tests_module = b.createModule(.{ .root_source_file = b.path("tests/lexer_tests.zig"), .target = target, .optimize = optimize });
    lexer_tests_module.addImport("ravi_lexer", lexer_module);
    lexer_tests_module.addImport("ravi_config", config_module);
    const lexer_tests = b.addTest(.{ .root_module = lexer_tests_module });

    const parser_tests_module = b.createModule(.{ .root_source_file = b.path("tests/parser_tests.zig"), .target = target, .optimize = optimize });
    parser_tests_module.addImport("ravi_lexer", lexer_module);
    parser_tests_module.addImport("ravi_parser", parser_module);
    parser_tests_module.addImport("ravi_syntax", syntax_module);
    const parser_tests = b.addTest(.{ .root_module = parser_tests_module });

    const compiler_tests_module = b.createModule(.{ .root_source_file = b.path("tests/compiler_vm_tests.zig"), .target = target, .optimize = optimize });
    compiler_tests_module.addImport("ravi_lexer", lexer_module);
    compiler_tests_module.addImport("ravi_ast", ast_module);
    compiler_tests_module.addImport("ravi_bytecode", bytecode_module);
    compiler_tests_module.addImport("ravi_vm", vm_module);
    compiler_tests_module.addImport("ravi_compiler", compiler_module);
    compiler_tests_module.addImport("ravi_dispatch", dispatch_module);
    compiler_tests_module.addImport("ravi_parser", parser_module);
    const compiler_tests = b.addTest(.{ .root_module = compiler_tests_module });

    const semantic_tests_module = b.createModule(.{ .root_source_file = b.path("tests/semantic_tests.zig"), .target = target, .optimize = optimize });
    semantic_tests_module.addImport("ravi_lexer", lexer_module);
    semantic_tests_module.addImport("ravi_parser", parser_module);
    semantic_tests_module.addImport("ravi_semantic", semantic_module);
    const semantic_tests = b.addTest(.{ .root_module = semantic_tests_module });
    const semantic_symbols_tests = b.addTest(.{ .root_module = semantic_symbols_module });

    const value_tests_module = b.createModule(.{ .root_source_file = b.path("tests/runtime_value_tests.zig"), .target = target, .optimize = optimize });
    value_tests_module.addImport("ravi_vm_value", nan_value_module);
    value_tests_module.addImport("ravi_vm_collections", vm_collections_module);
    const value_tests_split = b.addTest(.{ .root_module = value_tests_module });

    const collection_tests_module = b.createModule(.{ .root_source_file = b.path("tests/collection_tests.zig"), .target = target, .optimize = optimize });
    collection_tests_module.addImport("ravi_lexer", lexer_module);
    collection_tests_module.addImport("ravi_bytecode", bytecode_module);
    collection_tests_module.addImport("ravi_vm", vm_module);
    collection_tests_module.addImport("ravi_compiler", compiler_module);
    collection_tests_module.addImport("ravi_parser", parser_module);
    const collection_tests = b.addTest(.{ .root_module = collection_tests_module });

    const string_runtime_module = b.createModule(.{ .root_source_file = b.path("src/vm/strings.zig"), .target = target, .optimize = optimize });
    const string_runtime_tests_module = b.createModule(.{ .root_source_file = b.path("tests/string_runtime_tests.zig"), .target = target, .optimize = optimize });
    string_runtime_tests_module.addImport("ravi_vm_strings", string_runtime_module);
    const string_runtime_tests = b.addTest(.{ .root_module = string_runtime_tests_module });
    const backend_tests = b.addTest(.{ .root_module = backend_module });
    const optimizer_tests = b.addTest(.{ .root_module = optimizer_module });
    const debug_tests = b.addTest(.{ .root_module = debug_module });
    const dap_tests = b.addTest(.{ .root_module = dap_module });
    const scheduler_tests = b.addTest(.{ .root_module = scheduler_module });
    const async_state_tests = b.addTest(.{ .root_module = async_state_module });
    const gc_tests = b.addTest(.{ .root_module = gc_module });
    const nan_value_tests = b.addTest(.{ .root_module = nan_value_module });
    const dispatch_tests = b.addTest(.{ .root_module = dispatch_module });
    const bytecode_tests_module = b.createModule(.{ .root_source_file = b.path("tests/bytecode_tests.zig"), .target = target, .optimize = optimize });
    bytecode_tests_module.addImport("ravi_bytecode", bytecode_module);
    const bytecode_tests = b.addTest(.{ .root_module = bytecode_tests_module });
    const opcode_spec_tests = b.addTest(.{ .root_module = opcode_spec_module });
    const source_tests = b.addTest(.{ .root_module = source_module });
    const diagnostics_tests = b.addTest(.{ .root_module = diagnostics_module });
    const formatter_tests = b.addTest(.{ .root_module = formatter_module });
    const resolver_tests = b.addTest(.{ .root_module = resolver_module });
    const loader_tests = b.addTest(.{ .root_module = loader_module });
    const module_artifact_tests = b.addTest(.{ .root_module = module_artifact_module });
    const module_cache_module = b.createModule(.{ .root_source_file = b.path("src/modules/cache.zig"), .target = target, .optimize = optimize });
    const module_cache_tests = b.addTest(.{ .root_module = module_cache_module });
    const hir_tests = b.addTest(.{ .root_module = hir_module });
    const mir_tests = b.addTest(.{ .root_module = mir_module });
    const mir_tests_module = b.createModule(.{ .root_source_file = b.path("src/ir/mir_tests.zig"), .target = target, .optimize = optimize });
    mir_tests_module.addImport("ravi_hir", hir_module);
    mir_tests_module.addImport("ravi_mir", mir_module);
    const mir_tests_split = b.addTest(.{ .root_module = mir_tests_module });
    const mir_bytecode_tests = b.addTest(.{ .root_module = mir_bytecode_module });
    const hir_pipeline_tests = b.addTest(.{ .root_module = hir_pipeline_module });
    const lsp_tests = b.addTest(.{ .root_module = lsp_module });
    const lsp_protocol_tests = b.addTest(.{ .root_module = lsp_protocol_module });
    const jsonrpc_tests = b.addTest(.{ .root_module = jsonrpc_module });
    const phase0_tests_module = b.createModule(.{ .root_source_file = b.path("tests/phase0_tests.zig"), .target = target, .optimize = optimize });
    phase0_tests_module.addImport("ravi_bytecode", bytecode_module);
    phase0_tests_module.addImport("ravi_lexer", lexer_module);
    phase0_tests_module.addImport("ravi_parser", parser_module);
    const phase0_tests = b.addTest(.{ .root_module = phase0_tests_module });
    const phase1_tests_module = b.createModule(.{ .root_source_file = b.path("tests/phase1_tests.zig"), .target = target, .optimize = optimize });
    phase1_tests_module.addImport("ravi_bytecode", bytecode_module);
    phase1_tests_module.addImport("ravi_compiler", compiler_module);
    phase1_tests_module.addImport("ravi_diagnostics", diagnostics_module);
    phase1_tests_module.addImport("ravi_lexer", lexer_module);
    phase1_tests_module.addImport("ravi_parser", parser_module);
    phase1_tests_module.addImport("ravi_semantic", semantic_module);
    phase1_tests_module.addImport("ravi_vm", vm_module);
    phase1_tests_module.addImport("ravi_config", config_module);
    phase1_tests_module.addImport("ravi_dap", dap_module);
    phase1_tests_module.addImport("ravi_lsp_protocol", lsp_protocol_module);
    phase1_tests_module.addImport("ravi_debug", debug_module);
    const phase1_tests = b.addTest(.{ .root_module = phase1_tests_module });

    const test_step = b.step("test", "Run runtime unit tests");
    test_step.dependOn(&lexer_tests.step);
    test_step.dependOn(&parser_tests.step);
    test_step.dependOn(&compiler_tests.step);
    test_step.dependOn(&semantic_tests.step);
    test_step.dependOn(&semantic_symbols_tests.step);
    test_step.dependOn(&value_tests_split.step);
    test_step.dependOn(&collection_tests.step);
    test_step.dependOn(&string_runtime_tests.step);
    test_step.dependOn(&backend_tests.step);
    test_step.dependOn(&optimizer_tests.step);
    test_step.dependOn(&debug_tests.step);
    test_step.dependOn(&dap_tests.step);
    test_step.dependOn(&scheduler_tests.step);
    test_step.dependOn(&async_state_tests.step);
    test_step.dependOn(&gc_tests.step);
    test_step.dependOn(&nan_value_tests.step);
    test_step.dependOn(&dispatch_tests.step);
    test_step.dependOn(&bytecode_tests.step);
    test_step.dependOn(&opcode_spec_tests.step);
    test_step.dependOn(&source_tests.step);
    test_step.dependOn(&diagnostics_tests.step);
    test_step.dependOn(&formatter_tests.step);
    test_step.dependOn(&resolver_tests.step);
    test_step.dependOn(&loader_tests.step);
    test_step.dependOn(&module_artifact_tests.step);
    test_step.dependOn(&module_cache_tests.step);
    test_step.dependOn(&hir_tests.step);
    test_step.dependOn(&mir_tests.step);
    test_step.dependOn(&mir_tests_split.step);
    test_step.dependOn(&mir_bytecode_tests.step);
    test_step.dependOn(&hir_pipeline_tests.step);
    test_step.dependOn(&lsp_tests.step);
    test_step.dependOn(&lsp_protocol_tests.step);
    test_step.dependOn(&jsonrpc_tests.step);
    test_step.dependOn(&phase0_tests.step);
    test_step.dependOn(&phase1_tests.step);
}
