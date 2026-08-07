const std = @import("std");
const bytecode = @import("ravi_bytecode");
const ast = @import("ravi_ast");
const helpers = @import("helpers.zig");
const builtins = @import("builtins.zig");

pub fn expression(comptime Error: type, self: anytype, chunk: *bytecode.Chunk, module: *const ast.Module, expression_id: ast.ExprId, names: *std.ArrayListUnmanaged([]const u8)) Error!void {
    if (@as(usize, expression_id) >= module.expressions.items.len) return error.InvalidExpression;
    const expression_value = module.expressions.items[expression_id];
    switch (expression_value.kind) {
        .integer => |value| try chunk.emit(.{ .op = .constant, .operand = value }),
        .float => |value| {
            const float_index = try chunk.addFloat(value);
            try chunk.emit(.{ .op = .make_float, .operand = @intCast(float_index) });
        },
        .string => |value| {
            const string_index = try chunk.addString(value);
            try chunk.emit(.{ .op = .make_string, .operand = @intCast(string_index) });
        },
        .formatted_string => |formatted| {
            if (formatted.first_arg + formatted.arg_count > module.format_args.items.len) return error.InvalidExpression;
            for (module.format_args.items[formatted.first_arg .. formatted.first_arg + formatted.arg_count]) |argument| try expression(Error, self, chunk, module, argument, names);
            const format_index = try chunk.addFormat(formatted.template, formatted.arg_count);
            try chunk.emit(.{ .op = .make_format, .operand = @intCast(format_index) });
        },
        .boolean => |value| try chunk.emit(.{ .op = if (value) .true_value else .false_value }),
        .none => try chunk.emit(.{ .op = .constant, .operand = 0 }),
        .assignment => |assignment| {
            if (assignment.target) |target| {
                const member = if (@as(usize, target) < module.expressions.items.len) module.expressions.items[target].kind else return error.InvalidExpression;
                const member_value = switch (member) {
                    .member => |value| value,
                    else => return error.InvalidExpression,
                };
                try expression(Error, self, chunk, module, member_value.object, names);
                try chunk.emit(.{ .op = .dup });
                try expression(Error, self, chunk, module, assignment.value, names);
                const property = try chunk.addString(member_value.name);
                try chunk.emit(.{ .op = .set_property, .operand = @intCast(property) });
                try chunk.emit(.{ .op = .get_property, .operand = @intCast(property) });
            } else {
                try expression(Error, self, chunk, module, assignment.value, names);
            }
            if (assignment.target == null) {
                if (helpers.findCapture(self.ast_state.active_captures, assignment.name)) |capture| {
                    try chunk.emit(.{ .op = .store_capture, .operand = @intCast(capture) });
                    try chunk.emit(.{ .op = .load_capture, .operand = @intCast(capture) });
                } else {
                    const slot = try helpers.localSlot(names, self.allocator, assignment.name);
                    try chunk.emit(.{ .op = .store_local, .operand = @intCast(slot) });
                    try chunk.emit(.{ .op = .load_local, .operand = @intCast(slot) });
                }
            }
        },
        .name => |name| {
            if (helpers.findLocal(names.items, name)) |slot| {
                try chunk.emit(.{ .op = .load_local, .operand = @intCast(slot) });
            } else if (helpers.findCapture(self.ast_state.active_captures, name)) |capture| {
                try chunk.emit(.{ .op = .load_capture, .operand = @intCast(capture) });
            } else return error.InvalidName;
        },
        .member => return error.UnsupportedOperator,
        .unary => |unary| {
            try expression(Error, self, chunk, module, unary.operand, names);
            try chunk.emit(.{ .op = switch (unary.op) {
                .negate => .negate,
                .not => .not,
            } });
        },
        .binary => |binary| {
            try expression(Error, self, chunk, module, binary.left, names);
            try expression(Error, self, chunk, module, binary.right, names);
            const op: bytecode.OpCode = switch (binary.op) {
                .add => .add,
                .subtract => .subtract,
                .multiply => .multiply,
                .divide => .divide,
                .equal => .equal,
                .not_equal => .not_equal,
                .less => .less,
                .less_equal => .less_equal,
                .greater => .greater,
                .greater_equal => .greater_equal,
                .logic_and => .logic_and,
                .logic_or => .logic_or,
                else => return error.UnsupportedOperator,
            };
            try chunk.emit(.{ .op = op });
        },
        .array => |array| {
            if (array.first > module.expressions.items.len or array.count > module.expressions.items.len - array.first) return error.InvalidExpression;
            for (module.expressions.items[array.first .. array.first + array.count], array.first..) |_, element_id| try expression(Error, self, chunk, module, @intCast(element_id), names);
            try chunk.emit(.{ .op = .make_array, .operand = @intCast(array.count) });
        },
        .tuple => |tuple| {
            if (tuple.first > module.expressions.items.len or tuple.count > module.expressions.items.len - tuple.first) return error.InvalidExpression;
            for (module.expressions.items[tuple.first .. tuple.first + tuple.count], tuple.first..) |_, element_id| try expression(Error, self, chunk, module, @intCast(element_id), names);
            try chunk.emit(.{ .op = .make_tuple, .operand = @intCast(tuple.count) });
        },
        .set => |set| {
            if (set.first > module.expressions.items.len or set.count > module.expressions.items.len - set.first) return error.InvalidExpression;
            for (module.expressions.items[set.first .. set.first + set.count], set.first..) |_, element_id| try expression(Error, self, chunk, module, @intCast(element_id), names);
            try chunk.emit(.{ .op = .make_set, .operand = @intCast(set.count) });
        },
        .map => |map| {
            if (map.first > module.expressions.items.len or map.count > module.expressions.items.len - map.first or map.count % 2 != 0) return error.InvalidExpression;
            for (module.expressions.items[map.first .. map.first + map.count], map.first..) |_, element_id| try expression(Error, self, chunk, module, @intCast(element_id), names);
            try chunk.emit(.{ .op = .make_dict, .operand = @intCast(map.count / 2) });
        },
        .index => |index| {
            try expression(Error, self, chunk, module, index.object, names);
            try expression(Error, self, chunk, module, index.index, names);
            try chunk.emit(.{ .op = .index });
        },
        .slice => |slice| {
            try expression(Error, self, chunk, module, slice.object, names);
            if (slice.start) |start| try expression(Error, self, chunk, module, start, names) else try chunk.emit(.{ .op = .constant, .operand = -1 });
            if (slice.end) |end| try expression(Error, self, chunk, module, end, names) else try chunk.emit(.{ .op = .constant, .operand = -1 });
            try chunk.emit(.{ .op = .slice });
        },
        .call => |call| {
            if (call.first_arg > module.expressions.items.len or call.arg_count > module.expressions.items.len - call.first_arg) return error.InvalidExpression;
            if (module.expressions.items[call.callee].kind == .member) {
                const member = module.expressions.items[call.callee].kind.member;
                if (call.arg_count != 0) return error.UnsupportedOperator;
                try expression(Error, self, chunk, module, member.object, names);
                if (builtins.method(self.language, member.name, "keys", "kili")) try chunk.emit(.{ .op = .dict_keys }) else if (builtins.method(self.language, member.name, "values", "bele")) try chunk.emit(.{ .op = .dict_values }) else if (builtins.method(self.language, member.name, "items", "jodi")) try chunk.emit(.{ .op = .dict_items }) else return error.UnsupportedOperator;
                return;
            }
            try expression(Error, self, chunk, module, call.callee, names);
            for (module.expressions.items[call.first_arg .. call.first_arg + call.arg_count], call.first_arg..) |_, argument_id| try expression(Error, self, chunk, module, @intCast(argument_id), names);
            try chunk.emit(.{ .op = .call_value, .operand = @intCast(call.arg_count) });
        },
        .lambda => |lambda| {
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
            return error.InvalidFunction;
        },
    }
}
