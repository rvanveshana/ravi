const bytecode = @import("ravi_bytecode");

pub const OptimizationStats = struct { folded_operations: usize = 0, removed_pops: usize = 0 };
pub const Optimizer = struct {
    pub fn optimize(chunk: *bytecode.Chunk) OptimizationStats {
        var stats = OptimizationStats{};
        var i: usize = 0;
        while (i + 2 < chunk.code.items.len) : (i += 1) {
            const a = chunk.code.items[i];
            const b = chunk.code.items[i + 1];
            const op = chunk.code.items[i + 2].op;
            if (a.op == .constant and b.op == .constant and (op == .add or op == .subtract or op == .multiply)) {
                const value = switch (op) {
                    .add => a.operand + b.operand,
                    .subtract => a.operand - b.operand,
                    .multiply => a.operand * b.operand,
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
                            if (inst.operand > i + 1) {
                                inst.operand -= 2;
                            }
                        },
                        else => {},
                    }
                }
                for (chunk.functions.items) |*func| {
                    if (func.entry > i + 1) {
                        func.entry -= 2;
                    }
                }
                stats.folded_operations += 1;
            }
        }
        return stats;
    }
};
