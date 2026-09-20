const std = @import("std");
const mir = @import("ravi_mir");
const bytecode = @import("ravi_bytecode");
const vm_runtime = @import("ravi_vm");
const emitter = @import("ravi_mir_bytecode_emit");
pub const BlockLabels = struct {
    allocator: std.mem.Allocator,
    offsets: []usize,
    pub fn init(allocator: std.mem.Allocator, function: *const mir.Function) !BlockLabels {
        try function.verify();
        const offsets = try allocator.alloc(usize, function.blocks.items.len);
        errdefer allocator.free(offsets);
        for (function.blocks.items, 0..) |block, index| offsets[index] = block.first_instruction;
        return .{ .allocator = allocator, .offsets = offsets };
    }
    pub fn deinit(self: *BlockLabels) void {
        self.allocator.free(self.offsets);
    }
    pub fn offset(self: *const BlockLabels, block: mir.BlockId) !usize {
        const index = @intFromEnum(block);
        if (index >= self.offsets.len) return error.InvalidBlock;
        return self.offsets[index];
    }
};
pub fn lowerProgram(allocator: anytype, main: *const mir.Function, callables: []const *const mir.Function) !bytecode.Chunk {
    return lowerProgramWithMetadata(allocator, main, callables, &.{}, &.{});
}
pub fn lowerProgramWithMetadata(allocator: anytype, main: *const mir.Function, callables: []const *const mir.Function, classes: []const bytecode.ClassInfo, methods: []const bytecode.MethodInfo) !bytecode.Chunk {
    var chunk = bytecode.Chunk.init(allocator);
    errdefer chunk.deinit();
    try chunk.classes.appendSlice(allocator, classes);
    try chunk.methods.appendSlice(allocator, methods);
    try main.verify();
    for (callables) |function| try function.verify();
    try emitter.emitBody(&chunk, main);
    for (callables, 0..) |function, function_index| {
        var is_method = false;
        for (methods) |method| {
            if (method.function_index == function_index) is_method = true;
        }
        const entry = chunk.code.items.len;
        try emitter.emitBody(&chunk, function);
        _ = try chunk.addFunction(.{
            .entry = entry,
            .arity = function.parameter_count - @intFromBool(is_method),
            .fixed_count = function.fixed_count - @intFromBool(is_method),
            .varargs_index = function.varargs_index,
            .kwargs_index = function.kwargs_index,
            .defaults = function.defaults,
            .name = function.name,
            .resumable = function.resumable,
            .suspension_count = function.suspension_count,
            .capture_count = function.capture_count,
        });
    }
    try chunk.verify();
    return chunk;
}
pub fn lower(allocator: anytype, function: *const mir.Function) !bytecode.Chunk {
    var chunk = bytecode.Chunk.init(allocator);
    errdefer chunk.deinit();
    try function.verify();
    try emitter.emitBody(&chunk, function);
    try chunk.verify();
    return chunk;
}
test {
    _ = @import("mir_bytecode_tests.zig");
}
