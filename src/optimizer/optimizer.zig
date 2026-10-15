const bytecode = @import("ravi_bytecode");
const std = @import("std");
const integers = @import("ravi_vm_value").integer_arithmetic;

pub const OptimizationStats = struct { folded_operations: usize = 0, removed_pops: usize = 0 };
pub const Optimizer = struct {
    pub fn optimize(chunk: *bytecode.Chunk) !OptimizationStats {
        const count = chunk.code.items.len;
        const targets = try chunk.allocator.alloc(bool, count + 1);
        defer chunk.allocator.free(targets);
        @memset(targets, false);
        const relocation = try chunk.allocator.alloc(usize, count + 1);
        defer chunk.allocator.free(relocation);
        for (chunk.code.items) |inst| switch (inst.op) {
            .jump, .jump_if_false, .try_begin => {
                if (inst.operand < 0 or inst.operand >= count) return error.InvalidJump;
                targets[@intCast(inst.operand)] = true;
            },
            else => {},
        };
        for (chunk.functions.items) |function| {
            if (function.entry >= count) return error.InvalidInstruction;
            targets[function.entry] = true;
        }
        var stats = OptimizationStats{};
        var read: usize = 0;
        var write: usize = 0;
        while (read < count) {
            relocation[read] = write;
            const a = chunk.code.items[read];
            var consumed: usize = 1;
            var replacement = a;
            if (read + 1 < count and !targets[read + 1] and a.op == .constant and
                chunk.code.items[read + 1].op == .pop and (integers.validate(a.operand) catch null) != null)
            {
                relocation[read + 1] = write;
                read += 2;
                stats.removed_pops += 1;
                continue;
            }
            if (read + 2 < count and !targets[read + 1] and !targets[read + 2] and
                a.op == .constant and chunk.code.items[read + 1].op == .constant)
            {
                const operation: ?integers.Operation = switch (chunk.code.items[read + 2].op) {
                    .add => .add,
                    .subtract => .subtract,
                    .multiply => .multiply,
                    .divide => .divide,
                    .modulo => .modulo,
                    else => null,
                };
                if (operation) |op| {
                    if (integers.evaluate(op, a.operand, chunk.code.items[read + 1].operand) catch null) |value| {
                        replacement = .{ .op = .constant, .operand = value };
                        consumed = 3;
                        stats.folded_operations += 1;
                    }
                }
            }
            for (0..consumed) |offset| relocation[read + offset] = write;
            chunk.code.items[write] = replacement;
            if (chunk.source_map.items.len == count) chunk.source_map.items[write] = chunk.source_map.items[read];
            if (chunk.root_map.items.len == count) chunk.root_map.items[write] = chunk.root_map.items[read];
            write += 1;
            read += consumed;
        }
        relocation[count] = write;
        chunk.code.items.len = write;
        if (chunk.source_map.items.len == count) chunk.source_map.items.len = write;
        if (chunk.root_map.items.len == count) chunk.root_map.items.len = write;
        for (chunk.code.items) |*inst| switch (inst.op) {
            .jump, .jump_if_false, .try_begin => inst.operand = @intCast(relocation[@intCast(inst.operand)]),
            else => {},
        };
        for (chunk.functions.items) |*function| function.entry = relocation[function.entry];
        return stats;
    }
};

test "optimizer folds adjacent integer constants" {
    var chunk = bytecode.Chunk.init(std.testing.allocator);
    defer chunk.deinit();
    try chunk.emit(.{ .op = .constant, .operand = 20 });
    try chunk.emit(.{ .op = .constant, .operand = 22 });
    try chunk.emit(.{ .op = .add });
    try chunk.emit(.{ .op = .halt });
    const stats = try Optimizer.optimize(&chunk);
    try std.testing.expectEqual(@as(usize, 1), stats.folded_operations);
    try std.testing.expectEqual(@as(usize, 2), chunk.code.items.len);
    try std.testing.expectEqual(@as(i64, 42), chunk.code.items[0].operand);
}

