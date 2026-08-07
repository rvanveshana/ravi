const std = @import("std");

pub const ValueId = enum(u32) { _ };
pub const Type = enum { none, boolean, integer, float, string, dynamic };
pub const Binary = enum { add, subtract, multiply, divide, modulo, equal, less };

pub const Instruction = struct {
    result: ?ValueId = null,
    result_type: Type = .none,
    source_line: usize = 0,
    operation: Operation,

    pub const Operation = union(enum) {
        constant_integer: i64,
        binary: struct { operator: Binary, left: ValueId, right: ValueId },
        guard: struct { value: ValueId, expected: Type },
        suspend_point: struct { resume_line: usize },
        return_value: ?ValueId,
    };
};

pub const Function = struct {
    allocator: std.mem.Allocator,
    name: []const u8,
    instructions: std.ArrayListUnmanaged(Instruction) = .empty,
    next_value: u32 = 0,
    resumable: bool = false,
    suspension_count: usize = 0,

    pub fn init(allocator: std.mem.Allocator, name: []const u8) Function {
        return .{ .allocator = allocator, .name = name };
    }
    pub fn deinit(self: *Function) void {
        self.instructions.deinit(self.allocator);
    }
    pub fn appendValue(self: *Function, result_type: Type, operation: Instruction.Operation, source_line: usize) !ValueId {
        const result: ValueId = @enumFromInt(self.next_value);
        self.next_value += 1;
        try self.instructions.append(self.allocator, .{ .result = result, .result_type = result_type, .operation = operation, .source_line = source_line });
        return result;
    }
    pub fn appendEffect(self: *Function, operation: Instruction.Operation, source_line: usize) !void {
        try self.instructions.append(self.allocator, .{ .operation = operation, .source_line = source_line });
    }
};

test "HIR retains types guards and source identity" {
    var function = Function.init(std.testing.allocator, "main");
    defer function.deinit();
    const value = try function.appendValue(.integer, .{ .constant_integer = 42 }, 3);
    try function.appendEffect(.{ .guard = .{ .value = value, .expected = .integer } }, 3);
    try function.appendEffect(.{ .return_value = value }, 3);
    try std.testing.expectEqual(@as(usize, 3), function.instructions.items.len);
    try std.testing.expectEqual(@as(usize, 3), function.instructions.items[0].source_line);
}

test "HIR records resumable suspension source identity" {
    var function = Function.init(std.testing.allocator, "async_main");
    defer function.deinit();
    function.resumable = true;
    function.suspension_count = 1;
    try function.appendEffect(.{ .suspend_point = .{ .resume_line = 12 } }, 12);
    try std.testing.expect(function.resumable);
    try std.testing.expectEqual(@as(usize, 12), function.instructions.items[0].operation.suspend_point.resume_line);
    try std.testing.expectEqual(@as(usize, 1), function.suspension_count);
}
