const std = @import("std");
const ast = @import("ravi_ast");
const helpers = @import("ravi_hir_pipeline_helpers");
const lowering = @import("ravi_hir_lowering");

pub fn classIndex(module: *const ast.Module, name: []const u8) ?usize {
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

pub fn methodOwner(module: *const ast.Module, body_first: usize) ?void {
    for (module.statements.items) |statement| switch (statement.kind) {
        .class_decl => |class_decl| if (body_first >= class_decl.body_first and body_first < class_decl.body_first + class_decl.body_count) return {},
        else => {},
    };
    return null;
}

pub fn functionBodySupported(module: *const ast.Module, first: usize, count: usize, params_first: usize, params_count: usize, captures: []const []const u8, expressionSupported: anytype, expressionSupportedLocals: anytype, localIndex: anytype) bool {
    if (count == 0 or first >= module.statements.items.len) return false;
    const parameters = module.parameters.items[params_first .. params_first + params_count];
    var locals: std.ArrayListUnmanaged([]const u8) = .empty;
    defer locals.deinit(module.allocator);
    if (count > 1) for (module.statements.items[first .. first + count - 1]) |statement| {
        if (statement.kind == .yield_stmt) {
            const value = statement.kind.yield_stmt orelse return false;
            if (!expressionSupportedLocals(module, value, parameters, locals.items)) return false;
            continue;
        }
        const id = switch (statement.kind) {
            .expression => |value| value,
            else => return false,
        };
        const assignment = switch (module.expressions.items[@as(usize, id)].kind) {
            .assignment => |value| value,
            else => return false,
        };
        if (!expressionSupported(module, assignment.value, parameters, captures)) return false;
        if (assignment.target) |target| switch (module.expressions.items[@as(usize, target)].kind) {
            .member => |member| if (!expressionSupported(module, member.object, parameters, captures)) return false,
            else => return false,
        };
        if (assignment.target == null and localIndex(locals.items, assignment.name) == null) locals.append(module.allocator, assignment.name) catch return false;
    };
    const terminal = module.statements.items[first + count - 1];
    if (terminal.kind == .try_stmt) if (terminal.kind.try_stmt.except_binding) |binding| if (localIndex(locals.items, binding) == null) locals.append(module.allocator, binding) catch return false;
    return switch (terminal.kind) {
        .try_stmt => |try_stmt| trySupported(module, try_stmt, parameters, locals.items, captures),
        .yield_stmt => |value| if (value) |id| expressionSupportedLocals(module, id, parameters, locals.items) else false,
        .raise_stmt => |value| if (value) |id| expressionSupported(module, id, parameters, captures) else true,
        .return_stmt => |value| if (value) |id| expressionSupportedLocals(module, id, parameters, locals.items) else false,
        .expression => |id| if (module.expressions.items[@as(usize, id)].kind == .assignment) blk: {
            const assignment = module.expressions.items[@as(usize, id)].kind.assignment;
            const target = assignment.target orelse break :blk false;
            const member = switch (module.expressions.items[@as(usize, target)].kind) {
                .member => |value| value,
                else => break :blk false,
            };
            break :blk expressionSupported(module, member.object, parameters, captures) and expressionSupported(module, assignment.value, parameters, captures);
        } else false,
        else => false,
    };
}

pub fn trySupported(module: *const ast.Module, statement: anytype, parameters: []const ast.Parameter, locals: []const []const u8, captures: []const []const u8) bool {
    if (statement.body_count == 0 or statement.except_count > 1 or statement.finally_count > 1) return false;
    const body = module.statements.items[statement.body_first + statement.body_count - 1].kind;
    if (statement.except_count == 0 and statement.finally_count == 1) return finallySupported(module, statement, parameters, locals, captures);
    if (statement.except_count != 1 or statement.finally_count != 0 or statement.except_count == 0) return false;
    if (!assignmentRangeSupported(module, statement.body_first, statement.body_count -| 1, parameters, locals, captures) or !assignmentRangeSupported(module, statement.except_first, statement.except_count -| 1, parameters, locals, captures)) return false;
    const handler = module.statements.items[statement.except_first + statement.except_count - 1].kind;
    const body_supported = switch (body) {
        .raise_stmt => |value| if (value) |id| expressionSupportedWithFunctions(module, id, parameters, captures) else true,
        .return_stmt => |value| value != null and expressionSupportedWithFunctions(module, value.?, parameters, captures),
        else => false,
    };
    return body_supported and (statement.except_match == null or expressionSupportedWithLocals(module, statement.except_match.?, parameters, locals)) and switch (handler) {
        .return_stmt => |value| value != null and expressionSupportedWithLocals(module, value.?, parameters, locals),
        else => false,
    };
}

fn assignmentRangeSupported(module: *const ast.Module, first: usize, count: usize, parameters: []const ast.Parameter, locals: []const []const u8, captures: []const []const u8) bool {
    const end = std.math.add(usize, first, count) catch return false;
    if (end > module.statements.items.len) return false;
    for (module.statements.items[first..end]) |statement| {
        const id = switch (statement.kind) {
            .expression => |value| value,
            else => return false,
        };
        const assignment = switch (module.expressions.items[@as(usize, id)].kind) {
            .assignment => |value| value,
            else => return false,
        };
        if (assignment.target != null or !expressionSupportedWithLocals(module, assignment.value, parameters, locals) and !expressionSupportedWithFunctions(module, assignment.value, parameters, captures)) return false;
    }
    return true;
}

fn finallySupported(module: *const ast.Module, statement: anytype, parameters: []const ast.Parameter, locals: []const []const u8, captures: []const []const u8) bool {
    const body = module.statements.items[statement.body_first].kind;
    const finalizer = module.statements.items[statement.finally_first].kind;
    const body_ok = switch (body) {
        .return_stmt => |value| value != null and expressionSupportedWithFunctions(module, value.?, parameters, captures),
        else => false,
    };
    const finalizer_ok = switch (finalizer) {
        .expression => |id| if (module.expressions.items[@as(usize, id)].kind == .assignment) blk: {
            const assignment = module.expressions.items[@as(usize, id)].kind.assignment;
            break :blk assignment.target == null and expressionSupportedWithLocals(module, assignment.value, parameters, locals);
        } else false,
        else => false,
    };
    return body_ok and finalizer_ok;
}

pub fn expressionSupportedWithFunctions(module: *const ast.Module, id: ast.ExprId, parameters: []const ast.Parameter, captures: []const []const u8) bool {
    if (@as(usize, id) >= module.expressions.items.len) return false;
    return switch (module.expressions.items[id].kind) {
        .integer, .float, .string, .boolean, .none => true,
        .name => |name| std.mem.eql(u8, name, "tanna") or std.mem.eql(u8, name, "guru") or std.mem.eql(u8, name, "super") or helpers.parameterIndex(parameters, name) != null or lowering.localIndex(captures, name) != null or helpers.functionIndex(module, name) != null or classIndex(module, name) != null,
        .lambda => |lambda| lambda.params_count <= module.parameters.items.len -| lambda.params_first and expressionSupportedWithFunctions(module, lambda.body, module.parameters.items[lambda.params_first .. lambda.params_first + lambda.params_count], captures),
        .unary => |value| expressionSupportedWithFunctions(module, value.operand, parameters, captures),
        .binary => |value| helpers.binarySupported(value.op) and expressionSupportedWithFunctions(module, value.left, parameters, captures) and expressionSupportedWithFunctions(module, value.right, parameters, captures),
        .array => |value| collectionSupported(module, value.first, value.count, parameters, captures),
        .tuple => |value| collectionSupported(module, value.first, value.count, parameters, captures),
        .set => |value| collectionSupported(module, value.first, value.count, parameters, captures),
        .map => |value| collectionSupported(module, value.first, value.count * 2, parameters, captures),
        .index => |value| expressionSupportedWithFunctions(module, value.object, parameters, captures) and expressionSupportedWithFunctions(module, value.index, parameters, captures),
        .member => |value| expressionSupportedWithFunctions(module, value.object, parameters, captures),
        .call => |call| callSupported(module, call, parameters, captures),
        else => false,
    };
}

fn callSupported(module: *const ast.Module, call: anytype, parameters: []const ast.Parameter, captures: []const []const u8) bool {
    if (@as(usize, call.callee) >= module.expressions.items.len or call.first_arg > module.call_args.items.len or call.arg_count > module.call_args.items.len - call.first_arg) return false;
    if (module.expressions.items[call.callee].kind == .member) {
        const member = module.expressions.items[call.callee].kind.member;
        if (!expressionSupportedWithFunctions(module, member.object, parameters, captures)) return false;
        for (module.call_args.items[call.first_arg .. call.first_arg + call.arg_count]) |argument| if (!expressionSupportedWithFunctions(module, argument, parameters, captures)) return false;
        return true;
    }
    const name = switch (module.expressions.items[call.callee].kind) {
        .name => |value| value,
        else => return false,
    };
    if (classIndex(module, name)) |_| return argumentsSupported(module, call, parameters, captures);
    if (helpers.isPrintName(name) and call.arg_count == 1) return expressionSupportedWithFunctions(module, module.call_args.items[call.first_arg], parameters, captures);
    const declaration = functionParameters(module, name) orelse return false;
    const declared = module.parameters.items[declaration.first .. declaration.first + declaration.count];
    return callShapeSupported(module, call, declared) and argumentsSupported(module, call, parameters, captures);
}

fn argumentsSupported(module: *const ast.Module, call: anytype, parameters: []const ast.Parameter, captures: []const []const u8) bool {
    for (module.call_args.items[call.first_arg .. call.first_arg + call.arg_count]) |argument| if (!expressionSupportedWithFunctions(module, argument, parameters, captures)) return false;
    return true;
}

pub fn expressionSupportedWithLocals(module: *const ast.Module, id: ast.ExprId, parameters: []const ast.Parameter, locals: []const []const u8) bool {
    if (@as(usize, id) >= module.expressions.items.len) return false;
    return switch (module.expressions.items[id].kind) {
        .integer, .float, .string, .boolean, .none => true,
        .name => |name| std.mem.eql(u8, name, "tanna") or std.mem.eql(u8, name, "guru") or std.mem.eql(u8, name, "super") or helpers.parameterIndex(parameters, name) != null or lowering.localIndex(locals, name) != null or helpers.functionIndex(module, name) != null or classIndex(module, name) != null,
        .lambda => |lambda| lambda.params_count <= module.parameters.items.len -| lambda.params_first and expressionSupportedWithLocals(module, lambda.body, module.parameters.items[lambda.params_first .. lambda.params_first + lambda.params_count], locals),
        .unary => |value| expressionSupportedWithLocals(module, value.operand, parameters, locals),
        .binary => |value| helpers.binarySupported(value.op) and expressionSupportedWithLocals(module, value.left, parameters, locals) and expressionSupportedWithLocals(module, value.right, parameters, locals),
        .array => |value| collectionSupportedWithLocals(module, value.first, value.count, parameters, locals),
        .tuple => |value| collectionSupportedWithLocals(module, value.first, value.count, parameters, locals),
        .set => |value| collectionSupportedWithLocals(module, value.first, value.count, parameters, locals),
        .map => |value| collectionSupportedWithLocals(module, value.first, value.count * 2, parameters, locals),
        .index => |value| expressionSupportedWithLocals(module, value.object, parameters, locals) and expressionSupportedWithLocals(module, value.index, parameters, locals),
        .member => |value| expressionSupportedWithLocals(module, value.object, parameters, locals),
        .call => |call| callSupportedWithLocals(module, call, parameters, locals),
        else => false,
    };
}

fn callSupportedWithLocals(module: *const ast.Module, call: anytype, parameters: []const ast.Parameter, locals: []const []const u8) bool {
    if (@as(usize, call.callee) >= module.expressions.items.len or call.first_arg > module.call_args.items.len or call.arg_count > module.call_args.items.len - call.first_arg) return false;
    if (module.expressions.items[call.callee].kind == .member) {
        const member = module.expressions.items[call.callee].kind.member;
        return expressionSupportedWithLocals(module, member.object, parameters, locals) and argumentsSupportedWithLocals(module, call, parameters, locals);
    }
    const name = switch (module.expressions.items[call.callee].kind) {
        .name => |value| value,
        else => return false,
    };
    if (classIndex(module, name)) |_| return argumentsSupportedWithLocals(module, call, parameters, locals);
    if (helpers.isPrintName(name) and call.arg_count == 1) return expressionSupportedWithLocals(module, module.call_args.items[call.first_arg], parameters, locals);
    if (lowering.localIndex(locals, name) != null) return argumentsSupportedWithLocals(module, call, parameters, locals);
    const declaration = functionParameters(module, name) orelse return false;
    const declared = module.parameters.items[declaration.first .. declaration.first + declaration.count];
    return callShapeSupported(module, call, declared) and argumentsSupportedWithLocals(module, call, parameters, locals);
}

const FunctionParameters = struct { first: usize, count: usize };
fn functionParameters(module: *const ast.Module, name: []const u8) ?FunctionParameters {
    for (module.statements.items) |statement| switch (statement.kind) {
        .function => |function| if (std.mem.eql(u8, function.name, name)) return .{ .first = function.params_first, .count = function.params_count },
        else => {},
    };
    return null;
}
fn requiredParameters(parameters: []const ast.Parameter) usize {
    for (parameters, 0..) |parameter, index| if (parameter.default_value != null) return index;
    return parameters.len;
}

fn callShapeSupported(module: *const ast.Module, call: anytype, declared: []const ast.Parameter) bool {
    var fixed_count = declared.len;
    var has_varargs = false;
    var has_kwargs = false;
    for (declared, 0..) |parameter, index| switch (parameter.kind) {
        .variadic => {
            fixed_count = index;
            has_varargs = true;
        },
        .keyword_variadic => has_kwargs = true,
        .positional => {},
    };
    const positional_count = call.arg_count -| call.keyword_count;
    if (positional_count > fixed_count and !has_varargs) return false;
    if (positional_count < requiredParameters(declared[0..fixed_count])) return false;
    if (call.keyword_first > module.call_keywords.items.len or call.keyword_count > module.call_keywords.items.len - call.keyword_first) return false;
    for (module.call_keywords.items[call.keyword_first .. call.keyword_first + call.keyword_count]) |keyword| {
        var known = false;
        for (declared[0..fixed_count]) |parameter| {
            if (std.mem.eql(u8, parameter.name, keyword)) known = true;
        }
        if (!known and !has_kwargs) return false;
    }
    return true;
}

fn argumentsSupportedWithLocals(module: *const ast.Module, call: anytype, parameters: []const ast.Parameter, locals: []const []const u8) bool {
    for (module.call_args.items[call.first_arg .. call.first_arg + call.arg_count]) |argument| if (!expressionSupportedWithLocals(module, argument, parameters, locals)) return false;
    return true;
}

fn collectionSupported(module: *const ast.Module, first: usize, count: usize, parameters: []const ast.Parameter, captures: []const []const u8) bool {
    if (first > module.collection_items.items.len or count > module.collection_items.items.len - first) return false;
    for (first..first + count) |index| if (!expressionSupportedWithFunctions(module, module.collection_items.items[index], parameters, captures)) return false;
    return true;
}

fn collectionSupportedWithLocals(module: *const ast.Module, first: usize, count: usize, parameters: []const ast.Parameter, locals: []const []const u8) bool {
    if (first > module.collection_items.items.len or count > module.collection_items.items.len - first) return false;
    for (first..first + count) |index| if (!expressionSupportedWithLocals(module, module.collection_items.items[index], parameters, locals)) return false;
    return true;
}
