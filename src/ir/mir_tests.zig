const std = @import("std");
const hir = @import("ravi_hir");
const mir = @import("ravi_mir");

test "HIR lowers to verified MIR with stable source lines" {
    var source = hir.Function.init(std.testing.allocator, "main");
    defer source.deinit();
    const left = try source.appendValue(.integer, .{ .constant_integer = 20 }, 1);
    const right = try source.appendValue(.integer, .{ .constant_integer = 22 }, 1);
    const sum = try source.appendValue(.integer, .{ .binary = .{ .operator = .add, .left = left, .right = right } }, 1);
    try source.appendEffect(.{ .return_value = sum }, 1);
    try source.setBlocks(&.{.{ .first_instruction = 0, .instruction_count = source.instructions.items.len }});
    var function = try mir.Function.lower(std.testing.allocator, &source);
    defer function.deinit();
    try std.testing.expectEqual(@as(usize, 1), function.blocks.items.len);
    try std.testing.expectEqual(@as(usize, 1), function.instructions.items[2].source_line);
    try std.testing.expectEqual(@as(usize, 1), try function.foldConstants());
    try std.testing.expectEqual(@as(i64, 42), function.instructions.items[2].operation.constant_integer);
}

test "constant folding preserves trapping division" {
    var source = hir.Function.init(std.testing.allocator, "main");
    defer source.deinit();
    const numerator = try source.appendValue(.integer, .{ .constant_integer = 1 }, 1);
    const zero = try source.appendValue(.integer, .{ .constant_integer = 0 }, 1);
    const result = try source.appendValue(.integer, .{ .binary = .{ .operator = .divide, .left = numerator, .right = zero } }, 1);
    try source.appendEffect(.{ .return_value = result }, 1);
    try source.setBlocks(&.{.{ .first_instruction = 0, .instruction_count = source.instructions.items.len }});
    var function = try mir.Function.lower(std.testing.allocator, &source);
    defer function.deinit();
    try std.testing.expectEqual(@as(usize, 0), try function.foldConstants());
    try std.testing.expect(function.instructions.items[2].operation == .binary);
}

test "constant folding handles modulo and preserves zero divisor" {
    var source = hir.Function.init(std.testing.allocator, "main");
    defer source.deinit();
    const left = try source.appendValue(.integer, .{ .constant_integer = 17 }, 1);
    const right = try source.appendValue(.integer, .{ .constant_integer = 5 }, 1);
    const result = try source.appendValue(.integer, .{ .binary = .{ .operator = .modulo, .left = left, .right = right } }, 1);
    try source.appendEffect(.{ .return_value = result }, 1);
    try source.setBlocks(&.{.{ .first_instruction = 0, .instruction_count = source.instructions.items.len }});
    var function = try mir.Function.lower(std.testing.allocator, &source);
    defer function.deinit();
    try std.testing.expectEqual(@as(usize, 1), try function.foldConstants());
    try std.testing.expectEqual(@as(i64, 2), function.instructions.items[2].operation.constant_integer);
}

test "MIR preserves resumable machine metadata" {
    var source = hir.Function.init(std.testing.allocator, "async_main");
    defer source.deinit();
    source.resumable = true;
    source.suspension_count = 1;
    try source.appendEffect(.{ .suspend_point = .{ .resume_line = 8 } }, 8);
    try source.appendEffect(.{ .return_value = null }, 8);
    try source.setBlocks(&.{.{ .first_instruction = 0, .instruction_count = source.instructions.items.len }});
    var lowered = try mir.Function.lower(std.testing.allocator, &source);
    defer lowered.deinit();
    try std.testing.expect(lowered.resumable);
    try std.testing.expectEqual(@as(usize, 1), lowered.suspension_count);
    try std.testing.expectEqual(@as(usize, 8), lowered.instructions.items[0].operation.suspend_point.resume_line);
}

test "MIR constant folding rejects malformed value identifiers" {
    var function = mir.Function.init(std.testing.allocator);
    defer function.deinit();
    function.value_count = 1;
    try function.instructions.append(std.testing.allocator, .{ .result = @enumFromInt(0), .result_type = .integer, .source_line = 1, .operation = .{ .binary = .{ .operator = .add, .left = @enumFromInt(9), .right = @enumFromInt(0) } } });
    try function.blocks.append(std.testing.allocator, .{ .first_instruction = 0, .instruction_count = 1 });
    try std.testing.expectError(error.UndefinedValue, function.foldConstants());
}

test "MIR verifier rejects overlapping and overflowing blocks" {
    var function = mir.Function.init(std.testing.allocator);
    defer function.deinit();
    try function.instructions.append(std.testing.allocator, .{ .source_line = 1, .operation = .{ .return_value = null } });
    try function.blocks.append(std.testing.allocator, .{ .first_instruction = 0, .instruction_count = 1 });
    try function.blocks.append(std.testing.allocator, .{ .first_instruction = 0, .instruction_count = 1 });
    try std.testing.expectError(error.InvalidBlock, function.verify());
    function.blocks.items[1] = .{ .first_instruction = std.math.maxInt(usize), .instruction_count = 1 };
    try std.testing.expectError(error.InvalidBlock, function.verify());
}

test "MIR verifier rejects uncovered instructions" {
    var function = mir.Function.init(std.testing.allocator);
    defer function.deinit();
    try function.instructions.append(std.testing.allocator, .{ .source_line = 1, .operation = .{ .return_value = null } });
    try function.instructions.append(std.testing.allocator, .{ .source_line = 2, .operation = .{ .return_value = null } });
    try function.blocks.append(std.testing.allocator, .{ .first_instruction = 0, .instruction_count = 1 });
    try std.testing.expectError(error.InvalidBlock, function.verify());
}

test "MIR verifier requires the first block to be the entry offset" {
    var function = mir.Function.init(std.testing.allocator);
    defer function.deinit();
    try function.instructions.append(std.testing.allocator, .{ .source_line = 1, .operation = .{ .return_value = null } });
    try function.blocks.append(std.testing.allocator, .{ .first_instruction = 1, .instruction_count = 0 });
    try std.testing.expectError(error.InvalidBlock, function.verify());
}

test "MIR verifier requires control-flow terminators at block end" {
    var function = mir.Function.init(std.testing.allocator);
    defer function.deinit();
    try function.instructions.append(std.testing.allocator, .{ .source_line = 1, .operation = .{ .jump = @enumFromInt(0) } });
    try function.instructions.append(std.testing.allocator, .{ .source_line = 1, .operation = .{ .return_value = null } });
    try function.blocks.append(std.testing.allocator, .{ .first_instruction = 0, .instruction_count = 2 });
    try std.testing.expectError(error.InvalidBlock, function.verify());
}
