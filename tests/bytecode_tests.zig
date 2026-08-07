const std = @import("std");
const bytecode = @import("ravi_bytecode");

test "control-flow verifier rejects inconsistent stack joins" {
    var chunk = bytecode.Chunk.init(std.testing.allocator);
    defer chunk.deinit();
    try chunk.emit(.{ .op = .constant, .operand = 1 });
    try chunk.emit(.{ .op = .jump_if_false, .operand = 4 });
    try chunk.emit(.{ .op = .constant, .operand = 2 });
    try chunk.emit(.{ .op = .jump, .operand = 5 });
    try chunk.emit(.{ .op = .jump, .operand = 5 });
    try chunk.emit(.{ .op = .not });
    try chunk.emit(.{ .op = .halt });
    try std.testing.expectError(error.InvalidInstruction, chunk.verify());
}

test "control-flow verifier accepts balanced branches" {
    var chunk = bytecode.Chunk.init(std.testing.allocator);
    defer chunk.deinit();
    try chunk.emit(.{ .op = .constant, .operand = 1 });
    try chunk.emit(.{ .op = .jump_if_false, .operand = 4 });
    try chunk.emit(.{ .op = .constant, .operand = 2 });
    try chunk.emit(.{ .op = .jump, .operand = 5 });
    try chunk.emit(.{ .op = .constant, .operand = 3 });
    try chunk.emit(.{ .op = .halt });
    try chunk.verify();
}

test "verifier rejects hostile operands and invalid metadata without overflow" {
    var dict = bytecode.Chunk.init(std.testing.allocator);
    defer dict.deinit();
    try dict.emit(.{ .op = .make_dict, .operand = std.math.maxInt(i64) });
    try dict.emit(.{ .op = .halt });
    try std.testing.expectError(error.InvalidInstruction, dict.verify());

    var call = bytecode.Chunk.init(std.testing.allocator);
    defer call.deinit();
    try call.emit(.{ .op = .call_value, .operand = std.math.maxInt(i64) });
    try call.emit(.{ .op = .halt });
    try std.testing.expectError(error.InvalidInstruction, call.verify());

    var string = bytecode.Chunk.init(std.testing.allocator);
    defer string.deinit();
    try string.emit(.{ .op = .make_string, .operand = 0 });
    try string.emit(.{ .op = .halt });
    try std.testing.expectError(error.InvalidInstruction, string.verify());

    var float = bytecode.Chunk.init(std.testing.allocator);
    defer float.deinit();
    try float.emit(.{ .op = .make_float, .operand = 0 });
    try float.emit(.{ .op = .halt });
    try std.testing.expectError(error.InvalidInstruction, float.verify());

    var format = bytecode.Chunk.init(std.testing.allocator);
    defer format.deinit();
    _ = try format.addFormat("f\"{value}\"", std.math.maxInt(usize));
    try format.emit(.{ .op = .make_format, .operand = 0 });
    try format.emit(.{ .op = .halt });
    try std.testing.expectError(error.InvalidInstruction, format.verify());
}

test "verifier validates suspension operands and function metadata" {
    var chunk = bytecode.Chunk.init(std.testing.allocator);
    defer chunk.deinit();
    try chunk.emit(.{ .op = .suspend_point, .operand = -1 });
    try chunk.emit(.{ .op = .halt });
    try std.testing.expectError(error.InvalidInstruction, chunk.verify());

    var metadata = bytecode.Chunk.init(std.testing.allocator);
    defer metadata.deinit();
    try metadata.emit(.{ .op = .halt });
    try metadata.emit(.{ .op = .return_value });
    _ = try metadata.addFunction(.{ .entry = 1, .arity = 0, .name = "broken", .resumable = true, .suspension_count = 0 });
    try std.testing.expectError(error.InvalidInstruction, metadata.verify());
}

test "verifier survives deterministic malformed-bytecode fuzz corpus" {
    const opcode_count = @typeInfo(bytecode.OpCode).@"enum".field_names.len;
    var state: u64 = 0x726176695f66757a;
    for (0..256) |_| {
        var chunk = bytecode.Chunk.init(std.testing.allocator);
        defer chunk.deinit();
        const instruction_count = @as(usize, @intCast(state % 24)) + 1;
        for (0..instruction_count) |_| {
            state = state *% 6364136223846793005 +% 1442695040888963407;
            const operation: bytecode.OpCode = @enumFromInt(state % opcode_count);
            state = state *% 6364136223846793005 +% 1442695040888963407;
            try chunk.emit(.{ .op = operation, .operand = @bitCast(state) });
        }
        _ = chunk.verify() catch {};
    }
}
