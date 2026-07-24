const std = @import("std");
const mir = @import("ravi_mir");
const bytecode = @import("ravi_bytecode");
const vm_runtime = @import("ravi_vm");

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
    pub fn deinit(self: *BlockLabels) void { self.allocator.free(self.offsets); }
    pub fn offset(self: *const BlockLabels, block: mir.BlockId) !usize {
        const index = @intFromEnum(block);
        if (index >= self.offsets.len) return error.InvalidBlock;
        return self.offsets[index];
    }
};

/// Lower the currently supported straight-line integer MIR subset. Complex
/// SSA/control-flow operations intentionally fail until their stack/local
/// assignment strategy is implemented.
pub fn lower(allocator: anytype, function: *const mir.Function) !bytecode.Chunk {
    var chunk = bytecode.Chunk.init(allocator);
    errdefer chunk.deinit();
    try function.verify();
    if (function.blocks.items.len != 1) return error.UnsupportedMIR;
    for (function.instructions.items) |instruction| {
        chunk.setSourceLocation(.{ .start_offset = 0, .end_offset = 0, .line = instruction.source_line, .column = 0 });
        switch (instruction.operation) {
            .constant_integer => |value| {
                // Integer constants are represented directly by the operand.
                try chunk.emit(.{ .op = .constant, .operand = value });
                if (instruction.result) |result| try chunk.emit(.{ .op = .store_local, .operand = @intCast(@intFromEnum(result)) });
            },
            .binary => |binary| {
                try chunk.emit(.{ .op = .load_local, .operand = @intCast(@intFromEnum(binary.left)) });
                try chunk.emit(.{ .op = .load_local, .operand = @intCast(@intFromEnum(binary.right)) });
                try chunk.emit(.{ .op = switch (binary.operator) {
                    .add => .add, .subtract => .subtract, .multiply => .multiply,
                    .divide => .divide, .modulo => .modulo, .equal => .equal, .less => .less,
                } });
                if (instruction.result) |result| try chunk.emit(.{ .op = .store_local, .operand = @intCast(@intFromEnum(result)) });
            },
            .return_value => |value| if (value) |result| {
                try chunk.emit(.{ .op = .load_local, .operand = @intCast(@intFromEnum(result)) });
                try chunk.emit(.{ .op = .return_value });
            } else try chunk.emit(.{ .op = .return_value }),
            .suspend_point => try chunk.emit(.{ .op = .suspend_point, .operand = @intCast(instruction.operation.suspend_point.resume_line) }),
            else => return error.UnsupportedMIR,
        }
    }
    try chunk.verify();
    return chunk;
}

test "MIR block labels preserve verified instruction offsets" {
    var source = @import("ravi_hir").Function.init(std.testing.allocator, "main");
    defer source.deinit();
    _ = try source.appendValue(.integer, .{ .constant_integer = 1 }, 1);
    try source.appendEffect(.{ .return_value = @enumFromInt(0) }, 1);
    var lowered = try mir.Function.lower(std.testing.allocator, &source);
    defer lowered.deinit();
    var labels = try BlockLabels.init(std.testing.allocator, &lowered);
    defer labels.deinit();
    try std.testing.expectEqual(@as(usize, 0), try labels.offset(@enumFromInt(0)));
    try std.testing.expectError(error.InvalidBlock, labels.offset(@enumFromInt(1)));
}

test "straight-line MIR lowers to verified bytecode" {
    var source = @import("ravi_hir").Function.init(std.testing.allocator, "main");
    defer source.deinit();
    _ = try source.appendValue(.integer, .{ .constant_integer = 2 }, 3);
    _ = try source.appendValue(.integer, .{ .constant_integer = 3 }, 3);
    _ = try source.appendValue(.integer, .{ .binary = .{ .operator = .add, .left = @enumFromInt(0), .right = @enumFromInt(1) } }, 3);
    try source.appendEffect(.{ .return_value = @enumFromInt(2) }, 3);
    var lowered = try mir.Function.lower(std.testing.allocator, &source);
    defer lowered.deinit();
    var chunk = try lower(std.testing.allocator, &lowered);
    defer chunk.deinit();
    var found_add = false;
    for (chunk.code.items) |instruction| {
        if (instruction.op == .add) found_add = true;
    }
    try std.testing.expect(found_add);
}

test "lowered MIR executes through the production VM" {
    var source = @import("ravi_hir").Function.init(std.testing.allocator, "main");
    defer source.deinit();
    _ = try source.appendValue(.integer, .{ .constant_integer = 20 }, 4);
    _ = try source.appendValue(.integer, .{ .constant_integer = 22 }, 4);
    _ = try source.appendValue(.integer, .{ .binary = .{ .operator = .add, .left = @enumFromInt(0), .right = @enumFromInt(1) } }, 4);
    try source.appendEffect(.{ .return_value = @enumFromInt(2) }, 4);
    var lowered = try mir.Function.lower(std.testing.allocator, &source);
    defer lowered.deinit();
    var chunk = try lower(std.testing.allocator, &lowered);
    defer chunk.deinit();
    var vm = try vm_runtime.Vm.init(std.testing.allocator);
    defer vm.deinit();
    const result = try vm.runValue(&chunk);
    try std.testing.expectEqual(@as(i64, 42), result.asInt());
}

test "MIR bytecode lowering rejects control flow until labels are materialized" {
    var source = @import("ravi_hir").Function.init(std.testing.allocator, "branch");
    defer source.deinit();
    const condition = try source.appendValue(.integer, .{ .constant_integer = 1 }, 5);
    try source.appendEffect(.{ .return_value = condition }, 5);
    var lowered = try mir.Function.lower(std.testing.allocator, &source);
    defer lowered.deinit();
    // A verified single-block function with no unsupported operation remains
    // legal; this test documents that a branch operation is rejected below.
    lowered.instructions.items[1].operation = .{ .jump = @enumFromInt(0) };
    try std.testing.expectError(error.UnsupportedMIR, lower(std.testing.allocator, &lowered));
}

test "MIR lowering preserves suspension markers" {
    var source = @import("ravi_hir").Function.init(std.testing.allocator, "async_main");
    defer source.deinit();
    source.resumable = true;
    try source.appendEffect(.{ .suspend_point = .{ .resume_line = 12 } }, 12);
    var lowered = try mir.Function.lower(std.testing.allocator, &source);
    defer lowered.deinit();
    var chunk = try lower(std.testing.allocator, &lowered);
    defer chunk.deinit();
    try std.testing.expectEqual(bytecode.OpCode.suspend_point, chunk.code.items[0].op);
    try std.testing.expectEqual(@as(i64, 12), chunk.code.items[0].operand);
}
