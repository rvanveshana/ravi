const std = @import("std");
pub fn foldConstants(self: anytype) !usize {
    const constants = try self.allocator.alloc(?i64, self.value_count);
    defer self.allocator.free(constants);
    @memset(constants, null);
    var changed: usize = 0;
    for (self.instructions.items) |*instruction| {
        const result = instruction.result orelse continue;
        const result_index: usize = @intFromEnum(result);
        if (result_index >= constants.len) return error.InvalidDefinition;
        switch (instruction.operation) {
            .constant_integer => |value| constants[result_index] = value,
            .binary => |binary| {
                const left_index = @intFromEnum(binary.left);
                const right_index = @intFromEnum(binary.right);
                if (left_index >= constants.len or right_index >= constants.len) return error.UndefinedValue;
                const left = constants[left_index] orelse continue;
                const right = constants[right_index] orelse continue;
                const folded: ?i64 = switch (binary.operator) {
                    .add => left +% right,
                    .subtract => left -% right,
                    .multiply => left *% right,
                    .divide => if (right == 0 or (left == std.math.minInt(i64) and right == -1)) null else @divTrunc(left, right),
                    .modulo => if (right == 0) null else @mod(left, right),
                    .equal => @intFromBool(left == right),
                    .less => @intFromBool(left < right),
                    .not_equal, .less_equal, .greater, .greater_equal, .logic_and, .logic_or => null,
                };
                if (folded) |value| {
                    instruction.operation = .{ .constant_integer = value };
                    constants[result_index] = value;
                    changed += 1;
                }
            },
            else => {},
        }
    }
    try self.verify();
    return changed;
}
