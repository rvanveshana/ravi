const std = @import("std");
const ast = @import("ravi_ast");
const hir = @import("ravi_hir");
const mir = @import("ravi_mir");
const expressions = @import("ravi_hir_expr_lowering");
const exception_lowering = @import("ravi_hir_exception_lowering");
const local_discovery = @import("ravi_hir_local_discovery");
const lowerControl = @import("hir_control_lowering.zig").lowerControl;
const exceptionLocalName = "__ravi_exception";
const finallyResultName = "__ravi_finally_result";
fn parameterIndex(parameters: []const ast.Parameter, name: []const u8) ?usize {
    for (parameters, 0..) |parameter, index| if (std.mem.eql(u8, parameter.name, name)) return index;
    return null;
}
pub fn lowerFunction(allocator: std.mem.Allocator, module: *const ast.Module, declaration: anytype, index: usize, capture_names: []const []const u8, is_method: bool) !mir.Function {
    _ = index;
    var source = hir.Function.init(allocator, declaration.name);
    defer source.deinit();
    source.parameter_count = declaration.params_count + @intFromBool(is_method);
    source.fixed_count = source.parameter_count;
    source.capture_count = capture_names.len;
    source.return_type = try hir.fromName(declaration.return_type orelse "dinamika");
    const parameters = module.parameters.items[declaration.params_first .. declaration.params_first + declaration.params_count];
    if (is_method) try source.parameter_types.append(allocator, .dynamic);
    for (parameters) |parameter| try source.parameter_types.append(allocator, try hir.fromName(parameter.annotation orelse "dinamika"));
    for (parameters, 0..) |parameter, parameter_index| {
        const slot = parameter_index + @intFromBool(is_method);
        if (slot < source.defaults.len) source.defaults[slot] = parameter.default_value;
        switch (parameter.kind) {
            .variadic => source.varargs_index = slot,
            .keyword_variadic => source.kwargs_index = slot,
            .positional => {},
        }
    }
    source.fixed_count = source.parameter_count - @intFromBool(source.varargs_index != null) - @intFromBool(source.kwargs_index != null);
    const names = try allocator.alloc([]const u8, parameters.len + @intFromBool(is_method));
    defer allocator.free(names);
    if (is_method) {
        names[0] = "tanna";
        _ = try source.appendValue(.dynamic, .{ .parameter = 0 }, module.statements.items[declaration.body_first].span.line);
    }
    for (parameters, 0..) |parameter, parameter_index| {
        const slot = parameter_index + @intFromBool(is_method);
        names[slot] = parameter.name;
        _ = try source.appendValue(source.parameterType(slot), .{ .parameter = slot }, parameter.span.line);
    }
    var local_names: std.ArrayListUnmanaged([]const u8) = .empty;
    defer local_names.deinit(allocator);
    local_discovery.collectControlLocals(module, declaration.body_first, declaration.body_count, &local_names, parameters);
    if (declaration.body_count > 1) for (module.statements.items[declaration.body_first .. declaration.body_first + declaration.body_count - 1]) |statement| {
        if (statement.kind == .control and std.mem.eql(u8, statement.kind.control.keyword, "while")) {
            const body = module.statements.items[statement.kind.control.body_first];
            const id = switch (body.kind) {
                .expression => |value| value,
                else => return error.UnsupportedExpression,
            };
            const assignment = switch (module.expressions.items[id].kind) {
                .assignment => |value| value,
                else => return error.UnsupportedExpression,
            };
            if (expressions.localIndex(local_names.items, assignment.name) == null) try local_names.append(allocator, assignment.name);
            continue;
        }
        const id = switch (statement.kind) {
            .expression => |value| value,
            else => return error.UnsupportedExpression,
        };
        const assignment = switch (module.expressions.items[id].kind) {
            .assignment => |value| value,
            else => return error.UnsupportedExpression,
        };
        if (parameterIndex(parameters, assignment.name) != null) return error.InvalidParameter;
        if (expressions.localIndex(local_names.items, assignment.name) == null) try local_names.append(allocator, assignment.name);
    };
    source.local_count = local_names.items.len;
    if (firstTryBinding(module, declaration.body_first, declaration.body_count)) |binding| {
        if (parameterIndex(parameters, binding) != null) return error.InvalidParameter;
        if (expressions.localIndex(local_names.items, binding) == null) try local_names.append(allocator, binding);
        source.local_count = local_names.items.len;
    }
    if (firstTryMatch(module, declaration.body_first, declaration.body_count) != null and expressions.localIndex(local_names.items, exceptionLocalName) == null) {
        try local_names.append(allocator, exceptionLocalName);
        source.local_count = local_names.items.len;
    }
    if (firstTryFinallyAssignment(module, declaration.body_first, declaration.body_count)) |name| {
        if (parameterIndex(parameters, name) != null) return error.InvalidParameter;
        if (expressions.localIndex(local_names.items, name) == null) try local_names.append(allocator, name);
        if (expressions.localIndex(local_names.items, finallyResultName) == null) try local_names.append(allocator, finallyResultName);
        source.local_count = local_names.items.len;
    }
    const terminal = module.statements.items[declaration.body_first + declaration.body_count - 1];
    if (declaration.body_count > 1) for (module.statements.items[declaration.body_first .. declaration.body_first + declaration.body_count - 1]) |statement| {
        if (statement.kind == .yield_stmt) {
            const id = statement.kind.yield_stmt orelse return error.UnsupportedExpression;
            source.resumable = true;
            source.suspension_count += 1;
            _ = try expressions.lowerWithLocals(allocator, &source, module, id, names, local_names.items, capture_names);
            try source.appendEffect(.{ .suspend_point = .{ .resume_line = statement.span.line } }, statement.span.line);
            continue;
        }
        if (statement.kind == .control) continue;
        const id = switch (statement.kind) {
            .expression => |value| value,
            else => return error.UnsupportedExpression,
        };
        const assignment = switch (module.expressions.items[id].kind) {
            .assignment => |value| value,
            else => return error.UnsupportedExpression,
        };
        const value = try expressions.lowerWithLocals(allocator, &source, module, assignment.value, names, local_names.items, capture_names);
        if (expressions.localIndex(capture_names, assignment.name)) |slot| {
            try source.appendEffect(.{ .store_capture = .{ .slot = slot, .value = value } }, module.expressions.items[id].span.line);
        } else {
            try source.appendEffect(.{ .store_local = .{ .slot = expressions.localIndex(local_names.items, assignment.name) orelse return error.InvalidExpression, .value = value } }, module.expressions.items[id].span.line);
        }
    };
    if (declaration.body_count > 1 and module.statements.items[declaration.body_first + declaration.body_count - 2].kind == .control and std.mem.eql(u8, module.statements.items[declaration.body_first + declaration.body_count - 2].kind.control.keyword, "while")) {
        try lowerControl(allocator, &source, module, declaration, module.statements.items[declaration.body_first + declaration.body_count - 2].kind.control, names, local_names.items, capture_names);
    } else switch (terminal.kind) {
        .expression => |id| {
            const assignment = switch (module.expressions.items[id].kind) {
                .assignment => |value| value,
                else => return error.UnsupportedExpression,
            };
            const target = assignment.target orelse return error.UnsupportedExpression;
            const member = switch (module.expressions.items[@as(usize, target)].kind) {
                .member => |value| value,
                else => return error.UnsupportedExpression,
            };
            const object = try expressions.lowerWithLocals(allocator, &source, module, member.object, names, local_names.items, capture_names);
            const value = try expressions.lowerWithLocals(allocator, &source, module, assignment.value, names, local_names.items, capture_names);
            try source.appendEffect(.{ .store_property = .{ .object = object, .value = value, .name = member.name } }, module.expressions.items[id].span.line);
            const none = try source.appendValue(.none, .constant_none, module.expressions.items[id].span.line);
            try source.appendEffect(.{ .return_value = none }, module.expressions.items[id].span.line);
        },
        .return_stmt => |value| {
            const id = value orelse return error.UnsupportedExpression;
            try source.appendEffect(.{ .return_value = try expressions.lowerWithLocals(allocator, &source, module, id, names, local_names.items, capture_names) }, module.expressions.items[id].span.line);
        },
        .yield_stmt => |value| {
            const id = value orelse return error.UnsupportedExpression;
            source.resumable = true;
            source.suspension_count += 1;
            const yielded = try expressions.lowerWithLocals(allocator, &source, module, id, names, local_names.items, capture_names);
            try source.appendEffect(.{ .suspend_point = .{ .resume_line = terminal.span.line } }, terminal.span.line);
            try source.appendEffect(.{ .return_value = yielded }, terminal.span.line);
        },
        .raise_stmt => |value| try source.appendEffect(.{ .raise_value = if (value) |id| try expressions.lowerWithLocals(allocator, &source, module, id, names, local_names.items, capture_names) else null }, terminal.span.line),
        .try_stmt => |try_stmt| try exception_lowering.lowerTry(allocator, &source, module, try_stmt, names, local_names.items, capture_names),
        .control => |control| try lowerControl(allocator, &source, module, declaration, control, names, local_names.items, capture_names),
        else => return error.UnsupportedExpression,
    }
    if (source.instructions.items.len != 0 and source.blocks.items.len == 0) {
        try source.setBlocks(&.{.{ .first_instruction = 0, .instruction_count = source.instructions.items.len }});
    }
    var result = try mir.Function.lower(allocator, &source);
    errdefer result.deinit();
    _ = try result.foldConstants();
    return result;
}
fn firstTryBinding(module: *const ast.Module, first: usize, count: usize) ?[]const u8 {
    if (count == 0) return null;
    return switch (module.statements.items[first + count - 1].kind) {
        .try_stmt => |statement| statement.except_binding,
        else => null,
    };
}
fn firstTryMatch(module: *const ast.Module, first: usize, count: usize) ?ast.ExprId {
    if (count == 0) return null;
    return switch (module.statements.items[first + count - 1].kind) {
        .try_stmt => |statement| statement.except_match,
        else => null,
    };
}
fn firstTryFinallyAssignment(module: *const ast.Module, first: usize, count: usize) ?[]const u8 {
    if (count == 0) return null;
    const statement = switch (module.statements.items[first + count - 1].kind) {
        .try_stmt => |value| value,
        else => return null,
    };
    if (statement.except_count != 0 or statement.finally_count != 1) return null;
    return switch (module.statements.items[statement.finally_first].kind) {
        .expression => |id| switch (module.expressions.items[@as(usize, id)].kind) {
            .assignment => |assignment| assignment.name,
            else => null,
        },
        else => null,
    };
}
pub fn lowerLambda(allocator: std.mem.Allocator, module: *const ast.Module, declaration: anytype, index: usize, capture_names: []const []const u8) !mir.Function {
    _ = index;
    var source = hir.Function.init(allocator, "<lambda>");
    defer source.deinit();
    source.parameter_count = declaration.params_count;
    source.fixed_count = declaration.params_count;
    source.capture_count = capture_names.len;
    source.return_type = .dynamic;
    const parameters = module.parameters.items[declaration.params_first .. declaration.params_first + declaration.params_count];
    for (parameters) |parameter| try source.parameter_types.append(allocator, try hir.fromName(parameter.annotation orelse "dinamika"));
    const names = try allocator.alloc([]const u8, parameters.len);
    defer allocator.free(names);
    for (parameters, 0..) |parameter, parameter_index| {
        names[parameter_index] = parameter.name;
        _ = try source.appendValue(source.parameterType(parameter_index), .{ .parameter = parameter_index }, parameter.span.line);
    }
    const value = try expressions.lowerWithLocals(allocator, &source, module, declaration.body, names, &.{}, capture_names);
    try source.appendEffect(.{ .return_value = value }, module.expressions.items[declaration.body].span.line);
    try source.setBlocks(&.{.{ .first_instruction = 0, .instruction_count = source.instructions.items.len }});
    var result = try mir.Function.lower(allocator, &source);
    errdefer result.deinit();
    _ = try result.foldConstants();
    return result;
}
pub const localIndex = expressions.localIndex;
pub const collectCaptures = expressions.collectCaptures;
pub const lowerExpressionWithLocals = expressions.lowerWithLocals;
