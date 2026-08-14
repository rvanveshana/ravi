const std = @import("std");
const core = @import("modules_core.zig");
const runtime = @import("modules_runtime.zig");

pub const CompilerModules = struct {
    compiler: *std.Build.Module,
    backend: *std.Build.Module,
    optimizer: *std.Build.Module,
    semantic: *std.Build.Module,
    semantic_symbols: *std.Build.Module,
    hir: *std.Build.Module,
    mir: *std.Build.Module,
    mir_verify: *std.Build.Module,
    mir_contract: *std.Build.Module,
    native_backend: *std.Build.Module,
    hir_compatibility: *std.Build.Module,
    mir_bytecode: *std.Build.Module,
    mir_bytecode_emit: *std.Build.Module,
    hir_pipeline: *std.Build.Module,
    hir_pipeline_helpers: *std.Build.Module,
    hir_pipeline_support: *std.Build.Module,
    hir_lowering: *std.Build.Module,
    hir_exception_lowering: *std.Build.Module,
    hir_local_discovery: *std.Build.Module,
    hir_expr_lowering: *std.Build.Module,
    hir_call_lowering: *std.Build.Module,
};

pub fn add(b: *std.Build, target: std.Build.ResolvedTarget, optimize: std.builtin.OptimizeMode, modules: core.CoreModules, runtime_modules: runtime.RuntimeModules) CompilerModules {
    const compiler = b.createModule(.{ .root_source_file = b.path("src/compiler/compiler.zig"), .target = target, .optimize = optimize });
    compiler.addImport("ravi_ast", modules.ast);
    compiler.addImport("ravi_bytecode", modules.bytecode);
    compiler.addImport("ravi_config", modules.config);
    compiler.addImport("ravi_ast_helpers", modules.ast_helpers);
    const backend = b.createModule(.{ .root_source_file = b.path("src/backend/backend.zig"), .target = target, .optimize = optimize });
    const optimizer = b.createModule(.{ .root_source_file = b.path("src/optimizer/optimizer.zig"), .target = target, .optimize = optimize });
    optimizer.addImport("ravi_bytecode", modules.bytecode);
    const hir = b.createModule(.{ .root_source_file = b.path("src/ir/hir.zig"), .target = target, .optimize = optimize });
    const mir = b.createModule(.{ .root_source_file = b.path("src/ir/mir.zig"), .target = target, .optimize = optimize });
    mir.addImport("ravi_hir", hir);
    const mir_verify = b.createModule(.{ .root_source_file = b.path("src/ir/mir_verify.zig"), .target = target, .optimize = optimize });
    mir_verify.addImport("ravi_mir", mir);
    mir.addImport("ravi_mir_verify", mir_verify);
    const mir_contract = b.createModule(.{ .root_source_file = b.path("src/backend/mir_contract.zig"), .target = target, .optimize = optimize });
    mir_contract.addImport("ravi_mir", mir);
    const native_backend = b.createModule(.{ .root_source_file = b.path("src/backend/native.zig"), .target = target, .optimize = optimize });
    native_backend.addImport("ravi_mir", mir);
    native_backend.addImport("ravi_mir_contract", mir_contract);
    backend.addImport("ravi_mir", mir);
    backend.addImport("ravi_native_backend", native_backend);
    const hir_compatibility = b.createModule(.{ .root_source_file = b.path("src/compiler/hir_compatibility.zig"), .target = target, .optimize = optimize });
    hir_compatibility.addImport("ravi_ast", modules.ast);
    hir_compatibility.addImport("ravi_bytecode", modules.bytecode);
    hir_compatibility.addImport("ravi_compiler", compiler);
    const mir_bytecode = b.createModule(.{ .root_source_file = b.path("src/ir/mir_bytecode.zig"), .target = target, .optimize = optimize });
    mir_bytecode.addImport("ravi_mir", mir);
    mir_bytecode.addImport("ravi_bytecode", modules.bytecode);
    mir_bytecode.addImport("ravi_hir", hir);
    mir_bytecode.addImport("ravi_vm", runtime_modules.vm);
    const mir_bytecode_emit = b.createModule(.{ .root_source_file = b.path("src/ir/mir_bytecode_emit.zig"), .target = target, .optimize = optimize });
    mir_bytecode_emit.addImport("ravi_mir", mir);
    mir_bytecode_emit.addImport("ravi_bytecode", modules.bytecode);
    mir_bytecode.addImport("ravi_mir_bytecode_emit", mir_bytecode_emit);
    const hir_pipeline = b.createModule(.{ .root_source_file = b.path("src/compiler/hir_pipeline.zig"), .target = target, .optimize = optimize });
    const hir_pipeline_helpers = b.createModule(.{ .root_source_file = b.path("src/compiler/hir_pipeline_helpers.zig"), .target = target, .optimize = optimize });
    hir_pipeline_helpers.addImport("ravi_ast", modules.ast);
    const hir_pipeline_support = b.createModule(.{ .root_source_file = b.path("src/compiler/hir_pipeline_support.zig"), .target = target, .optimize = optimize });
    hir_pipeline_support.addImport("ravi_ast", modules.ast);
    hir_pipeline_support.addImport("ravi_hir_pipeline_helpers", hir_pipeline_helpers);
    const hir_lowering = b.createModule(.{ .root_source_file = b.path("src/compiler/hir_lowering.zig"), .target = target, .optimize = optimize });
    const hir_exception_lowering = b.createModule(.{ .root_source_file = b.path("src/compiler/hir_exception_lowering.zig"), .target = target, .optimize = optimize });
    const hir_local_discovery = b.createModule(.{ .root_source_file = b.path("src/compiler/hir_local_discovery.zig"), .target = target, .optimize = optimize });
    const hir_expr_lowering = b.createModule(.{ .root_source_file = b.path("src/compiler/hir_expr_lowering.zig"), .target = target, .optimize = optimize });
    const hir_call_lowering = b.createModule(.{ .root_source_file = b.path("src/compiler/hir_call_lowering.zig"), .target = target, .optimize = optimize });
    hir_expr_lowering.addImport("ravi_ast", modules.ast);
    hir_expr_lowering.addImport("ravi_hir", hir);
    hir_expr_lowering.addImport("ravi_hir_call_lowering", hir_call_lowering);
    hir_call_lowering.addImport("ravi_ast", modules.ast);
    hir_call_lowering.addImport("ravi_hir", hir);
    hir_lowering.addImport("ravi_ast", modules.ast);
    hir_lowering.addImport("ravi_hir", hir);
    hir_lowering.addImport("ravi_mir", mir);
    hir_lowering.addImport("ravi_hir_expr_lowering", hir_expr_lowering);
    hir_lowering.addImport("ravi_hir_exception_lowering", hir_exception_lowering);
    hir_lowering.addImport("ravi_hir_local_discovery", hir_local_discovery);
    hir_exception_lowering.addImport("ravi_ast", modules.ast);
    hir_exception_lowering.addImport("ravi_hir", hir);
    hir_exception_lowering.addImport("ravi_hir_expr_lowering", hir_expr_lowering);
    hir_local_discovery.addImport("ravi_ast", modules.ast);
    hir_pipeline_support.addImport("ravi_hir_lowering", hir_lowering);
    hir_pipeline.addImport("ravi_compiler", compiler);
    hir_pipeline.addImport("ravi_ast", modules.ast);
    hir_pipeline.addImport("ravi_hir", hir);
    hir_pipeline.addImport("ravi_mir", mir);
    hir_pipeline.addImport("ravi_mir_bytecode", mir_bytecode);
    hir_pipeline.addImport("ravi_bytecode", modules.bytecode);
    hir_pipeline.addImport("ravi_hir_compatibility", hir_compatibility);
    hir_pipeline.addImport("ravi_vm", runtime_modules.vm);
    hir_pipeline.addImport("ravi_hir_lowering", hir_lowering);
    hir_pipeline.addImport("ravi_ast_helpers", modules.ast_helpers);
    hir_pipeline.addImport("ravi_hir_pipeline_helpers", hir_pipeline_helpers);
    hir_pipeline.addImport("ravi_hir_pipeline_support", hir_pipeline_support);
    const semantic = b.createModule(.{ .root_source_file = b.path("src/semantic/analyzer.zig"), .target = target, .optimize = optimize });
    semantic.addImport("ravi_lexer", modules.lexer);
    semantic.addImport("ravi_ast", modules.ast);
    semantic.addImport("ravi_config", modules.config);
    semantic.addImport("ravi_types", modules.types);
    const semantic_symbols = b.createModule(.{ .root_source_file = b.path("src/semantic/symbols.zig"), .target = target, .optimize = optimize });
    semantic_symbols.addImport("ravi_types", modules.types);
    semantic.addImport("ravi_semantic_symbols", semantic_symbols);
    return .{ .compiler = compiler, .backend = backend, .optimizer = optimizer, .semantic = semantic, .semantic_symbols = semantic_symbols, .hir = hir, .mir = mir, .mir_verify = mir_verify, .mir_contract = mir_contract, .native_backend = native_backend, .hir_compatibility = hir_compatibility, .mir_bytecode = mir_bytecode, .mir_bytecode_emit = mir_bytecode_emit, .hir_pipeline = hir_pipeline, .hir_pipeline_helpers = hir_pipeline_helpers, .hir_pipeline_support = hir_pipeline_support, .hir_lowering = hir_lowering, .hir_exception_lowering = hir_exception_lowering, .hir_local_discovery = hir_local_discovery, .hir_expr_lowering = hir_expr_lowering, .hir_call_lowering = hir_call_lowering };
}
