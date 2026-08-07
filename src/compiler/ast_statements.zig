const std = @import("std");
const bytecode = @import("ravi_bytecode");
const ast = @import("ravi_ast");
const helpers = @import("helpers.zig");
const ast_helpers = @import("ast_helpers.zig");

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
            .function => |function| {
                if (function_index >= function_statements.items.len or function_statements.items[function_index] != index) return error.InvalidExpression;
                try chunk.emit(.{ .op = .make_function, .operand = @intCast(function_index) });
                const slot = try helpers.localSlot(names, self.allocator, function.name);
                try chunk.emit(.{ .op = .store_local, .operand = @intCast(slot) });
                try chunk.emit(.{ .op = .load_local, .operand = @intCast(slot) });
                function_index += 1;
                index = function.body_first + function.body_count;
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
                try self.compileAstStatements(chunk, module, index, 1, names, false, loops, break_targets);
                index += 1;
            },
        }
    }
}
