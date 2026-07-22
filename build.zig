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

    const vm_module = b.createModule(.{
        .root_source_file = b.path("src/vm/vm.zig"),
        .target = target,
        .optimize = optimize,
    });
    vm_module.addAnonymousImport("ravi_vm_collections", .{ .root_source_file = b.path("src/vm/collections.zig"), .target = target, .optimize = optimize });
    vm_module.addImport("ravi_bytecode", bytecode_module);

    const lexer_module = b.createModule(.{
        .root_source_file = b.path("src/lexer/lexer.zig"),
        .target = target,
        .optimize = optimize,
    });
    lexer_module.addImport("ravi_config", config_module);

    const ast_module = b.createModule(.{ .root_source_file = b.path("src/ast/ast.zig"), .target = target, .optimize = optimize });
    const types_module = b.createModule(.{ .root_source_file = b.path("src/types/type.zig"), .target = target, .optimize = optimize });

    const compiler_module = b.createModule(.{
        .root_source_file = b.path("src/compiler/compiler.zig"),
        .target = target,
        .optimize = optimize,
    });
    const compiler_expressions_module = b.createModule(.{ .root_source_file = b.path("src/compiler/expressions.zig"), .target = target, .optimize = optimize });
    compiler_module.addImport("ravi_lexer", lexer_module);
    compiler_module.addImport("ravi_bytecode", bytecode_module);
    compiler_module.addImport("ravi_config", config_module);
    compiler_module.addImport("ravi_compiler_expressions", compiler_expressions_module);

    const value_module = b.createModule(.{
        .root_source_file = b.path("src/runtime/value.zig"),
        .target = target,
        .optimize = optimize,
    });

    const backend_module = b.createModule(.{ .root_source_file = b.path("src/backend/backend.zig"), .target = target, .optimize = optimize });
    const optimizer_module = b.createModule(.{ .root_source_file = b.path("src/optimizer/optimizer.zig"), .target = target, .optimize = optimize });
    optimizer_module.addImport("ravi_bytecode", bytecode_module);

    const debug_module = b.createModule(.{ .root_source_file = b.path("src/debug/debug.zig"), .target = target, .optimize = optimize });
    debug_module.addImport("ravi_bytecode", bytecode_module);

    const scheduler_module = b.createModule(.{ .root_source_file = b.path("src/concurrency/scheduler.zig"), .target = target, .optimize = optimize });
    const syntax_module = b.createModule(.{ .root_source_file = b.path("src/syntax/syntax.zig"), .target = target, .optimize = optimize });
    syntax_module.addImport("ravi_lexer", lexer_module);

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
    root_module.addImport("ravi_lexer", lexer_module);
    root_module.addImport("ravi_compiler", compiler_module);
    root_module.addImport("ravi_value", value_module);
    root_module.addImport("ravi_backend", backend_module);
    root_module.addImport("ravi_optimizer", optimizer_module);
    root_module.addImport("ravi_debug", debug_module);
    root_module.addImport("ravi_scheduler", scheduler_module);
    root_module.addImport("ravi_syntax", syntax_module);

    const exe = b.addExecutable(.{
        .name = "ravi",
        .root_module = root_module,
    });
    b.installArtifact(exe);

    const run = b.addRunArtifact(exe);
    const run_step = b.step("run", "Tokenize the sample Ravi program");
    run_step.dependOn(&run.step);

    const value_tests = b.addTest(.{ .root_module = value_module });
    const parser_module = b.createModule(.{ .root_source_file = b.path("src/parser/parser.zig"), .target = target, .optimize = optimize });
    parser_module.addImport("ravi_lexer", lexer_module);
    parser_module.addImport("ravi_ast", ast_module);
    parser_module.addImport("ravi_config", config_module);

    const semantic_module = b.createModule(.{ .root_source_file = b.path("src/semantic/analyzer.zig"), .target = target, .optimize = optimize });
    semantic_module.addImport("ravi_lexer", lexer_module);
    semantic_module.addImport("ravi_ast", ast_module);
    semantic_module.addImport("ravi_config", config_module);
    semantic_module.addImport("ravi_types", types_module);

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
    compiler_tests_module.addImport("ravi_bytecode", bytecode_module);
    compiler_tests_module.addImport("ravi_vm", vm_module);
    compiler_tests_module.addImport("ravi_compiler", compiler_module);
    const compiler_tests = b.addTest(.{ .root_module = compiler_tests_module });

    const semantic_tests_module = b.createModule(.{ .root_source_file = b.path("tests/semantic_tests.zig"), .target = target, .optimize = optimize });
    semantic_tests_module.addImport("ravi_lexer", lexer_module);
    semantic_tests_module.addImport("ravi_parser", parser_module);
    semantic_tests_module.addImport("ravi_semantic", semantic_module);
    const semantic_tests = b.addTest(.{ .root_module = semantic_tests_module });

    const value_tests_module = b.createModule(.{ .root_source_file = b.path("tests/runtime_value_tests.zig"), .target = target, .optimize = optimize });
    value_tests_module.addImport("ravi_value", value_module);
    const value_tests_split = b.addTest(.{ .root_module = value_tests_module });

    const collection_tests_module = b.createModule(.{ .root_source_file = b.path("tests/collection_tests.zig"), .target = target, .optimize = optimize });
    collection_tests_module.addImport("ravi_lexer", lexer_module);
    collection_tests_module.addImport("ravi_vm", vm_module);
    collection_tests_module.addImport("ravi_compiler", compiler_module);
    const collection_tests = b.addTest(.{ .root_module = collection_tests_module });

    const string_runtime_module = b.createModule(.{ .root_source_file = b.path("src/vm/strings.zig"), .target = target, .optimize = optimize });
    const string_runtime_tests_module = b.createModule(.{ .root_source_file = b.path("tests/string_runtime_tests.zig"), .target = target, .optimize = optimize });
    string_runtime_tests_module.addImport("ravi_vm_strings", string_runtime_module);
    const string_runtime_tests = b.addTest(.{ .root_module = string_runtime_tests_module });

    const test_step = b.step("test", "Run runtime unit tests");
    test_step.dependOn(&value_tests.step);
    test_step.dependOn(&lexer_tests.step);
    test_step.dependOn(&parser_tests.step);
    test_step.dependOn(&compiler_tests.step);
    test_step.dependOn(&semantic_tests.step);
    test_step.dependOn(&value_tests_split.step);
    test_step.dependOn(&collection_tests.step);
    test_step.dependOn(&string_runtime_tests.step);
}
