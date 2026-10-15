const std = @import("std");
const core = @import("modules_core.zig");
const runtime = @import("modules_runtime.zig");

pub const CompilerModules = struct {
    compiler: *std.Build.Module,
    pipeline: *std.Build.Module,
    backend: *std.Build.Module,
    optimizer: *std.Build.Module,
    semantic: *std.Build.Module,
    semantic_symbols: *std.Build.Module,
    hir: *std.Build.Module,
    mir: *std.Build.Module,
    mir_verify: *std.Build.Module,
    mir_contract: *std.Build.Module,
    native_backend: *std.Build.Module,
    mir_bytecode: *std.Build.Module,
    mir_bytecode_emit: *std.Build.Module,
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
    optimizer.addImport("ravi_vm_value", modules.vm_value);
    const hir = b.createModule(.{ .root_source_file = b.path("src/ir/hir.zig"), .target = target, .optimize = optimize });
    compiler.addImport("ravi_hir", hir);
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
    const mir_bytecode = b.createModule(.{ .root_source_file = b.path("src/ir/mir_bytecode.zig"), .target = target, .optimize = optimize });
    mir_bytecode.addImport("ravi_mir", mir);
    mir_bytecode.addImport("ravi_bytecode", modules.bytecode);
    mir_bytecode.addImport("ravi_hir", hir);
    mir_bytecode.addImport("ravi_vm", runtime_modules.vm);
    const mir_bytecode_emit = b.createModule(.{ .root_source_file = b.path("src/ir/mir_bytecode_emit.zig"), .target = target, .optimize = optimize });
    mir_bytecode_emit.addImport("ravi_mir", mir);
    mir_bytecode_emit.addImport("ravi_bytecode", modules.bytecode);
    mir_bytecode.addImport("ravi_mir_bytecode_emit", mir_bytecode_emit);
    const semantic = b.createModule(.{ .root_source_file = b.path("src/semantic/analyzer.zig"), .target = target, .optimize = optimize });
    semantic.addImport("ravi_lexer", modules.lexer);
    semantic.addImport("ravi_ast", modules.ast);
    semantic.addImport("ravi_config", modules.config);
    semantic.addImport("ravi_types", modules.types);
    const semantic_symbols = b.createModule(.{ .root_source_file = b.path("src/semantic/symbols.zig"), .target = target, .optimize = optimize });
    semantic_symbols.addImport("ravi_types", modules.types);
    semantic.addImport("ravi_semantic_symbols", semantic_symbols);
    const pipeline = b.createModule(.{ .root_source_file = b.path("src/compiler/pipeline.zig"), .target = target, .optimize = optimize });
    pipeline.addImport("ravi_compiler", compiler);
    pipeline.addImport("ravi_ast", modules.ast);
    pipeline.addImport("ravi_bytecode", modules.bytecode);
    pipeline.addImport("ravi_config", modules.config);
    pipeline.addImport("ravi_lexer", modules.lexer);
    pipeline.addImport("ravi_semantic", semantic);
    pipeline.addImport("ravi_optimizer", optimizer);
    pipeline.addImport("ravi_vm", runtime_modules.vm);
    return .{ .compiler = compiler, .pipeline = pipeline, .backend = backend, .optimizer = optimizer, .semantic = semantic, .semantic_symbols = semantic_symbols, .hir = hir, .mir = mir, .mir_verify = mir_verify, .mir_contract = mir_contract, .native_backend = native_backend, .mir_bytecode = mir_bytecode, .mir_bytecode_emit = mir_bytecode_emit };
}
