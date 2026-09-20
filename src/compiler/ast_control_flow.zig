const std = @import("std");
const bytecode = @import("ravi_bytecode");
const ast = @import("ravi_ast");
const ast_helpers = @import("ravi_ast_helpers");
const helpers = @import("helpers.zig");
const AstLoopContext = ast_helpers.LoopContext;

pub fn lower(comptime CompileError: type, self: anytype, chunk: *bytecode.Chunk, module: *const ast.Module, control: anytype, names: *std.ArrayListUnmanaged([]const u8), loops: *std.ArrayListUnmanaged(AstLoopContext), break_targets: *std.ArrayListUnmanaged(usize), statement_index: *usize) CompileError!void {
    if (std.mem.eql(u8, control.keyword, "for")) {
        const iterable = control.iterable orelse return error.InvalidExpression;
        const target = control.target orelse return error.InvalidExpression;
        const collection_name = try std.fmt.allocPrint(self.allocator, "__ast_for_collection_{d}", .{names.items.len});
        const index_name = try std.fmt.allocPrint(self.allocator, "__ast_for_index_{d}", .{names.items.len});
        const collection_slot = try helpers.localSlot(names, self.allocator, collection_name);
        const index_slot = try helpers.localSlot(names, self.allocator, index_name);
        if (@as(usize, iterable) < module.expressions.items.len and module.expressions.items[iterable].kind == .call) {
            const range_call = module.expressions.items[iterable].kind.call;
            if (@as(usize, range_call.callee) < module.expressions.items.len and module.expressions.items[range_call.callee].kind == .name) {
                const range_name = module.expressions.items[range_call.callee].kind.name;
                const is_range = std.mem.eql(u8, range_name, if (self.language == .kn) "shreni" else "range") or std.mem.eql(u8, range_name, "range");
                if (is_range and range_call.arg_count >= 1 and range_call.arg_count <= 3) {
                    const current_name = try std.fmt.allocPrint(self.allocator, "__ast_range_current_{d}", .{names.items.len});
                    const limit_name = try std.fmt.allocPrint(self.allocator, "__ast_range_limit_{d}", .{names.items.len});
                    const step_name = try std.fmt.allocPrint(self.allocator, "__ast_range_step_{d}", .{names.items.len});
                    const current_slot = try helpers.localSlot(names, self.allocator, current_name);
                    const limit_slot = try helpers.localSlot(names, self.allocator, limit_name);
                    const step_slot = try helpers.localSlot(names, self.allocator, step_name);
                    if (range_call.first_arg > module.call_args.items.len or range_call.arg_count > module.call_args.items.len - range_call.first_arg) return error.InvalidExpression;
                    const range_args = module.call_args.items[range_call.first_arg .. range_call.first_arg + range_call.arg_count];
                    if (range_call.arg_count == 1) try chunk.emit(.{ .op = .constant, .operand = 0 }) else try self.compileAstExpression(chunk, module, range_args[0], names);
                    try chunk.emit(.{ .op = .store_local, .operand = @intCast(current_slot) });
                    try chunk.emit(.{ .op = .pop });
                    const limit_argument: usize = if (range_call.arg_count == 1) 0 else 1;
                    try self.compileAstExpression(chunk, module, range_args[limit_argument], names);
                    try chunk.emit(.{ .op = .store_local, .operand = @intCast(limit_slot) });
                    try chunk.emit(.{ .op = .pop });
                    if (range_call.arg_count == 3) try self.compileAstExpression(chunk, module, range_args[2], names) else try chunk.emit(.{ .op = .constant, .operand = 1 });
                    try chunk.emit(.{ .op = .store_local, .operand = @intCast(step_slot) });
                    try chunk.emit(.{ .op = .pop });
                    const loop_start = chunk.code.items.len;
                    try chunk.emit(.{ .op = .load_local, .operand = @intCast(current_slot) });
                    try chunk.emit(.{ .op = .load_local, .operand = @intCast(limit_slot) });
                    try chunk.emit(.{ .op = .load_local, .operand = @intCast(step_slot) });
                    try chunk.emit(.{ .op = .range_condition });
                    const exit_jump = chunk.code.items.len;
                    try chunk.emit(.{ .op = .jump_if_false, .operand = 0 });
                    const target_slot = try helpers.localSlot(names, self.allocator, target);
                    try chunk.emit(.{ .op = .load_local, .operand = @intCast(current_slot) });
                    try chunk.emit(.{ .op = .store_local, .operand = @intCast(target_slot) });
                    try chunk.emit(.{ .op = .pop });
                    const break_first = break_targets.items.len;
                    const continue_first = if (self.ast_state.continue_targets) |targets| targets.items.len else 0;
                    try loops.append(self.allocator, .{ .continue_target = std.math.maxInt(usize), .breaks_first = break_first, .continues_first = continue_first });
                    try self.compileAstStatements(chunk, module, control.body_first, control.body_count, names, true, loops, break_targets);
                    _ = loops.pop();
                    const increment_start = chunk.code.items.len;
                    if (self.ast_state.continue_targets) |targets| {
                        for (targets.items[continue_first..]) |target_jump| chunk.code.items[target_jump].operand = @intCast(increment_start);
                        targets.shrinkRetainingCapacity(continue_first);
                    }
                    const packed_slots = (@as(i64, @intCast(current_slot)) << 32) | @as(i64, @intCast(step_slot));
                    try chunk.emit(.{ .op = .range_step, .operand = packed_slots });
                    try chunk.emit(.{ .op = .jump, .operand = @intCast(loop_start) });
                    chunk.code.items[exit_jump].operand = @intCast(chunk.code.items.len);
                    for (break_targets.items[break_first..]) |target_jump| chunk.code.items[target_jump].operand = @intCast(chunk.code.items.len);
                    break_targets.shrinkRetainingCapacity(break_first);
                    statement_index.* = @max(statement_index.* + 1, control.body_first + control.body_count);
                    statement_index.* -= 1;
                    return;
                }
            }
        }
        if (@as(usize, iterable) < module.expressions.items.len and module.expressions.items[iterable].kind == .integer) {
            const current_name = try std.fmt.allocPrint(self.allocator, "__ast_range_current_{d}", .{names.items.len});
            const limit_name = try std.fmt.allocPrint(self.allocator, "__ast_range_limit_{d}", .{names.items.len});
            const step_name = try std.fmt.allocPrint(self.allocator, "__ast_range_step_{d}", .{names.items.len});
            const current_slot = try helpers.localSlot(names, self.allocator, current_name);
            const limit_slot = try helpers.localSlot(names, self.allocator, limit_name);
            const step_slot = try helpers.localSlot(names, self.allocator, step_name);
            try chunk.emit(.{ .op = .constant, .operand = 0 });
            try chunk.emit(.{ .op = .store_local, .operand = @intCast(current_slot) });
            try chunk.emit(.{ .op = .pop });
            try self.compileAstExpression(chunk, module, iterable, names);
            try chunk.emit(.{ .op = .store_local, .operand = @intCast(limit_slot) });
            try chunk.emit(.{ .op = .pop });
            try chunk.emit(.{ .op = .constant, .operand = 1 });
            try chunk.emit(.{ .op = .store_local, .operand = @intCast(step_slot) });
            try chunk.emit(.{ .op = .pop });
            const loop_start = chunk.code.items.len;
            try chunk.emit(.{ .op = .load_local, .operand = @intCast(current_slot) });
            try chunk.emit(.{ .op = .load_local, .operand = @intCast(limit_slot) });
            try chunk.emit(.{ .op = .load_local, .operand = @intCast(step_slot) });
            try chunk.emit(.{ .op = .range_condition });
            const exit_jump = chunk.code.items.len;
            try chunk.emit(.{ .op = .jump_if_false, .operand = 0 });
            const target_slot = try helpers.localSlot(names, self.allocator, target);
            try chunk.emit(.{ .op = .load_local, .operand = @intCast(current_slot) });
            try chunk.emit(.{ .op = .store_local, .operand = @intCast(target_slot) });
            try chunk.emit(.{ .op = .pop });
            const break_first = break_targets.items.len;
            const continue_first = if (self.ast_state.continue_targets) |targets| targets.items.len else 0;
            try loops.append(self.allocator, .{ .continue_target = std.math.maxInt(usize), .breaks_first = break_first });
            try self.compileAstStatements(chunk, module, control.body_first, control.body_count, names, true, loops, break_targets);
            _ = loops.pop();
            const increment_start = chunk.code.items.len;
            if (self.ast_state.continue_targets) |targets| {
                for (targets.items[continue_first..]) |target_jump| chunk.code.items[target_jump].operand = @intCast(increment_start);
                targets.shrinkRetainingCapacity(continue_first);
            }
            try chunk.emit(.{ .op = .range_step, .operand = (@as(i64, @intCast(current_slot)) << 32) | @as(i64, @intCast(step_slot)) });
            try chunk.emit(.{ .op = .jump, .operand = @intCast(loop_start) });
            chunk.code.items[exit_jump].operand = @intCast(chunk.code.items.len);
            for (break_targets.items[break_first..]) |target_jump| chunk.code.items[target_jump].operand = @intCast(chunk.code.items.len);
            break_targets.shrinkRetainingCapacity(break_first);
            statement_index.* = @max(statement_index.* + 1, control.body_first + control.body_count);
            statement_index.* -= 1;
            return;
        }
        try self.compileAstExpression(chunk, module, iterable, names);
        try chunk.emit(.{ .op = .iterable });
        try chunk.emit(.{ .op = .store_local, .operand = @intCast(collection_slot) });
        try chunk.emit(.{ .op = .pop });
        try chunk.emit(.{ .op = .constant, .operand = 0 });
        try chunk.emit(.{ .op = .store_local, .operand = @intCast(index_slot) });
        try chunk.emit(.{ .op = .pop });
        const loop_start = chunk.code.items.len;
        try chunk.emit(.{ .op = .load_local, .operand = @intCast(index_slot) });
        try chunk.emit(.{ .op = .load_local, .operand = @intCast(collection_slot) });
        try chunk.emit(.{ .op = .length });
        try chunk.emit(.{ .op = .less });
        const exit_jump = chunk.code.items.len;
        try chunk.emit(.{ .op = .jump_if_false, .operand = 0 });
        try chunk.emit(.{ .op = .load_local, .operand = @intCast(collection_slot) });
        try chunk.emit(.{ .op = .load_local, .operand = @intCast(index_slot) });
        try chunk.emit(.{ .op = .index });
        const target_slot = try helpers.localSlot(names, self.allocator, target);
        try chunk.emit(.{ .op = .store_local, .operand = @intCast(target_slot) });
        try chunk.emit(.{ .op = .pop });
        const break_first = break_targets.items.len;
        const continue_first = if (self.ast_state.continue_targets) |targets| targets.items.len else 0;
        try loops.append(self.allocator, .{ .continue_target = std.math.maxInt(usize), .breaks_first = break_first, .continues_first = continue_first });
        try self.compileAstStatements(chunk, module, control.body_first, control.body_count, names, true, loops, break_targets);
        _ = loops.pop();
        const increment_start = chunk.code.items.len;
        if (self.ast_state.continue_targets) |targets| {
            for (targets.items[continue_first..]) |target_jump| chunk.code.items[target_jump].operand = @intCast(increment_start);
            targets.shrinkRetainingCapacity(continue_first);
        }
        try chunk.emit(.{ .op = .load_local, .operand = @intCast(index_slot) });
        try chunk.emit(.{ .op = .constant, .operand = 1 });
        try chunk.emit(.{ .op = .add });
        try chunk.emit(.{ .op = .store_local, .operand = @intCast(index_slot) });
        try chunk.emit(.{ .op = .pop });
        try chunk.emit(.{ .op = .jump, .operand = @intCast(loop_start) });
        chunk.code.items[exit_jump].operand = @intCast(chunk.code.items.len);
        for (break_targets.items[break_first..]) |target_jump| chunk.code.items[target_jump].operand = @intCast(chunk.code.items.len);
        break_targets.shrinkRetainingCapacity(break_first);
    } else if (std.mem.eql(u8, control.keyword, "if") or std.mem.eql(u8, control.keyword, "elif")) {
        const condition = control.condition orelse return error.InvalidExpression;
        try self.compileAstExpression(chunk, module, condition, names);
        const false_jump = chunk.code.items.len;
        try chunk.emit(.{ .op = .jump_if_false, .operand = 0 });
        try self.compileAstStatements(chunk, module, control.body_first, control.body_count, names, true, loops, break_targets);
        if (control.else_count != 0) {
            const end_jump = chunk.code.items.len;
            try chunk.emit(.{ .op = .jump, .operand = 0 });
            chunk.code.items[false_jump].operand = @intCast(chunk.code.items.len);
            try self.compileAstStatements(chunk, module, control.else_first, control.else_count, names, true, loops, break_targets);
            chunk.code.items[end_jump].operand = @intCast(chunk.code.items.len);
        } else chunk.code.items[false_jump].operand = @intCast(chunk.code.items.len);
    } else if (std.mem.eql(u8, control.keyword, "while")) {
        const loop_start = chunk.code.items.len;
        const condition = control.condition orelse return error.InvalidExpression;
        try self.compileAstExpression(chunk, module, condition, names);
        const exit_jump = chunk.code.items.len;
        try chunk.emit(.{ .op = .jump_if_false, .operand = 0 });
        const break_first = break_targets.items.len;
        try loops.append(self.allocator, .{ .continue_target = loop_start, .breaks_first = break_first });
        try self.compileAstStatements(chunk, module, control.body_first, control.body_count, names, true, loops, break_targets);
        _ = loops.pop();
        try chunk.emit(.{ .op = .jump, .operand = @intCast(loop_start) });
        chunk.code.items[exit_jump].operand = @intCast(chunk.code.items.len);
        for (break_targets.items[break_first..]) |target| chunk.code.items[target].operand = @intCast(chunk.code.items.len);
        break_targets.shrinkRetainingCapacity(break_first);
    } else return error.UnsupportedOperator;
    statement_index.* = @max(statement_index.* + 1, control.body_first + control.body_count);
    if (control.else_count != 0) statement_index.* = @max(statement_index.*, control.else_first + control.else_count);
    statement_index.* -= 1;
}
