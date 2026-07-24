const bytecode = @import("ravi_bytecode");
const std = @import("std");

pub const OptimizationStats = struct { folded_operations: usize = 0, removed_pops: usize = 0 };
pub const Optimizer = struct {
    fn canFoldDivide(lhs: i64, rhs: i64) bool {
        return rhs != 0 and !(lhs == std.math.minInt(i64) and rhs == -1);
    }
    pub fn optimize(chunk: *bytecode.Chunk) OptimizationStats {
        var stats = OptimizationStats{};
        var i: usize = 0;
        while (i + 2 < chunk.code.items.len) : (i += 1) {
            const a = chunk.code.items[i];
            const b = chunk.code.items[i + 1];
            // A literal immediately discarded by `pop` cannot have side
            // effects. Remove this narrow pattern only; calls/property access
            // are deliberately retained because they may mutate or throw.
            if (a.op == .constant and b.op == .pop) {
                _ = chunk.code.orderedRemove(i);
                _ = chunk.code.orderedRemove(i);
                if (chunk.source_map.items.len >= i + 2) {
                    _ = chunk.source_map.orderedRemove(i);
                    _ = chunk.source_map.orderedRemove(i);
                }
                for (chunk.code.items) |*inst| switch (inst.op) {
                    .jump, .jump_if_false, .try_begin => {
                        if (inst.operand == @as(i64, @intCast(i + 1))) {
                            inst.operand = @intCast(i);
                        } else if (inst.operand > @as(i64, @intCast(i + 1))) {
                            inst.operand -= 2;
                        }
                    },
                    else => {},
                };
                for (chunk.functions.items) |*func| {
                    if (func.entry == i + 1) func.entry = i else if (func.entry > i + 1) func.entry -= 2;
                }
                stats.removed_pops += 1;
                continue;
            }
            const op = chunk.code.items[i + 2].op;
            const add = @addWithOverflow(a.operand, b.operand);
            const subtract = @subWithOverflow(a.operand, b.operand);
            const multiply = @mulWithOverflow(a.operand, b.operand);
            const can_fold = a.op == .constant and b.op == .constant and
                (op == .add or op == .subtract or op == .multiply or
                    (op == .divide and canFoldDivide(a.operand, b.operand)) or
                    (op == .modulo and b.operand != 0)) and
                ((op == .add and add[1] == 0) or
                    (op == .subtract and subtract[1] == 0) or
                    (op == .multiply and multiply[1] == 0) or
                    (op == .divide and canFoldDivide(a.operand, b.operand)) or
                    (op == .modulo and b.operand != 0));
            if (can_fold) {
                const value = switch (op) {
                    .add => add[0],
                    .subtract => subtract[0],
                    .multiply => multiply[0],
                    .divide => @divTrunc(a.operand, b.operand),
                    .modulo => @mod(a.operand, b.operand),
                    else => unreachable,
                };
                chunk.code.items[i] = .{ .op = .constant, .operand = value };
                _ = chunk.code.orderedRemove(i + 1);
                _ = chunk.code.orderedRemove(i + 1);
                if (chunk.source_map.items.len >= i + 3) {
                    _ = chunk.source_map.orderedRemove(i + 1);
                    _ = chunk.source_map.orderedRemove(i + 1);
                }
                // Fix jump targets and function entry points after instruction removal
                for (chunk.code.items) |*inst| {
                    switch (inst.op) {
                        .jump, .jump_if_false, .try_begin => {
                            if (inst.operand == @as(i64, @intCast(i + 1))) {
                                inst.operand = @intCast(i);
                            } else if (inst.operand > @as(i64, @intCast(i + 1))) {
                                inst.operand -= 2;
                            }
                        },
                        else => {},
                    }
                }
                for (chunk.functions.items) |*func| {
                    if (func.entry == i + 1) {
                        func.entry = i;
                    } else if (func.entry > i + 1) {
                        func.entry -= 2;
                    }
                }
                stats.folded_operations += 1;
            }
        }
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
    const stats = Optimizer.optimize(&chunk);
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
    const stats = Optimizer.optimize(&chunk);
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
    const stats = Optimizer.optimize(&chunk);
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
    const stats = Optimizer.optimize(&chunk);
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
    const stats = Optimizer.optimize(&chunk);
    try std.testing.expectEqual(@as(usize, 0), stats.folded_operations);
    try std.testing.expectEqual(bytecode.OpCode.add, chunk.code.items[2].op);
}
