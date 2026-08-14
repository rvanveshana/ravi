const std = @import("std");
const bytecode = @import("ravi_bytecode");
const ast = @import("ravi_ast");
const helpers = @import("helpers.zig");

pub fn expression(comptime Error: type, self: anytype, chunk: *bytecode.Chunk, module: *const ast.Module, expression_id: ast.ExprId, names: *std.ArrayListUnmanaged([]const u8), lambda: anytype) Error!void {
    for (self.ast_state.lambdas, 0..) |info, lambda_index| if (info.expression == expression_id) {
        if (info.params_first != lambda.params_first or info.params_count != lambda.params_count or info.body != lambda.body) return error.InvalidExpression;
        for (info.captures[0..info.capture_count]) |capture| {
            if (helpers.findLocal(names.items, capture)) |slot| {
                try chunk.emit(.{ .op = .load_local, .operand = @intCast(slot) });
            } else if (helpers.findCapture(self.ast_state.active_captures, capture)) |capture_slot| {
                try chunk.emit(.{ .op = .load_capture_ref, .operand = @intCast(capture_slot) });
            } else return error.InvalidName;
        }
        if (info.capture_count == 0) try chunk.emit(.{ .op = .make_function, .operand = @intCast(self.ast_state.function_count + lambda_index) }) else try chunk.emit(.{ .op = .make_closure, .operand = @intCast(self.ast_state.function_count + lambda_index) });
        return;
    };
    _ = module;
    return error.InvalidFunction;
}
