const std = @import("std");
const ast = @import("ravi_ast");
const hir = @import("ravi_hir");
const calls = @import("ravi_hir_call_lowering");
fn functionIndex(module: *const ast.Module, name: []const u8) ?usize {
    var index: usize = 0;
    for (module.statements.items) |statement| switch (statement.kind) {
        .function => |function| {
            if (std.mem.eql(u8, function.name, name)) return index;
            index += 1;
        },
        else => {},
    };
    return null;
}
fn classIndex(module: *const ast.Module, name: []const u8) ?usize {
    var index: usize = 0;
    for (module.statements.items) |statement| switch (statement.kind) {
        .class_decl => |class_decl| {
            if (std.mem.eql(u8, class_decl.name, name)) return index;
            index += 1;
        },
        else => {},
    };
    return null;
}
fn methodIndex(module: *const ast.Module, class_name: []const u8, method_name: []const u8) ?usize {
    var index: usize = 0;
    for (module.statements.items) |statement| switch (statement.kind) {
        .function => |function| {
            for (module.statements.items) |owner| switch (owner.kind) {
                .class_decl => |class_decl| if (std.mem.eql(u8, class_decl.name, class_name) and function.body_first >= class_decl.body_first and function.body_first < class_decl.body_first + class_decl.body_count and std.mem.eql(u8, function.name, method_name)) return index,
                else => {},
            };
            index += 1;
        },
        else => {},
    };
    return null;
}
fn anyMethodIndex(module: *const ast.Module, method_name: []const u8) ?usize {
    var index: usize = 0;
    for (module.statements.items) |statement| switch (statement.kind) {
        .function => |function| {
            if (std.mem.eql(u8, function.name, method_name)) return index;
            index += 1;
        },
        else => {},
    };
    return null;
}
fn lambdaIndex(module: *const ast.Module, expression_id: ast.ExprId) ?usize {
    var index: usize = 0;
    for (module.expressions.items, 0..) |expression, current| if (expression.kind == .lambda) {
        if (current == @as(usize, expression_id)) return functionCount(module) + index;
        index += 1;
    };
    return null;
}
fn functionCount(module: *const ast.Module) usize {
    var count: usize = 0;
    for (module.statements.items) |statement| {
        if (statement.kind == .function) count += 1;
    }
    return count;
}
pub fn localIndex(names: []const []const u8, name: []const u8) ?usize {
    for (names, 0..) |candidate, index| if (std.mem.eql(u8, candidate, name)) return index;
    return null;
}
pub fn collectCaptures(allocator: std.mem.Allocator, module: *const ast.Module, expression_id: ast.ExprId, parameters: []const ast.Parameter, visible: []const []const u8) ![]const []const u8 {
    var captures: std.ArrayListUnmanaged([]const u8) = .empty;
    errdefer captures.deinit(allocator);
    try collectCaptureNames(allocator, module, expression_id, parameters, visible, &captures);
    return captures.toOwnedSlice(allocator);
}
fn collectCaptureNames(allocator: std.mem.Allocator, module: *const ast.Module, expression_id: ast.ExprId, parameters: []const ast.Parameter, visible: []const []const u8, captures: *std.ArrayListUnmanaged([]const u8)) !void {
    if (@as(usize, expression_id) >= module.expressions.items.len) return error.InvalidExpression;
    switch (module.expressions.items[expression_id].kind) {
        .name => |name| if (parameterRecordIndex(parameters, name) == null and localIndex(visible, name) != null and localIndex(captures.items, name) == null) try captures.append(allocator, name),
        .unary => |value| try collectCaptureNames(allocator, module, value.operand, parameters, visible, captures),
        .binary => |value| {
            try collectCaptureNames(allocator, module, value.left, parameters, visible, captures);
            try collectCaptureNames(allocator, module, value.right, parameters, visible, captures);
        },
        .call => |value| {
            try collectCaptureNames(allocator, module, value.callee, parameters, visible, captures);
            for (module.call_args.items[value.first_arg .. value.first_arg + value.arg_count]) |argument| try collectCaptureNames(allocator, module, argument, parameters, visible, captures);
        },
        .array => |value| for (value.first..value.first + value.count) |index| try collectCaptureNames(allocator, module, @intCast(index), parameters, visible, captures),
        .tuple => |value| for (value.first..value.first + value.count) |index| try collectCaptureNames(allocator, module, @intCast(index), parameters, visible, captures),
        .set => |value| for (value.first..value.first + value.count) |index| try collectCaptureNames(allocator, module, @intCast(index), parameters, visible, captures),
        .map => |value| for (value.first..value.first + value.count) |index| try collectCaptureNames(allocator, module, @intCast(index), parameters, visible, captures),
        .index => |value| {
            try collectCaptureNames(allocator, module, value.object, parameters, visible, captures);
            try collectCaptureNames(allocator, module, value.index, parameters, visible, captures);
        },
        else => {},
    }
}
pub fn lower(allocator: std.mem.Allocator, function: *hir.Function, module: *const ast.Module, expression_id: ast.ExprId, parameter_names: []const []const u8, parameter_base: ?usize, capture_names: []const []const u8) anyerror!hir.ValueId {
    if (@as(usize, expression_id) >= module.expressions.items.len) return error.InvalidExpression;
    const expression = module.expressions.items[expression_id];
    return switch (expression.kind) {
        .integer => |value| function.appendValue(.integer, .{ .constant_integer = value }, expression.span.line),
        .float => |value| function.appendValue(.float, .{ .constant_float = value }, expression.span.line),
        .string => |value| function.appendValue(.string, .{ .constant_string = value }, expression.span.line),
        .boolean => |value| function.appendValue(.boolean, .{ .constant_boolean = value }, expression.span.line),
        .none => function.appendValue(.none, .constant_none, expression.span.line),
        .name => |name| if (parameterIndex(parameter_names, name)) |slot| function.appendValue(function.parameterType((parameter_base orelse 0) + slot), .{ .parameter = (parameter_base orelse 0) + slot }, expression.span.line) else if ((std.mem.eql(u8, name, "guru") or std.mem.eql(u8, name, "super")) and parameterIndex(parameter_names, "tanna") != null) function.appendValue(function.parameterType(parameter_base orelse 0), .{ .parameter = parameter_base orelse 0 }, expression.span.line) else if (localIndex(capture_names, name)) |slot| function.appendValue(.dynamic, .{ .load_capture = slot }, expression.span.line) else if (functionIndex(module, name)) |index| function.appendValue(.dynamic, .{ .make_function = index }, expression.span.line) else error.InvalidName,
        .member => |member| {
            const object = try lower(allocator, function, module, member.object, parameter_names, parameter_base, capture_names);
            return function.appendValue(.dynamic, .{ .get_property = .{ .object = object, .name = member.name } }, expression.span.line);
        },
        .lambda => return function.appendValue(.dynamic, .{ .make_function = lambdaIndex(module, expression_id) orelse return error.InvalidFunction }, expression.span.line),
        .unary => |unary| {
            const operand = try lower(allocator, function, module, unary.operand, parameter_names, parameter_base, capture_names);
            return function.appendValue(if (unary.op == .not) .boolean else .integer, .{ .unary = .{ .operator = if (unary.op == .not) .not else .negate, .operand = operand } }, expression.span.line);
        },
        .binary => |binary| {
            const left = try lower(allocator, function, module, binary.left, parameter_names, parameter_base, capture_names);
            const right = try lower(allocator, function, module, binary.right, parameter_names, parameter_base, capture_names);
            const operator: hir.Binary = switch (binary.op) {
                .add => .add,
                .subtract => .subtract,
                .multiply => .multiply,
                .divide => .divide,
                .modulo => .modulo,
                .equal => .equal,
                .not_equal => .not_equal,
                .less => .less,
                .less_equal => .less_equal,
                .greater => .greater,
                .greater_equal => .greater_equal,
                .logic_and => .logic_and,
                .logic_or => .logic_or,
                else => return error.UnsupportedExpression,
            };
            return function.appendValue(expressionType(module, expression_id), .{ .binary = .{ .operator = operator, .left = left, .right = right } }, expression.span.line);
        },
        .array => |value| return collection(allocator, function, module, value.first, value.count, parameter_names, parameter_base, capture_names, .make_array, expression.span.line),
        .tuple => |value| return collection(allocator, function, module, value.first, value.count, parameter_names, parameter_base, capture_names, .make_tuple, expression.span.line),
        .set => |value| return collection(allocator, function, module, value.first, value.count, parameter_names, parameter_base, capture_names, .make_set, expression.span.line),
        .map => |value| return collection(allocator, function, module, value.first, value.count * 2, parameter_names, parameter_base, capture_names, .make_dict, expression.span.line),
        .index => |value| {
            const object = try lower(allocator, function, module, value.object, parameter_names, parameter_base, capture_names);
            const key = try lower(allocator, function, module, value.index, parameter_names, parameter_base, capture_names);
            return function.appendValue(.dynamic, .{ .index = .{ .object = object, .key = key } }, expression.span.line);
        },
        .call => |call| {
            const callee = switch (module.expressions.items[call.callee].kind) {
                .name => |name| name,
                else => return error.InvalidFunction,
            };
            if (isPrintName(callee)) {
                if (call.arg_count != 1) return error.InvalidFunction;
                return function.appendValue(.none, .{ .print = try lower(allocator, function, module, module.call_args.items[call.first_arg], parameter_names, parameter_base, capture_names) }, expression.span.line);
            }
            if (classIndex(module, callee)) |class_index| {
                const receiver = try function.appendValue(.dynamic, .{ .make_instance = class_index }, expression.span.line);
                const constructor = methodIndex(module, callee, "init") orelse methodIndex(module, callee, "huttu");
                if (constructor) |method| {
                    const arguments = try callArguments(allocator, function, module, call.first_arg, call.arg_count, parameter_names, parameter_base, false, &.{}, capture_names);
                    return function.appendValue(.dynamic, .{ .call_method = .{ .function = method, .receiver = receiver, .arguments = arguments, .returns_receiver = true } }, expression.span.line);
                }
                if (call.arg_count != 0) return error.InvalidFunction;
                return receiver;
            }
            const arguments = try callArguments(allocator, function, module, call.first_arg, call.arg_count, parameter_names, parameter_base, false, &.{}, capture_names);
            if (functionIndex(module, callee)) |index| return function.appendValue(.integer, .{ .call = .{ .function = index, .arguments = try calls.directArguments(allocator, function, module, callee, call, parameter_names, &.{}, capture_names, expression.span.line, lowerArgument) } }, expression.span.line);
            const callee_value = try lower(allocator, function, module, call.callee, parameter_names, parameter_base, capture_names);
            return function.appendValue(.dynamic, .{ .call_value = .{ .callee = callee_value, .arguments = arguments } }, expression.span.line);
        },
        else => error.UnsupportedExpression,
    };
}
pub fn lowerWithLocals(allocator: std.mem.Allocator, function: *hir.Function, module: *const ast.Module, expression_id: ast.ExprId, parameter_names: []const []const u8, local_names: []const []const u8, capture_names: []const []const u8) anyerror!hir.ValueId {
    if (@as(usize, expression_id) >= module.expressions.items.len) return error.InvalidExpression;
    const expression = module.expressions.items[expression_id];
    switch (expression.kind) {
        .name => |name| if (localIndex(local_names, name)) |slot| return function.appendValue(.integer, .{ .load_local = slot }, expression.span.line),
        .member => |member| {
            const object = try lowerWithLocals(allocator, function, module, member.object, parameter_names, local_names, capture_names);
            return function.appendValue(.dynamic, .{ .get_property = .{ .object = object, .name = member.name } }, expression.span.line);
        },
        .assignment => |assignment| if (assignment.target) |target| {
            const member = switch (module.expressions.items[@as(usize, target)].kind) {
                .member => |value| value,
                else => return error.UnsupportedExpression,
            };
            const object = try lowerWithLocals(allocator, function, module, member.object, parameter_names, local_names, capture_names);
            const value = try lowerWithLocals(allocator, function, module, assignment.value, parameter_names, local_names, capture_names);
            try function.appendEffect(.{ .store_property = .{ .object = object, .value = value, .name = member.name } }, expression.span.line);
            return value;
        },
        .lambda => |lambda| {
            const visible = try allocator.alloc([]const u8, local_names.len + capture_names.len);
            defer allocator.free(visible);
            @memcpy(visible[0..local_names.len], local_names);
            @memcpy(visible[local_names.len..], capture_names);
            const names = try collectCaptures(allocator, module, lambda.body, module.parameters.items[lambda.params_first .. lambda.params_first + lambda.params_count], visible);
            defer allocator.free(names);
            const captures = try allocator.alloc(hir.ValueId, names.len);
            for (names, 0..) |name, index| captures[index] = if (localIndex(local_names, name)) |slot| try function.appendValue(.dynamic, .{ .load_local = slot }, expression.span.line) else if (localIndex(capture_names, name)) |slot| try function.appendValue(.dynamic, .{ .load_capture_ref = slot }, expression.span.line) else return error.InvalidName;
            return function.appendValue(.dynamic, .{ .make_closure = .{ .function = lambdaIndex(module, expression_id) orelse return error.InvalidFunction, .captures = captures } }, expression.span.line);
        },
        else => {},
    }
    switch (expression.kind) {
        .call => |call| {
            if (module.expressions.items[call.callee].kind == .member) {
                const member = module.expressions.items[call.callee].kind.member;
                const receiver = try lowerWithLocals(allocator, function, module, member.object, parameter_names, local_names, capture_names);
                const arguments = try callArguments(allocator, function, module, call.first_arg, call.arg_count, parameter_names, local_names, true, local_names, capture_names);
                const method = anyMethodIndex(module, member.name) orelse return error.InvalidFunction;
                if (module.expressions.items[member.object].kind == .name and (std.mem.eql(u8, module.expressions.items[member.object].kind.name, "guru") or std.mem.eql(u8, module.expressions.items[member.object].kind.name, "super"))) return function.appendValue(.dynamic, .{ .call_super = .{ .function = method, .receiver = receiver, .arguments = arguments } }, expression.span.line);
                return function.appendValue(.dynamic, .{ .call_method = .{ .function = method, .receiver = receiver, .arguments = arguments } }, expression.span.line);
            }
            const callee = switch (module.expressions.items[call.callee].kind) {
                .name => |name| name,
                else => return error.InvalidFunction,
            };
            if (isPrintName(callee)) return function.appendValue(.none, .{ .print = try lowerWithLocals(allocator, function, module, module.call_args.items[call.first_arg], parameter_names, local_names, capture_names) }, expression.span.line);
            const arguments = try callArguments(allocator, function, module, call.first_arg, call.arg_count, parameter_names, local_names, true, local_names, capture_names);
            if (functionIndex(module, callee)) |index| return function.appendValue(.integer, .{ .call = .{ .function = index, .arguments = try calls.directArguments(allocator, function, module, callee, call, parameter_names, local_names, capture_names, expression.span.line, lowerLocalArgument) } }, expression.span.line);
            const callee_value = try lowerWithLocals(allocator, function, module, call.callee, parameter_names, local_names, capture_names);
            return function.appendValue(.dynamic, .{ .call_value = .{ .callee = callee_value, .arguments = arguments } }, expression.span.line);
        },
        else => {},
    }
    return lower(allocator, function, module, expression_id, parameter_names, null, capture_names);
}
fn callArguments(allocator: std.mem.Allocator, function: *hir.Function, module: *const ast.Module, first: usize, count: usize, parameters: []const []const u8, locals: anytype, with_locals: bool, local_names: []const []const u8, capture_names: []const []const u8) ![]hir.ValueId {
    const arguments = try allocator.alloc(hir.ValueId, count);
    for (module.call_args.items[first .. first + count], 0..) |argument, index| arguments[index] = if (with_locals) try lowerWithLocals(allocator, function, module, argument, parameters, local_names, capture_names) else try lower(allocator, function, module, argument, parameters, null, capture_names);
    _ = locals;
    return arguments;
}
fn lowerArgument(allocator: std.mem.Allocator, function: *hir.Function, module: *const ast.Module, argument: ast.ExprId, parameters: []const []const u8, local_names: []const []const u8, capture_names: []const []const u8) !hir.ValueId {
    _ = local_names;
    return lower(allocator, function, module, argument, parameters, null, capture_names);
}
fn lowerLocalArgument(allocator: std.mem.Allocator, function: *hir.Function, module: *const ast.Module, argument: ast.ExprId, parameters: []const []const u8, local_names: []const []const u8, capture_names: []const []const u8) !hir.ValueId {
    return lowerWithLocals(allocator, function, module, argument, parameters, local_names, capture_names);
}
fn collection(allocator: std.mem.Allocator, function: *hir.Function, module: *const ast.Module, first: usize, count: usize, parameters: []const []const u8, base: ?usize, capture_names: []const []const u8, tag: std.meta.Tag(hir.Instruction.Operation), line: usize) !hir.ValueId {
    const values = try allocator.alloc(hir.ValueId, count);
    for (values, 0..) |*value, index| value.* = try lower(allocator, function, module, @intCast(first + index), parameters, base, capture_names);
    return function.appendValue(.dynamic, switch (tag) {
        .make_array => .{ .make_array = values },
        .make_tuple => .{ .make_tuple = values },
        .make_set => .{ .make_set = values },
        .make_dict => .{ .make_dict = values },
        else => unreachable,
    }, line);
}
fn parameterIndex(names: []const []const u8, name: []const u8) ?usize {
    for (names, 0..) |candidate, index| if (std.mem.eql(u8, candidate, name)) return index;
    return null;
}
fn parameterRecordIndex(parameters: []const ast.Parameter, name: []const u8) ?usize {
    for (parameters, 0..) |parameter, index| if (std.mem.eql(u8, parameter.name, name)) return index;
    return null;
}
fn isPrintName(name: []const u8) bool {
    return std.mem.eql(u8, name, "mudrisu") or std.mem.eql(u8, name, "print");
}
fn expressionType(module: *const ast.Module, expression_id: ast.ExprId) hir.Type {
    return switch (module.expressions.items[@as(usize, expression_id)].kind) {
        .float => .float,
        .boolean => .boolean,
        .none => .none,
        .string => .string,
        .unary => |value| if (value.op == .not) .boolean else expressionType(module, value.operand),
        .binary => |value| switch (value.op) {
            .equal, .not_equal, .less, .less_equal, .greater, .greater_equal, .logic_and, .logic_or => .boolean,
            else => if (expressionType(module, value.left) == .float or expressionType(module, value.right) == .float) .float else .integer,
        },
        else => .integer,
    };
}
