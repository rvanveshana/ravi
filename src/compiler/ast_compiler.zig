const std = @import("std");
const method_catalog = @import("ravi_hir").builtins;
const bytecode = @import("ravi_bytecode");
const ast = @import("ravi_ast");
const helpers = @import("helpers.zig");
const builtins = @import("builtins.zig");
const lambda_lowering = @import("ast_lambda_lowering.zig");
pub fn expression(comptime Error: type, self: anytype, chunk: *bytecode.Chunk, module: *const ast.Module, expression_id: ast.ExprId, names: *std.ArrayListUnmanaged([]const u8)) Error!void {
    if (@as(usize, expression_id) >= module.expressions.items.len) return error.InvalidExpression;
    const expression_value = module.expressions.items[expression_id];
    const language = expression_value.language orelse self.language;
    self.last_location = .{ .source_id = expression_value.span.source_id, .start_offset = expression_value.span.start_offset, .end_offset = expression_value.span.end_offset, .line = expression_value.span.line, .column = 1 };
    const previous_location = chunk.current_location;
    chunk.setSourceLocation(self.last_location);
    defer chunk.setSourceLocation(previous_location);
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
        .none => try chunk.emit(.{ .op = .none_value }),
        .assignment => |assignment| {
            if (assignment.target) |target| {
                const member = if (@as(usize, target) < module.expressions.items.len) module.expressions.items[target].kind else return error.InvalidExpression;
                if (member == .index) {
                    try expression(Error, self, chunk, module, member.index.object, names);
                    try expression(Error, self, chunk, module, member.index.index, names);
                    try expression(Error, self, chunk, module, assignment.value, names);
                    const slot = names.items.len;
                    try names.append(self.allocator, "");
                    try chunk.emit(.{ .op = .store_local, .operand = @intCast(slot) });
                    try chunk.emit(.{ .op = .store_index });
                    try chunk.emit(.{ .op = .load_local, .operand = @intCast(slot) });
                    return;
                }
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
                if (!assignment.array_type) try @import("type_guards.zig").emit(chunk, assignment.annotation);
                if (helpers.findCapture(self.ast_state.active_captures, assignment.name)) |capture| {
                    try chunk.emit(.{ .op = .store_capture, .operand = @intCast(capture) });
                } else {
                    const slot = try helpers.localSlot(names, self.allocator, assignment.name);
                    try chunk.emit(.{ .op = .store_local, .operand = @intCast(slot) });
                }
            }
        },
        .name => |name| {
            if (helpers.findLocal(names.items, name)) |slot| {
                try chunk.emit(.{ .op = .load_local, .operand = @intCast(slot) });
            } else if (helpers.findCapture(self.ast_state.active_captures, name)) |capture| {
                try chunk.emit(.{ .op = .load_capture, .operand = @intCast(capture) });
            } else if ((std.mem.eql(u8, name, "guru") or std.mem.eql(u8, name, "super")) and helpers.findLocal(names.items, "tanna") != null) {
                try chunk.emit(.{ .op = .load_local, .operand = @intCast(helpers.findLocal(names.items, "tanna").?) });
            } else if (!try builtins.functionReference(Error, self, chunk, module, name)) return error.InvalidName;
        },
        .spawn => |operand| {
            if (@as(usize, operand) >= module.expressions.items.len) return error.InvalidExpression;
            const call = switch (module.expressions.items[operand].kind) {
                .call => |value| value,
                else => return error.InvalidExpression,
            };
            if (call.keyword_count != 0 or call.first_arg > module.call_args.items.len or call.arg_count > module.call_args.items.len - call.first_arg) return error.InvalidExpression;
            try expression(Error, self, chunk, module, call.callee, names);
            for (module.call_args.items[call.first_arg .. call.first_arg + call.arg_count]) |argument| try expression(Error, self, chunk, module, argument, names);
            try chunk.emit(.{ .op = .spawn, .operand = @intCast(call.arg_count) });
        },
        .wait => |operand| {
            try expression(Error, self, chunk, module, operand, names);
            try chunk.emit(.{ .op = .wait });
        },
        .member => |member| {
            try expression(Error, self, chunk, module, member.object, names);
            const property = try chunk.addString(member.name);
            try chunk.emit(.{ .op = .get_property, .operand = @intCast(property) });
        },
        .unary => |unary| {
            try expression(Error, self, chunk, module, unary.operand, names);
            try chunk.emit(.{ .op = switch (unary.op) {
                .negate => .negate,
                .not => .not,
            } });
        },
        .binary => |binary| try @import("ast_binary.zig").lower(Error, self, chunk, module, binary, names, expression),
        .array => |value| try @import("ast_collections.zig").lower(Error, self, chunk, module, value.first, value.count, .make_array, names, expression),
        .tuple => |value| try @import("ast_collections.zig").lower(Error, self, chunk, module, value.first, value.count, .make_tuple, names, expression),
        .set => |value| try @import("ast_collections.zig").lower(Error, self, chunk, module, value.first, value.count, .make_set, names, expression),
        .map => |value| try @import("ast_collections.zig").lower(Error, self, chunk, module, value.first, value.count, .make_dict, names, expression),
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
            if (call.first_arg > module.call_args.items.len or call.arg_count > module.call_args.items.len - call.first_arg) return error.InvalidExpression;
            if (call.callee >= module.expressions.items.len) return error.InvalidExpression;
            if (module.expressions.items[call.callee].kind == .name) {
                const name = module.expressions.items[call.callee].kind.name;
                if (try builtins.hostCall(Error, self, chunk, module, name, call, names, expression)) return;
                if (builtins.isPrint(language, name)) {
                    if (call.arg_count != 1) return error.UnsupportedOperator;
                    try expression(Error, self, chunk, module, module.call_args.items[call.first_arg], names);
                    try chunk.emit(.{ .op = .print });
                    try chunk.emit(.{ .op = .constant, .operand = 0 });
                    return;
                }
                if (builtins.isType(language, name)) {
                    if (call.arg_count != 1) return error.UnsupportedOperator;
                    try expression(Error, self, chunk, module, module.call_args.items[call.first_arg], names);
                    try chunk.emit(.{ .op = .type_query });
                    return;
                }
                if (builtins.isSleep(language, name)) {
                    if (call.arg_count != 1) return error.UnsupportedOperator;
                    try expression(Error, self, chunk, module, module.call_args.items[call.first_arg], names);
                    try chunk.emit(.{ .op = .sleep });
                    return;
                }
                if (std.mem.eql(u8, name, "__ravi_exception")) {
                    if (call.arg_count != 1) return error.InvalidFunction;
                    try expression(Error, self, chunk, module, module.call_args.items[call.first_arg], names);
                    try chunk.emit(.{ .op = .make_exception });
                    return;
                }
                if (helpers.findLocal(names.items, name) == null and self.findAstFunction(module, name) == null and (std.mem.eql(u8, name, "add") or std.mem.eql(u8, name, "sub") or std.mem.eql(u8, name, "mul") or std.mem.eql(u8, name, "div") or std.mem.eql(u8, name, "mod"))) {
                    if (call.arg_count != 2) return error.InvalidFunction;
                    for (module.call_args.items[call.first_arg .. call.first_arg + call.arg_count]) |argument_id| try expression(Error, self, chunk, module, argument_id, names);
                    const op: bytecode.OpCode = if (std.mem.eql(u8, name, "add")) .add else if (std.mem.eql(u8, name, "sub")) .subtract else if (std.mem.eql(u8, name, "mul")) .multiply else if (std.mem.eql(u8, name, "div")) .divide else .modulo;
                    try chunk.emit(.{ .op = op });
                    return;
                }
                if (helpers.findLocal(names.items, name)) |slot| {
                    try chunk.emit(.{ .op = .load_local, .operand = @intCast(slot) });
                    if (self.findAstFunction(module, name)) |function_index| {
                        const function_info = chunk.functions.items[function_index];
                        if (function_info.varargs_index != null or function_info.kwargs_index != null) {
                            const positional_count = call.arg_count -| call.keyword_count;
                            if (positional_count < function_info.fixed_count) return error.InvalidFunction;
                            const positional_args = module.call_args.items[call.first_arg .. call.first_arg + positional_count];
                            for (positional_args[0..function_info.fixed_count]) |argument_id| try expression(Error, self, chunk, module, argument_id, names);
                            if (function_info.varargs_index) |varargs_index| {
                                if (varargs_index != function_info.fixed_count) return error.InvalidFunction;
                                for (positional_args[function_info.fixed_count..]) |argument_id| try expression(Error, self, chunk, module, argument_id, names);
                                try chunk.emit(.{ .op = .make_tuple, .operand = @intCast(positional_count - function_info.fixed_count) });
                            } else if (positional_count != function_info.fixed_count) return error.InvalidFunction;
                            if (function_info.kwargs_index) |kwargs_index| {
                                if (kwargs_index != function_info.fixed_count + @intFromBool(function_info.varargs_index != null)) return error.InvalidFunction;
                                const keyword_values = module.call_args.items[call.first_arg + positional_count .. call.first_arg + call.arg_count];
                                if (call.keyword_first + call.keyword_count > module.call_keywords.items.len) return error.InvalidExpression;
                                for (module.call_keywords.items[call.keyword_first .. call.keyword_first + call.keyword_count], keyword_values) |keyword, argument_id| {
                                    const quoted = try self.allocator.alloc(u8, keyword.len + 2);
                                    defer self.allocator.free(quoted);
                                    quoted[0] = '"';
                                    @memcpy(quoted[1 .. quoted.len - 1], keyword);
                                    quoted[quoted.len - 1] = '"';
                                    const key = try chunk.addString(quoted);
                                    try chunk.emit(.{ .op = .make_string, .operand = @intCast(key) });
                                    try expression(Error, self, chunk, module, argument_id, names);
                                }
                                try chunk.emit(.{ .op = .make_dict, .operand = @intCast(call.keyword_count) });
                            } else if (call.keyword_count != 0) return error.UnsupportedOperator;
                            try chunk.emit(.{ .op = .call_value, .operand = @intCast(function_info.arity) });
                            return;
                        }
                    }
                    for (module.call_args.items[call.first_arg .. call.first_arg + call.arg_count]) |argument_id| try expression(Error, self, chunk, module, argument_id, names);
                    try chunk.emit(.{ .op = .call_value, .operand = @intCast(call.arg_count) });
                    return;
                }
                if (self.findAstFunction(module, name)) |function_index| {
                    const function_info = chunk.functions.items[function_index];
                    const positional_count = call.arg_count -| call.keyword_count;
                    if (call.keyword_count != 0 and function_info.kwargs_index == null) return error.UnsupportedOperator;
                    const fixed_count = function_info.fixed_count;
                    if (positional_count < fixed_count) return error.InvalidFunction;
                    const positional_args = module.call_args.items[call.first_arg .. call.first_arg + positional_count];
                    for (positional_args[0..fixed_count]) |argument_id| try expression(Error, self, chunk, module, argument_id, names);
                    if (function_info.varargs_index) |varargs_index| {
                        const extra_count = positional_count - fixed_count;
                        if (varargs_index != fixed_count) return error.InvalidFunction;
                        for (positional_args[fixed_count..]) |argument_id| try expression(Error, self, chunk, module, argument_id, names);
                        try chunk.emit(.{ .op = .make_tuple, .operand = @intCast(extra_count) });
                    } else if (positional_count != fixed_count) return error.InvalidFunction;
                    if (function_info.kwargs_index) |kwargs_index| {
                        if (kwargs_index != fixed_count + @intFromBool(function_info.varargs_index != null)) return error.InvalidFunction;
                        const keyword_values = module.call_args.items[call.first_arg + positional_count .. call.first_arg + call.arg_count];
                        if (call.keyword_first + call.keyword_count > module.call_keywords.items.len) return error.InvalidExpression;
                        for (module.call_keywords.items[call.keyword_first .. call.keyword_first + call.keyword_count], keyword_values) |keyword, argument_id| {
                            const key = try chunk.addString(keyword);
                            try chunk.emit(.{ .op = .make_string, .operand = @intCast(key) });
                            try expression(Error, self, chunk, module, argument_id, names);
                        }
                        try chunk.emit(.{ .op = .make_dict, .operand = @intCast(call.keyword_count) });
                    } else if (call.keyword_count != 0) return error.UnsupportedOperator;
                    try chunk.emit(.{ .op = .call, .operand = @intCast(function_index) });
                    return;
                }
                var class_index: ?usize = null;
                var class_cursor: usize = 0;
                for (module.statements.items) |statement| switch (statement.kind) {
                    .class_decl => |class_decl| {
                        if (std.mem.eql(u8, class_decl.name, name)) class_index = class_cursor;
                        class_cursor += 1;
                    },
                    else => {},
                };
                if (class_index) |resolved_class_index| {
                    try chunk.emit(.{ .op = .make_instance, .operand = @intCast(resolved_class_index) });
                    for (chunk.methods.items) |method| if (method.class_index == resolved_class_index and (std.mem.eql(u8, method.name, "huttu") or std.mem.eql(u8, method.name, "init"))) {
                        if (call.arg_count != chunk.functions.items[method.function_index].arity) return error.InvalidFunction;
                        try chunk.emit(.{ .op = .dup });
                        for (module.call_args.items[call.first_arg .. call.first_arg + call.arg_count]) |argument_id| try expression(Error, self, chunk, module, argument_id, names);
                        try chunk.emit(.{ .op = .call_method, .operand = @intCast(method.function_index) });
                        try chunk.emit(.{ .op = .pop });
                        return;
                    };
                    if (call.arg_count != 0) return error.InvalidFunction;
                    return;
                }
            }
            if (module.expressions.items[call.callee].kind == .member) {
                const member = module.expressions.items[call.callee].kind.member;
                try expression(Error, self, chunk, module, member.object, names);
                for (module.call_args.items[call.first_arg .. call.first_arg + call.arg_count]) |argument_id| try expression(Error, self, chunk, module, argument_id, names);
                const method = member.name;
                if (method_catalog.resolve(method, language, call.arg_count)) |method_index| {
                    const info = method_catalog.methods[method_index];
                    if (call.arg_count != info.arguments or call.keyword_count != 0) return error.InvalidFunction;
                    try chunk.emit(.{ .op = std.meta.stringToEnum(bytecode.OpCode, info.opcode) orelse return error.InvalidFunction, .operand = if (std.mem.eql(u8, info.opcode, "pop_collection")) @intCast(info.arguments) else 0 });
                    if (info.mutates) try chunk.emit(.{ .op = .constant, .operand = 0 });
                } else {
                    var method_index: ?usize = null;
                    for (chunk.methods.items) |method_info| if (std.mem.eql(u8, method_info.name, method) and chunk.functions.items[method_info.function_index].arity == call.arg_count) {
                        method_index = method_info.function_index;
                        break;
                    };
                    if (method_index) |function_index| {
                        for (chunk.methods.items) |info| if (info.function_index == function_index and info.visibility == 1 and helpers.findLocal(names.items, "tanna") == null) return error.PrivateAccess;
                        const object = module.expressions.items[member.object].kind;
                        const is_super = object == .name and (std.mem.eql(u8, object.name, "guru") or std.mem.eql(u8, object.name, "super"));
                        try chunk.emit(.{ .op = if (is_super) .call_super else .call_method, .operand = @intCast(function_index) });
                    } else return error.UnsupportedOperator;
                }

                return;
            }
            try expression(Error, self, chunk, module, call.callee, names);
            for (module.call_args.items[call.first_arg .. call.first_arg + call.arg_count]) |argument_id| try expression(Error, self, chunk, module, argument_id, names);
            try chunk.emit(.{ .op = .call_value, .operand = @intCast(call.arg_count) });
        },
        .lambda => |lambda| {
            try lambda_lowering.expression(Error, self, chunk, module, expression_id, names, lambda);
        },
    }
}
