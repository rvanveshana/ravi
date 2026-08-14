const std = @import("std");

pub const CoreModules = struct {
    config: *std.Build.Module,
    packed_bytecode: *std.Build.Module,
    opcode_spec: *std.Build.Module,
    bytecode: *std.Build.Module,
    verifier: *std.Build.Module,
    vm_value: *std.Build.Module,
    vm_collections: *std.Build.Module,
    async_state: *std.Build.Module,
    scheduler: *std.Build.Module,
    debug: *std.Build.Module,
    gc: *std.Build.Module,
    dispatch: *std.Build.Module,
    lexer: *std.Build.Module,
    ast: *std.Build.Module,
    ast_helpers: *std.Build.Module,
    types: *std.Build.Module,
    source: *std.Build.Module,
    diagnostics: *std.Build.Module,
};

pub fn add(b: *std.Build, target: std.Build.ResolvedTarget, optimize: std.builtin.OptimizeMode) CoreModules {
    const config = b.createModule(.{ .root_source_file = b.path("config/constants.zig"), .target = target, .optimize = optimize });
    const packed_bytecode = b.createModule(.{ .root_source_file = b.path("src/bytecode/packed.zig"), .target = target, .optimize = optimize });
    const opcode_spec = b.createModule(.{ .root_source_file = b.path("src/bytecode/spec.zig"), .target = target, .optimize = optimize });
    opcode_spec.addImport("ravi_packed_bytecode", packed_bytecode);
    const bytecode = b.createModule(.{ .root_source_file = b.path("src/bytecode/bytecode.zig"), .target = target, .optimize = optimize });
    bytecode.addImport("ravi_packed_bytecode", packed_bytecode);
    bytecode.addImport("ravi_opcode_spec", opcode_spec);
    const verifier = b.createModule(.{ .root_source_file = b.path("src/bytecode/verifier.zig"), .target = target, .optimize = optimize });
    verifier.addImport("ravi_opcode_spec", opcode_spec);
    bytecode.addImport("ravi_bytecode_verifier", verifier);
    const vm_value = b.createModule(.{ .root_source_file = b.path("src/vm/value.zig"), .target = target, .optimize = optimize });
    const vm_collections = b.createModule(.{ .root_source_file = b.path("src/vm/collections.zig"), .target = target, .optimize = optimize });
    vm_collections.addImport("ravi_vm_value", vm_value);
    const async_state = b.createModule(.{ .root_source_file = b.path("src/concurrency/async_state.zig"), .target = target, .optimize = optimize });
    async_state.addImport("ravi_vm_value", vm_value);
    const debug = b.createModule(.{ .root_source_file = b.path("src/debug/debug.zig"), .target = target, .optimize = optimize });
    debug.addImport("ravi_bytecode", bytecode);
    const scheduler = b.createModule(.{ .root_source_file = b.path("src/concurrency/scheduler.zig"), .target = target, .optimize = optimize });
    const gc = b.createModule(.{ .root_source_file = b.path("src/memory/gc.zig"), .target = target, .optimize = optimize });
    const dispatch = b.createModule(.{ .root_source_file = b.path("src/vm/dispatch.zig"), .target = target, .optimize = optimize });
    dispatch.addImport("ravi_bytecode", bytecode);
    dispatch.addImport("ravi_vm_value", vm_value);
    const lexer = b.createModule(.{ .root_source_file = b.path("src/lexer/lexer.zig"), .target = target, .optimize = optimize });
    lexer.addImport("ravi_config", config);
    const ast = b.createModule(.{ .root_source_file = b.path("src/ast/ast.zig"), .target = target, .optimize = optimize });
    const ast_helpers = b.createModule(.{ .root_source_file = b.path("src/compiler/ast_helpers.zig"), .target = target, .optimize = optimize });
    ast_helpers.addImport("ravi_ast", ast);
    const types = b.createModule(.{ .root_source_file = b.path("src/types/type.zig"), .target = target, .optimize = optimize });
    const source = b.createModule(.{ .root_source_file = b.path("src/source/source.zig"), .target = target, .optimize = optimize });
    const diagnostics = b.createModule(.{ .root_source_file = b.path("src/diagnostics/diagnostic.zig"), .target = target, .optimize = optimize });
    diagnostics.addImport("ravi_source", source);
    return .{ .config = config, .packed_bytecode = packed_bytecode, .opcode_spec = opcode_spec, .bytecode = bytecode, .verifier = verifier, .vm_value = vm_value, .vm_collections = vm_collections, .async_state = async_state, .scheduler = scheduler, .debug = debug, .gc = gc, .dispatch = dispatch, .lexer = lexer, .ast = ast, .ast_helpers = ast_helpers, .types = types, .source = source, .diagnostics = diagnostics };
}