test "optimizer removes only side-effect-free constant pop pairs" {
    var chunk = bytecode.Chunk.init(std.testing.allocator);
    defer chunk.deinit();
    try chunk.emit(.{ .op = .constant, .operand = 7 });
    try chunk.emit(.{ .op = .pop });
    try chunk.emit(.{ .op = .halt });
    const stats = try Optimizer.optimize(&chunk);
    try std.testing.expectEqual(@as(usize, 1), stats.removed_pops);
    try std.testing.expectEqual(@as(usize, 1), chunk.code.items.len);
    try std.testing.expectEqual(bytecode.OpCode.halt, chunk.code.items[0].op);
}

test "optimizer folds nonzero modulo but preserves divide-by-zero trap" {
    var chunk = bytecode.Chunk.init(std.testing.allocator);
    defer chunk.deinit();
    try chunk.emit(.{ .op = .constant, .operand = 17 });
    try chunk.emit(.{ .op = .constant, .operand = 5 });
    try chunk.emit(.{ .op = .modulo });
    try chunk.emit(.{ .op = .constant, .operand = 9 });
    try chunk.emit(.{ .op = .constant, .operand = 0 });
    try chunk.emit(.{ .op = .modulo });
    const stats = try Optimizer.optimize(&chunk);
    try std.testing.expectEqual(@as(usize, 1), stats.folded_operations);
    try std.testing.expectEqual(@as(i64, 2), chunk.code.items[0].operand);
    try std.testing.expectEqual(bytecode.OpCode.modulo, chunk.code.items[3].op);
}

test "optimizer folds safe division and preserves exceptional cases" {
    var chunk = bytecode.Chunk.init(std.testing.allocator);
    defer chunk.deinit();
    try chunk.emit(.{ .op = .constant, .operand = 42 });
    try chunk.emit(.{ .op = .constant, .operand = 5 });
    try chunk.emit(.{ .op = .divide });
    try chunk.emit(.{ .op = .constant, .operand = 42 });
    try chunk.emit(.{ .op = .constant, .operand = 0 });
    try chunk.emit(.{ .op = .divide });
    const stats = try Optimizer.optimize(&chunk);
    try std.testing.expectEqual(@as(usize, 1), stats.folded_operations);
    try std.testing.expectEqual(@as(i64, 8), chunk.code.items[0].operand);
    try std.testing.expectEqual(bytecode.OpCode.divide, chunk.code.items[3].op);
}

test "optimizer leaves overflowing integer arithmetic for runtime" {
    var chunk = bytecode.Chunk.init(std.testing.allocator);
    defer chunk.deinit();
    try chunk.emit(.{ .op = .constant, .operand = std.math.maxInt(i64) });
    try chunk.emit(.{ .op = .constant, .operand = 1 });
    try chunk.emit(.{ .op = .add });
    const stats = try Optimizer.optimize(&chunk);
    try std.testing.expectEqual(@as(usize, 0), stats.folded_operations);
    try std.testing.expectEqual(bytecode.OpCode.add, chunk.code.items[2].op);
}

test "optimizer preserves negative remainder and runtime integer boundaries" {
    var chunk = bytecode.Chunk.init(std.testing.allocator);
    defer chunk.deinit();
    try chunk.emit(.{ .op = .constant, .operand = -7 });
    try chunk.emit(.{ .op = .constant, .operand = 3 });
    try chunk.emit(.{ .op = .modulo });
    try chunk.emit(.{ .op = .constant, .operand = integers.max + 1 });
    try chunk.emit(.{ .op = .constant, .operand = 1 });
    try chunk.emit(.{ .op = .subtract });
    const stats = try Optimizer.optimize(&chunk);
    try std.testing.expectEqual(@as(usize, 1), stats.folded_operations);
    try std.testing.expectEqual(@as(i64, -1), chunk.code.items[0].operand);
    try std.testing.expectEqual(bytecode.OpCode.subtract, chunk.code.items[3].op);
}

test "optimizer respects incoming edges to the middle of a candidate" {
    var chunk = bytecode.Chunk.init(std.testing.allocator);
    defer chunk.deinit();
    try chunk.emit(.{ .op = .jump, .operand = 2 });
    try chunk.emit(.{ .op = .constant, .operand = 1 });
    try chunk.emit(.{ .op = .constant, .operand = 2 });
    try chunk.emit(.{ .op = .add });
    const stats = try Optimizer.optimize(&chunk);
    try std.testing.expectEqual(@as(usize, 0), stats.folded_operations);
    try std.testing.expectEqual(@as(i64, 2), chunk.code.items[0].operand);
}
