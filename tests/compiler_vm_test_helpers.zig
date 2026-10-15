const std = @import("std");
const bytecode = @import("ravi_bytecode");
const vm_mod = @import("ravi_vm");

pub fn compileSource(source: []const u8, language: anytype) !bytecode.Chunk {
    var pipeline = @import("ravi_pipeline").Pipeline{ .allocator = std.testing.allocator };
    return pipeline.compileSource(source, language);
}

pub fn run(source: []const u8, language: anytype) !i64 {
    return runAst(source, language);
}

pub fn runAst(source: []const u8, language: anytype) !i64 {
    var chunk = try compileSource(source, language);
    defer chunk.deinit();
    var vm = try vm_mod.Vm.init(std.testing.allocator);
    defer vm.deinit();
    return vm.run(&chunk);
}
