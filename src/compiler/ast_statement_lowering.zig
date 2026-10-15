const std = @import("std");
const bytecode = @import("ravi_bytecode");
const ast = @import("ravi_ast");
const ast_helpers = @import("ravi_ast_helpers");
const helpers = @import("helpers.zig");
const AstLoopContext = ast_helpers.LoopContext;

pub fn lower(comptime CompileError: type, self: anytype, chunk: *bytecode.Chunk, module: *const ast.Module, first: usize, count: usize, names: *std.ArrayListUnmanaged([]const u8), discard_expression: bool, loops: *std.ArrayListUnmanaged(AstLoopContext), break_targets: *std.ArrayListUnmanaged(usize)) CompileError!void {
    if (first > module.statements.items.len or count > module.statements.items.len - first) return error.InvalidExpression;
    var statement_index = first;
    while (statement_index < first + count) : (statement_index += 1) {
        const statement = module.statements.items[statement_index];
        chunk.setSourceLocation(.{ .source_id = statement.span.source_id, .start_offset = statement.span.start_offset, .end_offset = statement.span.end_offset, .line = statement.span.line, .column = 1 });
        switch (statement.kind) {
            .expression => |expression| {
                try self.compileAstExpression(chunk, module, expression, names);
                if (discard_expression) try chunk.emit(.{ .op = .pop });
            },
            .return_stmt => |expression| {
                if (expression) |value| try self.compileAstExpression(chunk, module, value, names) else try chunk.emit(.{ .op = .none_value });
                try @import("type_guards.zig").emit(chunk, self.ast_state.return_type);
                try self.compileAstFinalizers(chunk, module, names, loops, break_targets);
                try chunk.emit(.{ .op = .return_value });
            },
            .yield_stmt => |expression| {
                if (expression) |value| try self.compileAstExpression(chunk, module, value, names) else try chunk.emit(.{ .op = .none_value });
                try chunk.emit(.{ .op = .suspend_point, .operand = @intCast(statement.span.line) });
                try chunk.emit(.{ .op = .pop });
            },
            .raise_stmt => |expression| {
                if (expression) |value| try self.compileAstExpression(chunk, module, value, names) else try chunk.emit(.{ .op = .constant, .operand = 0 });
                try chunk.emit(.{ .op = .raise_value });
            },
            .function => |function| {
                var function_index: ?usize = null;
                for (self.ast_state.function_statements, 0..) |declaration_index, candidate| if (declaration_index == statement_index) {
                    function_index = candidate;
                    break;
                };
                const index = function_index orelse return error.InvalidFunction;
                const capture_info = self.ast_state.function_captures[index];
                for (capture_info.captures[0..capture_info.capture_count]) |capture| {
                    if (helpers.findLocal(names.items, capture)) |slot| {
                        try chunk.emit(.{ .op = .load_local_ref, .operand = @intCast(slot) });
                    } else if (helpers.findCapture(self.ast_state.active_captures, capture)) |capture_slot| {
                        try chunk.emit(.{ .op = .load_capture_ref, .operand = @intCast(capture_slot) });
                    } else return error.InvalidName;
                }
                try chunk.emit(.{ .op = if (capture_info.capture_count == 0) .make_function else .make_closure, .operand = @intCast(index) });
                const slot = try helpers.localSlot(names, self.allocator, function.name);
                try chunk.emit(.{ .op = .store_local, .operand = @intCast(slot) });
                try chunk.emit(.{ .op = .pop });
                statement_index = function.body_first + function.body_count;
                statement_index -= 1;
            },
            .try_stmt => |try_stmt| {
                const begin_try = chunk.code.items.len;
                try chunk.emit(.{ .op = .try_begin, .operand = 0 });
                const finalizer_first = if (self.ast_state.finalizers) |finalizer_list| finalizer_list.items.len else 0;
                if (try_stmt.finally_count != 0) if (self.ast_state.finalizers) |finalizer_list| try finalizer_list.append(self.allocator, .{ .first = try_stmt.finally_first, .count = try_stmt.finally_count });
                try self.compileAstStatements(chunk, module, try_stmt.body_first, try_stmt.body_count, names, true, loops, break_targets);
                if (self.ast_state.finalizers) |finalizer_list| finalizer_list.shrinkRetainingCapacity(finalizer_first);
                try chunk.emit(.{ .op = .try_end });
                if (try_stmt.finally_count != 0) try self.compileAstStatements(chunk, module, try_stmt.finally_first, try_stmt.finally_count, names, true, loops, break_targets);
                const skip_handler = chunk.code.items.len;
                try chunk.emit(.{ .op = .jump, .operand = 0 });
                chunk.code.items[begin_try].operand = @intCast(chunk.code.items.len);
                var no_match: ?usize = null;
                if (try_stmt.except_type) |exception_type| {
                    try chunk.emit(.{ .op = .dup });
                    const quoted = try std.fmt.allocPrint(self.allocator, "\"{s}\"", .{exception_type});
                    defer self.allocator.free(quoted);
                    const type_name = try chunk.addString(quoted);
                    try chunk.emit(.{ .op = .make_string, .operand = @intCast(type_name) });
                    try chunk.emit(.{ .op = .exception_match });
                    no_match = chunk.code.items.len;
                    try chunk.emit(.{ .op = .jump_if_false, .operand = 0 });
                } else if (try_stmt.except_match) |match| {
                    try chunk.emit(.{ .op = .dup });
                    try self.compileAstExpression(chunk, module, match, names);
                    try chunk.emit(.{ .op = .equal });
                    const match_jump = chunk.code.items.len;
                    try chunk.emit(.{ .op = .jump_if_false, .operand = 0 });
                    no_match = match_jump;
                }
                if (try_stmt.except_binding) |binding| {
                    const slot = try helpers.localSlot(names, self.allocator, binding);
                    try chunk.emit(.{ .op = .store_local, .operand = @intCast(slot) });
                }
                if (try_stmt.except_count != 0) {
                    if (try_stmt.except_binding != null or try_stmt.except_match != null) {
                        try chunk.emit(.{ .op = .pop });
                    } else {
                        try chunk.emit(.{ .op = .pop });
                    }
                    try self.compileAstStatements(chunk, module, try_stmt.except_first, try_stmt.except_count, names, true, loops, break_targets);
                } else {
                    try chunk.emit(.{ .op = .raise_value });
                }
                if (try_stmt.finally_count != 0) try self.compileAstStatements(chunk, module, try_stmt.finally_first, try_stmt.finally_count, names, true, loops, break_targets);
                if (no_match) |match_jump| {
                    const matched_end = chunk.code.items.len;
                    try chunk.emit(.{ .op = .jump, .operand = 0 });
                    chunk.code.items[match_jump].operand = @intCast(chunk.code.items.len);
                    try chunk.emit(.{ .op = .raise_value });
                    chunk.code.items[matched_end].operand = @intCast(chunk.code.items.len);
                }
                chunk.code.items[skip_handler].operand = @intCast(chunk.code.items.len);
                statement_index = @max(statement_index + 1, try_stmt.body_first + try_stmt.body_count);
                if (try_stmt.except_count != 0) statement_index = @max(statement_index, try_stmt.except_first + try_stmt.except_count);
                if (try_stmt.finally_count != 0) statement_index = @max(statement_index, try_stmt.finally_first + try_stmt.finally_count);
                statement_index -= 1;
            },
            .transfer => |transfer_keyword| {
                if (std.mem.eql(u8, transfer_keyword, "pass")) {
                    // Intentional no-op statement.
                } else if (std.mem.eql(u8, transfer_keyword, "break")) {
                    if (loops.items.len == 0) return error.UnsupportedOperator;
                    try self.compileAstFinalizers(chunk, module, names, loops, break_targets);
                    const jump = chunk.code.items.len;
                    try chunk.emit(.{ .op = .jump, .operand = 0 });
                    try break_targets.append(self.allocator, jump);
                } else if (std.mem.eql(u8, transfer_keyword, "continue")) {
                    if (loops.items.len == 0) return error.UnsupportedOperator;
                    try self.compileAstFinalizers(chunk, module, names, loops, break_targets);
                    const context = loops.items[loops.items.len - 1];
                    const jump = chunk.code.items.len;
                    const pending = context.continue_target == std.math.maxInt(usize);
                    try chunk.emit(.{ .op = .jump, .operand = if (pending) 0 else @intCast(context.continue_target) });
                    if (pending) if (self.ast_state.continue_targets) |targets| try targets.append(self.allocator, jump);
                } else return error.UnsupportedOperator;
            },
            .control => |control| try @import("ast_control_flow.zig").lower(CompileError, self, chunk, module, control, names, loops, break_targets, &statement_index),
            else => return error.UnsupportedOperator,
        }
    }
}
