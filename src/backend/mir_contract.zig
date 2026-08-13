const std = @import("std");
const mir = @import("ravi_mir");

/// Backend-independent checks applied before any target-specific lowering.
pub fn verify(function: *const mir.Function) !void {
    try function.verify();
    var suspension_count: usize = 0;
    for (function.instructions.items) |instruction| {
        if (instruction.source_line == 0) return error.InvalidSourceIdentity;
        switch (instruction.operation) {
            .suspend_point => |point| {
                suspension_count += 1;
                if (point.resume_line == 0) return error.InvalidSuspensionMetadata;
            },
            .call => |call| if (call.function == std.math.maxInt(usize)) return error.InvalidCall,
            .binary => |binary| {
                const expected: mir.Type = switch (binary.operator) {
                    .equal, .less => .boolean,
                    else => .integer,
                };
                if (instruction.result_type != expected) return error.InvalidType;
            },
            .guard => |guard| if (guard.expected != instruction.result_type and instruction.result_type != .dynamic) return error.InvalidType,
            else => {},
        }
    }
    if (suspension_count != function.suspension_count) return error.InvalidSuspensionMetadata;
}

test "MIR contract accepts verified scalar functions" {
    var function = mir.Function.init(std.testing.allocator);
    defer function.deinit();
    const value = try function.instructions.addOne(std.testing.allocator);
    value.* = .{ .result = @enumFromInt(0), .result_type = .integer, .source_line = 1, .operation = .{ .constant_integer = 42 } };
    function.value_count = 1;
    try function.instructions.append(std.testing.allocator, .{ .source_line = 1, .operation = .{ .return_value = @enumFromInt(0) } });
    try function.blocks.append(std.testing.allocator, .{ .first_instruction = 0, .instruction_count = 2 });
    try verify(&function);
}
