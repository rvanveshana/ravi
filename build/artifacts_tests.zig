const std = @import("std");
const core = @import("modules_core.zig");
const runtime = @import("modules_runtime.zig");
const compiler = @import("modules_compiler.zig");
const language = @import("modules_language.zig");
const test_step = @import("test_step.zig");

pub fn add(b: *std.Build, target: std.Build.ResolvedTarget, optimize: std.builtin.OptimizeMode, core_modules: core.CoreModules, runtime_modules: runtime.RuntimeModules, compiler_modules: compiler.CompilerModules, language_modules: language.LanguageModules) test_step.TestArtifacts {
    const lexer_tests_module = b.createModule(.{ .root_source_file = b.path("tests/lexer_tests.zig"), .target = target, .optimize = optimize });
    lexer_tests_module.addImport("ravi_lexer", core_modules.lexer);
    lexer_tests_module.addImport("ravi_config", core_modules.config);
    const lexer = b.addTest(.{ .root_module = lexer_tests_module });

    const parser_tests_module = b.createModule(.{ .root_source_file = b.path("tests/parser_tests.zig"), .target = target, .optimize = optimize });
    parser_tests_module.addImport("ravi_lexer", core_modules.lexer);
    parser_tests_module.addImport("ravi_parser", language_modules.parser);
    parser_tests_module.addImport("ravi_syntax", language_modules.syntax);
    const parser = b.addTest(.{ .root_module = parser_tests_module });

    const helper_module = b.createModule(.{ .root_source_file = b.path("tests/compiler_vm_test_helpers.zig"), .target = target, .optimize = optimize });
    helper_module.addImport("ravi_bytecode", core_modules.bytecode);
    helper_module.addImport("ravi_compiler", compiler_modules.compiler);
    helper_module.addImport("ravi_lexer", core_modules.lexer);
    helper_module.addImport("ravi_parser", language_modules.parser);
    helper_module.addImport("ravi_vm", runtime_modules.vm);
    const compiler_vm_roots = [_][]const u8{ "compiler_vm_core_tests.zig", "compiler_vm_language_tests.zig", "compiler_vm_control_flow_tests.zig", "compiler_vm_values_tests.zig", "compiler_vm_collections_tests.zig", "compiler_vm_runtime_tests.zig" };
    const compiler_vm = b.allocator.alloc(*std.Build.Step, compiler_vm_roots.len) catch @panic("out of memory allocating compiler VM test steps");
    for (compiler_vm_roots, 0..) |root, index| {
        const module = b.createModule(.{ .root_source_file = b.path(b.fmt("tests/{s}", .{root})), .target = target, .optimize = optimize });
        module.addImport("ravi_ast", core_modules.ast);
        module.addImport("ravi_bytecode", core_modules.bytecode);
        module.addImport("ravi_compiler", compiler_modules.compiler);
        module.addImport("ravi_dispatch", core_modules.dispatch);
        module.addImport("ravi_lexer", core_modules.lexer);
        module.addImport("ravi_parser", language_modules.parser);
        module.addImport("ravi_vm", runtime_modules.vm);
        module.addImport("compiler_vm_test_helpers", helper_module);
        compiler_vm[index] = &b.addRunArtifact(b.addTest(.{ .root_module = module })).step;
    }

    const semantic_tests_module = b.createModule(.{ .root_source_file = b.path("tests/semantic_tests.zig"), .target = target, .optimize = optimize });
    semantic_tests_module.addImport("ravi_lexer", core_modules.lexer);
    semantic_tests_module.addImport("ravi_parser", language_modules.parser);
    semantic_tests_module.addImport("ravi_semantic", compiler_modules.semantic);
    const semantic = b.addTest(.{ .root_module = semantic_tests_module });
    const semantic_symbols = b.addTest(.{ .root_module = compiler_modules.semantic_symbols });

    const value_module = b.createModule(.{ .root_source_file = b.path("tests/runtime_value_tests.zig"), .target = target, .optimize = optimize });
    value_module.addImport("ravi_vm_value", core_modules.vm_value);
    value_module.addImport("ravi_vm_collections", core_modules.vm_collections);
    const value = b.addTest(.{ .root_module = value_module });
    const collection_module = b.createModule(.{ .root_source_file = b.path("tests/collection_tests.zig"), .target = target, .optimize = optimize });
    collection_module.addImport("ravi_lexer", core_modules.lexer);
    collection_module.addImport("ravi_bytecode", core_modules.bytecode);
    collection_module.addImport("ravi_vm", runtime_modules.vm);
    collection_module.addImport("ravi_compiler", compiler_modules.compiler);
    collection_module.addImport("ravi_parser", language_modules.parser);
    const collection = b.addTest(.{ .root_module = collection_module });
    const string_module = b.createModule(.{ .root_source_file = b.path("tests/string_runtime_tests.zig"), .target = target, .optimize = optimize });
    string_module.addImport("ravi_vm_strings", runtime_modules.strings);
    const string_runtime = b.addTest(.{ .root_module = string_module });

    const bytecode_module = b.createModule(.{ .root_source_file = b.path("tests/bytecode_tests.zig"), .target = target, .optimize = optimize });
    bytecode_module.addImport("ravi_bytecode", core_modules.bytecode);
    const phase0_module = b.createModule(.{ .root_source_file = b.path("tests/phase0_tests.zig"), .target = target, .optimize = optimize });
    phase0_module.addImport("ravi_bytecode", core_modules.bytecode);
    phase0_module.addImport("ravi_lexer", core_modules.lexer);
    phase0_module.addImport("ravi_parser", language_modules.parser);
    const phase1_module = b.createModule(.{ .root_source_file = b.path("tests/phase1_tests.zig"), .target = target, .optimize = optimize });
    phase1_module.addImport("ravi_bytecode", core_modules.bytecode);
    phase1_module.addImport("ravi_compiler", compiler_modules.compiler);
    phase1_module.addImport("ravi_diagnostics", core_modules.diagnostics);
    phase1_module.addImport("ravi_lexer", core_modules.lexer);
    phase1_module.addImport("ravi_parser", language_modules.parser);
    phase1_module.addImport("ravi_semantic", compiler_modules.semantic);
    phase1_module.addImport("ravi_vm", runtime_modules.vm);
    phase1_module.addImport("ravi_config", core_modules.config);
    phase1_module.addImport("ravi_dap", language_modules.dap);
    phase1_module.addImport("ravi_lsp_protocol", language_modules.lsp_protocol);
    phase1_module.addImport("ravi_debug", core_modules.debug);

    const mir_tests_module = b.createModule(.{ .root_source_file = b.path("src/ir/mir_tests.zig"), .target = target, .optimize = optimize });
    mir_tests_module.addImport("ravi_hir", compiler_modules.hir);
    mir_tests_module.addImport("ravi_mir", compiler_modules.mir);

    return .{
        .lexer = &b.addRunArtifact(lexer).step,
        .parser = &b.addRunArtifact(parser).step,
        .compiler_vm = compiler_vm,
        .semantic = &b.addRunArtifact(semantic).step,
        .semantic_symbols = &b.addRunArtifact(semantic_symbols).step,
        .value = &b.addRunArtifact(value).step,
        .vm = &b.addRunArtifact(b.addTest(.{ .root_module = runtime_modules.vm })).step,
        .collection = &b.addRunArtifact(collection).step,
        .string_runtime = &b.addRunArtifact(string_runtime).step,
        .backend = &b.addRunArtifact(b.addTest(.{ .root_module = compiler_modules.backend })).step,
        .optimizer = &b.addRunArtifact(b.addTest(.{ .root_module = compiler_modules.optimizer })).step,
        .debug = &b.addRunArtifact(b.addTest(.{ .root_module = core_modules.debug })).step,
        .dap = &b.addRunArtifact(b.addTest(.{ .root_module = language_modules.dap })).step,
        .scheduler = &b.addRunArtifact(b.addTest(.{ .root_module = core_modules.scheduler })).step,
        .async_state = &b.addRunArtifact(b.addTest(.{ .root_module = core_modules.async_state })).step,
        .gc = &b.addRunArtifact(b.addTest(.{ .root_module = core_modules.gc })).step,
        .nan_value = &b.addRunArtifact(b.addTest(.{ .root_module = core_modules.vm_value })).step,
        .dispatch = &b.addRunArtifact(b.addTest(.{ .root_module = core_modules.dispatch })).step,
        .bytecode = &b.addRunArtifact(b.addTest(.{ .root_module = bytecode_module })).step,
        .opcode_spec = &b.addRunArtifact(b.addTest(.{ .root_module = core_modules.opcode_spec })).step,
        .source = &b.addRunArtifact(b.addTest(.{ .root_module = core_modules.source })).step,
        .diagnostics = &b.addRunArtifact(b.addTest(.{ .root_module = core_modules.diagnostics })).step,
        .formatter = &b.addRunArtifact(b.addTest(.{ .root_module = language_modules.formatter })).step,
        .resolver = &b.addRunArtifact(b.addTest(.{ .root_module = language_modules.resolver })).step,
        .loader = &b.addRunArtifact(b.addTest(.{ .root_module = language_modules.loader })).step,
        .module_artifact = &b.addRunArtifact(b.addTest(.{ .root_module = language_modules.artifact })).step,
        .module_cache = &b.addRunArtifact(b.addTest(.{ .root_module = language_modules.cache })).step,
        .hir = &b.addRunArtifact(b.addTest(.{ .root_module = compiler_modules.hir })).step,
        .mir = &b.addRunArtifact(b.addTest(.{ .root_module = compiler_modules.mir })).step,
        .mir_split = &b.addRunArtifact(b.addTest(.{ .root_module = mir_tests_module })).step,
        .mir_bytecode = &b.addRunArtifact(b.addTest(.{ .root_module = compiler_modules.mir_bytecode })).step,
        .hir_pipeline = &b.addRunArtifact(b.addTest(.{ .root_module = compiler_modules.hir_pipeline })).step,
        .lsp = &b.addRunArtifact(b.addTest(.{ .root_module = language_modules.lsp })).step,
        .lsp_protocol = &b.addRunArtifact(b.addTest(.{ .root_module = language_modules.lsp_protocol })).step,
        .jsonrpc = &b.addRunArtifact(b.addTest(.{ .root_module = language_modules.jsonrpc })).step,
        .phase0 = &b.addRunArtifact(b.addTest(.{ .root_module = phase0_module })).step,
        .phase1 = &b.addRunArtifact(b.addTest(.{ .root_module = phase1_module })).step,
    };
}
