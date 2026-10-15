const std = @import("std");
const bytecode = @import("ravi_bytecode");
const ast = @import("ravi_ast");
const helpers = @import("helpers.zig");
const ast_helpers = @import("ravi_ast_helpers");

pub fn finalizers(comptime Error: type, self: anytype, chunk: *bytecode.Chunk, module: *const ast.Module, names: *std.ArrayListUnmanaged([]const u8), loops: *std.ArrayListUnmanaged(ast_helpers.LoopContext), break_targets: *std.ArrayListUnmanaged(usize)) Error!void {
    const finalizer_list = self.ast_state.finalizers orelse return;
    const original_limit = self.ast_state.finalizer_limit;
    const limit = @min(original_limit orelse finalizer_list.items.len, finalizer_list.items.len);
    var index = limit;
    while (index > 0) {
        index -= 1;
        const finalizer = finalizer_list.items[index];
        self.ast_state.finalizer_limit = index;
        try self.compileAstStatements(chunk, module, finalizer.first, finalizer.count, names, true, loops, break_targets);
    }
    self.ast_state.finalizer_limit = original_limit;
}

pub fn topLevel(comptime Error: type, self: anytype, chunk: *bytecode.Chunk, module: *const ast.Module, names: *std.ArrayListUnmanaged([]const u8), function_statements: *const std.ArrayListUnmanaged(usize), loops: *std.ArrayListUnmanaged(ast_helpers.LoopContext), break_targets: *std.ArrayListUnmanaged(usize)) Error!void {
    var index: usize = 0;
    var function_index: usize = 0;
    while (index < module.statements.items.len) {
        const statement = module.statements.items[index];
        switch (statement.kind) {
            .import => return error.InvalidName,
            .function => |function| {
                if (function_index >= function_statements.items.len or function_statements.items[function_index] != index) return error.InvalidExpression;
                const capture_info = self.ast_state.function_captures[function_index];
                for (capture_info.captures[0..capture_info.capture_count]) |capture| {
                    if (helpers.findLocal(names.items, capture)) |slot| try chunk.emit(.{ .op = .load_local_ref, .operand = @intCast(slot) }) else if (helpers.findCapture(self.ast_state.active_captures, capture)) |capture_slot| try chunk.emit(.{ .op = .load_capture_ref, .operand = @intCast(capture_slot) }) else return error.InvalidName;
                }
                try chunk.emit(.{ .op = if (capture_info.capture_count == 0) .make_function else .make_closure, .operand = @intCast(function_index) });
                const slot = try helpers.localSlot(names, self.allocator, function.name);
                try chunk.emit(.{ .op = .store_local, .operand = @intCast(slot) });
                try chunk.emit(.{ .op = .pop });
                function_index += 1;
                index = function.body_first + function.body_count;
            },
            .class_decl => |class_decl| {
                while (function_index < function_statements.items.len and function_statements.items[function_index] < class_decl.body_first + class_decl.body_count) function_index += 1;
                index = @max(index + 1, class_decl.body_first + class_decl.body_count);
            },
            .control => |control| {
                try self.compileAstStatements(chunk, module, index, 1, names, false, loops, break_targets);
                index = @max(index + 1, control.body_first + control.body_count);
                if (control.else_count != 0) index = @max(index, control.else_first + control.else_count);
            },
            .try_stmt => |try_stmt| {
                try self.compileAstStatements(chunk, module, index, 1, names, false, loops, break_targets);
                index = @max(index + 1, try_stmt.body_first + try_stmt.body_count);
                if (try_stmt.except_count != 0) index = @max(index, try_stmt.except_first + try_stmt.except_count);
                if (try_stmt.finally_count != 0) index = @max(index, try_stmt.finally_first + try_stmt.finally_count);
            },
            else => {
                try self.compileAstStatements(chunk, module, index, 1, names, index + 1 != module.statements.items.len, loops, break_targets);
                index += 1;
            },
        }
    }
}
